--!strict
-- Developer Product effects. MonetizationService owns the single ProcessReceipt callback; this service
-- only registers validators (checked before the purchase prompt) and grant handlers (no yields; the
-- receipt id is recorded in the same frame by MonetizationService).
--   LuckX3       - timed LuckService source; remaining seconds saved in data.boosts (paused offline)
--   InstantTame  - PillowService.FinishTaming
--   CatBox       - random cat (Config/Monetization.CatBoxWeights) seated via PillowService.GrantNewCat
--   SummonMythic - CatSpawnService.SpawnBonusCat + server announcement
--   Coin packs   - EconomyService.AddCoins, scaled with income per second

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local Cats = require(Config.Cats)
local Monetization = require(Config.Monetization)
local ExclusiveShop = require(Config.ExclusiveShop)
local Rarities = require(Config.Rarities)
local DataService = require(script.Parent.DataService)
local CatSpawnService = require(script.Parent.CatSpawnService)
local EconomyService = require(script.Parent.EconomyService)
local LuckService = require(script.Parent.LuckService)
local MonetizationService = require(script.Parent.MonetizationService)
local NotificationService = require(script.Parent.NotificationService)
local PillowService = require(script.Parent.PillowService)

local ProductService = {
	Priority = 92,
}

local LUCK_BOOST = "LuckX3"
local BOOST_ENDS_ATTRIBUTE = "LuckBoostEndsAt" -- server time, UI mirror
local SUMMON_MAX_WILD = 3
local random = Random.new()
local luckUntil: { [Player]: number } = {} -- os.clock() deadline this session

local function luckRemaining(player: Player): number
	local deadline = luckUntil[player]
	return if deadline then math.max(0, deadline - os.clock()) else 0
end

local function mirrorLuck(player: Player)
	local remaining = luckRemaining(player)
	player:SetAttribute(BOOST_ENDS_ATTRIBUTE, if remaining > 0 then workspace:GetServerTimeNow() + remaining else nil)
end

local function rollCatBox(): string
	local total = 0
	for _, weight in Monetization.CatBoxWeights do
		total += weight
	end
	local roll = random:NextNumber(0, total)
	local chosen = "Common"
	for _, rarity in Rarities.List do
		local weight = (Monetization.CatBoxWeights :: any)[rarity.id]
		if weight then
			roll -= weight
			chosen = rarity.id
			if roll <= 0 then
				break
			end
		end
	end
	local pool = Cats.ByRarity[chosen]
	return pool[random:NextInteger(1, #pool)].id
end

-- Studio test profile only: distribution check for the Cat Box roll.
function ProductService.DebugRollCatBox(count: number): { [string]: number }
	local result: { [string]: number } = {}
	if not DataService.IsStudioTestProfile() then
		return result
	end
	for _ = 1, count do
		local catDef = Cats.Get(rollCatBox()) :: Cats.Cat
		result[catDef.rarity] = (result[catDef.rarity] or 0) + 1
	end
	return result
end

function ProductService:Init(): ()
	MonetizationService.RegisterProductHandler("ServerLuck", function(player: Player): (boolean, string?)
		if not LuckService.AddServerBoost(ExclusiveShop.ServerLuckMultiplier, ExclusiveShop.ServerLuckDuration) then
			return false, "ExclusiveShop.CannotBuy"
		end
		local minutes = math.ceil(ExclusiveShop.ServerLuckDuration / 60)
		NotificationService.AnnounceLocalized("ExclusiveShop.ServerLuckAnnouncement", { player = player.DisplayName,
			multiplier = ExclusiveShop.ServerLuckMultiplier, minutes = minutes })
		return true, "ExclusiveShop.ServerLuckGranted"
	end)
	LuckService.RegisterLuckSource("LuckX3Product", function(player: Player): number
		return if luckRemaining(player) > 0 then Monetization.LuckX3Multiplier else 1
	end)
	DataService.RegisterSaveHook("Boosts", function(player: Player, data)
		if luckUntil[player] ~= nil then
			local remaining = luckRemaining(player)
			data.boosts[LUCK_BOOST] = if remaining > 0 then remaining else nil
		end
	end)

	MonetizationService.RegisterProductHandler("LuckX3", function(player: Player, data): (boolean, string?)
		local remaining = luckRemaining(player) + Monetization.LuckX3Duration
		luckUntil[player] = os.clock() + remaining
		data.boosts[LUCK_BOOST] = remaining
		mirrorLuck(player)
		return true, `Luck x{Monetization.LuckX3Multiplier} active for {math.ceil(remaining / 60)} minutes!`
	end)

	MonetizationService.RegisterProductValidator("InstantTame", function(player: Player): (boolean, string?)
		return PillowService.CountUntamed(player) > 0, "All your cats are already tamed."
	end)
	MonetizationService.RegisterProductHandler("InstantTame", function(player: Player): (boolean, string?)
		local count = PillowService.FinishTaming(player)
		return true, `{count} {if count == 1 then "cat is" else "cats are"} tamed now!`
	end)

	MonetizationService.RegisterProductValidator("CatBox", function(player: Player): (boolean, string?)
		return PillowService.GetFreePillow(player) ~= nil, "Free a pillow first - the Cat Box cat needs somewhere to sit."
	end)
	MonetizationService.RegisterProductHandler("CatBox", function(player: Player): (boolean, string?)
		local catId = rollCatBox()
		local model = PillowService.GrantNewCat(player, catId)
		if model == nil then
			return false, "Free a pillow to receive your Cat Box cat - it will be delivered then."
		end
		local catDef = Cats.Get(catId) :: Cats.Cat
		return true, `Your Cat Box had a {catDef.rarity} {catDef.name}!`
	end)

	MonetizationService.RegisterProductValidator("SummonMythic", function(_player: Player): (boolean, string?)
		return CatSpawnService.GetBonusCount() < SUMMON_MAX_WILD, "Too many summoned cats are roaming right now. Try again soon!"
	end)
	MonetizationService.RegisterProductHandler("SummonMythic", function(player: Player): (boolean, string?)
		local model = CatSpawnService.SpawnBonusCat(Monetization.SummonRarity, SUMMON_MAX_WILD)
		if model == nil then
			return false, "The Mythic cat couldn't appear yet - it will be summoned shortly."
		end
		local catDef = Cats.Get(tostring(model:GetAttribute("CatId")))
		NotificationService.Announce(`{player.DisplayName} summoned a Mythic {if catDef then catDef.name else "cat"}! Catch it!`,
			if catDef then catDef.id else nil, tostring(model:GetAttribute("Mutation") or ""))
		return true, nil
	end)

	for key in Monetization.CoinPacks do
		MonetizationService.RegisterProductHandler(key, function(player: Player): (boolean, string?)
			local amount = Monetization.CoinPackAmount(key, EconomyService.GetIncomePerSecond(player))
			EconomyService.AddCoins(player, amount)
			return true, `+{amount} coins!`
		end)
	end
end

function ProductService:Start(): ()
	local function loaded(player: Player)
		local data = DataService.GetData(player)
		local saved = if data then data.boosts[LUCK_BOOST] else nil
		luckUntil[player] = os.clock() + (if type(saved) == "number" and saved > 0 and saved < math.huge then saved else 0)
		mirrorLuck(player)
	end
	DataService.DataLoaded:Connect(loaded)
	for _, player in Players:GetPlayers() do
		if DataService.GetData(player) then
			loaded(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		-- The final save hook still needs the deadline; forget it afterwards.
		task.delay(30, function()
			if player.Parent ~= Players then
				luckUntil[player] = nil
			end
		end)
	end)
end

return ProductService

