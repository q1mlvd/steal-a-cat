--!strict
-- Stealing gameplay: steal prompts on other players' cats, server-side hold check, owner alert with
-- an arrow to the thief, the new-player shield, and stolen cats running home after being dropped.
--
-- A stolen cat is "in transit" from BeginSteal until it is placed by the thief (ownership moves),
-- back on its owner's pillow, or discarded because the owner left. While in transit the victim's save
-- still has the cat on its (reserved) pillow; see PillowService for the save side.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local CatSchema = require(Config.CatSchema)
local Cats = require(Config.Cats)
local Defense = require(Config.Defense)
local GameConfig = require(Config.Game)
local Loyalty = require(Config.Loyalty)
local PlotPrompts = require(Config.PlotPrompts)
local Stealing = require(Config.Stealing)
local Tags = require(Config.Tags)
local Network = require(ReplicatedStorage.Shared.Network)
local CarryService = require(script.Parent.CarryService)
local CatSpawnService = require(script.Parent.CatSpawnService)
local DataService = require(script.Parent.DataService)
local NotificationService = require(script.Parent.NotificationService)
local PillowService = require(script.Parent.PillowService)
local PlotService = require(script.Parent.PlotService)
local CatReturnNavigation = require(script.Parent.CatReturnNavigation)

local ATTR = CatSchema.Attributes
local RETURNING_FOLDER_NAME = "Returning"

type Transit = {
	model: Model,
	victim: Player,
	thief: Player?,
	ending: boolean, -- set before we destroy the Model ourselves
	suppressAlert: boolean,
	destroyingConnection: RBXScriptConnection,
}

-- Trusted service callbacks MUST NOT yield. They run only after the steal's pickup succeeded;
-- consumable modifiers can therefore commit their inventory change in this same frame.
export type StealModifier = (thief: Player, model: Model) -> boolean
type BellTracking = {
	victim: Player,
	uniqueId: string,
	destroyingConnection: RBXScriptConnection,
	ancestryConnection: RBXScriptConnection,
	bellConnection: RBXScriptConnection,
}

local StealService = {
	Priority = 65,
}

local transits: { [Model]: Transit } = {}
local stealModifiers: { { name: string, callback: StealModifier } } = {}
local bellTrackers: { [Model]: BellTracking } = {}
local holdStarts: { [Player]: { prompt: ProximityPrompt, at: number } } = {}
local lastAttemptAt: { [Player]: number } = {}
local shieldEndsAt: { [Player]: number } = {} -- server time
local returningFolder: Folder
local stealAlertEvent: RemoteEvent
local bellTrackingEvent: RemoteEvent
local lastBellTrackingAt = 0

local function catName(model: Model): string
	local catDef = Cats.Get(tostring(model:GetAttribute(ATTR.CatId)))
	return if catDef then catDef.name else "cat"
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root
	end
	return nil
end

-- Transit bookkeeping ------------------------------------------------------------

local function stopBellTracking(model: Model)
	local tracker = bellTrackers[model]
	if tracker == nil then
		return
	end
	bellTrackers[model] = nil
	tracker.destroyingConnection:Disconnect()
	tracker.ancestryConnection:Disconnect()
	tracker.bellConnection:Disconnect()
	if tracker.victim.Parent == Players then
		bellTrackingEvent:FireClient(tracker.victim, false, tracker.uniqueId)
	end
end

local function startBellTracking(model: Model, victim: Player)
	-- A subsequent theft replaces the previous victim's locator with the new owner's locator.
	stopBellTracking(model)
	local uniqueId = model:GetAttribute(ATTR.UniqueId)
	local root = model:FindFirstChild("HumanoidRootPart")
	local data = DataService.GetData(victim)
	local record = if data and type(uniqueId) == "string" then data.cats[uniqueId] else nil
	if type(uniqueId) ~= "string" or uniqueId == "" or record == nil or record.bell ~= true
		or model:GetAttribute(Defense.BellAttribute) ~= true or root == nil or not root:IsA("BasePart") then
		return
	end
	bellTrackers[model] = {
		victim = victim,
		uniqueId = uniqueId,
		destroyingConnection = model.Destroying:Connect(function()
			stopBellTracking(model)
		end),
		ancestryConnection = model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(workspace) then
				stopBellTracking(model)
			end
		end),
		bellConnection = model:GetAttributeChangedSignal(Defense.BellAttribute):Connect(function()
			if model:GetAttribute(Defense.BellAttribute) ~= true then
				stopBellTracking(model)
			end
		end),
	}
	bellTrackingEvent:FireClient(victim, true, uniqueId, model, catName(model), root.Position)
end

