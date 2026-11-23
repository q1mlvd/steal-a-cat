--!strict
-- General game settings. Values marked with a stage are not used yet.

local Game = {
	-- Server size. Informational: Players.MaxPlayers is read-only from scripts,
	-- so set the real cap in Game Settings > Places > Server Fill / Max Players.
	MaxPlayers = 8,

	-- Economy
	StartingCoins = 0,
	IncomeTickInterval = 1, -- seconds between coin payouts (Stage 5)

	-- Houses / pillows
	StartingPillows = 4,
	MaxPillows = 30, -- upgrade cap; houses start with StartingPillows

	-- Interaction / anti-exploit
	InteractionMaxDistance = 12, -- studs; server-side range check for prompts and remotes (Stage 4)

	-- Networking
	RemoteWaitTimeout = 10, -- seconds a lookup waits for a remote to replicate before erroring
}

return table.freeze(Game)

