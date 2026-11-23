--!strict
-- Catch prompt and mini-game tuning. Green-zone width per rarity is Rarities.catchZoneSize.

return table.freeze({
	-- ProximityPrompt on every wild cat
	PromptName = "CatchPrompt",
	PromptActionText = "Catch",
	PromptKey = Enum.KeyCode.E,
	PromptGamepadKey = Enum.KeyCode.ButtonX,
	PromptMaxDistance = 8,

	-- Server validation
	MaxCatchDistance = 12, -- studs between player and cat (prompt distance + slack for lag/movement)
	AttemptCooldown = 0.5, -- seconds between catch attempts per player
	FailIgnoreTime = 5, -- after a failed catch, that cat refuses this player for this long

	-- Mini-game (the server picks values per session)
	MarkerTravelTimeMin = 0.6, -- seconds for the marker to cross the bar once
	MarkerTravelTimeMax = 0.9,
	TravelTimeRarityScale = 0.06, -- each rarity tier above Common makes the marker 6% faster
	Timeout = 6, -- seconds the player has to press
	LatencyTolerance = 0.03, -- seconds of slack on each zone edge to absorb timing jitter...
	MaxToleranceZoneFraction = 0.25, -- ...but never more than this fraction of the zone (keeps rare zones hard)
	MaxLatencyCompensation = 0.4, -- cap on the ping the server subtracts (stops fake-lag abuse)
	MinInputDelay = 0.15, -- client ignores presses this soon after the bar appears (prompt key bleed)
	ResultDisplayTime = 0.9, -- seconds the client shows the result before hiding the bar
})

