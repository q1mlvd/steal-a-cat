--!strict
-- Permanent upgrades (Config/Upgrades). Levels live in PlayerData.upgrades; purchases reuse the shop
-- stall session and commit TrySpend + level increment in the same profile without yielding.
-- Effects: Speed/Hands through CarryService providers (AntiCheatService follows CarryService), Jump on
-- the Humanoid, Bowl Magnet through EconomyService.Collect, Pillows through PlayerData.pillowCount +
-- PillowService.RefreshPlot. Player attributes are display mirrors only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = ReplicatedStorage.Shared.Config
local Carrying = require(Config.Carrying)
local GameConfig = require(Config.Game)
local Monetization = require(Config.Monetization)
local Shop = require(Config.Shop)
local Upgrades = require(Config.Upgrades)
local Network = require(ReplicatedStorage.Shared.Network)
local Maid = require(ReplicatedStorage.Shared.Util.Maid)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local CarryService = require(script.Parent.CarryService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MonetizationService = require(script.Parent.MonetizationService)
local NotificationService = require(script.Parent.NotificationService)
local PillowService = require(script.Parent.PillowService)
local PlotService = require(script.Parent.PlotService)
local ShopService = require(script.Parent.ShopService)

local UpgradeService = {
	Priority = 88,

	-- (player, upgradeId, newLevel) after a successful purchase
	LevelChanged = Signal.new() :: Signal.Signal<Player, string, number>,
}

local purchaseTimes: { [Player]: number } = {}
local playerMaids: { [Player]: Maid.Maid } = {}
local plotBounds: { [Model]: { cframe: CFrame, half: Vector3 } } = {}

-- Public API -----------------------------------------------------------------

function UpgradeService.GetLevel(player: Player, id: string): number
	local data = DataService.GetData(player)
	if data == nil or Upgrades.Get(id) == nil then
		return 0
	end
	return Upgrades.SanitizeLevel(id, data.upgrades[id])
end

function UpgradeService.GetEffect(player: Player, id: string): number
	return Upgrades.EffectAt(id, UpgradeService.GetLevel(player, id))
end

-- Saved pillowCount: Pillows upgrade level + Extra Pillows pass (a shortcut, still capped at MaxPillows).
function UpgradeService.GetPillowCount(player: Player): number
	local bonus = if MonetizationService.OwnsPass(player, "ExtraPillows") then Monetization.ExtraPillowsBonus else 0
	return math.min(Upgrades.PillowCount(UpgradeService.GetLevel(player, "Pillows")) + bonus, GameConfig.MaxPillows)
end

-- Keeps data.pillowCount consistent and re-applies it to the house. Never removes cats (they wait).
local function syncPillows(player: Player)
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	data.pillowCount = UpgradeService.GetPillowCount(player)
	PillowService.RefreshPlot(player)
end

local function mirror(player: Player)
	for _, definition in Upgrades.List do
		player:SetAttribute(Upgrades.LevelAttributePrefix .. definition.id, UpgradeService.GetLevel(player, definition.id))
	end
end

local function applyJump(player: Player)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid == nil then
		return
	end
	local height = StarterPlayer.CharacterJumpHeight + UpgradeService.GetEffect(player, "Jump")
	if humanoid.UseJumpPower then
		-- Same apex height expressed as launch speed: v = sqrt(2 g h).
		humanoid.JumpPower = math.sqrt(2 * workspace.Gravity * height)
	else
		humanoid.JumpHeight = height
	end
end

local function apply(player: Player)
	CarryService.RefreshPlayer(player) -- WalkSpeed (with carry slowdown) + capacity mirror
	applyJump(player)
end

function UpgradeService.Purchase(player: Player, upgradeId: unknown): (boolean, string)
	local now = os.clock()
	if now - (purchaseTimes[player] or -math.huge) < Upgrades.PurchaseCooldown then
		return false, "Please wait."
	end
	purchaseTimes[player] = now
	if type(upgradeId) ~= "string" or #upgradeId > Shop.MaxIdLength then
		return false, "Unknown upgrade."
	end
	local definition = Upgrades.Get(upgradeId)
	if definition == nil then
		return false, "Unknown upgrade."
	end
	if not definition.available then
		return false, `{definition.name} isn't available yet.`
	end
	if not ShopService.HasSession(player) then
		return false, "Visit the shop stall to buy upgrades."
	end
	local data = DataService.GetData(player)
	if data == nil then
		return false, "Your save is still loading."
	end
	local level = Upgrades.SanitizeLevel(definition.id, data.upgrades[definition.id])
	if level >= #definition.levels then
		return false, `{definition.name} is already maxed.`
	end
	if definition.id == "Pillows" and UpgradeService.GetPillowCount(player) >= GameConfig.MaxPillows then
		return false, `You already have the maximum {GameConfig.MaxPillows} pillows.`
	end
	local nextLevel = level + 1
	-- TrySpend, level increment and save request are one non-yielding transaction in this same profile.
	if not EconomyService.TrySpend(player, definition.levels[nextLevel].cost) then
		return false, "Not enough coins."
	end
	data.upgrades[definition.id] = nextLevel
	if definition.id == "Pillows" then
		data.pillowCount = UpgradeService.GetPillowCount(player)
	end
	DataService.SaveNow(player)
	mirror(player)
	apply(player)
	if definition.id == "Pillows" then
		PillowService.RefreshPlot(player) -- unlock the new pillows, seat any waiting cats
	end
	UpgradeService.LevelChanged:Fire(player, definition.id, nextLevel)
	return true, `{definition.name} upgraded to level {nextLevel}!`
end

-- Re-applies every upgrade effect from the live data (after a rebirth reset). No yields.
function UpgradeService.ApplyAll(player: Player)
	mirror(player)
	apply(player)
	syncPillows(player)
end

-- Studio test profile only (refused otherwise): sets a level without paying, then applies it.
function UpgradeService.DebugSetLevel(player: Player, id: string, level: number): boolean
	local data = DataService.GetData(player)
	if not DataService.IsStudioTestProfile() or data == nil or Upgrades.Get(id) == nil then
		return false
	end
	data.upgrades[id] = Upgrades.SanitizeLevel(id, level)
	mirror(player)
	apply(player)
	syncPillows(player)
	return true
end

-- Bowl Magnet ------------------------------------------------------------------

local function distanceToPlot(plot: Model, position: Vector3): number
	local bounds = plotBounds[plot]
	if bounds == nil then
		local cframe, size = plot:GetBoundingBox()
		bounds = { cframe = cframe, half = size / 2 }
		plotBounds[plot] = bounds
	end
	local localPosition = bounds.cframe:PointToObjectSpace(position)
	return Vector3.new(
		math.max(math.abs(localPosition.X) - bounds.half.X, 0),
		math.max(math.abs(localPosition.Y) - bounds.half.Y, 0),
		math.max(math.abs(localPosition.Z) - bounds.half.Z, 0)
	).Magnitude
end

local function magnetTick()
	for _, player in Players:GetPlayers() do
		-- Auto Collect pass: collects wherever the player is (same logic, unlimited radius).
		local data = DataService.GetData(player)
		local autoCollect = MonetizationService.OwnsPass(player, "AutoCollect")
			and data ~= nil and data.settings.autoCollectEnabled ~= false
		local radius = if autoCollect then math.huge
			else UpgradeService.GetEffect(player, "BowlMagnet")
		local plot = if radius > 0 then PlotService.GetPlot(player) else nil
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if plot and root and root:IsA("BasePart") and humanoid and humanoid.Health > 0
			and EconomyService.GetBowlCoins(plot) >= 1 and distanceToPlot(plot, root.Position) <= radius then
			EconomyService.Collect(player, false)
		end
	end
end

-- Lifecycle ------------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", Carrying.CharacterLoadTimeout)
	if humanoid and player.Character == character then
		applyJump(player)
	end
end

local function onPlayerAdded(player: Player)
	if playerMaids[player] then
		return
	end
	local maid = Maid.new()
	playerMaids[player] = maid
	maid:Add(player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end))
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
	if DataService.GetData(player) then
		mirror(player)
		apply(player)
	end
