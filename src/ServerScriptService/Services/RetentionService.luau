--!strict
-- Retention (Config/Retention): daily rewards (7-day streak), daily quests, offline income, friend income
-- bonus and group luck bonus. Every grant is a no-yield change of the live profile followed by SaveNow.
-- Days are UTC days from os.time() on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = ReplicatedStorage.Shared.Config
local Cats = require(Config.Cats)
local Items = require(Config.Items)
local Retention = require(Config.Retention)
local Network = require(ReplicatedStorage.Shared.Network)
local CatchService = require(script.Parent.CatchService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local LuckService = require(script.Parent.LuckService)
local MultiplierService = require(script.Parent.MultiplierService)
local NotificationService = require(script.Parent.NotificationService)
local PillowService = require(script.Parent.PillowService)
local PlotService = require(script.Parent.PlotService)
local ShopService = require(script.Parent.ShopService)

local RetentionService = {
	Priority = 98,
}

local random = Random.new()
local dayOffset = 0 -- Studio test only
local lastRequestAt: { [Player]: number } = {}
local joinLastSeen: { [Player]: number } = {}
local friends: { [Player]: { [Player]: boolean } } = {}
local inGroup: { [Player]: boolean } = {}
local dailyEvent: RemoteEvent
local questEvent: RemoteEvent
local welcomeEvent: RemoteEvent

local function today(): number
	return math.floor(os.time() / Retention.SecondsPerDay) + dayOffset
end

-- Studio only: pretend `offset` days have passed (daily/quest tests).
function RetentionService.DebugSetDayOffset(offset: number): boolean
	if not RunService:IsStudio() then
		return false
	end
	dayOffset = offset
	return true
end

local function rewardText(reward: Retention.Reward): string
	if reward.kind == "Coins" then
		return `{reward.amount}+ coins`
	elseif reward.kind == "Item" then
		local item = Items.Get(reward.itemId or "")
		return `{reward.amount}x {if item then item.name else reward.itemId}`
	end
	return `{reward.rarity} cat`
end

-- Grants a reward inside the caller's no-yield update. Returns a message.
local function grant(player: Player, data: any, reward: Retention.Reward): string
	if reward.kind == "Coins" then
		local amount = math.floor(math.max(reward.amount, EconomyService.GetIncomePerSecond(player) * (reward.incomeSeconds or 0)))
		EconomyService.AddCoins(player, amount)
		return `+{amount} coins`
	elseif reward.kind == "Item" then
		local item = Items.Get(reward.itemId or "")
		if item == nil then
			return ""
		end
		local count = data.inventory[item.id]
		data.inventory[item.id] = math.min(item.maxStack, (if type(count) == "number" then count else 0) + reward.amount)
		ShopService.Sync(player)
		return `+{reward.amount} {item.name}`
	end
	local pool = Cats.ByRarity[reward.rarity or "Epic"]
	local catDef = pool[random:NextInteger(1, #pool)]
	if PillowService.GrantNewCat(player, catDef.id) then
		return `A {catDef.name} moved into your house!`
	end
	table.insert(data.dailyReward.pendingCats, catDef.id)
	return `{catDef.name} is waiting for a free pillow - claim it from the Daily menu.`
end

-- Daily ---------------------------------------------------------------------------------

local function dailyState(data: any): (number, boolean)
	-- Returns the streak day the next claim gives, and whether it can be claimed today.
	local day = today()
	local reward = data.dailyReward
	if reward.lastClaimDay == day then
		return reward.streak, false
	end
	local continues = reward.lastClaimDay == day - 1 and reward.streak < #Retention.Daily
	return if continues then reward.streak + 1 else 1, true
end

local function sendDaily(player: Player)
	local data = DataService.GetData(player)
	if data == nil then return end
	local nextDay, claimable = dailyState(data)
	local rewards = {}
	for _, reward in Retention.Daily do
		table.insert(rewards, rewardText(reward))
	end
	dailyEvent:FireClient(player, {
		streak = data.dailyReward.streak, nextDay = nextDay, claimable = claimable,
		pending = #data.dailyReward.pendingCats, rewards = rewards,
	})
end

local function deliverPending(player: Player): number
	local data = DataService.GetData(player)
	if data == nil then return 0 end
	local delivered = 0
	local pending = data.dailyReward.pendingCats
	while #pending > 0 and PillowService.GetFreePillow(player) do
		local catId = table.remove(pending, 1)
		if PillowService.GrantNewCat(player, catId) then
			delivered += 1
		else
			table.insert(pending, 1, catId)
			break
		end
	end
	if delivered > 0 then
		DataService.SaveNow(player)
		NotificationService.Notify(player, `{delivered} reward cat(s) moved into your house!`, "Success")
	end
	return delivered
end

function RetentionService.ClaimDaily(player: Player): (boolean, string)
	local data = DataService.GetData(player)
	if data == nil or PlotService.GetPlot(player) == nil then
		return false, "Your house is still loading."
	end
	local nextDay, claimable = dailyState(data)
	if not claimable then
		return false, "Come back tomorrow for your next reward!"
	end
	data.dailyReward.lastClaimDay = today()
	data.dailyReward.streak = nextDay
	local message = grant(player, data, Retention.Daily[nextDay])
	DataService.SaveNow(player)
	return true, `Day {nextDay} reward: {message}`
end

-- Quests --------------------------------------------------------------------------------

local function ensureQuests(data: any, player: Player)
	local day = today()
	if data.questDay == day and next(data.quests) ~= nil then
		return
	end
	local rng = Random.new(day * 1000003 + player.UserId)
	local pool = table.clone(Retention.QuestPool)
	local quests = {}
	for _ = 1, math.min(Retention.QuestsPerDay, #pool) do
		local quest = table.remove(pool, rng:NextInteger(1, #pool))
		quests[quest.id] = { progress = 0, claimed = false }
	end
	data.quests = quests
	data.questDay = day
end

local function questDef(id: string): Retention.Quest?
	for _, quest in Retention.QuestPool do
		if quest.id == id then return quest end
	end
	return nil
end

local function sendQuests(player: Player)
	local data = DataService.GetData(player)
	if data == nil then return end
	ensureQuests(data, player)
	local list = {}
	for id, state in data.quests do
		local quest = questDef(id)
		if quest then
			table.insert(list, { id = id, text = quest.text, progress = state.progress, target = quest.target,
				claimed = state.claimed, reward = rewardText(quest.reward) })
		end
	end
	table.sort(list, function(a, b): boolean return a.id < b.id end)
	questEvent:FireClient(player, list)
end

function RetentionService.AddProgress(player: Player, stat: string, amount: number)
	local data = DataService.GetData(player)
	if data == nil or amount <= 0 then return end
	ensureQuests(data, player)
	local changed = false
	for id, state in data.quests do
		local quest = questDef(id)
		if quest and quest.stat == stat and not state.claimed and state.progress < quest.target then
			state.progress = math.min(quest.target, state.progress + amount)
			changed = true
			if state.progress >= quest.target then
				NotificationService.Notify(player, `Quest complete: {quest.text}! Claim it in Quests.`, "Success")
			end
		end
	end
	if changed then sendQuests(player) end
end

function RetentionService.ClaimQuest(player: Player, questId: unknown): (boolean, string)
	local data = DataService.GetData(player)
	if data == nil or type(questId) ~= "string" then
		return false, "Unknown quest."
	end
	ensureQuests(data, player)
	local state = data.quests[questId]
	local quest = questDef(questId)
	if state == nil or quest == nil then
		return false, "Unknown quest."
	end
	if state.claimed or state.progress < quest.target then
		return false, "Finish the quest first."
	end
	state.claimed = true
	local message = grant(player, data, quest.reward)
	DataService.SaveNow(player)
	return true, `{quest.text}: {message}`
end

-- Offline income -----------------------------------------------------------------------

local function offlineIncome(player: Player)
	local lastSeen = joinLastSeen[player]
	joinLastSeen[player] = nil
	if lastSeen == nil or lastSeen <= 0 then return end
	local seconds = math.clamp(os.time() - lastSeen, 0, Retention.OfflineMaxSeconds)
	if seconds < Retention.OfflineMinSeconds then return end
	local amount = math.floor(EconomyService.GetIncomePerSecond(player) * seconds * Retention.OfflineRate)
	if amount < 1 then return end
	EconomyService.AddToBowl(player, amount)
	welcomeEvent:FireClient(player, amount, seconds)
end

-- Studio only: run the join-time offline income as if the player had been away `seconds`.
function RetentionService.DebugOffline(player: Player, seconds: number): boolean
	if not RunService:IsStudio() then
		return false
	end
	joinLastSeen[player] = os.time() - seconds
	offlineIncome(player)
	return true
end

-- Friends / group ----------------------------------------------------------------------

local function friendCount(player: Player): number
	local count = 0
	for other, isFriend in friends[player] or {} do
		if isFriend and other.Parent == Players then count += 1 end
	end
	return math.min(count, Retention.FriendBonusMaxFriends)
end

local function checkFriends(player: Player)
	friends[player] = friends[player] or {}
	for _, other in Players:GetPlayers() do
		if other ~= player and friends[player][other] == nil then
			local ok, result = pcall(player.IsFriendsWith, player, other.UserId)
			local isFriend = ok and result == true
			friends[player][other] = isFriend
			friends[other] = friends[other] or {}
			friends[other][player] = isFriend
		end
	end
end

-- Read-only HUD values share the same daily/quest/friend rules as claims and multipliers.
function RetentionService.GetFriendBonusPercent(player: Player): number
	return math.floor(Retention.FriendBonusPerFriend * friendCount(player) * 100 + 0.5)
end

function RetentionService.GetHudState(player: Player): { [string]: any }
	local data = DataService.GetData(player)
	if data == nil then
		return { dailyClaimable = false, dailyReadyAt = 0, pendingDailyCats = 0,
			pendingDailyClaimable = false, questClaimableCount = 0, friendBonusPercent = 0 }
	end
	ensureQuests(data, player)
	local _, claimable = dailyState(data)
	local completed = 0
	for id, state in data.quests do
		local quest = questDef(id)
		if quest and not state.claimed and state.progress >= quest.target then completed += 1 end
	end
	local pending = #data.dailyReward.pendingCats
	return {
		dailyClaimable = claimable,
		dailyReadyAt = if claimable then 0 else (data.dailyReward.lastClaimDay - dayOffset + 1) * Retention.SecondsPerDay,
		pendingDailyCats = pending,
		pendingDailyClaimable = pending > 0 and PillowService.GetFreePillow(player) ~= nil,
		questClaimableCount = completed,
		friendBonusPercent = RetentionService.GetFriendBonusPercent(player),
	}
end

-- Lifecycle -----------------------------------------------------------------------------

function RetentionService:Init(): ()
	dailyEvent = Network.GetEvent("DailyInfo")
	questEvent = Network.GetEvent("QuestInfo")
	welcomeEvent = Network.GetEvent("WelcomeBack")
	DataService.RegisterSaveHook("LastSeen", function(_player: Player, data)
		data.lastSeen = os.time()
	end)
	MultiplierService.RegisterIncomeSource("Friends", function(player: Player): number
		return 1 + Retention.FriendBonusPerFriend * friendCount(player)
	end)
	LuckService.RegisterLuckSource("Group", function(player: Player): number
		return if inGroup[player] then Retention.GroupLuckMultiplier else 1
	end)
end

function RetentionService:Start(): ()
	DataService.DataLoaded:Connect(function(player: Player, data)
		joinLastSeen[player] = data.lastSeen -- read before this session's first save overwrites it
	end)
	for _, player in Players:GetPlayers() do
		local data = DataService.GetData(player)
		if data then joinLastSeen[player] = data.lastSeen end
	end
	PlotService.PlotAssigned:Connect(function(player: Player)
		offlineIncome(player)
		deliverPending(player)
		local data = DataService.GetData(player)
		if data then
			local _, claimable = dailyState(data)
			if claimable then sendDaily(player) end -- daily popup on join
		end
	end)
	local function onPlayerAdded(player: Player)
		task.spawn(checkFriends, player)
		if Retention.GroupId ~= 0 then
			task.spawn(function()
				local ok, result = pcall(player.IsInGroup, player, Retention.GroupId)
				inGroup[player] = ok and result == true
			end)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do onPlayerAdded(player) end
	Players.PlayerRemoving:Connect(function(player: Player)
		friends[player] = nil
		for _, set in friends do set[player] = nil end
		inGroup[player] = nil
		joinLastSeen[player] = nil
		lastRequestAt[player] = nil
	end)

	CatchService.CatCaught:Connect(function(player: Player) RetentionService.AddProgress(player, "Catch", 1) end)
	PillowService.CatStolen:Connect(function(thief: Player) RetentionService.AddProgress(thief, "Steal", 1) end)
	PillowService.CatReturnedHome:Connect(function(owner: Player) RetentionService.AddProgress(owner, "CatBack", 1) end)
	PillowService.LoyaltyReturnCompleted:Connect(function(owner: Player) RetentionService.AddProgress(owner, "CatBack", 1) end)
	EconomyService.BowlCollected:Connect(function(player: Player, amount: number) RetentionService.AddProgress(player, "Collect", amount) end)

	Network.GetEvent("RetentionRequest").OnServerEvent:Connect(function(player: Player, kind: unknown)
		local now = os.clock()
		if now - (lastRequestAt[player] or -math.huge) < 0.5 then return end
		lastRequestAt[player] = now
		if kind == "Daily" then
			deliverPending(player)
			sendDaily(player)
		elseif kind == "Quests" then
			sendQuests(player)
		end
	end)
	Network.GetEvent("DailyClaim").OnServerEvent:Connect(function(player: Player)
		local ok, message = RetentionService.ClaimDaily(player)
		NotificationService.Notify(player, message, if ok then "Success" else "Error")
		sendDaily(player)
	end)
	Network.GetEvent("QuestClaim").OnServerEvent:Connect(function(player: Player, questId: unknown)
		local ok, message = RetentionService.ClaimQuest(player, questId)
		NotificationService.Notify(player, message, if ok then "Success" else "Error")
		sendQuests(player)
	end)
	-- Pending reward cats move in as soon as a pillow is free.
	task.spawn(function()
		while true do
			task.wait(10)
			for _, player in Players:GetPlayers() do
				local data = DataService.GetData(player)
				if data and #data.dailyReward.pendingCats > 0 then deliverPending(player) end
			end
		end
	end)
end

return RetentionService


