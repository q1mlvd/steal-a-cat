--!strict
-- HUD actions use server state. Home accepts no destination from the client.
return table.freeze({
	HomeCooldown = 5,
	HomeGraceSeconds = 2,
	RequestCooldown = 0.25,
	SnapshotInterval = 1,
	AutoCollectPassKey = "AutoCollect",
	DayNightCycleSeconds = 1200,
	DayStartHour = 6,
	NightStartHour = 18,
	DayNightAnchorAttribute = "DayNightAnchor",
	-- Increase this revision and replace this list when a catalog release adds items.
	-- NEW is shown for a player's first view of this catalog, then saved in settings.
	ShopRevision = 1,
	NewShopItemIds = table.freeze({
		"YarnBall", "Fish", "BaitCan", "Net", "LaserPointer", "Catnip",
		"SoftPaws", "Bell", "GuardDog", "BoxTrap", "BribeFood", "Vacuum",
	}),
})

