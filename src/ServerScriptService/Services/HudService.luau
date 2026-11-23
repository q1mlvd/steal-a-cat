--!strict
-- Additive server HUD state and actions. No destination, badge or pass ownership is client supplied.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local Hud = require(Config.Hud)
local Items = require(Config.Items)
local Mutations = require(Config.Mutations)
local Rebirth = require(Config.Rebirth)
local Shop = require(Config.Shop)
local Network = require(ReplicatedStorage.Shared.Network)
local AntiCheatService = require(script.Parent.AntiCheatService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local LuckService = require(script.Parent.LuckService)
local MonetizationService = require(script.Parent.MonetizationService)
local MergeService = require(script.Parent.MergeService)
local PillowService = require(script.Parent.PillowService)
local PlotService = require(script.Parent.PlotService)
local RetentionService = require(script.Parent.RetentionService)
local PlaytimeRewardService = require(script.Parent.PlaytimeRewardService)
local CatIndexService = require(script.Parent.CatIndexService)
local ShopService = require(script.Parent.ShopService)

local HudService = { Priority = 103 }
local homeReadyAt: { [Player]: number } = {}
local requestTimes: { [Player]: { [string]: number } } = {}
local stateEvent: RemoteEvent
local dayNightAnchor = 0

local function allowed(player: Player, action: string): boolean
	if player.Parent ~= Players then return false end
	local now = os.clock()
	local times = requestTimes[player]
	if times == nil then times = {}; requestTimes[player] = times end
	if now - (times[action] or -math.huge) < Hud.RequestCooldown then return false end
	times[action] = now
	return true
end

function HudService.GetSnapshot(player: Player): { [string]: any }
	local data = DataService.GetData(player)
	local loaded = data ~= nil
	local state: { [string]: any } = RetentionService.GetHudState(player)
	state.loaded = loaded
	state.serverNow = workspace:GetServerTimeNow()
	state.homeReadyAt = homeReadyAt[player] or 0
	state.dayNightAnchor = dayNightAnchor
	state.autoCollectOwned = MonetizationService.OwnsPass(player, Hud.AutoCollectPassKey)
	state.autoCollectEnabled = state.autoCollectOwned and data ~= nil and data.settings.autoCollectEnabled ~= false
	state.coins = EconomyService.GetCoins(player)
	state.incomePerSecond = EconomyService.GetIncomePerSecond(player)
	state.luckMultiplier = LuckService.GetLuckMultiplier(player)
	local playtime = PlaytimeRewardService.GetHudState(player)
	state.freeGiftClaimable = playtime.freeGiftClaimable
	state.playtimeClaimableCount = playtime.playtimeClaimableCount
	state.playtimeNextAt = playtime.playtimeNextAt
	state.serverLuck = LuckService.GetServerBoostState()
	state.indexRewardsReady = (CatIndexService.GetSnapshot(player).claimableCount or 0) > 0
	state.canRebirth = data ~= nil and PlotService.GetPlot(player) ~= nil
		and data.coins >= Rebirth.CostFor(data.rebirths) and not PillowService.HasCatsInTransit(player)
	state.canMerge = false
	for _, group in PillowService.GetMergeGroups(player) do
		if group.count >= Mutations.MergeCount and Mutations.NextTier(group.tier) ~= nil then
			state.canMerge = true
			break
		end
	end
	local usable = 0
	local snapshot = ShopService.GetSnapshot(player)
	for _, item in Items.List do
		if (snapshot.inventory[item.id] or 0) > 0 or (item.id == "Fish" and snapshot.fishReady)
			or (item.id == "SoftPaws" and snapshot.softPawsReady) then usable += 1 end
	end
	state.usableItems = usable
	local newItems: { [string]: boolean } = {}
	if data and (data.settings.shopSeenRevision or 0) < Hud.ShopRevision then
		for _, id in Hud.NewShopItemIds do
			if Items.Get(id) ~= nil then newItems[id] = true end
		end
	end
	state.newShopItems = newItems
	state.shopHasNewItems = next(newItems) ~= nil
	return state
end

function HudService.Sync(player: Player): ()
	if player.Parent == Players then stateEvent:FireClient(player, HudService.GetSnapshot(player)) end
end

-- This API is also callable by the guarded StudioDebug bridge for repeatable tests.
function HudService.GoHome(player: Player): (boolean, string, { [string]: any })
	if not allowed(player, "Home") then return false, "Hud.PleaseWait", HudService.GetSnapshot(player) end
	local data = DataService.GetData(player)
	local plot = PlotService.GetPlot(player)
	if data == nil or plot == nil or PlotService.GetOwner(plot) ~= player then
		return false, "Hud.HomeLoading", HudService.GetSnapshot(player)
	end
	local now = workspace:GetServerTimeNow()
	if now < (homeReadyAt[player] or 0) then return false, "Hud.HomeCooldownMessage", HudService.GetSnapshot(player) end
	if PillowService.HasCatsInTransit(player) then return false, "Hud.HomeBusy", HudService.GetSnapshot(player) end
	if player:GetAttribute(Shop.CatchingAttribute) == true then return false, "Hud.HomeCatching", HudService.GetSnapshot(player) end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if character == nil or root == nil or not root:IsA("BasePart") or humanoid == nil or humanoid.Health <= 0 then
		return false, "Hud.HomeAlive", HudService.GetSnapshot(player)
	end
	-- All validations and movement are one frame; the client cannot choose another player's house.
	homeReadyAt[player] = now + Hud.HomeCooldown
	AntiCheatService.Grace(player, Hud.HomeGraceSeconds)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(PlotService.GetSpawnCFrame(plot))
	HudService.Sync(player)
	return true, "Hud.HomeDone", HudService.GetSnapshot(player)
end

function HudService.SetAutoCollect(player: Player, enabled: unknown): (boolean, string, { [string]: any })
	if not allowed(player, "AutoCollect") then return false, "Hud.PleaseWait", HudService.GetSnapshot(player) end
	if type(enabled) ~= "boolean" then return false, "Hud.InvalidRequest", HudService.GetSnapshot(player) end
	local data = DataService.GetData(player)
	if data == nil then return false, "Hud.HomeLoading", HudService.GetSnapshot(player) end
	if not MonetizationService.OwnsPass(player, Hud.AutoCollectPassKey) then
		return false, "Hud.AutoCollectOwned", HudService.GetSnapshot(player)
	end
	data.settings.autoCollectEnabled = enabled
	DataService.SaveNow(player)
	HudService.Sync(player)
	return true, if enabled then "Hud.AutoCollectOn" else "Hud.AutoCollectOff", HudService.GetSnapshot(player)
end

function HudService.MarkShopSeen(player: Player): { [string]: any }
	if not allowed(player, "ShopSeen") then return HudService.GetSnapshot(player) end
	local data = DataService.GetData(player)
	if data and (data.settings.shopSeenRevision or 0) < Hud.ShopRevision then
		data.settings.shopSeenRevision = Hud.ShopRevision
		DataService.SaveNow(player)
	end
	HudService.Sync(player)
	return HudService.GetSnapshot(player)
end

function HudService:Init(): ()
	stateEvent = Network.GetEvent("HudState")
end

function HudService:Start(): ()
	dayNightAnchor = workspace:GetServerTimeNow() - Lighting.ClockTime / 24 * Hud.DayNightCycleSeconds
	workspace:SetAttribute(Hud.DayNightAnchorAttribute, dayNightAnchor)
	Network.GetFunction("HudSnapshot").OnServerInvoke = function(player: Player)
		if allowed(player, "Snapshot") then return HudService.GetSnapshot(player) end
		return nil
	end
	Network.GetFunction("HudHome").OnServerInvoke = HudService.GoHome
	Network.GetFunction("HudAutoCollect").OnServerInvoke = HudService.SetAutoCollect
	Network.GetFunction("HudShopSeen").OnServerInvoke = HudService.MarkShopSeen
	Network.GetFunction("HudMerge").OnServerInvoke = function(player: Player)
		return allowed(player, "Merge") and MergeService.OpenMenu(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		homeReadyAt[player] = nil
		requestTimes[player] = nil
	end)
	DataService.DataLoaded:Connect(HudService.Sync)
	PlotService.PlotAssigned:Connect(HudService.Sync)
	MonetizationService.PassChanged:Connect(function(player: Player) HudService.Sync(player) end)
	while true do
		local cycleProgress = (workspace:GetServerTimeNow() - dayNightAnchor) % Hud.DayNightCycleSeconds
		Lighting.ClockTime = cycleProgress / Hud.DayNightCycleSeconds * 24
		for _, player in Players:GetPlayers() do HudService.Sync(player) end
		task.wait(Hud.SnapshotInterval)
	end
end

return HudService

