--!strict
-- Server-owned loyalty growth, petting and escapes. PillowService owns both reservations and commits.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = ReplicatedStorage.Shared.Config
local CatSchema = require(Config.CatSchema)
local Cats = require(Config.Cats)
local GameConfig = require(Config.Game)
local Loyalty = require(Config.Loyalty)
local PlotPrompts = require(Config.PlotPrompts)
local Tags = require(Config.Tags)
local Network = require(ReplicatedStorage.Shared.Network)
local DataSchema = require(ServerScriptService.Data.DataSchema)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PillowService = require(script.Parent.PillowService)
local PlotService = require(script.Parent.PlotService)
local CatReturnNavigation = require(script.Parent.CatReturnNavigation)

local ATTR = CatSchema.Attributes
type Seated = { owner: Player, lastGrowthAt: number, lastRollAt: number, prompt: ProximityPrompt }
type EscapeRun = { ticket: PillowService.LoyaltyReturnTicket, cancelNavigation: (() -> ())? }
local seated: { [Model]: Seated } = {}
local runs: { [Model]: EscapeRun } = {}
local lastAttemptAt: { [Player]: number } = {}
local random = Random.new()
local celebrationEvent: RemoteEvent
local LoyaltyService = { Priority = 68 }

local function getRecord(owner: Player, model: Model): DataSchema.CatRecord?
	local data = DataService.GetData(owner)
	local id = model:GetAttribute(ATTR.UniqueId)
	return if data and type(id) == "string" then data.cats[id] else nil
end

local function accrue(model: Model, entry: Seated, now: number, suppliedRecord: DataSchema.CatRecord?)
	local elapsed = math.max(0, now - entry.lastGrowthAt)
	entry.lastGrowthAt = now
	local record = suppliedRecord or getRecord(entry.owner, model)
	if record == nil or record.originalOwnerUserId ~= entry.owner.UserId then
		return
	end
	if record.loyalty >= Loyalty.Max then
		record.loyaltySeconds = 0
		return
	end
	local progress = (record.loyaltySeconds or 0) + elapsed
	local steps = math.floor(progress / Loyalty.GrowthInterval)
	record.loyaltySeconds = progress % Loyalty.GrowthInterval
	if steps > 0 then
		record.loyalty = math.clamp(record.loyalty + steps * Loyalty.GrowthAmount, Loyalty.Min, Loyalty.Max)
		model:SetAttribute(ATTR.Loyalty, record.loyalty)
	end
end

local function untrack(model: Model)
	local entry = seated[model]
	if entry then
		accrue(model, entry, os.clock(), nil)
		seated[model] = nil
		entry.prompt:Destroy()
	end
end

