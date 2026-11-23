--!strict
-- Coins, bowls and collecting. Tick rate and starting coins live in Config/Game.

return table.freeze({
	LeaderstatName = "Coins",
	IncomeAttribute = "IncomePerSecond", -- on Player: current income per second (display mirror)
	BowlAttribute = "BowlCoins", -- on each plot's Bowl part: coins waiting (display mirror)

	CollectPromptName = "CollectPrompt",
	CollectActionText = "Collect",
	CollectCooldown = 0.5, -- seconds between collects per player
	TouchCollectEnabled = true, -- walking into your bowl also collects

	CollectSoundId = "", -- placeholder: set to "rbxassetid://<id>" to play a sound on collect
	CountUpSpeed = 8, -- client display catch-up rate for animated numbers (higher = faster)
})

