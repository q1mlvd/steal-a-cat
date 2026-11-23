--!strict
-- Luck. LuckService multiplies every registered source per player (passes, timed boosts, group,
-- server-wide event boost).
--
-- How luck works on a SHARED world spawn (decision): when a normal wild cat spawns, the spawner takes the
-- highest luck multiplier among living players within NearbyRadius of the spawn point (1 if none) and
-- multiplies the weight of every rarity above Common by it. So a lucky player shifts what appears around
-- them, and everyone nearby benefits too. Secret cats keep their own separate global roll (unchanged).
-- Mutations (Stage 12) use the same nearby luck for their roll.

return table.freeze({
	NearbyRadius = 150, -- studs from the spawn point
	MaxMultiplier = 20, -- safety cap on the combined multiplier
	LuckAttribute = "LuckMultiplier", -- player attribute mirror for UI
})