end

local function onPlayerRemoving(player: Player)
	purchaseTimes[player] = nil
	local maid = playerMaids[player]
	if maid then
		maid:Clean()
		playerMaids[player] = nil
	end
end

function UpgradeService:Init(): ()
	CarryService.SetCapacityProvider(function(player: Player): number
		return UpgradeService.GetEffect(player, "Hands")
	end)
	CarryService.SetSpeedBonusProvider(function(player: Player): number
		return UpgradeService.GetEffect(player, "Speed")
	end)
end

function UpgradeService:Start(): ()
	for _, plot in PlotService.GetPlots() do
		local cframe, size = plot:GetBoundingBox()
		plotBounds[plot] = { cframe = cframe, half = size / 2 }
	end
	DataService.DataLoaded:Connect(function(player: Player)
		-- pillowCount always follows the saved Pillows level (runs before the house is assigned).
		local data = DataService.GetData(player)
		if data then
			data.pillowCount = UpgradeService.GetPillowCount(player)
		end
		mirror(player)
		apply(player)
	end)
	-- Extra Pillows ownership is verified asynchronously; apply it (or its loss) when known.
	MonetizationService.PassChanged:Connect(function(player: Player, key: string)
		if key == "ExtraPillows" then
			syncPillows(player)
		end
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Network.GetEvent("UpgradePurchase").OnServerEvent:Connect(function(player: Player, upgradeId: unknown)
		local success, message = UpgradeService.Purchase(player, upgradeId)
		NotificationService.Notify(player, message, if success then "Success" else "Error")
	end)
	while true do
		task.wait(Upgrades.MagnetInterval)
		magnetTick()
	end
end

return UpgradeService


