--!strict
-- Daily rewards, daily quests, offline income, leaderboards, friend and group bonuses.
-- Days are UTC days: math.floor(os.time() / SecondsPerDay) on the server.

export type Reward = { kind: "Coins" | "Item" | "Cat", amount: number, itemId: string?, rarity: string?, incomeSeconds: number? }
export type Quest = { id: string, text: string, stat: "Catch" | "Steal" | "CatBack" | "Collect", target: number, reward: Reward }

return table.freeze({
	SecondsPerDay = 86400,

	-- Daily rewards: streak day 1..7 (missing a day restarts at 1; after day 7 it starts again).
	-- Coins: max(amount, income/s x incomeSeconds). Day 7: guaranteed Epic cat on a free pillow, or kept as
	-- a claimable reward while no pillow is free.
	Daily = table.freeze({
		table.freeze({ kind = "Coins", amount = 500, incomeSeconds = 120 } :: Reward),
		table.freeze({ kind = "Coins", amount = 1500, incomeSeconds = 240 } :: Reward),
		table.freeze({ kind = "Item", amount = 3, itemId = "YarnBall" } :: Reward),
		table.freeze({ kind = "Coins", amount = 4000, incomeSeconds = 480 } :: Reward),
		table.freeze({ kind = "Item", amount = 2, itemId = "Fish" } :: Reward),
		table.freeze({ kind = "Coins", amount = 10000, incomeSeconds = 900 } :: Reward),
		table.freeze({ kind = "Cat", amount = 1, rarity = "Epic" } :: Reward),
	}),

	-- Daily quests: QuestsPerDay picked per player per UTC day from the pool (deterministic seed).
	QuestsPerDay = 3,
	QuestPool = table.freeze({
		table.freeze({ id = "catch10", text = "Catch 10 cats", stat = "Catch", target = 10, reward = { kind = "Coins", amount = 5000, incomeSeconds = 300 } } :: Quest),
		table.freeze({ id = "catch25", text = "Catch 25 cats", stat = "Catch", target = 25, reward = { kind = "Coins", amount = 15000, incomeSeconds = 900 } } :: Quest),
		table.freeze({ id = "steal3", text = "Steal 3 cats", stat = "Steal", target = 3, reward = { kind = "Coins", amount = 10000, incomeSeconds = 600 } } :: Quest),
		table.freeze({ id = "catback1", text = "Get a cat back", stat = "CatBack", target = 1, reward = { kind = "Item", amount = 1, itemId = "Fish" } } :: Quest),
		table.freeze({ id = "collect50k", text = "Collect 50,000 coins", stat = "Collect", target = 50000, reward = { kind = "Item", amount = 2, itemId = "YarnBall" } } :: Quest),
		table.freeze({ id = "collect500k", text = "Collect 500,000 coins", stat = "Collect", target = 500000, reward = { kind = "Coins", amount = 50000, incomeSeconds = 1800 } } :: Quest),
	}),

	-- Offline income (bowl), consistent with the live bowl: income/s x seconds offline x rate.
	OfflineMaxSeconds = 8 * 3600,
	OfflineRate = 0.5,
	OfflineMinSeconds = 60, -- shorter absences get nothing (and no popup)

	-- Global leaderboards (OrderedDataStore). Studio uses separate store names.
	LeaderboardInterval = 120,
	LeaderboardTop = 10,
	LeaderboardStudioPrefix = "StudioTest_",
	Leaderboards = table.freeze({
		table.freeze({ id = "Income", store = "LB_IncomePerSecond_v1", title = "Income /s" }),
		table.freeze({ id = "Stolen", store = "LB_CatsStolen_v1", title = "Cats stolen" }),
		table.freeze({ id = "Loyal", store = "LB_MostLoyalCat_v1", title = "Most loyal cat" }),
	}),

	-- Friends in the same server: +10% income each, max +30% (MultiplierService "Friends").
	FriendBonusPerFriend = 0.1,
	FriendBonusMaxFriends = 3,
	-- Members of this Roblox group get extra luck (0 = disabled).
	GroupId = 0,
	GroupLuckMultiplier = 1.25,
})

