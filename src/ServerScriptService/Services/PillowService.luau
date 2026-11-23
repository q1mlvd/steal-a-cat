--!strict
-- Placing cats on pillows, picking them up, taming, restoring saved cats, and the save side of stealing.
--
-- Ownership: a cat becomes owned (a record in the owner's save, keyed by UniqueId) the first time it is
-- placed. The record is kept current on every place / pick-up / tame. An owned cat that is carried by
-- its owner and dropped (death / reset / slap) goes back to a free pillow; on leave the save keeps it.
--
-- Stealing (see StealService for the gameplay side):
--   * BeginSteal: the cat leaves its pillow but the pillow stays RESERVED for it and the victim's save
--     record is unchanged (still on that pillow). Nothing is written to the thief's save.
--   * Thief places it in their own house: transferOwnership moves the record from the victim's save to
--     the thief's save in the same frame (no yields), then both profiles are saved immediately.
--   * Any other ending (slap, death, anti-cheat, leave) calls ReturnHome / RespawnFromSave, which only
--     re-seats the cat for its owner; the saves were never changed, so nothing can be lost or duplicated.
-- Seated cats live in PlotService:GetRuntimeFolder(plot) and are destroyed with the plot on leave
-- (that does NOT touch the save).
--
-- Pillows above the owner's pillowCount (Pillows upgrade) are locked: hidden, not collidable, not usable.
-- Cats without an unlocked free pillow are never deleted: they stay in the save as "waiting" (no Model)
-- and are seated when a pillow frees up (RefreshPlot after an upgrade, a stolen cat leaving, rejoin).

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = ReplicatedStorage.Shared.Config
local CatSchema = require(Config.CatSchema)
local CatSpawning = require(Config.CatSpawning)
local Cats = require(Config.Cats)
local Defense = require(Config.Defense)
local GameConfig = require(Config.Game)
local Loyalty = require(Config.Loyalty)
local Mutations = require(Config.Mutations)
local Pillows = require(Config.Pillows)
local PlotPrompts = require(Config.PlotPrompts)
local Plots = require(Config.Plots)
local Rarities = require(Config.Rarities)
local Tags = require(Config.Tags)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local DataSchema = require(ServerScriptService.Data.DataSchema)
local CarryService = require(script.Parent.CarryService)
local CatSpawnService = require(script.Parent.CatSpawnService)
local CatReturnNavigation = require(script.Parent.CatReturnNavigation)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local NotificationService = require(script.Parent.NotificationService)
local PlotService = require(script.Parent.PlotService)
local Monetization = require(Config.Monetization)

local ATTR = CatSchema.Attributes

type UnseatMode = "PickUp" | "Steal" | "Destroyed"

type Placement = {
	model: Model,
	pillow: BasePart,
	plot: Model,
	owner: Player,
	prompt: ProximityPrompt,
	destroyingConnection: RBXScriptConnection,
}

-- This ticket reserves source and destination while the save stays with sourceOwner.
export type LoyaltyReturnTicket = {
	model: Model,
	sourceOwner: Player,
	targetOwner: Player,
	sourcePlot: Model,
	targetPlot: Model,
	sourcePillow: BasePart,
	targetPillow: BasePart,
}

type LoyaltyReturnState = {
	ticket: LoyaltyReturnTicket,
	uniqueId: string,
	catId: string,
	destroyingConnection: RBXScriptConnection,
}

-- A newly caught, unowned cat has no save record until this delivery actually seats it.
export type FreshDeliveryTicket = {
	model: Model,
	owner: Player,
	plot: Model,
	pillow: BasePart,
	originalOwnerUserId: number,
}

type FreshDeliveryState = {
	ticket: FreshDeliveryTicket,
	uniqueId: string,
	catId: string,
	paid: boolean?, -- owned record is committed with the receipt before the physical route begins
	destroyingConnection: RBXScriptConnection,
}

local PillowService = {
	Priority = 60,

	-- (owner, model) after a cat is seated on a pillow.
	CatPlaced = Signal.new() :: Signal.Signal<Player, Model>,
	-- (model) after a cat leaves its pillow (picked up, stolen, or destroyed with the plot).
	CatUnplaced = Signal.new() :: Signal.Signal<Model>,
	-- (model) when taming finishes.
	CatTamed = Signal.new() :: Signal.Signal<Model>,
	-- (thief, victim, model) after a thief placed a stolen cat and ownership moved.
	CatStolen = Signal.new() :: Signal.Signal<Player, Player, Model>,
	-- (owner, model) after a stolen cat is back on its owner's pillow.
	CatReturnedHome = Signal.new() :: Signal.Signal<Player, Model>,
	-- (originalOwner, model) after a loyalty escape seated the cat back with its original owner.
	LoyaltyReturnCompleted = Signal.new() :: Signal.Signal<Player, Model>,
}

local pillowPlot: { [BasePart]: Model } = {}
local occupants: { [BasePart]: Model } = {} -- seated cat, or a stolen cat the pillow is reserved for
local placements: { [Model]: Placement } = {}
local reservations: { [Model]: BasePart } = {} -- stolen cat -> its owner's pillow
local loyaltyReturns: { [Model]: LoyaltyReturnState } = {}
local freshDeliveries: { [Model]: FreshDeliveryState } = {}
local lastActionAt: { [Player]: number } = {}
local stolenDropHandler: CarryService.DropHandler? = nil
local waiting: { [Player]: { [string]: true } } = {} -- saved cats with no Model, waiting for a pillow
local pillowTransparency: { [BasePart]: number } = {}

-- Helpers --------------------------------------------------------------------

local function makePrompt(parent: Instance, name: string, actionText: string, kind: PlotPrompts.Kind): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = actionText
	prompt.KeyboardKeyCode = PlotPrompts.KeyCode
	prompt.GamepadKeyCode = PlotPrompts.GamepadKeyCode
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PlotPrompts.MaxDistance
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute(PlotPrompts.KindAttribute, kind)
	CollectionService:AddTag(prompt, Tags.PlotPrompt)
	prompt.Parent = parent
	return prompt
end

local function getRootPosition(player: Player): Vector3?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function isNear(player: Player, part: BasePart): boolean
	local position = getRootPosition(player)
	return position ~= nil and (position - part.Position).Magnitude <= GameConfig.InteractionMaxDistance
end

local function throttle(player: Player): boolean
	local now = os.clock()
	if now - (lastActionAt[player] or 0) < Pillows.ActionCooldown then
		return false
	end
	lastActionAt[player] = now
	return true
end

local function catParts(model: Model): (BasePart?, Humanoid?)
	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return if root and root:IsA("BasePart") then root else nil, humanoid
end

local function catName(model: Model): string
	local catDef = Cats.Get(tostring(model:GetAttribute(ATTR.CatId)))
	return if catDef then catDef.name else "Cat"
end

local function uniqueIdOf(model: Model): string
	return tostring(model:GetAttribute(ATTR.UniqueId))
end

local function pillowIndexOf(pillow: BasePart): number
	local index = pillow:GetAttribute(Plots.PillowIndexAttribute)
	return if type(index) == "number" then index else math.huge
end

-- Pillows the player may use (index within their pillowCount), in index order.
local function usablePillows(plot: Model, data: DataSchema.PlayerData?): { BasePart }
	local limit = if data then data.pillowCount else GameConfig.StartingPillows
	local result = {}
	for _, pillow in PlotService.GetPillows(plot) do
		if pillowIndexOf(pillow) <= limit then
			table.insert(result, pillow)
		end
	end
	return result
end

local function firstFreePillow(plot: Model, data: DataSchema.PlayerData?): BasePart?
	for _, pillow in usablePillows(plot, data) do
		if occupants[pillow] == nil then
			return pillow
		end
	end
	return nil
end

-- Shows pillows 1..limit and hides/disables the rest (server-side, so every client agrees).
local function applyPillowLocks(plot: Model, limit: number)
	for _, pillow in PlotService.GetPillows(plot) do
		local locked = pillowIndexOf(pillow) > limit
		if locked then
			pillow.CanCollide = false
			pillow.CanQuery = false
			pillow.Transparency = Pillows.LockedTransparency
		else
			pillow.CanQuery = true
			pillow.CanCollide = true
			pillow.Transparency = pillowTransparency[pillow] or 0
		end
		pillow:SetAttribute(Pillows.LockedAttribute, if locked then true else nil)
	end
end

local function waitingCount(player: Player): number
	local count = 0
	for _ in waiting[player] or {} do
		count += 1
	end
	return count
end

local function notifyWaiting(player: Player)
	local count = waitingCount(player)
	if count > 0 and player.Parent == Players then
		NotificationService.Notify(player, `{count} {if count == 1 then "cat is" else "cats are"} waiting for a free pillow — safe in your save. Buy more Pillows in the shop!`, "Info")
	end
end

local function ownerOf(model: Model): Player?
	local ownerId = model:GetAttribute(ATTR.OwnerUserId)
	return if type(ownerId) == "number" and ownerId ~= CatSchema.WildOwnerUserId then Players:GetPlayerByUserId(ownerId) else nil
end

-- An owned cat (has a save record) whose current owner is this player.
local function isOwnedBy(player: Player, model: Model): boolean
	return model:GetAttribute(ATTR.OriginalOwnerUserId) ~= nil and model:GetAttribute(ATTR.OwnerUserId) == player.UserId
end

-- An owned cat that belongs to someone else (i.e. this player is carrying it as a thief).
local function isStolenBy(player: Player, model: Model): boolean
	local ownerId = model:GetAttribute(ATTR.OwnerUserId)
	return model:GetAttribute(ATTR.OriginalOwnerUserId) ~= nil
		and type(ownerId) == "number"
		and ownerId ~= CatSchema.WildOwnerUserId
		and ownerId ~= player.UserId
end

local function releaseReservation(model: Model)
	local pillow = reservations[model]
	if pillow then
		reservations[model] = nil
		if occupants[pillow] == model then
			occupants[pillow] = nil
			pillow:SetAttribute(Pillows.OccupiedAttribute, nil)
		end
	end
end

-- Seating --------------------------------------------------------------------

-- Remove a placement.
--   PickUp    - owner picked it up: save record leaves the pillow, taming pauses.
--   Steal     - a thief took it: the pillow stays reserved and the save record stays on it, taming pauses.
--   Destroyed - destroyed with the plot on leave: the save is not touched.
local function unseat(model: Model, mode: UnseatMode)
	local placement = placements[model]
	if placement == nil then
		return
	end
	placements[model] = nil
	placement.destroyingConnection:Disconnect()
	placement.prompt:Destroy()

	if mode == "Steal" then
		reservations[model] = placement.pillow -- occupants[pillow] stays = model
	else
		occupants[placement.pillow] = nil
		placement.pillow:SetAttribute(Pillows.OccupiedAttribute, nil)
	end

	local remaining: number? = nil
	local endsAt = model:GetAttribute(ATTR.TameEndsAt)
	if type(endsAt) == "number" then
		remaining = math.max(0, endsAt - workspace:GetServerTimeNow())
		model:SetAttribute(ATTR.TameRemaining, remaining)
		model:SetAttribute(ATTR.TameEndsAt, nil)
	end
	model:SetAttribute(ATTR.PillowIndex, nil)

	if mode ~= "Destroyed" then
		local data = DataService.GetData(placement.owner)
		local record = if data then data.cats[uniqueIdOf(model)] else nil
		if record then
			record.tameEndsAt = nil
			if remaining then
				record.tameRemaining = remaining
			end
			if mode == "PickUp" then
				record.pillowIndex = nil
			end
		end
	end

	PillowService.CatUnplaced:Fire(model)
end

local function seat(player: Player, model: Model, pillow: BasePart, plot: Model): boolean
	local root, humanoid = catParts(model)
	local runtime = PlotService.GetRuntimeFolder(plot)
	local catId = tostring(model:GetAttribute(ATTR.CatId))
	local rarity = Rarities.Get(tostring(model:GetAttribute(ATTR.Rarity)))
	if root == nil or humanoid == nil or runtime == nil or rarity == nil then
		return false
	end
	releaseReservation(model)

	-- Merge tier: Mega/Giga cats are bigger (scale before measuring the seat height).
	local tierData = DataService.GetData(player)
	local tierRecord = if tierData then tierData.cats[uniqueIdOf(model)] else nil
	local tier = Mutations.GetTier(if tierRecord then tierRecord.tier else model:GetAttribute(ATTR.Tier))
	if math.abs(model:GetScale() - tier.scale) > 1e-3 then
		model:ScaleTo(tier.scale)
	end
	model:SetAttribute(ATTR.Tier, tier.id)

	-- Sit still on the pillow: anchored, no Humanoid simulation, no collisions with players.
	root.Anchored = true
	root.CanCollide = false
	humanoid.EvaluateStateMachine = false
	local rootHeight = humanoid.HipHeight + root.Size.Y / 2
	local seatPosition = pillow.Position + Vector3.new(0, pillow.Size.Y / 2 + rootHeight, 0)
	model:PivotTo(CFrame.new(seatPosition) * pillow.CFrame.Rotation) -- faces the door like the pillow
	model.Parent = runtime

	local pillowIndex = pillowIndexOf(pillow)
	model:SetAttribute(ATTR.State, CatSchema.States.OnPillow)
	model:SetAttribute(ATTR.OwnerUserId, player.UserId)
	model:SetAttribute(ATTR.CarrierUserId, nil)
	model:SetAttribute(ATTR.PillowIndex, pillowIndex)

	local tamed = model:GetAttribute(ATTR.Tamed) == true
	local endsAt: number? = nil
	if not tamed then
		local remaining = model:GetAttribute(ATTR.TameRemaining)
		local seconds = if type(remaining) == "number" then remaining else rarity.tameTime
		endsAt = workspace:GetServerTimeNow() + seconds
		model:SetAttribute(ATTR.TameDuration, rarity.tameTime)
		model:SetAttribute(ATTR.TameEndsAt, endsAt)
		model:SetAttribute(ATTR.TameRemaining, nil)
	end

	-- Save record: created the first time a cat is placed (that's when it becomes owned).
	local data = DataService.GetData(player)
	if data then
		local uniqueId = uniqueIdOf(model)
		local record = data.cats[uniqueId]
		if record == nil then
			local originalId = model:GetAttribute(ATTR.OriginalOwnerUserId)
			local firstOwnerId = if type(originalId) == "number" and originalId ~= CatSchema.WildOwnerUserId
				then originalId else player.UserId
			record = DataSchema.NewCatRecord(catId, firstOwnerId, rarity.tameTime)
			-- A wild cat's rolled mutation becomes part of its first record.
			local rolled = model:GetAttribute(ATTR.Mutation)
			record.mutation = if type(rolled) == "string" and Mutations.IsValid(rolled) then rolled else ""
			-- Eternal Loyalty pass: a cat this player caught starts loyal (also Laser deliveries).
			if firstOwnerId == player.UserId and MonetizationService.OwnsPass(player, "EternalLoyalty") then
				record.loyalty = Monetization.EternalLoyaltyStart
			end
			data.cats[uniqueId] = record
		end
		record.pillowIndex = pillowIndex
		record.tamed = tamed
		record.tameEndsAt = endsAt
		if endsAt then
			record.tameRemaining = math.max(0, endsAt - workspace:GetServerTimeNow())
		elseif tamed then
			record.tameRemaining = 0
		end
		model:SetAttribute(ATTR.OriginalOwnerUserId, record.originalOwnerUserId)
		model:SetAttribute(ATTR.Mutation, record.mutation)
		model:SetAttribute(ATTR.Loyalty, record.loyalty)
		model:SetAttribute(ATTR.TimesReturned, record.timesReturned)
		model:SetAttribute(Defense.BellAttribute, if record.bell then true else nil)
		model:SetAttribute(ATTR.PetAvailableAt, record.lastPetAt + Loyalty.PetCooldown)
	end

	occupants[pillow] = model
	pillow:SetAttribute(Pillows.OccupiedAttribute, true)
	placements[model] = {
		model = model,
		pillow = pillow,
		plot = plot,
		owner = player,
		prompt = makePrompt(root, Pillows.PickUpPromptName, Pillows.PickUpActionText, PlotPrompts.Kinds.PickUp),
		-- The plot's Runtime folder is cleared when the owner leaves; that destroys the cat (save untouched).
		destroyingConnection = model.Destroying:Connect(function()
			unseat(model, "Destroyed")
		end),
	}

	PillowService.CatPlaced:Fire(player, model)
	return true
end

-- Moves a stolen cat's record from the victim's save to the thief's save. Same frame, no yields:
-- in memory the cat is never in both saves or in neither. Returns false (nothing changed) if either
-- save isn't available, e.g. the victim is leaving right now.
local function transferOwnership(victim: Player?, thief: Player, model: Model): boolean
	if victim == nil then
		return false
	end
	local victimData = DataService.GetData(victim)
	local thiefData = DataService.GetData(thief)
	local uniqueId = uniqueIdOf(model)
	local record = if victimData then victimData.cats[uniqueId] else nil
	local rarity = Rarities.Get(tostring(model:GetAttribute(ATTR.Rarity)))
	if victimData == nil or thiefData == nil or record == nil or rarity == nil or thiefData.cats[uniqueId] ~= nil then
		return false
	end

	-- Preserve every per-cat field, including pet cooldown and future mutations.
	local transferred = table.clone(record)
	transferred.tamed = false -- untamed again for the new owner
	transferred.tameRemaining = rarity.tameTime
	transferred.tameEndsAt = nil
	transferred.pillowIndex = nil -- set by seat()
	thiefData.cats[uniqueId] = transferred
	victimData.cats[uniqueId] = nil
	victimData.stats.catsLostToThieves += 1
	thiefData.stats.catsStolen += 1

	releaseReservation(model)
	model:SetAttribute(ATTR.OwnerUserId, thief.UserId)
	model:SetAttribute(ATTR.Tamed, nil)
	model:SetAttribute(ATTR.TameRemaining, nil)
	return true
end

-- Actions ----------------------------------------------------------------------

local function tryPlace(player: Player, pillow: BasePart)
	local plot = pillowPlot[pillow]
	if plot == nil or not throttle(player) then
		return
	end
	if PlotService.GetOwner(plot) ~= player then
		NotificationService.Notify(player, "This isn't your house!", "Error")
		return
	end
	local data = DataService.GetData(player)
	if occupants[pillow] or not isNear(player, pillow) or not table.find(usablePillows(plot, data), pillow) then
		return
	end
	local carried = CarryService.GetCarried(player)
	local model = carried[#carried]
	if model == nil then
		NotificationService.Notify(player, "Catch a cat first!", "Error")
		return
	end

	local victim: Player? = nil
	if isStolenBy(player, model) then
		victim = ownerOf(model)
		if not transferOwnership(victim, player, model) then
			NotificationService.Notify(player, "You can't place this cat right now.", "Error")
			return
		end
	end

	if not CarryService.Release(player, model) then
		return
	end
	if not seat(player, model, pillow, plot) then
		CarryService.PickUp(player, model) -- never leave a cat floating detached
		return
	end

	if victim then
		-- Write both saves now (thief first: if the server died between the two writes the cat would be
		-- in both saves rather than in neither - see the Stage 7 report).
		DataService.SaveNow(player)
		DataService.SaveNow(victim)
		PillowService.CatStolen:Fire(player, victim, model)
		-- The victim's reserved pillow is free now: a waiting cat may take it.
		local victimPlayer = victim :: Player
		task.defer(function()
			PillowService.RefreshPlot(victimPlayer)
		end)
	end
end

local function tryPickUp(player: Player, model: Model)
	local placement = placements[model]
	if placement == nil or not throttle(player) then
		return
	end
	if PlotService.GetOwner(placement.plot) ~= player or model:GetAttribute(ATTR.OwnerUserId) ~= player.UserId then
		return -- other players use the Steal prompt (StealService)
	end
	if not CarryService.CanCarry(player) then
		NotificationService.Notify(player, "Your hands are full!", "Error")
		return
	end
	local root = catParts(model)
	if root == nil or not isNear(player, root) then
		return
	end

	local pillow, plot = placement.pillow, placement.plot
	unseat(model, "PickUp")
	if not CarryService.PickUp(player, model) then
		seat(player, model, pillow, plot) -- put it back
	end
end

-- Carrier died / reset / was slapped / left.
local function onCatDropped(player: Player, model: Model, leaving: boolean): boolean
	if isStolenBy(player, model) then
		if stolenDropHandler then
			return stolenDropHandler(player, model, leaving)
		end
		PillowService.ReturnHome(model)
		return true
	end
	if not isOwnedBy(player, model) then
		return false -- e.g. a wild cat just caught: back to the wild
	end
	if leaving or player.Parent ~= Players then
		model:Destroy() -- the save keeps the record; it gets a free pillow at next join
		return true
	end

	local plot = PlotService.GetPlot(player)
	local data = DataService.GetData(player)
	local pillow = if plot then firstFreePillow(plot, data) else nil
	if plot and pillow and seat(player, model, pillow, plot) then
		return true
	end

	-- Nowhere to put it: the record stays in the save (pillowIndex nil) and the Model goes away, exactly like
	-- leaving while carrying it. It is seated again as soon as a pillow frees up. Never deleted, never wild.
	local uniqueId = uniqueIdOf(model)
	if data == nil or data.cats[uniqueId] == nil then
		return false
	end
	model:Destroy()
	local set = waiting[player] or {}
	waiting[player] = set
	set[uniqueId] = true
	notifyWaiting(player)
	return true
end

-- Restore --------------------------------------------------------------------

local function restoreOne(player: Player, plot: Model, pillow: BasePart, uniqueId: string, record: DataSchema.CatRecord): Model?
	local model = CatSpawnService.CreateCatModel(record.catId, uniqueId)
	if model == nil then
		warn(`[PillowService] {player.Name} has unknown cat "{record.catId}" ({uniqueId}); kept in save, not spawned`)
		return nil
	end
	model:SetAttribute(ATTR.Tamed, if record.tamed then true else nil)
	model:SetAttribute(ATTR.TameRemaining, if record.tamed then nil else record.tameRemaining)
	if not seat(player, model, pillow, plot) then
		model:Destroy()
		return nil
	end
	return model
end

local function restoreCats(player: Player, plot: Model)
	local data = DataService.GetData(player)
	if data == nil then
		return
	end

	local byIndex: { [number]: BasePart } = {}
	for _, pillow in usablePillows(plot, data) do
		byIndex[pillowIndexOf(pillow)] = pillow
	end

	-- First the cats that remember their pillow, then the rest (carried at leave, or pillow taken) in a stable order.
	local unseated: { string } = {}
	for uniqueId, record in data.cats do
		record.tameEndsAt = nil -- session-only value from a previous session
		local pillow = if record.pillowIndex then byIndex[record.pillowIndex] else nil
		if pillow and occupants[pillow] == nil then
			restoreOne(player, plot, pillow, uniqueId, record)
		else
			table.insert(unseated, uniqueId)
		end
	end
	table.sort(unseated)
	local set: { [string]: true } = {}
	for _, uniqueId in unseated do
		local pillow = firstFreePillow(plot, data)
		if pillow == nil then
			set[uniqueId] = true -- kept in the save, seated when a pillow frees up
			continue
		end
		restoreOne(player, plot, pillow, uniqueId, data.cats[uniqueId])
	end
	waiting[player] = set
	if next(set) ~= nil then
		task.delay(Pillows.WaitingNoticeDelay, notifyWaiting, player)
	end
end

-- Seats waiting cats (saved, no Model) on free unlocked pillows. Returns how many were seated.
local function seatWaiting(player: Player): number
	local set = waiting[player]
	local plot = PlotService.GetPlot(player)
	local data = DataService.GetData(player)
	if set == nil or plot == nil or data == nil or PlotService.GetOwner(plot) ~= player then
		return 0
	end
	local ids: { string } = {}
	for uniqueId in set do
		table.insert(ids, uniqueId)
	end
	table.sort(ids)
	local seated = 0
	for _, uniqueId in ids do
		local record = data.cats[uniqueId]
		if record == nil then
			set[uniqueId] = nil -- no longer this player's cat
			continue
		end
		local pillow = firstFreePillow(plot, data)
		if pillow == nil then
			break
		end
		set[uniqueId] = nil
		if restoreOne(player, plot, pillow, uniqueId, record) then
			seated += 1
		end
	end
	return seated
end

local function tameTick()
	local now = workspace:GetServerTimeNow()
	for model, placement in placements do
		local endsAt = model:GetAttribute(ATTR.TameEndsAt)
		if type(endsAt) == "number" and now >= endsAt then
			model:SetAttribute(ATTR.Tamed, true)
			model:SetAttribute(ATTR.TameEndsAt, nil)
			model:SetAttribute(ATTR.TameRemaining, nil)

			local data = DataService.GetData(placement.owner)
			local record = if data then data.cats[uniqueIdOf(model)] else nil
			if record then
				record.tamed = true
				record.tameRemaining = 0
				record.tameEndsAt = nil
			end

			PillowService.CatTamed:Fire(model)
			NotificationService.Notify(placement.owner, `{catName(model)} is now tamed!`, "Success")
		end
	end
end

local function forgetLoyaltyReturn(ticket: LoyaltyReturnTicket, releaseTarget: boolean): boolean
	local state = loyaltyReturns[ticket.model]
	if state == nil or state.ticket ~= ticket then
		return false
	end
	loyaltyReturns[ticket.model] = nil
	state.destroyingConnection:Disconnect()
	if releaseTarget and occupants[ticket.targetPillow] == ticket.model then
		occupants[ticket.targetPillow] = nil
		ticket.targetPillow:SetAttribute(Pillows.OccupiedAttribute, nil)
	end
	return true
end

-- Mirrors every prerequisite used by seat(), with ownership and capacity checks as well.
-- This is deliberately synchronous: validation, record move, and seating share one frame.
local function canSeatReturn(player: Player, model: Model, pillow: BasePart, plot: Model,
	data: DataSchema.PlayerData, expectedOccupant: Model?): boolean
	local root, humanoid = catParts(model)
	local runtime = PlotService.GetRuntimeFolder(plot)
	return player.Parent == Players
		and PlotService.GetPlot(player) == plot and PlotService.GetOwner(plot) == player
		and plot:IsDescendantOf(workspace) and pillowPlot[pillow] == plot
		and pillow:IsDescendantOf(plot) and table.find(usablePillows(plot, data), pillow) ~= nil
		and occupants[pillow] == expectedOccupant
		and model:IsDescendantOf(workspace) and root ~= nil and humanoid ~= nil
		and runtime ~= nil and runtime:IsDescendantOf(plot)
		and Rarities.Get(tostring(model:GetAttribute(ATTR.Rarity))) ~= nil
end

local function cancelLoyaltyReturn(ticket: LoyaltyReturnTicket, sourceLeaving: boolean, lostModel: boolean)
	local state = loyaltyReturns[ticket.model]
	if state == nil or state.ticket ~= ticket then
		return
	end
	if not forgetLoyaltyReturn(ticket, true) then
		return
	end
	local model = ticket.model
	-- A leaving owner's save already contains this cat on its source pillow. Never move it.
	local sourceData = DataService.GetData(ticket.sourceOwner)
	if sourceLeaving or ticket.sourceOwner.Parent ~= Players or sourceData == nil
		or PlotService.GetPlot(ticket.sourceOwner) ~= ticket.sourcePlot then
		releaseReservation(model)
		if not lostModel then
			model:Destroy()
		end
		return
	end
	-- Identity belongs to the ticket even if a model attribute was unexpectedly changed in transit.
	model:SetAttribute(ATTR.UniqueId, state.uniqueId)
	model:SetAttribute(ATTR.CatId, state.catId)
	model:SetAttribute(ATTR.OwnerUserId, ticket.sourceOwner.UserId)
	if lostModel or model.Parent == nil then
		PillowService.RespawnFromSave(model)
	else
		PillowService.ReturnHome(model)
	end
end

local function forgetFreshDelivery(ticket: FreshDeliveryTicket, releasePillow: boolean): boolean
	local state = freshDeliveries[ticket.model]
	if state == nil or state.ticket ~= ticket then
		return false
	end
	freshDeliveries[ticket.model] = nil
	state.destroyingConnection:Disconnect()
	if releasePillow and occupants[ticket.pillow] == ticket.model then
		occupants[ticket.pillow] = nil
		ticket.pillow:SetAttribute(Pillows.OccupiedAttribute, nil)
	end
	return true
end

local function freshIdentityIsUnowned(uniqueId: string): boolean
	-- A fresh delivery must never invent a second copy of a cat that has a live save record.
	for _, player in Players:GetPlayers() do
		local data = DataService.GetData(player)
		if data and data.cats[uniqueId] ~= nil then
			return false
		end
	end
	return true
end

local function playerIsAlive(player: Player): boolean
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return humanoid ~= nil and humanoid.Health > 0
end

-- Public API -----------------------------------------------------------------

-- Called by ItemService before consuming a Bell. Equipping and the inventory decrement are
-- synchronous; the single existing record carries the Bell through theft and loyalty transfers.
function PillowService.EquipBell(player: Player, model: Model): boolean
	local placement = placements[model]
	local uniqueId = model:GetAttribute(ATTR.UniqueId)
	local data = DataService.GetData(player)
	local root = catParts(model)
	local position = getRootPosition(player)
	if player.Parent ~= Players or not playerIsAlive(player) or placement == nil
		or placement.owner ~= player or PlotService.GetPlot(player) ~= placement.plot
		or PlotService.GetOwner(placement.plot) ~= player
		or model:GetAttribute(ATTR.State) ~= CatSchema.States.OnPillow
		or model:GetAttribute(ATTR.OwnerUserId) ~= player.UserId
		or type(uniqueId) ~= "string" or uniqueId == "" or data == nil
		or root == nil or position == nil or (position - root.Position).Magnitude > Defense.BellEquipDistance
		or not model:IsDescendantOf(workspace) or loyaltyReturns[model] ~= nil then
		return false
	end
	local record = data.cats[uniqueId]
	if record == nil or record.bell == true or record.catId ~= model:GetAttribute(ATTR.CatId)
		or record.pillowIndex ~= pillowIndexOf(placement.pillow) then
		return false
	end
	for _, otherPlayer in Players:GetPlayers() do
		local otherData = if otherPlayer ~= player then DataService.GetData(otherPlayer) else nil
		if otherData and otherData.cats[uniqueId] ~= nil then
			return false -- never alter an ambiguous saved identity
		end
	end
	record.bell = true
	model:SetAttribute(Defense.BellAttribute, true)
	DataService.SaveNow(player)
	return true
end

-- Re-applies the owner's unlocked pillow count to their house and seats waiting cats on free pillows.
-- Call after pillowCount changes (UpgradeService). Returns how many waiting cats were seated.
function PillowService.RefreshPlot(player: Player): number
	local plot = PlotService.GetPlot(player)
	local data = DataService.GetData(player)
	if plot == nil or data == nil or PlotService.GetOwner(plot) ~= player then
		return 0
	end
	applyPillowLocks(plot, data.pillowCount)
	-- Pillows can only shrink if a pass was revoked: their cats wait in the save (never deleted).
	local set = waiting[player] or {}
	waiting[player] = set
	for model, placement in table.clone(placements) do
		if placement.owner == player and placement.plot == plot and pillowIndexOf(placement.pillow) > data.pillowCount then
			local uniqueId = uniqueIdOf(model)
			unseat(model, "PickUp")
			model:Destroy()
			if data.cats[uniqueId] then
				set[uniqueId] = true
			end
		end
	end
	local seated = seatWaiting(player)
	if seated > 0 then
		NotificationService.Notify(player, `{seated} waiting {if seated == 1 then "cat" else "cats"} moved onto a free pillow!`, "Success")
	end
	return seated
end

-- Merges MergeCount seated cats of this player with the same CatId and tier into one cat of the next tier.
-- Only the player's own cats on their own unlocked pillows, never stolen/returning/carried/in transit.
-- Inputs are removed and the result record added in ONE no-yield update, then the save is requested.
-- The result: best input mutation, average loyalty, OriginalOwnerUserId = this player, sits on the first
-- input's pillow. Returns (ok, message, resultModel).
function PillowService.MergeCats(player: Player, catId: string, tierId: string): (boolean, string, Model?)
	local plot = PlotService.GetPlot(player)
	local data = DataService.GetData(player)
	local catDef = Cats.Get(catId)
	local rarity = if catDef then Rarities.Get(catDef.rarity) else nil
	local nextTier = Mutations.NextTier(tierId)
	if plot == nil or data == nil or catDef == nil or rarity == nil or PlotService.GetOwner(plot) ~= player then
		return false, "You can't merge right now.", nil
	end
	if nextTier == nil then
		return false, "Giga cats can't be merged further.", nil
	end
	local usable = usablePillows(plot, data)
	local inputs: { { model: Model, placement: Placement, uniqueId: string, record: DataSchema.CatRecord } } = {}
	for model, placement in placements do
		local uniqueId = uniqueIdOf(model)
		local record = data.cats[uniqueId]
		if placement.owner == player and placement.plot == plot and record ~= nil
			and model:GetAttribute(ATTR.State) == CatSchema.States.OnPillow
			and model:GetAttribute(ATTR.OwnerUserId) == player.UserId
			and model:GetAttribute(ATTR.CatId) == catId and record.catId == catId
			and Mutations.GetTier(record.tier).id == tierId
			and record.pillowIndex == pillowIndexOf(placement.pillow)
			and table.find(usable, placement.pillow) ~= nil
			and loyaltyReturns[model] == nil and freshDeliveries[model] == nil and reservations[model] == nil then
			table.insert(inputs, { model = model, placement = placement, uniqueId = uniqueId, record = record })
		end
	end
	if #inputs < Mutations.MergeCount then
		return false, `You need {Mutations.MergeCount} {tierId} {catDef.name} cats on your pillows.`, nil
	end
	table.sort(inputs, function(a, b): boolean
		return pillowIndexOf(a.placement.pillow) < pillowIndexOf(b.placement.pillow)
	end)
	for index = #inputs, Mutations.MergeCount + 1, -1 do
		table.remove(inputs, index)
	end
	for _, input in inputs do
		for _, other in Players:GetPlayers() do
			local otherData = if other ~= player then DataService.GetData(other) else nil
			if otherData and otherData.cats[input.uniqueId] ~= nil then
				return false, "One of these cats can't be merged right now.", nil -- ambiguous identity
			end
		end
	end

	-- Result record (built before touching anything).
	local mutation = ""
	local loyaltySum, lastPetAt, bell, allTamed = 0, 0, false, true
	for _, input in inputs do
		mutation = Mutations.Best(mutation, input.record.mutation)
		loyaltySum += input.record.loyalty
		lastPetAt = math.max(lastPetAt, input.record.lastPetAt)
		bell = bell or input.record.bell == true
		allTamed = allTamed and input.record.tamed
	end
	local result = DataSchema.NewCatRecord(catId, player.UserId, rarity.tameTime)
	result.mutation = mutation
	result.tier = nextTier.id
	result.loyalty = math.floor(loyaltySum / #inputs)
	result.lastPetAt = lastPetAt
	result.bell = bell
	result.tamed = allTamed
	result.tameRemaining = if allTamed then 0 else rarity.tameTime
	local pillow = inputs[1].placement.pillow
	result.pillowIndex = pillowIndexOf(pillow)
	local resultId = HttpService:GenerateGUID(false)

	-- One frame, no yields: remove inputs, add result.
	for _, input in inputs do
		data.cats[input.uniqueId] = nil
	end
	data.cats[resultId] = result
	for _, input in inputs do
		unseat(input.model, "Destroyed") -- frees the pillow; the save was already updated above
		input.model:Destroy()
	end
	local model = restoreOne(player, plot, pillow, resultId, result)
	if model == nil then
		-- Could not build the Model: the single record is safe in the save and waits for a pillow.
		local set = waiting[player] or {}
		waiting[player] = set
		set[resultId] = true
	end
	DataService.SaveNow(player)
	return true, `Merged into a {nextTier.displayName} {catDef.name}!`, model
end

-- Cats this player could merge: {catId, tier, count, mutation (best)} for every seated group.
function PillowService.GetMergeGroups(player: Player): { { catId: string, tier: string, count: number, mutation: string } }
	local plot = PlotService.GetPlot(player)
	local data = DataService.GetData(player)
	local groups: { [string]: { catId: string, tier: string, count: number, mutation: string } } = {}
	if plot == nil or data == nil then
		return {}
	end
	for model, placement in placements do
		local record = data.cats[uniqueIdOf(model)]
		if placement.owner == player and placement.plot == plot and record
			and model:GetAttribute(ATTR.State) == CatSchema.States.OnPillow
			and loyaltyReturns[model] == nil and reservations[model] == nil then
			local tier = Mutations.GetTier(record.tier).id
			local key = record.catId .. "|" .. tier
			local group = groups[key] or { catId = record.catId, tier = tier, count = 0, mutation = "" }
			group.count += 1
			group.mutation = Mutations.Best(group.mutation, record.mutation)
			groups[key] = group
		end
	end
	local list = {}
	for _, group in groups do
		table.insert(list, group)
	end
	table.sort(list, function(a, b): boolean
		if a.count ~= b.count then return a.count > b.count end
		return a.catId < b.catId
	end)
	return list
end

-- True while any cat of this player is away from its pillow in a tracked flow: stolen (reserved pillow),
-- loyalty-returning (either side), Laser delivery, or carried by this player.
function PillowService.HasCatsInTransit(player: Player): boolean
	if #CarryService.GetCarried(player) > 0 then
		return true
	end
	for _, pillow in reservations do
		if pillowPlot[pillow] == PlotService.GetPlot(player) then
			return true
		end
	end
	for _, state in loyaltyReturns do
		if state.ticket.sourceOwner == player or state.ticket.targetOwner == player then
			return true
		end
	end
	for _, state in freshDeliveries do
		if state.ticket.owner == player then
			return true
		end
	end
	return false
end

-- Seated cats of this player (for the rebirth keep list): {uniqueId, catId, tier, mutation}.
function PillowService.GetSeatedCats(player: Player): { { uniqueId: string, catId: string, tier: string, mutation: string } }
	local data = DataService.GetData(player)
	local result = {}
	if data == nil then
		return result
	end
	for model, placement in placements do
		local uniqueId = uniqueIdOf(model)
		local record = data.cats[uniqueId]
		if placement.owner == player and record then
			table.insert(result, { uniqueId = uniqueId, catId = record.catId, tier = Mutations.GetTier(record.tier).id, mutation = record.mutation })
		end
	end
	return result
end

-- Rebirth (called by RebirthService inside its single no-yield update): every cat record of this player
-- except `keep` is removed together with its Model; waiting entries are cleared. Kept records lose their
-- pillow index so they are re-seated on the (reset) unlocked pillows by RefreshPlot.
function PillowService.ApplyRebirth(player: Player, keep: { [string]: true }): number
	local data = DataService.GetData(player)
	if data == nil then
		return 0
	end
	local removed = 0
	for model, placement in table.clone(placements) do
		if placement.owner == player then
			local uniqueId = uniqueIdOf(model)
			unseat(model, if keep[uniqueId] then "PickUp" else "Destroyed")
			model:Destroy()
		end
	end
	for uniqueId in table.clone(data.cats) do
		if not keep[uniqueId] then
			data.cats[uniqueId] = nil
			removed += 1
		end
	end
	local set: { [string]: true } = {}
	for uniqueId in keep do
		if data.cats[uniqueId] then
			data.cats[uniqueId].pillowIndex = nil
			set[uniqueId] = true -- re-seated by RefreshPlot
		end
	end
	waiting[player] = set
	return removed
end

-- Untamed cats currently seated in this player's house.
function PillowService.CountUntamed(player: Player): number
	local count = 0
	for model, placement in placements do
		if placement.owner == player and type(model:GetAttribute(ATTR.TameEndsAt)) == "number" then
			count += 1
		end
	end
	return count
end

-- Instant Tame: finishes taming of every untamed seated cat of this player (records + Models). No yields.
function PillowService.FinishTaming(player: Player): number
	local data = DataService.GetData(player)
	local count = 0
	for model, placement in placements do
		if placement.owner == player and type(model:GetAttribute(ATTR.TameEndsAt)) == "number" then
			model:SetAttribute(ATTR.Tamed, true)
			model:SetAttribute(ATTR.TameEndsAt, nil)
			model:SetAttribute(ATTR.TameRemaining, nil)
			local record = if data then data.cats[uniqueIdOf(model)] else nil
			if record then
				record.tamed = true
				record.tameRemaining = 0
				record.tameEndsAt = nil
			end
			PillowService.CatTamed:Fire(model)
			count += 1
		end
	end
	return count
end

-- A brand-new owned cat (Cat Box, daily reward...) seated straight onto a free unlocked pillow. Uses the
-- normal first-record path (seat creates the single record). Never creates a record without a pillow.
-- No yields. Returns the Model, or nil when there is no free pillow.
function PillowService.GrantNewCat(player: Player, catId: string): Model?
	local plot = PlotService.GetPlot(player)
	local data = DataService.GetData(player)
	local pillow = if plot and data then firstFreePillow(plot, data) else nil
	if plot == nil or data == nil or pillow == nil or PlotService.GetOwner(plot) ~= player or Cats.Get(catId) == nil then
		return nil
	end
	local model = CatSpawnService.CreateCatModel(catId, HttpService:GenerateGUID(false))
	if model == nil then
		return nil
	end
	model:SetAttribute(ATTR.OriginalOwnerUserId, player.UserId)
	if not seat(player, model, pillow, plot) then
		model:Destroy()
		return nil
	end
	return model
end

-- Paid deliveries commit one owned record and reserve its pillow in the receipt's no-yield frame.
-- They walk through the same fresh route, but never become wild on a failed route or disconnect.
function PillowService.GrantFreshPaidCat(player: Player, catId: string): Model?
	local plot = PlotService.GetPlot(player)
	local data = DataService.GetData(player)
	local definition = Cats.Get(catId)
	local pillow = if plot and data then firstFreePillow(plot, data) else nil
	if player.Parent ~= Players or not playerIsAlive(player) or plot == nil or data == nil or pillow == nil
		or PlotService.GetOwner(plot) ~= player or definition == nil then return nil end
	local model = CatSpawnService.CreateCatModel(catId, HttpService:GenerateGUID(false))
	if model == nil then return nil end
	model:SetAttribute(ATTR.OriginalOwnerUserId, player.UserId)
	if type((definition :: any).defaultMutation) == "string" then model:SetAttribute(ATTR.Mutation, (definition :: any).defaultMutation) end
	if not seat(player, model, pillow, plot) then model:Destroy() return nil end
	local uniqueId = uniqueIdOf(model)
	unseat(model, "PickUp")
	data.cats[uniqueId].pillowIndex = pillowIndexOf(pillow)
	occupants[pillow] = model
	pillow:SetAttribute(Pillows.OccupiedAttribute, true)
	local ticket: FreshDeliveryTicket = table.freeze({model=model,owner=player,plot=plot,pillow=pillow,originalOwnerUserId=player.UserId})
	freshDeliveries[model] = {
		ticket=ticket, uniqueId=uniqueId, catId=catId, paid=true,
		destroyingConnection=model.Destroying:Connect(function()
			forgetFreshDelivery(ticket, true)
			if DataService.GetData(player) and player.Parent == Players then
				local set=waiting[player] or {} waiting[player]=set set[uniqueId]=true
				task.defer(function() seatWaiting(player) end)
			end
		end),
	}
	model:SetAttribute(ATTR.State, CatSchema.States.Returning)
	local door = plot:FindFirstChild("Door")
	if door and door:IsA("BasePart") then
		model:PivotTo(door.CFrame + door.CFrame.LookVector * Loyalty.Return.DoorOffset + Vector3.new(0, -door.Size.Y/2 + Pillows.PaidDeliveryLift, 0))
	end
	model.Parent = CatReturnNavigation.GetReturningFolder()
	task.defer(function()
		local function active():boolean return freshDeliveries[model] ~= nil and player.Parent == Players and DataService.GetData(player) ~= nil end
		local function finish()
			if not active() then return end
			if not PillowService.CompleteFreshDelivery(ticket) then
				local set=waiting[player] or {} waiting[player]=set set[uniqueId]=true
				model:Destroy() seatWaiting(player)
			end
		end
		if active() then CatReturnNavigation.Run(model,nil,plot,pillow.Position,active,finish,finish) end
	end)
	return model
end

-- Free unlocked pillows in this player's house (also mirrored as a player attribute for store UI).
function PillowService.CountFreePillows(player: Player): number
	local plot = PlotService.GetPlot(player)
	local data = DataService.GetData(player)
	if plot == nil or data == nil then
		return 0
	end
	local count = 0
	for _, pillow in usablePillows(plot, data) do
		if occupants[pillow] == nil then
			count += 1
		end
	end
	return count
end

-- Saved cats that currently have no pillow (and no Model).
function PillowService.GetWaitingCount(player: Player): number
	return waitingCount(player)
end

-- Studio test profile only (refused otherwise): adds one saved cat for this player, seated on a free
-- unlocked pillow or left waiting. Returns its UniqueId.
function PillowService.DebugAddCat(player: Player, catId: string): string?
	local plot = PlotService.GetPlot(player)
	local data = DataService.GetData(player)
	local catDef = Cats.Get(catId)
	local rarity = if catDef then Rarities.Get(catDef.rarity) else nil
	if not DataService.IsStudioTestProfile() or plot == nil or data == nil or catDef == nil or rarity == nil then
		return nil
	end
	local uniqueId = HttpService:GenerateGUID(false)
	data.cats[uniqueId] = DataSchema.NewCatRecord(catId, player.UserId, rarity.tameTime)
	local pillow = firstFreePillow(plot, data)
	if pillow then
		restoreOne(player, plot, pillow, uniqueId, data.cats[uniqueId])
	else
		local set = waiting[player] or {}
		waiting[player] = set
		set[uniqueId] = true
	end
	return uniqueId
end

function PillowService.GetFreePillow(player: Player): BasePart?
	local plot = PlotService.GetPlot(player)
	local data = DataService.GetData(player)
	return if player.Parent == Players and plot and data then firstFreePillow(plot, data) else nil
end

function PillowService.IsFreshDelivering(model: Model): boolean
	return freshDeliveries[model] ~= nil
end

-- Reserve capacity and detach in one frame. No save is touched while a fresh cat walks home.
function PillowService.BeginFreshDelivery(player: Player, model: Model): FreshDeliveryTicket?
	local uniqueId = model:GetAttribute(ATTR.UniqueId)
	local catId = model:GetAttribute(ATTR.CatId)
	local originalId = model:GetAttribute(ATTR.OriginalOwnerUserId)
	local plot = PlotService.GetPlot(player)
	local data = DataService.GetData(player)
	local pillow = if plot and data then firstFreePillow(plot, data) else nil
	if type(uniqueId) ~= "string" or uniqueId == "" or type(catId) ~= "string" or Cats.Get(catId) == nil
		or type(originalId) ~= "number" or originalId ~= originalId or math.abs(originalId) == math.huge
		or originalId == CatSchema.WildOwnerUserId or originalId % 1 ~= 0
		or plot == nil or data == nil or pillow == nil or not playerIsAlive(player)
		or freshDeliveries[model] ~= nil or loyaltyReturns[model] ~= nil
		or model:GetAttribute(ATTR.State) ~= CatSchema.States.Carried
		or model:GetAttribute(ATTR.OwnerUserId) ~= CatSchema.WildOwnerUserId
		or model:GetAttribute(ATTR.CarrierUserId) ~= player.UserId
		or table.find(CarryService.GetCarried(player), model) == nil
		or not freshIdentityIsUnowned(uniqueId)
		or not canSeatReturn(player, model, pillow, plot, data, nil) then
		return nil
	end
	local ticket: FreshDeliveryTicket = table.freeze({
		model = model,
		owner = player,
		plot = plot,
		pillow = pillow,
		originalOwnerUserId = originalId,
	})
	occupants[pillow] = model
	pillow:SetAttribute(Pillows.OccupiedAttribute, true)
	if not CarryService.Release(player, model) then
		occupants[pillow] = nil
		pillow:SetAttribute(Pillows.OccupiedAttribute, nil)
		return nil
	end
	freshDeliveries[model] = {
		ticket = ticket,
		uniqueId = uniqueId,
		catId = catId,
		destroyingConnection = model.Destroying:Connect(function()
			forgetFreshDelivery(ticket, true)
		end),
	}
	model:SetAttribute(ATTR.State, CatSchema.States.Returning)
	return ticket
end

function PillowService.CompleteFreshDelivery(ticket: FreshDeliveryTicket): boolean
	local model = ticket.model
	local state = freshDeliveries[model]
	local data = DataService.GetData(ticket.owner)
	if state == nil or state.ticket ~= ticket or data == nil or (not state.paid and not playerIsAlive(ticket.owner))
		or model:GetAttribute(ATTR.UniqueId) ~= state.uniqueId or model:GetAttribute(ATTR.CatId) ~= state.catId
		or model:GetAttribute(ATTR.State) ~= CatSchema.States.Returning
		or model:GetAttribute(ATTR.OwnerUserId) ~= (if state and state.paid then ticket.owner.UserId else CatSchema.WildOwnerUserId)
		or model:GetAttribute(ATTR.OriginalOwnerUserId) ~= ticket.originalOwnerUserId
		or model:GetAttribute(ATTR.CarrierUserId) ~= nil
		or (if state.paid then data.cats[state.uniqueId] == nil or data.cats[state.uniqueId].catId ~= state.catId else not freshIdentityIsUnowned(state.uniqueId))
		or not canSeatReturn(ticket.owner, model, ticket.pillow, ticket.plot, data, model) then
		PillowService.CancelFreshDelivery(ticket)
		return false
	end
	-- Existing seat() creates the single first-ownership record and starts normal taming.
	-- It deliberately does not increment TimesReturned or grant the Loyal bonus.
	forgetFreshDelivery(ticket, false)
	if not seat(ticket.owner, model, ticket.pillow, ticket.plot) then
		if occupants[ticket.pillow] == model then
			occupants[ticket.pillow] = nil
			ticket.pillow:SetAttribute(Pillows.OccupiedAttribute, nil)
		end
		return false
	end
	DataService.SaveNow(ticket.owner)
	return true
end

-- The delivery controller owns physical rollback to the wild; this only releases its destination.
function PillowService.CancelFreshDelivery(ticket: FreshDeliveryTicket): boolean
	return forgetFreshDelivery(ticket, true)
end

function PillowService.IsLoyaltyReturning(model: Model): boolean
	return loyaltyReturns[model] ~= nil
end

-- Leaves both records unchanged. Source reservation guarantees an available rollback pillow;
-- target reservation prevents a player or a second returning cat taking the destination.
function PillowService.BeginLoyaltyReturn(model: Model, target: Player): LoyaltyReturnTicket?
	local placement = placements[model]
	local uniqueId = model:GetAttribute(ATTR.UniqueId)
	if placement == nil or loyaltyReturns[model] ~= nil or type(uniqueId) ~= "string" or uniqueId == ""
		or model:GetAttribute(ATTR.State) ~= CatSchema.States.OnPillow then
		return nil
	end
	local source = placement.owner
	local sourceData = DataService.GetData(source)
	local targetData = DataService.GetData(target)
	local targetPlot = PlotService.GetPlot(target)
	local record = if sourceData then sourceData.cats[uniqueId] else nil
	local targetPillow = if targetPlot and targetData then firstFreePillow(targetPlot, targetData) else nil
	if source == target or sourceData == nil or targetData == nil or record == nil
		or targetPlot == nil or targetPillow == nil or targetData.cats[uniqueId] ~= nil
		or model:GetAttribute(ATTR.OwnerUserId) ~= source.UserId
		or model:GetAttribute(ATTR.OriginalOwnerUserId) ~= target.UserId
		or record.originalOwnerUserId ~= target.UserId
		or record.catId ~= model:GetAttribute(ATTR.CatId)
		or record.pillowIndex ~= pillowIndexOf(placement.pillow)
		or not canSeatReturn(source, model, placement.pillow, placement.plot, sourceData, model)
		or not canSeatReturn(target, model, targetPillow, targetPlot, targetData, nil) then
		return nil
	end

	local ticket: LoyaltyReturnTicket = table.freeze({
		model = model,
		sourceOwner = source,
		targetOwner = target,
		sourcePlot = placement.plot,
		targetPlot = targetPlot,
		sourcePillow = placement.pillow,
		targetPillow = targetPillow,
	})
	unseat(model, "Steal")
	occupants[targetPillow] = model
	targetPillow:SetAttribute(Pillows.OccupiedAttribute, true)
	loyaltyReturns[model] = {
		ticket = ticket,
		uniqueId = uniqueId,
		catId = record.catId,
		destroyingConnection = model.Destroying:Connect(function()
			cancelLoyaltyReturn(ticket, false, true)
		end),
	}
	model:SetAttribute(ATTR.State, CatSchema.States.Returning)
	model:SetAttribute(ATTR.CarrierUserId, nil)
	return ticket
end

function PillowService.CompleteLoyaltyReturn(ticket: LoyaltyReturnTicket): boolean
	local model = ticket.model
	local state = loyaltyReturns[model]
	if state == nil or state.ticket ~= ticket then
		return false
	end
	-- Never retain a profile table across the walking coroutine's yields.
	local sourceData = DataService.GetData(ticket.sourceOwner)
	local targetData = DataService.GetData(ticket.targetOwner)
	local uniqueId = state.uniqueId
	local record = if sourceData then sourceData.cats[uniqueId] else nil
	if sourceData == nil or targetData == nil or record == nil or targetData.cats[uniqueId] ~= nil
		or model:GetAttribute(ATTR.UniqueId) ~= uniqueId or model:GetAttribute(ATTR.CatId) ~= state.catId
		or record.catId ~= state.catId
		or model:GetAttribute(ATTR.State) ~= CatSchema.States.Returning
		or model:GetAttribute(ATTR.OwnerUserId) ~= ticket.sourceOwner.UserId
		or model:GetAttribute(ATTR.OriginalOwnerUserId) ~= ticket.targetOwner.UserId
		or record.originalOwnerUserId ~= ticket.targetOwner.UserId
		or reservations[model] ~= ticket.sourcePillow or occupants[ticket.sourcePillow] ~= model
		or not canSeatReturn(ticket.sourceOwner, model, ticket.sourcePillow, ticket.sourcePlot, sourceData, model)
		or not canSeatReturn(ticket.targetOwner, model, ticket.targetPillow, ticket.targetPlot, targetData, model) then
		cancelLoyaltyReturn(ticket, false, false)
		return false
	end

	-- All fallible prerequisites passed. No yields occur until both live saves and the model agree.
	local previousRecord = table.clone(record)
	record.timesReturned += 1
	record.tamed = true
	record.tameRemaining = 0
	record.tameEndsAt = nil
	record.pillowIndex = pillowIndexOf(ticket.targetPillow)
	targetData.cats[uniqueId] = record
	sourceData.cats[uniqueId] = nil
	model:SetAttribute(ATTR.Tamed, true)
	model:SetAttribute(ATTR.TameEndsAt, nil)
	model:SetAttribute(ATTR.TameRemaining, nil)
	-- Clear the in-flight marker before CatPlaced listeners run; destination stays occupied.
	forgetLoyaltyReturn(ticket, false)
	if not seat(ticket.targetOwner, model, ticket.targetPillow, ticket.targetPlot) then
		-- Defensive rollback for a failed seat: restore the source record in the same frame.
		targetData.cats[uniqueId] = nil
		sourceData.cats[uniqueId] = previousRecord
		if occupants[ticket.targetPillow] == model then
			occupants[ticket.targetPillow] = nil
			ticket.targetPillow:SetAttribute(Pillows.OccupiedAttribute, nil)
		end
		reservations[model] = ticket.sourcePillow
		occupants[ticket.sourcePillow] = model
		ticket.sourcePillow:SetAttribute(Pillows.OccupiedAttribute, true)
		model:SetAttribute(ATTR.OwnerUserId, ticket.sourceOwner.UserId)
		model:SetAttribute(ATTR.Tamed, if previousRecord.tamed then true else nil)
		model:SetAttribute(ATTR.TameRemaining, previousRecord.tameRemaining)
		PillowService.ReturnHome(model)
		return false
	end
	DataService.SaveNow(ticket.targetOwner)
	DataService.SaveNow(ticket.sourceOwner)
	local source = ticket.sourceOwner
	task.defer(function()
		PillowService.RefreshPlot(source) -- the source pillow is free now
	end)
	PillowService.LoyaltyReturnCompleted:Fire(ticket.targetOwner, model)
	return true
end

function PillowService.CancelLoyaltyReturn(ticket: LoyaltyReturnTicket)
	cancelLoyaltyReturn(ticket, false, false)
end

function PillowService.GetPlacedCats(plot: Model): { Model }
	local models = {}
	for model, placement in placements do
		if placement.plot == plot then
			table.insert(models, model)
		end
	end
	return models
end

function PillowService.GetOccupant(pillow: BasePart): Model?
	return occupants[pillow]
end

function PillowService.IsPlaced(model: Model): boolean
	return placements[model] ~= nil
end

function PillowService.GetPlacementOwner(model: Model): Player?
	local placement = placements[model]
	return if placement then placement.owner else nil
end

function PillowService.IsStolenBy(player: Player, model: Model): boolean
	return isStolenBy(player, model)
end

-- StealService decides what a dropped stolen cat does (run home).
function PillowService.SetStolenDropHandler(handler: CarryService.DropHandler)
	stolenDropHandler = handler
end

-- Takes a seated cat off its pillow into the thief's hands. The owner's pillow stays reserved and the
-- owner's save is left as is. Returns the victim, or nil if the steal couldn't start.
function PillowService.BeginSteal(thief: Player, model: Model): Player?
	local placement = placements[model]
	local timesReturned = model:GetAttribute(ATTR.TimesReturned)
	if placement == nil or loyaltyReturns[model] ~= nil or not CarryService.CanCarry(thief)
		or (type(timesReturned) == "number" and timesReturned >= Loyalty.UnstealableReturns) then
		return nil
	end
	local victim, pillow, plot = placement.owner, placement.pillow, placement.plot
	unseat(model, "Steal")
	if CarryService.PickUp(thief, model) then
		return victim
	end
	seat(victim, model, pillow, plot) -- couldn't pick up: put it back
	return nil
end

-- Where a stolen cat should walk to: its reserved pillow (or nil if it has none).
function PillowService.GetReturnPosition(model: Model): Vector3?
	local pillow = reservations[model]
	return if pillow then pillow.Position else nil
end

-- Seats a stolen cat back on its owner's reserved (or any free) pillow. If the owner or their house is
-- gone, the Model is destroyed - the owner's save still has the cat, so it comes back at their next join.
function PillowService.ReturnHome(model: Model): boolean
	local owner = ownerOf(model)
	local plot = if owner then PlotService.GetPlot(owner) else nil
	local data = if owner then DataService.GetData(owner) else nil
	if owner == nil or plot == nil or data == nil or data.cats[uniqueIdOf(model)] == nil then
		releaseReservation(model)
		model:Destroy()
		return false
	end

	local reserved = reservations[model]
	releaseReservation(model)
	local pillow = if reserved and occupants[reserved] == nil then reserved else firstFreePillow(plot, data)
	model:SetAttribute(ATTR.CarrierUserId, nil)
	if pillow and seat(owner, model, pillow, plot) then
		PillowService.CatReturnedHome:Fire(owner, model)
		return true
	end
	model:Destroy()
	return false
end

-- A stolen cat's Model was lost (e.g. fell out of the world): rebuild it from the owner's save onto
-- its reserved pillow. Returns the new Model.
function PillowService.RespawnFromSave(lostModel: Model): Model?
	local owner = ownerOf(lostModel)
	local uniqueId = uniqueIdOf(lostModel)
	local reserved = reservations[lostModel]
	releaseReservation(lostModel)

	local plot = if owner then PlotService.GetPlot(owner) else nil
	local data = if owner then DataService.GetData(owner) else nil
	local record = if data then data.cats[uniqueId] else nil
	if owner == nil or plot == nil or record == nil then
		return nil
	end
	local pillow = if reserved and occupants[reserved] == nil then reserved else firstFreePillow(plot, data)
	if pillow == nil then
		return nil
	end
	local model = restoreOne(owner, plot, pillow, uniqueId, record)
	if model then
		PillowService.CatReturnedHome:Fire(owner, model)
	end
	return model
end

-- The owner left mid-steal: drop the reservation (the Model is destroyed by the caller; the save keeps the cat).
function PillowService.ForgetInTransit(model: Model)
	releaseReservation(model)
end

-- Lifecycle ------------------------------------------------------------------

function PillowService:Init(): ()
	-- Returning cats walk across the crowded second floor without tripping on 1-stud pillows.
	if not PhysicsService:IsCollisionGroupRegistered(Pillows.CollisionGroup) then
		PhysicsService:RegisterCollisionGroup(Pillows.CollisionGroup)
	end
	if not PhysicsService:IsCollisionGroupRegistered(CatSpawning.CollisionGroup) then
		PhysicsService:RegisterCollisionGroup(CatSpawning.CollisionGroup)
	end
	PhysicsService:CollisionGroupSetCollidable(Pillows.CollisionGroup, CatSpawning.CollisionGroup, false)
	for _, plot in PlotService.GetPlots() do
		for _, pillow in PlotService.GetPillows(plot) do
			pillowPlot[pillow] = plot
			pillow.CollisionGroup = Pillows.CollisionGroup
			pillowTransparency[pillow] = pillow.Transparency
			pillow:SetAttribute(Pillows.OccupiedAttribute, nil)
			local existing = pillow:FindFirstChild(Pillows.PlacePromptName)
			if existing then
				existing:Destroy()
			end
			makePrompt(pillow, Pillows.PlacePromptName, Pillows.PlaceActionText, PlotPrompts.Kinds.Place)
		end
		applyPillowLocks(plot, GameConfig.StartingPillows) -- empty houses show the starting pillows
		local secondFloor = plot:FindFirstChild("SecondFloor")
		if secondFloor then
			for _, part in secondFloor:GetDescendants() do
				if part:IsA("BasePart") and table.find(Pillows.CatPassThroughParts, part.Name) then
					part.CollisionGroup = Pillows.CollisionGroup
				end
			end
		end
	end

	CarryService.SetDropHandler(onCatDropped)

	-- Taming keeps running in real time while on a pillow; freeze the remaining time into the save.
	DataService.RegisterSaveHook("PillowTaming", function(_player: Player, data: DataSchema.PlayerData)
		local now = workspace:GetServerTimeNow()
		for _, record in data.cats do
			if record.tameEndsAt then
				record.tameRemaining = math.max(0, record.tameEndsAt - now)
			end
		end
	end)
end

function PillowService:Start(): ()
	PlotService.PlotAssigned:Connect(function(player: Player, plot: Model)
		local data = DataService.GetData(player)
		applyPillowLocks(plot, if data then data.pillowCount else GameConfig.StartingPillows)
		restoreCats(player, plot)
	end)
	PlotService.PlotReleased:Connect(function(player: Player, plot: Model)
		waiting[player] = nil
		applyPillowLocks(plot, GameConfig.StartingPillows)
		for _, state in table.clone(freshDeliveries) do
			if state.ticket.plot == plot then
				forgetFreshDelivery(state.ticket, true)
				if state.paid then state.ticket.model:Destroy() end
			end
		end
		for _, state in table.clone(loyaltyReturns) do
			local ticket = state.ticket
			if ticket.sourcePlot == plot or ticket.targetPlot == plot then
				cancelLoyaltyReturn(ticket, ticket.sourcePlot == plot, false)
			end
		end
		for model, pillow in reservations do
			if pillowPlot[pillow] == plot then
				releaseReservation(model)
			end
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt.Name == Pillows.PlacePromptName then
			local pillow = prompt.Parent
			if pillow and pillow:IsA("BasePart") then
				tryPlace(player, pillow)
			end
		elseif prompt.Name == Pillows.PickUpPromptName then
			local model = prompt:FindFirstAncestorOfClass("Model")
			if model and CollectionService:HasTag(model, Tags.Cat) then
				tryPickUp(player, model)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		for _, state in table.clone(freshDeliveries) do
			if state.ticket.owner == player then
				forgetFreshDelivery(state.ticket, true)
				if state.paid then state.ticket.model:Destroy() end
			end
		end
		for _, state in table.clone(loyaltyReturns) do
			local ticket = state.ticket
			if ticket.sourceOwner == player or ticket.targetOwner == player then
				cancelLoyaltyReturn(ticket, ticket.sourceOwner == player, false)
			end
		end
		lastActionAt[player] = nil
		waiting[player] = nil
	end)

	while true do
		task.wait(Pillows.TameCheckInterval)
		tameTick()
		for _, player in Players:GetPlayers() do
			player:SetAttribute(Pillows.FreePillowsAttribute, PillowService.CountFreePillows(player))
		end
	end
end

return PillowService

