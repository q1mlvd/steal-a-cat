--!strict
-- Catch flow: ProximityPrompt -> server validation -> client mini-game -> server-verified result.
-- The server picks every mini-game parameter and times the press itself; the client only says "now".
--
-- Timing: the client starts the bar when CatchStart arrives (~half a round trip after sentAt) and its
-- CatchSubmit arrives another half trip after the press. So the press happened at about
-- (receivedAt - sentAt - roundTrip) on the bar's clock. Player:GetNetworkPing() is the round trip.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local Catching = require(Config.Catching)
local Items = require(Config.Items)
local Shop = require(Config.Shop)
local Cats = require(Config.Cats)
local Events = require(Config.Events)
local CatSchema = require(Config.CatSchema)
local Rarities = require(Config.Rarities)
local Tags = require(Config.Tags)
local Network = require(ReplicatedStorage.Shared.Network)
local CatchMinigame = require(ReplicatedStorage.Shared.CatchMinigame)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local CatSpawnService = require(script.Parent.CatSpawnService)
local CarryService = require(script.Parent.CarryService)
local NotificationService = require(script.Parent.NotificationService)
local DataService = require(script.Parent.DataService)
local ItemService = require(script.Parent.ItemService)

local ATTR = CatSchema.Attributes

type Session = {
	id: string,
	cat: Model,
	params: CatchMinigame.Params,
	sentAt: number,
}

local CatchService = {
	Priority = 50,
	-- (player, model) after a successful catch (the cat is now carried)
	CatCaught = Signal.new() :: Signal.Signal<Player, Model>,
}

local random = Random.new()
local sessions: { [Player]: Session } = {}
local lastAttemptAt: { [Player]: number } = {}
-- cat -> player -> os.clock() until which that cat refuses the player (after a failed catch)
local failIgnore: { [Model]: { [Player]: number } } = {}

local catchStartEvent: RemoteEvent
local catchResultEvent: RemoteEvent
local catchSubmitEvent: RemoteEvent

local function getPrompt(model: Model): ProximityPrompt?
	local root = model:FindFirstChild("HumanoidRootPart")
	local prompt = if root then root:FindFirstChild(Catching.PromptName) else nil
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end

local function setPromptEnabled(model: Model, enabled: boolean)
	local prompt = getPrompt(model)
	if prompt then
		prompt.Enabled = enabled
	end
end

