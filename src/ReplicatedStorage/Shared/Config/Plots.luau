--!strict
-- Player house (plot) settings.

return table.freeze({
	-- Attributes on plot instances (set in the map, or by PlotService at runtime)
	IndexAttribute = "PlotIndex", -- number on each plot Model; free plots are handed out lowest first
	PillowIndexAttribute = "PillowIndex", -- number on each pillow part
	OwnerAttribute = "OwnerUserId", -- set by the server on the plot Model; display mirror for clients
	PlayerPlotAttribute = "HousePlotIndex", -- on the Player once they have a house (hides the loading screen)

	-- Floors: walkable heights above the bottom of the plot's InteriorZone (ground floor, second floor).
	-- InteriorZone covers both floors; SecondFloor holds the slab, upper walls, stairs and rails.
	FloorHeights = table.freeze({ 0, 13 }),
	FloorHeightTolerance = 0.5, -- studs

	-- Sign text
	SignEmptyText = "Empty House",
	SignOwnerFormat = "%s's House", -- %s = owner's DisplayName

	-- Spawning
	SpawnHeightOffset = 3, -- studs above the SpawnPoint part to place the character's root
	CharacterLoadTimeout = 10, -- seconds to wait for HumanoidRootPart before giving up on a teleport

	NoFreePlotKickMessage = "This server has no free houses. Please join another server.",
})