local function updateBellTrackers()
	local now = os.clock()
	if now - lastBellTrackingAt < Defense.BellTrackingInterval then
		return
	end
	lastBellTrackingAt = now
	for model, tracker in table.clone(bellTrackers) do
		if tracker.victim.Parent ~= Players or not model:IsDescendantOf(workspace)
			or model:GetAttribute(Defense.BellAttribute) ~= true
			or (model:GetAttribute(ATTR.OwnerUserId) == tracker.victim.UserId
				and model:GetAttribute(ATTR.State) == CatSchema.States.OnPillow) then
			stopBellTracking(model)
			continue
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			-- Model references may be nil on a distant client with StreamingEnabled. The server's
			-- position keeps this locator useful beyond streaming range without revealing other cats.
			bellTrackingEvent:FireClient(tracker.victim, true, tracker.uniqueId, model, catName(model), root.Position)
		end
	end
end

local function endTransit(model: Model)
	local transit = transits[model]
	if transit == nil then
		return
	end
	transits[model] = nil
	transit.ending = true
	transit.destroyingConnection:Disconnect()
	if not transit.suppressAlert and transit.victim.Parent == Players then
		stealAlertEvent:FireClient(transit.victim, false)
	end
end

local function beginTransit(model: Model, victim: Player, thief: Player, suppressAlert: boolean)
	local transit: Transit
	transit = {
		model = model,
		victim = victim,
		thief = thief,
		ending = false,
		suppressAlert = suppressAlert,
		destroyingConnection = model.Destroying:Connect(function()
			-- Lost without us ending it (e.g. fell out of the world): rebuild from the owner's save.
			if transits[model] == transit and not transit.ending then
				transit.ending = true
				endTransit(model)
				if victim.Parent == Players then
					PillowService.RespawnFromSave(model)
				end
			end
		end),
	}
	transits[model] = transit
	if not suppressAlert then
		stealAlertEvent:FireClient(victim, true, thief, catName(model))
	end
	-- Bell is independent of Soft Paws and continues after ownership moves onto a thief's pillow.
	startBellTracking(model, victim)
end

-- Steal prompts ------------------------------------------------------------------

local holdMultiplier = 1 -- Rain event halves steal holds (EventService)

local function holdFor(model: Model): number
	return (if model:GetAttribute(ATTR.Tamed) == true then Stealing.HoldTamed else Stealing.HoldUntamed) * holdMultiplier
end

local function addStealPrompt(_owner: Player, model: Model)
	local timesReturned = model:GetAttribute(ATTR.TimesReturned)
	if type(timesReturned) == "number" and timesReturned >= Loyalty.UnstealableReturns then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root == nil then
		return
	end
	local existing = root:FindFirstChild(Stealing.StealPromptName)
	if existing then
		existing:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = Stealing.StealPromptName
	prompt.ActionText = Stealing.StealActionText
	prompt.ObjectText = catName(model)
	prompt.KeyboardKeyCode = PlotPrompts.KeyCode
	prompt.GamepadKeyCode = PlotPrompts.GamepadKeyCode
	prompt.HoldDuration = holdFor(model)
	prompt.MaxActivationDistance = PlotPrompts.MaxDistance
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute(PlotPrompts.KindAttribute, PlotPrompts.Kinds.Steal)
	CollectionService:AddTag(prompt, Tags.PlotPrompt)
	prompt.Parent = root
end