local function ensurePrompt(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root == nil then
		return
	end
	local prompt = getPrompt(model)
	if prompt == nil then
		local newPrompt = Instance.new("ProximityPrompt")
		newPrompt.Name = Catching.PromptName
		newPrompt.ActionText = Catching.PromptActionText
		newPrompt.KeyboardKeyCode = Catching.PromptKey
		newPrompt.GamepadKeyCode = Catching.PromptGamepadKey
		newPrompt.HoldDuration = 0
		-- Client presentation narrows this to the player's unlocked range; the server verifies it too.
		newPrompt.MaxActivationDistance = Items.Effects.Net.CatchDistance
		newPrompt.RequiresLineOfSight = false
		local catDef = Cats.Get(tostring(model:GetAttribute(ATTR.CatId)))
		newPrompt.ObjectText = if catDef then catDef.name else ""
		newPrompt.Parent = root
		prompt = newPrompt
	end
	(prompt :: ProximityPrompt).Enabled = true
end

local function getRootPosition(instance: Instance?): Vector3?
	if instance == nil then
		return nil
	end
	local root = instance:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return humanoid ~= nil and humanoid.Health > 0
end

local function isInRange(player: Player, model: Model): boolean
	local playerPosition = getRootPosition(player.Character)
	local catPosition = getRootPosition(model)
	return playerPosition ~= nil and catPosition ~= nil
		and (playerPosition - catPosition).Magnitude <= ItemService.GetCatchDistance(player)
end

local function finish(player: Player, session: Session, success: boolean)
	if sessions[player] ~= session then
		return
	end
	sessions[player] = nil
	player:SetAttribute(Shop.CatchingAttribute, nil)
	local model = session.cat

	if success and CatSpawnService.ClaimWildCat(model) then
		if CarryService.PickUp(player, model) then
			-- Capture the first successful catcher; ownership/save creation still happens on placement.
			if model:GetAttribute(ATTR.OriginalOwnerUserId) == nil then
				model:SetAttribute(ATTR.OriginalOwnerUserId, player.UserId)
			end
			DataService.Update(player, "stats", function(stats)
				stats.catsCaught += 1
				return stats
			end)
			catchResultEvent:FireClient(player, session.id, true)
			CatchService.CatCaught:Fire(player, model)
			return
		end
		-- Couldn't carry after all (died at the last moment): give the cat back to the wild.
		CatSpawnService.ReleaseToWild(model)
		success = false
	end

	if CatSpawnService.IsWild(model) then
		CatSpawnService.UnlockWildCat(model, true)
		setPromptEnabled(model, true)
	end
	local ignored = failIgnore[model] or {}
	ignored[player] = os.clock() + Catching.FailIgnoreTime
	failIgnore[model] = ignored

	if player.Parent then
		catchResultEvent:FireClient(player, session.id, false)
	end
end

local function tryStartCatch(player: Player, model: Model)
	local now = os.clock()
	if sessions[player] then
		return
	end
	if now - (lastAttemptAt[player] or 0) < Catching.AttemptCooldown then
		return
	end
	lastAttemptAt[player] = now

	if not CatSpawnService.IsWild(model) then
		return
	end
	if model:GetAttribute(Events.Rain.HidingAttribute) == true then
		NotificationService.Notify(player, "The cat is hiding from the rain!", "Error")
		return
	end
	if CatSpawnService.IsLocked(model) then
		NotificationService.Notify(player, "Someone is already catching this cat!", "Error")
		return
	end
	local ignoredUntil = failIgnore[model] and failIgnore[model][player]
	if ignoredUntil and now < ignoredUntil then
		NotificationService.Notify(player, "This cat doesn't trust you yet!", "Error")
		return
	end
	if not isAlive(player) or not isInRange(player, model) then
		return
	end
	if not CarryService.CanCarry(player) then
		NotificationService.Notify(player, "Your hands are full!", "Error")
		return
	end

	local rarity = Rarities.Get(tostring(model:GetAttribute(ATTR.Rarity)))
	local catDef = Cats.Get(tostring(model:GetAttribute(ATTR.CatId)))
	if rarity == nil or catDef == nil then
		return
	end
	if not CatSpawnService.LockWildCat(model) then
		return
	end
	setPromptEnabled(model, false)

	local session: Session = {
		id = HttpService:GenerateGUID(false),
		cat = model,
		params = nil :: any,
		sentAt = 0,
	}
	session.params = CatchMinigame.Generate(session.id, catDef.name, rarity, random)
	-- Consume an armed Fish only after all catch prerequisites and the exclusive cat lock passed.
	-- Expand around the generated centre, shifting at the bar edges rather than cutting the zone off.
	if ItemService.ConsumeFishBoost(player) then
		local fish = Items.Effects.Fish
		local params = session.params
		local centre = params.zoneStart + params.zoneSize / 2
		params.zoneSize = math.min(params.zoneSize * fish.GreenZoneMultiplier, fish.MaximumGreenWidth)
		params.zoneStart = math.clamp(centre - params.zoneSize / 2, 0, 1 - params.zoneSize)
		params.tolerance = math.min(Catching.LatencyTolerance / params.travelTime,
			params.zoneSize * Catching.MaxToleranceZoneFraction)
	end
	sessions[player] = session
	player:SetAttribute(Shop.CatchingAttribute, true)

	session.sentAt = os.clock()
	catchStartEvent:FireClient(player, session.params)

	task.delay(session.params.timeout + Catching.MaxLatencyCompensation, function()
		finish(player, session, false) -- no-op if the session already finished
	end)
end

local function onSubmit(player: Player, sessionId: unknown)
	local receivedAt = os.clock()
	local session = sessions[player]
	if session == nil or type(sessionId) ~= "string" or sessionId ~= session.id then
		return
	end

	local latency = math.clamp(player:GetNetworkPing(), 0, Catching.MaxLatencyCompensation)
	local elapsed = receivedAt - session.sentAt - latency
	local hit = CatchMinigame.IsHit(session.params, elapsed)
	local valid = isAlive(player) and isInRange(player, session.cat)

	finish(player, session, hit and valid)
end

local function onPlayerRemoving(player: Player)
	player:SetAttribute(Shop.CatchingAttribute, nil)
	local session = sessions[player]
	if session then
		sessions[player] = nil
		if CatSpawnService.IsWild(session.cat) then
			CatSpawnService.UnlockWildCat(session.cat, false)
			setPromptEnabled(session.cat, true)
		end
	end
	lastAttemptAt[player] = nil
	for _, ignored in failIgnore do
		ignored[player] = nil
	end
end

function CatchService:Init(): ()
	catchStartEvent = Network.GetEvent("CatchStart")
	catchResultEvent = Network.GetEvent("CatchResult")
	catchSubmitEvent = Network.GetEvent("CatchSubmit")
end

function CatchService:Start(): ()
	CatSpawnService.WildCatAdded:Connect(ensurePrompt)
	CatSpawnService.WildCatRemoved:Connect(function(model: Model, _reason: string)
		setPromptEnabled(model, false)
		failIgnore[model] = nil
	end)
	for _, model in CatSpawnService.GetWildCats() do
		ensurePrompt(model)
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt.Name ~= Catching.PromptName then
			return
		end
		local model = prompt:FindFirstAncestorOfClass("Model")
		if model and CollectionService:HasTag(model, Tags.Cat) and getPrompt(model) == prompt then
			tryStartCatch(player, model)
		end
	end)

	catchSubmitEvent.OnServerEvent:Connect(onSubmit)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return CatchService

