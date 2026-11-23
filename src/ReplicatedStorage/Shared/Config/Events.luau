--!strict
-- Live events (EventService). Only one event runs at a time; an event that comes due while another runs
-- waits. Clients read the workspace attributes below for the countdown UI.

export type EventName = "Starfall" | "Rain" | "DogRaid"

return table.freeze({
	Schedule = table.freeze({
		Starfall = table.freeze({ interval = 3600, duration = 180, title = "STARFALL", icon = "\u{2B50}",
			announce = "Starfall! Starry cats are falling from the sky - catch them!" }),
		Rain = table.freeze({ interval = 1800, duration = 120, title = "RAIN", icon = "\u{1F327}",
			announce = "It's raining! Wild cats hide, and stealing is twice as fast!" }),
		DogRaid = table.freeze({ interval = 2700, duration = 120, title = "DOG RAID", icon = "\u{1F436}",
			announce = "Dog raid! Dogs are coming for your bowls - slap them away (F)!" }),
	}),
	Order = table.freeze({ "Starfall", "Rain", "DogRaid" }),
	TickInterval = 1,
	ActiveAttribute = "EventName", -- workspace: active event (nil when none)
	EndsAtAttribute = "EventEndsAt", -- workspace: server time
	NextAttribute = "NextEventName",
	NextAtAttribute = "NextEventAt",

	Starfall = table.freeze({
		SpawnInterval = 12, -- seconds between star cats
		MaxCats = 6, -- bonus cats at once (shared with summoned cats)
		DropHeight = 60,
		Mutation = "Starry",
		-- Every regular species can eventually be discovered in the Starry collection.
		RarityWeights = table.freeze({ Common = 10, Uncommon = 50, Rare = 30, Epic = 15, Legendary = 5, Mythic = 1, Secret = 0.05 }),
	}),
	Rain = table.freeze({
		StealHoldMultiplier = 0.5,
		HidingAttribute = "Hiding", -- on wild cats while it rains: can't be caught
		HiddenTransparency = 0.7, -- client-side look
	}),
	DogRaid = table.freeze({
		DogsPerHouse = 1,
		SpawnDistance = 30, -- studs outside the door
		Speed = 9,
		StealDistance = 4, -- studs from the bowl
		StealFraction = 0.25, -- of the bowl's coins (never cats)
		RewardBase = 500,
		RewardIncomeSeconds = 30, -- reward = max(base, income/s x this)
		Label = "Raid Dog",
		Color = Color3.fromRGB(90, 90, 100),
	}),

	-- Seasons: nil = off. "Halloween" / "Christmas" add seasonal cats (Config/Cats season field) and
	-- seasonal mutations (Config/Mutations season field) to the spawn roll.
	Season = nil :: string?,
	SeasonalCatChance = 0.25, -- chance a spawn uses a seasonal cat of the rolled rarity, when one exists
})

