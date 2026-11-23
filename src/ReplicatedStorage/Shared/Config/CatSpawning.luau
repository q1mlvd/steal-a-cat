--!strict
-- Wild cat population and AI tuning.

export type AreaRule = {
	weight: number, -- share of TargetWildCats this area holds (relative to the other areas)
	rarities: { string }, -- rarities that may spawn here; picked by Rarities.spawnWeight among these
}

local areas: { [string]: AreaRule } = {
	-- Starter areas near spawn so new players find a cat quickly
	Square = { weight = 3, rarities = { "Common" } },
	Paths = { weight = 4, rarities = { "Common" } },
	-- Districts
	Residential = { weight = 6, rarities = { "Common", "Uncommon" } },
	Park = { weight = 5, rarities = { "Uncommon", "Rare" } },
	Industrial = { weight = 4, rarities = { "Rare", "Epic" } },
	Rooftops = { weight = 2, rarities = { "Legendary" } },
	Sewers = { weight = 1, rarities = { "Mythic" } }, -- Secret uses its own roll below
}
for _, rule in areas do
	table.freeze(rule.rarities)
	table.freeze(rule)
end

return table.freeze({
	-- Population
	TargetWildCats = 25,
	SpawnInterval = 2, -- seconds between top-up passes
	SpawnBatchSize = 3, -- max cats added per top-up pass (the first fill on server start is unlimited)
	SpawnPointAttempts = 12, -- random points tried per spawn before giving up this pass
	SpawnMinPlayerDistance = 25, -- studs; never pop a cat in right next to a player
	WildLifetimeMin = 180, -- seconds a wild cat lives before it may despawn
	WildLifetimeMax = 300,
	DespawnSafeDistance = 40, -- studs; an expired cat waits until no player is this close
	DespawnFadeTime = 0.5,

	Areas = table.freeze(areas),

	-- Secret cats are never in an area pool. Every top-up pass (SpawnInterval) rolls SpawnChancePerTick:
	-- expected time between Secrets = SpawnInterval / SpawnChancePerTick = 2 / 0.0002 = 10000 s (~2.8 h).
	Secret = table.freeze({
		RarityId = "Secret",
		Area = "Sewers",
		SpawnChancePerTick = 0.0002,
		MaxWild = 1, -- wild Secret cats allowed at once (not counted toward TargetWildCats)
		LifetimeMin = 600,
		LifetimeMax = 900,
		Announcement = "A SECRET cat appeared in the Sewers!",
		-- Studio only: set this attribute to true on Workspace.Cats.Wild to force a Secret on the next pass.
		DebugForceAttribute = "DebugSpawnSecret",
	}),

	-- AI loop
	AITickInterval = 0.2, -- seconds between AI updates (all cats in one loop)
	StatsSmoothing = 0.1, -- EMA factor for the AvgTickMs debug attribute

	-- Wander
	WanderSpeed = 6,
	WanderMinDistance = 8,
	WanderMaxDistance = 30,
	WanderAttempts = 6,
	IdleTimeMin = 1.5,
	IdleTimeMax = 4,
	ArriveDistance = 2.5,
	MoveToRefreshInterval = 4, -- re-issue MoveTo before Humanoid's built-in 8 s timeout

	-- Flee (speed comes from Rarities.fleeSpeed)
	FleeRadius = 18, -- a player this close makes the cat run
	FleeSafeRadius = 30, -- cat calms down once every player is this far
	FleeStepDistance = 20, -- how far ahead each flee target is
	FleeRetargetInterval = 0.5,
	FleeMaxDuration = 4, -- after this long running, the cat must rest
	FleeRestTime = 2.5, -- resting cats stand still and ignore players: the window to catch them
	FleeAngles = table.freeze({ 0, 35, -35, 70, -70, 110, -110 }), -- degrees tried around "directly away"

	-- Stuck detection
	StuckCheckInterval = 2,
	StuckMinMove = 1, -- studs moved per check to count as progress
	StuckMaxStrikes = 5, -- consecutive stuck checks before the cat is despawned

	-- Ground / path probing
	GroundTolerance = 3, -- spawn ground must be within this of its zone's bottom face
	MaxStepHeight = 2, -- max height change between path samples (stops walking off roofs)
	LineSampleStep = 4, -- studs between path samples
	GroundProbeUp = 4,
	GroundProbeDown = 12,
	ReleaseProbeDepth = 60, -- studs searched below a dropped cat for ground
	ObstacleProbeHeight = 1.5, -- height of the forward wall check above ground

	CollisionGroup = "Cats", -- cats don't collide with each other
})

