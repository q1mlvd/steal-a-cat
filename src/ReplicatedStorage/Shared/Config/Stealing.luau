--!strict
-- Stealing, stolen cats running home, the new-player shield, and the carrier speed check.

return table.freeze({
	-- Steal prompt on cats sitting on someone else's pillow
	StealPromptName = "StealPrompt",
	StealActionText = "Steal",
	HoldTamed = 1.5, -- seconds to hold for a tamed cat
	HoldUntamed = 0.5, -- seconds to hold for an untamed cat
	HoldTolerance = 0.15, -- server accepts a hold this much shorter than required (timing jitter)
	AttemptCooldown = 1, -- seconds between steal attempts per player

	-- New players: their cats can't be stolen for this long after they get their house
	NewPlayerShieldDuration = 300,
	ShieldAttribute = "ShieldEndsAt", -- on the plot Model: workspace:GetServerTimeNow() when the shield ends
	DebugEndShieldAttribute = "DebugEndShield", -- Studio only: set true on a Player (server side) to end their shield now

	-- A dropped stolen cat runs home by itself (can't be caught on the way)
	ReturnSpeed = 18,
	ReturnMaxTime = 30, -- seconds; after this it simply appears back on its pillow
	WaypointTimeout = 3, -- seconds per path waypoint before giving up walking
	ReturnStepInterval = 0.1,
	ReturnArriveDistance = 3,
	PathAgentRadius = 1.5,
	PathAgentHeight = 3,

	-- Server speed check for players carrying cats (catches speed hacks / teleports)
	SpeedCheckInterval = 0.5,
	SpeedTolerance = 1.5, -- allowed: WalkSpeed x tolerance ...
	SpeedSlack = 4, -- ... + this many studs per check (lag, slopes, knockback)
	SpeedStrikesToDrop = 2, -- consecutive violations before the cats are taken away
})

