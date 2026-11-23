--!strict
-- Coins and income. Balances live in the player's save (DataService); leaderstats, the IncomePerSecond
-- attribute and each Bowl's BowlCoins attribute are read-only mirrors for clients.
-- Every IncomeTickInterval, each owned plot's bowl gains (sum of placed cats' coinsPerSecond x per-cat sources)
-- x MultiplierService:GetIncomeMultiplier(owner) x interval. The owner collects the bowl into Coins.
-- Per-cat effects (Loyalty, mutations) register sources here; player-wide effects remain in MultiplierService.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local CatSchema = require(Config.CatSchema)
local Cats = require(Config.Cats)
local Economy = require(Config.Economy)
local GameConfig = require(Config.Game)
local PlotPrompts = require(Config.PlotPrompts)
local Tags = require(Config.Tags)
local Mutations = require(Config.Mutations)
local Loyalty = require(Config.Loyalty)
local Network = require(ReplicatedStorage.Shared.Network)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local DataService = require(script.Parent.DataService)
local MultiplierService = require(script.Parent.MultiplierService)
local NotificationService = require(script.Parent.NotificationService)
local PillowService = require(script.Parent.PillowService)
local PlotService = require(script.Parent.PlotService)

local ATTR = CatSchema.Attributes
local LEADERSTATS_NAME = "leaderstats" -- Roblox requires this exact name

export type CatIncomeSource = (owner: Player, model: Model) -> number
-- A complete per-cat rate BEFORE player-wide multipliers. nil delegates to the existing catalog/sources.
export type CatIncomeResolver = (owner: Player, record: any) -> number?

local EconomyService = {
	Priority = 70,

	-- (player, newBalance)
	CoinsChanged = Signal.new() :: Signal.Signal<Player, number>,
	-- (player, amount) after coins were collected from the player's bowl
	BowlCollected = Signal.new() :: Signal.Signal<Player, number>,
}

local coinValues: { [Player]: NumberValue } = {}
local bowlCoins: { [Model]: number } = {} -- runtime copy per plot; the owner's save holds the real value
local bowlParts: { [Model]: BasePart } = {}
local lastCollectAt: { [Player]: number } = {}
local catIncomeSources: { [string]: CatIncomeSource } = {}
local invalidCatIncomeSources: { [string]: boolean } = {}
local catIncomeResolvers: { [string]: CatIncomeResolver } = {}
local resolverOrder: { string } = {}
local invalidIncomeResolvers: { [string]: boolean } = {}

local coinsCollectedEvent: RemoteEvent

local function setCoins(player: Player, amount: number)
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	data.coins = amount
	local value = coinValues[player]
	if value then
		value.Value = amount
	end
	EconomyService.CoinsChanged:Fire(player, amount)
end

-- `owner`: also write the amount into that player's save (omit for runtime-only resets).
local function setBowl(plot: Model, amount: number, owner: Player?)
	bowlCoins[plot] = amount
	local bowl = bowlParts[plot]
	if bowl then
		bowl:SetAttribute(Economy.BowlAttribute, amount)
	end
	if owner then
		local data = DataService.GetData(owner)
		if data then
			data.bowlCoins = amount
		end
	end
end

