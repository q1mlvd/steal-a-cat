--!strict
-- Shared rules for ProximityPrompts inside houses (place, pick up, collect).
-- The server keeps these prompts enabled and validates every trigger; the client hides the ones that
-- don't apply to the local player (another player's house, nothing to place, hands full...).

export type Kind = "Place" | "PickUp" | "Collect" | "Steal" | "Lock" | "Pet" | "Merge"

return table.freeze({
	KindAttribute = "PromptKind", -- Kind, on each prompt tagged Tags.PlotPrompt
	Kinds = table.freeze({
		Place = "Place" :: Kind,
		PickUp = "PickUp" :: Kind,
		Collect = "Collect" :: Kind,
		Steal = "Steal" :: Kind,
		Lock = "Lock" :: Kind,
		Pet = "Pet" :: Kind,
		Merge = "Merge" :: Kind, -- Merge Machine (owner only)
	}),
	MaxDistance = 8,
	KeyCode = Enum.KeyCode.E,
	GamepadKeyCode = Enum.KeyCode.ButtonX,
	ClientRefreshInterval = 0.2, -- seconds between client visibility checks

	-- Prompts shown at (nearly) the same spot stack upward instead of overlapping.
	StackGroupDistance = 3, -- studs; visible prompts closer than this share one stack
	StackSpacing = 80, -- pixels between stacked prompts (default prompt UI is 72px tall)
	-- Bottom-to-top order inside a stack. Wild-cat Catch and the shop stall use their prompt Name.
	StackOrder = table.freeze({ "Collect", "Place", "PickUp", "Steal", "Lock", "Merge", "CatchPrompt", "ShopPrompt", "Pet" }),
})


