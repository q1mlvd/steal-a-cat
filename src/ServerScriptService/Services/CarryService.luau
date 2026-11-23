--!strict
-- Carrying cats: attaches a cat to a character, applies the carry speed penalty, and drops carried
-- cats back into the wild when the carrier dies, resets, or leaves.
-- While carried, the cat is welded to the character (so it moves with the player's physics) and lives in
-- Workspace.Cats.Carried.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = ReplicatedStorage.Shared.Config
local Carrying = require(Config.Carrying)
local CatSchema = require(Config.CatSchema)
local Rarities = require(Config.Rarities)
local Maid = require(ReplicatedStorage.Shared.Util.Maid)
local CatSpawnService = require(script.Parent.CatSpawnService)

local ATTR = CatSchema.Attributes
local CARRIED_FOLDER_NAME = "Carried"

local CarryService = {
	Priority = 40,
}

-- Decides what happens to a cat when its carrier dies, resets or leaves. Return true if the handler
-- took care of the Model; otherwise it is released to the wild.
export type DropHandler = (player: Player, model: Model, leaving: boolean) -> boolean
-- Per-player values from upgrades (UpgradeService). Must not yield.
export type PlayerNumberProvider = (player: Player) -> number

local dropHandler: DropHandler? = nil
local capacityProvider: PlayerNumberProvider? = nil
local speedBonusProvider: PlayerNumberProvider? = nil
local speedBonuses: { [string]: PlayerNumberProvider } = {} -- additive named bonuses, e.g. Cat Index milestones
local speedMultipliers: { [string]: PlayerNumberProvider } = {} -- e.g. Fast Legs pass
local capacityBonuses: { [string]: PlayerNumberProvider } = {} -- e.g. Big Hands pass

local carried: { [Player]: { Model } } = {}
local playerMaids: { [Player]: Maid.Maid } = {}
local carriedFolder: Folder

local function getAliveParts(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if character == nil then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root == nil or not root:IsA("BasePart") or humanoid == nil or humanoid.Health <= 0 then
		return nil, nil
	end
	return root, humanoid
end

local function provided(provider: PlayerNumberProvider?, player: Player, fallback: number): number
	if provider == nil then
		return fallback
	end
	local ok, value = pcall(provider, player)
	return if ok and type(value) == "number" and value == value and math.abs(value) < math.huge then value else fallback
end

-- Upgraded speed before the carry slowdown.
local function baseWalkSpeed(player: Player): number
	local speed = StarterPlayer.CharacterWalkSpeed + math.max(0, provided(speedBonusProvider, player, 0))
	for _, bonus in speedBonuses do
		speed += math.max(0, provided(bonus, player, 0))
	end
	for _, multiplier in speedMultipliers do
		speed *= math.max(1, provided(multiplier, player, 1))
	end
	return speed
end

-- Upgraded speed x (1 - summed carry penalty): the slowdown applies on top of the upgrade.
local function expectedWalkSpeed(player: Player): number
	local penalty = 0
	for _, model in carried[player] or {} do
		local rarity = Rarities.Get(tostring(model:GetAttribute(ATTR.Rarity)))
		if rarity then
			penalty += rarity.carrySpeedPenalty
		end
	end
	penalty = math.min(penalty, Carrying.MaxTotalSpeedPenalty)
	return baseWalkSpeed(player) * (1 - penalty)
end

local function updateWalkSpeed(player: Player)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid == nil then
		return
	end
	humanoid.WalkSpeed = expectedWalkSpeed(player)
end

-- Carried cats must not push the player around: the root becomes non-colliding and massless
-- (the template's other parts already are), and the cat's Humanoid stops simulating.
local function setCarriedPhysics(model: Model, isCarried: boolean)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = false
		root.CanCollide = not isCarried
		root.Massless = isCarried
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.EvaluateStateMachine = not isCarried
	end
end

local function detach(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart")
	local weld = if root then root:FindFirstChild(Carrying.WeldName) else nil
	if weld then
		weld:Destroy()
	end
	setCarriedPhysics(model, false)
	model:SetAttribute(ATTR.CarrierUserId, nil)
end

-- Public API -----------------------------------------------------------------

function CarryService.GetCapacity(player: Player): number
	local capacity = math.max(Carrying.DefaultCapacity, math.floor(provided(capacityProvider, player, Carrying.DefaultCapacity)))
	for _, bonus in capacityBonuses do
		capacity += math.max(0, math.floor(provided(bonus, player, 0)))
	end
	return math.min(capacity, Carrying.MaxCapacity)
end

-- Named multipliers on the upgraded walk speed (>= 1, multiply together). The speed check follows them.
function CarryService.RegisterSpeedMultiplier(name: string, provider: PlayerNumberProvider)
	speedMultipliers[name] = provider
end

-- Named additive speed on top of the existing upgrade provider, before pass multipliers/carry penalties.
function CarryService.RegisterSpeedBonus(name: string, provider: PlayerNumberProvider)
	assert(type(name) == "string" and name ~= "", "[CarryService] Speed bonus needs a name")
	assert(type(provider) == "function", "[CarryService] Speed bonus must be a function")
	speedBonuses[name] = provider
end

function CarryService.UnregisterSpeedBonus(name: string)
	speedBonuses[name] = nil
end

-- Named extra capacity on top of the Hands upgrade, capped at Carrying.MaxCapacity.
function CarryService.RegisterCapacityBonus(name: string, provider: PlayerNumberProvider)
	capacityBonuses[name] = provider
end

-- Server-side speed the player is allowed to move at right now (upgrade + carry slowdown).
function CarryService.GetExpectedWalkSpeed(player: Player): number
	return expectedWalkSpeed(player)
end

function CarryService.SetCapacityProvider(provider: PlayerNumberProvider)
	capacityProvider = provider
end

function CarryService.SetSpeedBonusProvider(provider: PlayerNumberProvider)
	speedBonusProvider = provider
end

-- Re-applies WalkSpeed and the capacity mirror, e.g. after an upgrade or when data loads.
function CarryService.RefreshPlayer(player: Player)
	if carried[player] == nil then
		return
	end
	player:SetAttribute(Carrying.CapacityAttribute, CarryService.GetCapacity(player))
	updateWalkSpeed(player)
end

-- Players currently holding at least one cat.
function CarryService.GetCarriers(): { Player }
	local result = {}
	for player, list in carried do
		if #list > 0 then
			table.insert(result, player)
		end
	end
	return result
end

function CarryService.GetCarried(player: Player): { Model }
	return table.clone(carried[player] or {})
end

function CarryService.CanCarry(player: Player): boolean
	local list = carried[player]
	return list ~= nil and #list < CarryService.GetCapacity(player)
end

-- Attaches a cat Model the caller already owns (e.g. after CatSpawnService.ClaimWildCat).
-- Returns false if the player can't carry it (dead, hands full, left).
function CarryService.PickUp(player: Player, model: Model): boolean
	local list = carried[player]
	if list == nil or not CarryService.CanCarry(player) then
		return false
	end
	local root = getAliveParts(player)
	local catRoot = model:FindFirstChild("HumanoidRootPart")
	if root == nil or catRoot == nil or not catRoot:IsA("BasePart") then
		return false
	end

	setCarriedPhysics(model, true)
	local slot = #list
	model:PivotTo(root.CFrame * Carrying.CarryOffset + Vector3.new(0, slot * Carrying.StackSpacing, 0))

	local weld = Instance.new("WeldConstraint")
	weld.Name = Carrying.WeldName
	weld.Part0 = root
	weld.Part1 = catRoot
	weld.Parent = catRoot

	model.Parent = carriedFolder
	model:SetAttribute(ATTR.State, CatSchema.States.Carried)
	model:SetAttribute(ATTR.CarrierUserId, player.UserId) -- ownership changes only when placed (PillowService)

	table.insert(list, model)
	updateWalkSpeed(player)
	return true
end

-- Detaches a carried cat without returning it to the wild (e.g. placing it on a pillow).
-- The caller takes ownership of the Model. Returns false if this player isn't carrying it.
function CarryService.Release(player: Player, model: Model): boolean
	local list = carried[player]
	local index = if list then table.find(list, model) else nil
	if list == nil or index == nil then
		return false
	end
	table.remove(list, index)
	detach(model)
	updateWalkSpeed(player)
	return true
end

function CarryService.SetDropHandler(handler: DropHandler)
	dropHandler = handler
end

-- Drops every carried cat: the drop handler gets the first say (e.g. own cats go back to a pillow),
-- the rest go back into the wild where they are. `ignore` is excluded from the ground probe.
function CarryService.DropAll(player: Player, ignore: Instance?, leaving: boolean?)
	local list = carried[player]
	if list == nil or #list == 0 then
		return
	end
	carried[player] = {}
	for _, model in list do
		detach(model)
		if model.Parent then
			local handled = dropHandler ~= nil and dropHandler(player, model, leaving == true)
			if not handled then
				CatSpawnService.ReleaseToWild(model, ignore)
			end
		end
	end
	updateWalkSpeed(player)
end

-- Lifecycle ------------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", Carrying.CharacterLoadTimeout)
	if humanoid == nil or not humanoid:IsA("Humanoid") or player.Character ~= character then
		return
	end
	updateWalkSpeed(player) -- upgraded speed on every spawn
	-- Connection lives on the Humanoid and is cleaned up with the character.
	humanoid.Died:Connect(function()
		CarryService.DropAll(player, character)
	end)
end

local function onPlayerAdded(player: Player)
	if playerMaids[player] then
		return
	end
	local maid = Maid.new()
	playerMaids[player] = maid
	carried[player] = {}

	player:SetAttribute(Carrying.CapacityAttribute, CarryService.GetCapacity(player))
	maid:Add(player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end))
	-- Covers resets/respawns where Died didn't fire (e.g. LoadCharacter).
	maid:Add(player.CharacterRemoving:Connect(function(character: Model)
		CarryService.DropAll(player, character)
	end))
	local character = player.Character
	if character then
		task.spawn(onCharacterAdded, player, character)
	end
end

local function onPlayerRemoving(player: Player)
	CarryService.DropAll(player, player.Character, true)
	local maid = playerMaids[player]
	if maid then
		maid:Clean()
		playerMaids[player] = nil
	end
	carried[player] = nil
end

function CarryService:Init(): ()
	carriedFolder = Instance.new("Folder")
	carriedFolder.Name = CARRIED_FOLDER_NAME
	carriedFolder.Parent = CatSpawnService.GetCatsFolder()
end

function CarryService:Start(): ()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return CarryService