local function isFiniteNonNegative(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function catIncomeMultiplier(owner: Player, model: Model): number
	local multiplier = 1
	for name, source in catIncomeSources do
		local ok, factor = pcall(source, owner, model)
		if not ok or not isFiniteNonNegative(factor) then
			if not invalidCatIncomeSources[name] then
				warn(`[EconomyService] Cat income source "{name}" failed or returned an invalid factor; ignoring it`)
				invalidCatIncomeSources[name] = true
			end
			continue
		end
		local product = multiplier * (factor :: number)
		if not isFiniteNonNegative(product) then
			if not invalidCatIncomeSources[name] then
				warn(`[EconomyService] Cat income source "{name}" overflowed; ignoring it`)
				invalidCatIncomeSources[name] = true
			end
			continue
		end
		invalidCatIncomeSources[name] = nil
		multiplier = product
	end
	return multiplier
end

local function incomeRecord(owner: Player, model: Model): any
	local catId = model:GetAttribute(ATTR.CatId)
	local uniqueId = model:GetAttribute(ATTR.UniqueId)
	local data = DataService.GetData(owner)
	local saved = if data and type(uniqueId) == "string" then data.cats[uniqueId] else nil
	if saved and saved.catId == catId then return saved end
	-- Preview callers may pass a model without a saved record; do not create or edit one.
	return { catId = if type(catId) == "string" then catId else "",
		mutation = model:GetAttribute(ATTR.Mutation), tier = model:GetAttribute(ATTR.Tier),
		timesReturned = model:GetAttribute(ATTR.TimesReturned), loyalty = model:GetAttribute(ATTR.Loyalty) }
end

local function resolvedIncome(owner: Player, record: any): number?
	for _, name in resolverOrder do
		local resolver = catIncomeResolvers[name]
		if resolver == nil then continue end
		local ok, rate = pcall(resolver, owner, record)
		if ok and rate == nil then continue end
		if ok and isFiniteNonNegative(rate) then invalidIncomeResolvers[name] = nil return rate :: number end
		if not invalidIncomeResolvers[name] then
			invalidIncomeResolvers[name] = true
			warn(`[EconomyService] Cat income resolver "{name}" failed or returned an invalid rate; using the catalog`)
		end
	end
	return nil
end

local function rawModelIncome(owner: Player, model: Model): number
	local record = incomeRecord(owner, model)
	local resolved = resolvedIncome(owner, record)
	if resolved ~= nil then return resolved end
	local catDef = Cats.Get(record.catId)
	if catDef == nil then return 0 end
	local income = catDef.coinsPerSecond * catIncomeMultiplier(owner, model)
	return if isFiniteNonNegative(income) then income else 0
end

local function baseIncome(plot: Model, owner: Player): number
	local total = 0
	for _, model in PillowService.GetPlacedCats(plot) do
		local income = rawModelIncome(owner, model)
		if isFiniteNonNegative(total + income) then total += income end
	end
	return total
end

local function incomeTick(interval: number)
	for _, plot in PlotService.GetPlots() do
		local owner = PlotService.GetOwner(plot)
		if owner == nil then
			continue
		end
		local perSecond = baseIncome(plot, owner) * MultiplierService.GetIncomeMultiplier(owner)
		owner:SetAttribute(Economy.IncomeAttribute, perSecond)
		if perSecond > 0 then
			setBowl(plot, (bowlCoins[plot] or 0) + perSecond * interval, owner)
		end
	end
end

-- Public API -----------------------------------------------------------------

-- Sources multiply for this cat only and must not yield. Re-registering a name replaces its source.
function EconomyService.RegisterCatIncomeSource(name: string, source: CatIncomeSource): ()
	assert(type(name) == "string" and name ~= "", "[EconomyService] Cat income source needs a name")
	assert(type(source) == "function", "[EconomyService] Cat income source must be a function")
	catIncomeSources[name] = source
	invalidCatIncomeSources[name] = nil
end

function EconomyService.UnregisterCatIncomeSource(name: string): ()
	catIncomeSources[name] = nil
	invalidCatIncomeSources[name] = nil
end

function EconomyService.RegisterCatIncomeResolver(name: string, resolver: CatIncomeResolver): ()
	assert(type(name) == "string" and name ~= "", "[EconomyService] Cat income resolver needs a name")
	assert(type(resolver) == "function", "[EconomyService] Cat income resolver must be a function")
	if catIncomeResolvers[name] == nil and not table.find(resolverOrder, name) then table.insert(resolverOrder, name) end
	catIncomeResolvers[name] = resolver
	invalidIncomeResolvers[name] = nil
end

function EconomyService.UnregisterCatIncomeResolver(name: string): ()
	catIncomeResolvers[name] = nil
	invalidIncomeResolvers[name] = nil
end

-- Best regular OWNED record, including waiting/in-transit cats. Excludes all exclusive catalog entries.
-- Tier, mutation and the permanent Loyal return bonus are included; player-wide multipliers are excluded.
-- With no regular cats, the cheapest regular catalog rate keeps an exclusive's first income useful.
function EconomyService.GetRegularCatIncomePerSecond(player: Player): number
	local data = DataService.GetData(player)
	local best = 0
	if data then
		for _, record in data.cats do
			local cat = if type(record.catId) == "string" then Cats.Get(record.catId) else nil
			if cat and (cat :: any).exclusive ~= true then
				local loyal = if type(record.timesReturned) == "number" and record.timesReturned >= Loyalty.LoyalReturns then Loyalty.LoyalIncomeMultiplier else 1
				local rate = cat.coinsPerSecond * Mutations.GetTier(record.tier).multiplier * Mutations.Multiplier(record.mutation) * loyal
				if isFiniteNonNegative(rate) then best = math.max(best, rate) end
			end
		end
	end
	if best > 0 then return best end
	local minimum = math.huge
	for _, cat in Cats.List do
		if (cat :: any).exclusive ~= true and isFiniteNonNegative(cat.coinsPerSecond) and cat.coinsPerSecond > 0 then minimum = math.min(minimum, cat.coinsPerSecond) end
	end
	return if minimum < math.huge then minimum else 0
end

function EconomyService.GetCatIncomeMultiplier(owner: Player, model: Model): number
	return catIncomeMultiplier(owner, model)
end

-- Actual contribution of one cat, including the owner's player-wide multiplier.
function EconomyService.GetCatIncomePerSecond(owner: Player, model: Model): number
	local income = rawModelIncome(owner, model) * MultiplierService.GetIncomeMultiplier(owner)
	return if isFiniteNonNegative(income) then income else 0
end

function EconomyService.GetCoins(player: Player): number
	local data = DataService.GetData(player)
	return if data then data.coins else 0
end

function EconomyService.AddCoins(player: Player, amount: number)
	assert(amount >= 0 and amount == amount and amount ~= math.huge, "[EconomyService] AddCoins needs a finite, non-negative amount")
	local data = DataService.GetData(player)
	if data then
		setCoins(player, data.coins + amount)
	end
end

-- Spends coins if the player has enough. Returns false (and changes nothing) otherwise.
function EconomyService.TrySpend(player: Player, amount: number): boolean
	assert(amount >= 0 and amount == amount, "[EconomyService] TrySpend needs a non-negative amount")
	local data = DataService.GetData(player)
	if data == nil or data.coins < amount then
		return false
	end
	setCoins(player, data.coins - amount)
	return true
end

function EconomyService.GetIncomePerSecond(player: Player): number
	local plot = PlotService.GetPlot(player)
	return if plot then baseIncome(plot, player) * MultiplierService.GetIncomeMultiplier(player) else 0
end

function EconomyService.GetBowlCoins(plot: Model): number
	return bowlCoins[plot] or 0
end

-- Moves the whole coins from the player's bowl into their balance. Returns the amount collected.
function EconomyService.Collect(player: Player, fromPrompt: boolean): number
	local plot = PlotService.GetPlot(player)
	local bowl = if plot then bowlParts[plot] else nil
	local data = DataService.GetData(player)
	if plot == nil or bowl == nil or data == nil then
		return 0
	end
	local now = os.clock()
	if now - (lastCollectAt[player] or 0) < Economy.CollectCooldown then
		return 0
	end

	local amount = math.floor(bowlCoins[plot] or 0) -- fractions stay in the bowl
	if amount < 1 then
		if fromPrompt then
			NotificationService.Notify(player, "The bowl is empty. Put cats on pillows to earn coins!", "Info")
		end
		return 0
	end
	lastCollectAt[player] = now

	setBowl(plot, (bowlCoins[plot] or 0) - amount, player)
	EconomyService.AddCoins(player, amount)
	data.stats.coinsEarnedTotal += amount
	coinsCollectedEvent:FireClient(player, amount, bowl.Position)
	EconomyService.BowlCollected:Fire(player, amount)
	return amount
end

-- Offline income: adds coins to the player's bowl (runtime + save), like normal bowl income.
function EconomyService.AddToBowl(player: Player, amount: number)
	local plot = PlotService.GetPlot(player)
	if plot == nil or amount ~= amount or amount <= 0 or amount == math.huge then
		return
	end
	setBowl(plot, (bowlCoins[plot] or 0) + amount, player)
end

-- Dog Raid: takes `fraction` of the plot owner's bowl (coins only; never cats). Returns the amount.
function EconomyService.StealFromBowl(plot: Model, fraction: number): number
	local owner = PlotService.GetOwner(plot)
	local amount = math.floor((bowlCoins[plot] or 0) * math.clamp(fraction, 0, 1))
	if owner == nil or amount < 1 then
		return 0
	end
	setBowl(plot, (bowlCoins[plot] or 0) - amount, owner)
	return amount
end

-- Rebirth: coins and bowl to 0 in the live profile (no yields; RebirthService saves afterwards).
function EconomyService.ResetForRebirth(player: Player)
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	setCoins(player, 0)
	local plot = PlotService.GetPlot(player)
	if plot then
		setBowl(plot, 0, player)
	else
		data.bowlCoins = 0
	end
end

-- Lifecycle ------------------------------------------------------------------

local function isNear(player: Player, part: BasePart): boolean
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return root ~= nil and root:IsA("BasePart") and (root.Position - part.Position).Magnitude <= GameConfig.InteractionMaxDistance
end

local function setupBowl(plot: Model)
	local bowl = plot:FindFirstChild("Bowl")
	if bowl == nil or not bowl:IsA("BasePart") then
		return
	end
	bowlParts[plot] = bowl
	setBowl(plot, 0)

	local existing = bowl:FindFirstChild(Economy.CollectPromptName)
	if existing then
		existing:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = Economy.CollectPromptName
	prompt.ActionText = Economy.CollectActionText
	prompt.KeyboardKeyCode = PlotPrompts.KeyCode
	prompt.GamepadKeyCode = PlotPrompts.GamepadKeyCode
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PlotPrompts.MaxDistance
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute(PlotPrompts.KindAttribute, PlotPrompts.Kinds.Collect)
	CollectionService:AddTag(prompt, Tags.PlotPrompt)
	prompt.Parent = bowl

	if Economy.TouchCollectEnabled then
		bowl.Touched:Connect(function(hit: BasePart)
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = if character then Players:GetPlayerFromCharacter(character) else nil
			if player and PlotService.GetOwner(plot) == player then
				EconomyService.Collect(player, false)
			end
		end)
	end
end

local function onPlayerAdded(player: Player)
	if coinValues[player] then
		return
	end
	local data = DataService.WaitForData(player)
	if data == nil or player.Parent ~= Players or coinValues[player] then
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = LEADERSTATS_NAME
	local value = Instance.new("NumberValue")
	value.Name = Economy.LeaderstatName
	value.Value = data.coins
	value.Parent = leaderstats
	leaderstats.Parent = player

	coinValues[player] = value
	player:SetAttribute(Economy.IncomeAttribute, 0)
end

local function onPlayerRemoving(player: Player)
	coinValues[player] = nil
	lastCollectAt[player] = nil
end

function EconomyService:Init(): ()
	coinsCollectedEvent = Network.GetEvent("CoinsCollected")
	for _, plot in PlotService.GetPlots() do
		setupBowl(plot)
	end
end

function EconomyService:Start(): ()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Plots are assigned only after data loads, so the saved bowl amount is available here.
	PlotService.PlotAssigned:Connect(function(player: Player, plot: Model)
		local data = DataService.GetData(player)
		setBowl(plot, if data then data.bowlCoins else 0)
	end)
	PlotService.PlotReleased:Connect(function(_player: Player, plot: Model)
		setBowl(plot, 0) -- runtime only; the save keeps the owner's bowl
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt.Name ~= Economy.CollectPromptName then
			return
		end
		local bowl = prompt.Parent
		local plot = if bowl then bowl:FindFirstAncestorOfClass("Model") else nil
		if plot and bowl and bowl:IsA("BasePart") and PlotService.GetOwner(plot) == player and isNear(player, bowl) then
			EconomyService.Collect(player, true)
		end
	end)

	while true do
		task.wait(GameConfig.IncomeTickInterval)
		incomeTick(GameConfig.IncomeTickInterval)
	end
end

return EconomyService

