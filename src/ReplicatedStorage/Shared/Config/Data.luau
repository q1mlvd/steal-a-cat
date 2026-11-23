--!strict
-- Player data persistence settings (used by the server's DataService).

return table.freeze({
	StoreName = "PlayerData", -- DataStore name; change only together with a data migration plan
	KeyPrefix = "Player_", -- profile key = KeyPrefix .. UserId

	-- Studio only: when true, every Studio session loads "StudioTest_<UserId>" instead of the real
	-- "Player_<UserId>" save, so solo tests never touch a real profile. Ignored outside Studio.
	-- Studio debug hooks (StudioDebugService) only run while this is on.
	StudioTestProfile = false, -- set true for solo Studio tests (uses StudioTest_<UserId>, never the real save)
	StudioTestKeyPrefix = "StudioTest_",
	AutoSavePeriod = 150, -- seconds between autosaves of each profile (2.5 min)
	WaitPollInterval = 0.1, -- seconds between checks in DataService.WaitForData

	LoadFailedKickMessage = "We couldn't load your save right now. To keep your progress safe, please rejoin in a minute!",
	SessionLostKickMessage = "Your save was opened on another server. Please rejoin.",
	NewerVersionKickMessage = "This server is out of date for your save. Please rejoin to get a newer server.",

	-- Studio only: set this attribute to true on your Player (server side) to wipe your save.
	DebugWipeAttribute = "DebugWipeData",
	DebugWipeKickMessage = "Your save was wiped (Studio debug). Press Play again to start fresh.",
})