local function track(owner: Player, model: Model)
	untrack(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	local record = getRecord(owner, model)
	if root == nil or not root:IsA("BasePart") or record == nil then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = Loyalty.PetPromptName
	prompt.ActionText = Loyalty.PetActionText
	prompt.KeyboardKeyCode = Loyalty.PetKeyCode
	prompt.GamepadKeyCode = Loyalty.PetGamepadKeyCode
	prompt.MaxActivationDistance = PlotPrompts.MaxDistance
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt:SetAttribute(PlotPrompts.KindAttribute, PlotPrompts.Kinds.Pet)
	CollectionService:AddTag(prompt, Tags.PlotPrompt)
	prompt.Parent = root
	model:SetAttribute(ATTR.PetAvailableAt, record.lastPetAt + Loyalty.PetCooldown)
	seated[model] = {owner = owner, lastGrowthAt = os.clock(), lastRollAt = os.clock(), prompt = prompt}
end

local function tryPet(player: Player, prompt: ProximityPrompt)
	local now = os.clock()
	if now - (lastAttemptAt[player] or -math.huge) < Loyalty.PetAttemptCooldown then
		return
	end
	lastAttemptAt[player] = now
	local model = prompt:FindFirstAncestorOfClass("Model")
	local entry = if model then seated[model] else nil
	if model == nil or entry == nil or entry.prompt ~= prompt or entry.owner ~= player
		or model:GetAttribute(ATTR.State) ~= CatSchema.States.OnPillow
		or model:GetAttribute(ATTR.OwnerUserId) ~= player.UserId
		or model:GetAttribute(ATTR.OriginalOwnerUserId) ~= player.UserId then
		return
	end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local catRoot = model:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") or humanoid == nil or humanoid.Health <= 0
		or catRoot == nil or not catRoot:IsA("BasePart")
		or (root.Position - catRoot.Position).Magnitude > GameConfig.InteractionMaxDistance then
		return
	end
	local record = getRecord(player, model)
	if record == nil or record.originalOwnerUserId ~= player.UserId
		or os.time() < record.lastPetAt + Loyalty.PetCooldown then
		return
	end
	accrue(model, entry, now, record)
	record.lastPetAt = os.time()
	record.loyalty = math.clamp(record.loyalty + Loyalty.PetAmount, Loyalty.Min, Loyalty.Max)
	model:SetAttribute(ATTR.Loyalty, record.loyalty)
	model:SetAttribute(ATTR.PetAvailableAt, record.lastPetAt + Loyalty.PetCooldown)
	DataService.SaveNow(player)
end

local function cancelRun(model: Model)
	local run = runs[model]
	if run == nil then
		return
	end
	runs[model] = nil
	if run.cancelNavigation then
		run.cancelNavigation()
	end
	PillowService.CancelLoyaltyReturn(run.ticket)
end

local function beginEscape(model: Model, originalOwner: Player): boolean
	local ticket = PillowService.BeginLoyaltyReturn(model, originalOwner)
	if ticket == nil then
		return false
	end
	local run: EscapeRun = {ticket = ticket, cancelNavigation = nil}
	runs[model] = run
	local function active(): boolean
		return runs[model] == run and PillowService.IsLoyaltyReturning(model)
			and ticket.sourceOwner.Parent == Players and ticket.targetOwner.Parent == Players
			and DataService.IsLoaded(ticket.sourceOwner) and DataService.IsLoaded(ticket.targetOwner)
			and PlotService.GetPlot(ticket.sourceOwner) == ticket.sourcePlot
			and PlotService.GetPlot(ticket.targetOwner) == ticket.targetPlot
	end
	run.cancelNavigation = CatReturnNavigation.Run(model, ticket.sourcePlot, ticket.targetPlot,
		ticket.targetPillow.Position, active, function()
			if runs[model] ~= run then
				return
			end
			if not active() or not PillowService.CompleteLoyaltyReturn(ticket) then
				cancelRun(model)
				return
			end
			runs[model] = nil
			local def = Cats.Get(tostring(model:GetAttribute(ATTR.CatId)))
			celebrationEvent:FireClient(originalOwner, if def then def.name else "Cat", model:GetAttribute(ATTR.TimesReturned))
		end, function()
			cancelRun(model)
		end)
	return true
end

local function tick()
	local now = os.clock()
	for model, entry in seated do
		if not PillowService.IsPlaced(model) or model:GetAttribute(ATTR.State) ~= CatSchema.States.OnPillow then
			untrack(model)
			continue
		end
		accrue(model, entry, now, nil)
		local force = RunService:IsStudio() and model:GetAttribute(Loyalty.DebugForceEscapeAttribute) == true
		if not force and now - entry.lastRollAt < Loyalty.EscapeInterval then
			continue
		end
		entry.lastRollAt = now
		local record = getRecord(entry.owner, model)
		if record == nil or record.originalOwnerUserId == entry.owner.UserId then
			continue
		end
		local originalOwner = Players:GetPlayerByUserId(record.originalOwnerUserId)
		if originalOwner == nil or PillowService.GetFreePillow(originalOwner) == nil then
			continue -- wait on this pillow; no reservation, no save move
		end
		local chance = math.clamp(record.loyalty / Loyalty.EscapeLoyaltyDivisor / Loyalty.PercentScale, 0, 1)
		if force or random:NextNumber() < chance then
			if beginEscape(model, originalOwner) and force then
				model:SetAttribute(Loyalty.DebugForceEscapeAttribute, false)
			end
		end
	end
	for model, run in runs do
		if not PillowService.IsLoyaltyReturning(model) or run.ticket.sourceOwner.Parent ~= Players
			or run.ticket.targetOwner.Parent ~= Players or not DataService.IsLoaded(run.ticket.sourceOwner)
			or not DataService.IsLoaded(run.ticket.targetOwner) then
			cancelRun(model)
		end
	end
end

-- Server-only shop API. Finds the single owning save, including cats currently returning/carried.
function LoyaltyService.ReduceLoyalty(uniqueId: string, amount: number): boolean
	if type(uniqueId) ~= "string" or uniqueId == "" or type(amount) ~= "number"
		or amount ~= amount or amount <= 0 or amount == math.huge then
		return false
	end
	local owner: Player? = nil
	local record: DataSchema.CatRecord? = nil
	for _, player in Players:GetPlayers() do
		local data = DataService.GetData(player)
		if data and data.cats[uniqueId] then
			if record then
				return false -- reject ambiguous identity rather than editing a duplicate
			end
			owner, record = player, data.cats[uniqueId]
		end
	end
	if record == nil or owner == nil then
		return false
	end
	record.loyalty = math.clamp(record.loyalty - amount, Loyalty.Min, Loyalty.Max)
	for _, instance in CollectionService:GetTagged(Tags.Cat) do
		if instance:IsA("Model") and instance:GetAttribute(ATTR.UniqueId) == uniqueId then
			instance:SetAttribute(ATTR.Loyalty, record.loyalty)
		end
	end
	DataService.SaveNow(owner)
	return true
end

function LoyaltyService:Init(): ()
	celebrationEvent = Network.GetEvent("CatLoyaltyReturned")
	EconomyService.RegisterCatIncomeSource("Loyal", function(_owner: Player, model: Model): number
		local returns = model:GetAttribute(ATTR.TimesReturned)
		return if type(returns) == "number" and returns >= Loyalty.LoyalReturns then Loyalty.LoyalIncomeMultiplier else 1
	end)
	DataService.RegisterSaveHook("LoyaltyGrowth", function(player: Player, data: DataSchema.PlayerData)
		local now = os.clock()
		for model, entry in seated do
			if entry.owner == player then
				local id = model:GetAttribute(ATTR.UniqueId)
				local record = if type(id) == "string" then data.cats[id] else nil
				if record then
					accrue(model, entry, now, record)
				end
			end
		end
	end)
end

function LoyaltyService:Start(): ()
	PillowService.CatPlaced:Connect(track)
	PillowService.CatUnplaced:Connect(untrack)
	for _, plot in PlotService.GetPlots() do
		local owner = PlotService.GetOwner(plot)
		if owner then
			for _, model in PillowService.GetPlacedCats(plot) do
				track(owner, model)
			end
		end
	end
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt.Name == Loyalty.PetPromptName then
			tryPet(player, prompt)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastAttemptAt[player] = nil
		for model, run in runs do
			if run.ticket.sourceOwner == player or run.ticket.targetOwner == player then
				cancelRun(model)
			end
		end
	end)
	while true do
		task.wait(Loyalty.TickInterval)
		tick()
	end
end

return LoyaltyService