local function removeStealPrompt(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart")
	local prompt = if root then root:FindFirstChild(Stealing.StealPromptName) else nil
	if prompt then
		prompt:Destroy()
	end
end

local function updateStealHold(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart")
	local prompt = if root then root:FindFirstChild(Stealing.StealPromptName) else nil
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.HoldDuration = holdFor(model)
	end
end

-- Scales every steal hold (server timing and prompt hold) - e.g. 0.5 during Rain.
function StealService.SetHoldMultiplier(multiplier: number)
	holdMultiplier = math.clamp(multiplier, 0.1, 1)
	for _, prompt in CollectionService:GetTagged(Tags.PlotPrompt) do
		if prompt.Name == Stealing.StealPromptName then
			local model = prompt:FindFirstAncestorOfClass("Model")
			if model then
				updateStealHold(model)
			end
		end
	end
end

-- Shield ---------------------------------------------------------------------------

local function shieldRemaining(victim: Player): number
	local endsAt = shieldEndsAt[victim]
	return if endsAt then math.max(0, endsAt - workspace:GetServerTimeNow()) else 0
end

-- Steal ------------------------------------------------------------------------------

local function tryStartSteal(thief: Player, model: Model, prompt: ProximityPrompt)
	local timesReturned = model:GetAttribute(ATTR.TimesReturned)
	local catRootForPrompt = model:FindFirstChild("HumanoidRootPart")
	if model:GetAttribute(ATTR.State) ~= CatSchema.States.OnPillow
		or (type(timesReturned) == "number" and timesReturned >= Loyalty.UnstealableReturns)
		or catRootForPrompt == nil or prompt.Parent ~= catRootForPrompt
		or catRootForPrompt:FindFirstChild(Stealing.StealPromptName) ~= prompt then
		return
	end
	local now = os.clock()
	-- The engine's hold can be skipped by exploits, so time it ourselves.
	local hold = holdStarts[thief]
	holdStarts[thief] = nil
	if hold == nil or hold.prompt ~= prompt or now - hold.at < prompt.HoldDuration - Stealing.HoldTolerance then
		return
	end
	if now - (lastAttemptAt[thief] or 0) < Stealing.AttemptCooldown then
		return
	end
	lastAttemptAt[thief] = now

	local victim = PillowService.GetPlacementOwner(model)
	if victim == nil or victim == thief then
		return
	end
	local shieldLeft = shieldRemaining(victim)
	if shieldLeft > 0 then
		NotificationService.Notify(thief, `This house is protected for new players ({math.ceil(shieldLeft)}s left).`, "Error")
		return
	end
	if PlotService.GetPlot(thief) == nil or not DataService.IsLoaded(thief) then
		return
	end
	local root = getRoot(thief)
	local catRoot = model:FindFirstChild("HumanoidRootPart")
	local victimPlot = PlotService.GetPlot(victim)
	if root == nil or catRoot == nil or not catRoot:IsA("BasePart") or victimPlot == nil
		or (root.Position - catRoot.Position).Magnitude > GameConfig.InteractionMaxDistance
		or not PlotService.IsInsidePlot(thief, victimPlot) then
		return
	end
	if not CarryService.CanCarry(thief) then
		NotificationService.Notify(thief, "Your hands are full!", "Error")
		return
	end

	if PillowService.BeginSteal(thief, model) ~= victim then
		return
	end
	local suppressAlert = false
	for _, modifier in stealModifiers do
		local ok, result = pcall(modifier.callback, thief, model)
		if ok then
			suppressAlert = suppressAlert or result == true
		else
			warn(`[StealService] Steal modifier "{modifier.name}" failed: {result}`)
		end
	end
	beginTransit(model, victim, thief, suppressAlert)
	if not suppressAlert then
		NotificationService.Notify(victim, "Your cat is being stolen!", "Alert")
	end
	NotificationService.Notify(thief, "Run home and put it on a pillow!", "Info")
end

-- Running home ---------------------------------------------------------------------

local function runHome(model: Model)
	local transit = transits[model]
	if transit == nil then
		PillowService.ReturnHome(model)
		return
	end
	local sourcePlot = if transit.thief then PlotService.GetPlot(transit.thief) else nil
	transit.thief = nil
	local targetPlot = PlotService.GetPlot(transit.victim)
	local target = PillowService.GetReturnPosition(model)
	if targetPlot == nil or target == nil then
		transit.ending = true
		if not PillowService.ReturnHome(model) then
			endTransit(model)
		end
		return
	end
	local function finishReturn()
		if transits[model] == transit then
			transit.ending = true
			if not PillowService.ReturnHome(model) then
				endTransit(model)
			end
		end
	end
	local ok, err = xpcall(function()
		CatReturnNavigation.Run(model, sourcePlot, targetPlot, target, function(): boolean
			return transits[model] == transit and transit.victim.Parent == Players
				and DataService.IsLoaded(transit.victim) and PlotService.GetPlot(transit.victim) == targetPlot
		end, finishReturn, finishReturn)
	end, debug.traceback)
	if not ok then
		warn(`[StealService] Return navigation could not start: {err}`)
		finishReturn() -- retain the original record and seat it on its existing reserved pillow
	end
end

-- A stolen cat was dropped because its thief died / reset / was slapped / left.
local function onStolenDropped(_thief: Player, model: Model, _leaving: boolean): boolean
	runHome(model)
	return true
end

-- The victim left: whatever the thief holds (or the cat running home) disappears; the victim's save
-- still has it on its pillow, so it is back at their next join.
local function onVictimLeaving(victim: Player)
	for model, transit in transits do
		if transit.victim ~= victim then
			continue
		end
		transit.ending = true
		local thief = transit.thief
		if thief and CarryService.Release(thief, model) then
			NotificationService.Notify(thief, "The owner left, so the cat went home.", "Info")
		end
		endTransit(model)
		PillowService.ForgetInTransit(model)
		model:Destroy()
	end
end

-- Public API -----------------------------------------------------------------

function StealService.RegisterStealModifier(name: string, callback: StealModifier): ()
	assert(name ~= "", "Steal modifier name cannot be empty")
	for _, modifier in stealModifiers do
		assert(modifier.name ~= name, `Steal modifier "{name}" is already registered`)
	end
	table.insert(stealModifiers, { name = name, callback = callback })
end

function StealService.IsInTransit(model: Model): boolean
	return transits[model] ~= nil
end

function StealService.GetShieldRemaining(player: Player): number
	return shieldRemaining(player)
end

-- Studio + test profile only: picks up one of the player's own seated cats as if it were stolen
-- (reserved pillow, transit, run-home on drop) so solo tests can reach the 2-player return paths.
-- The cat is never placed by its "thief": DebugDropSelfStolen sends it home like a slapped thief's drop.
local function debugAllowed(): boolean
	return RunService:IsStudio() and DataService.IsStudioTestProfile()
end

function StealService.DebugSelfSteal(player: Player, model: Model): boolean
	if not debugAllowed() or PillowService.GetPlacementOwner(model) ~= player or transits[model] ~= nil then
		return false
	end
	if PillowService.BeginSteal(player, model) ~= player then
		return false
	end
	beginTransit(model, player, player, true)
	return true
end

-- Same as the stolen-cat drop handler for every self-stolen cat in the player's hands. (DropAll treats
-- a carrier who is also the owner as carrying their own cat, so it can't stand in here.)
function StealService.DebugDropSelfStolen(player: Player): number
	if not debugAllowed() then
		return 0
	end
	local dropped = 0
	for _, model in table.clone(CarryService.GetCarried(player)) do
		local transit = transits[model]
		if transit and transit.thief == player and transit.victim == player and CarryService.Release(player, model) then
			dropped += 1
			runHome(model)
		end
	end
	return dropped
end

-- Lifecycle ------------------------------------------------------------------

function StealService:Init(): ()
	stealAlertEvent = Network.GetEvent("StealAlert")
	bellTrackingEvent = Network.GetEvent("BellTracking")
	returningFolder = Instance.new("Folder")
	returningFolder.Name = RETURNING_FOLDER_NAME
	returningFolder.Parent = CatSpawnService.GetCatsFolder()
	PillowService.SetStolenDropHandler(onStolenDropped)
end

function StealService:Start(): ()
	RunService.Heartbeat:Connect(updateBellTrackers)
	PillowService.CatPlaced:Connect(addStealPrompt)
	PillowService.CatPlaced:Connect(function(owner: Player, model: Model)
		local tracker = bellTrackers[model]
		if tracker and tracker.victim == owner then
			stopBellTracking(model)
		end
	end)
	PillowService.CatUnplaced:Connect(removeStealPrompt)
	PillowService.CatTamed:Connect(updateStealHold)

	PillowService.CatStolen:Connect(function(thief: Player, victim: Player, model: Model)
		local transit = transits[model]
		local suppressAlert = transit ~= nil and transit.suppressAlert
		endTransit(model)
		if not suppressAlert then
			NotificationService.Notify(victim, `{thief.DisplayName} stole your {catName(model)}!`, "Error")
		end
		NotificationService.Notify(thief, `You stole {catName(model)}! It's yours now.`, "Success")
	end)
	PillowService.CatReturnedHome:Connect(function(owner: Player, model: Model)
		-- The Model may be new (rebuilt from the save); end whichever transit points at this owner's cat.
		for transitModel, transit in transits do
			if transitModel == model or (transit.victim == owner and transit.ending) then
				endTransit(transitModel)
			end
		end
		NotificationService.Notify(owner, "\u{1F3E0} " .. catName(model) .. " came back home!", "Homecoming")
	end)

	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt.Name == Stealing.StealPromptName then
			holdStarts[player] = { prompt = prompt, at = os.clock() }
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt.Name ~= Stealing.StealPromptName then
			return
		end
		local model = prompt:FindFirstAncestorOfClass("Model")
		if model and CollectionService:HasTag(model, Tags.Cat) then
			tryStartSteal(player, model, prompt)
		end
	end)

	PlotService.PlotAssigned:Connect(function(player: Player, plot: Model)
		local endsAt = workspace:GetServerTimeNow() + Stealing.NewPlayerShieldDuration
		shieldEndsAt[player] = endsAt
		plot:SetAttribute(Stealing.ShieldAttribute, endsAt)

		if RunService:IsStudio() then
			player:GetAttributeChangedSignal(Stealing.DebugEndShieldAttribute):Connect(function()
				if player:GetAttribute(Stealing.DebugEndShieldAttribute) == true and PlotService.GetPlot(player) == plot then
					shieldEndsAt[player] = nil
					plot:SetAttribute(Stealing.ShieldAttribute, nil)
				end
			end)
		end
	end)
	PlotService.PlotReleased:Connect(function(_player: Player, plot: Model)
		plot:SetAttribute(Stealing.ShieldAttribute, nil)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		onVictimLeaving(player)
		for model, tracker in table.clone(bellTrackers) do
			if tracker.victim == player then
				stopBellTracking(model)
			end
		end
		holdStarts[player] = nil
		lastAttemptAt[player] = nil
		shieldEndsAt[player] = nil
	end)
end

return StealService

