--!strict
-- Loading screen shown until the player's save is loaded and they get their house.

return table.freeze({
	Title = "Loading your save...",
	SlowHintDelay = 10, -- seconds before the hint below appears
	SlowHint = "Still loading - your save may be finishing on another server. Hang tight!",
	FadeTime = 0.4,
	-- Look (UI pack: LoadingBackground + Logo)
	LogoWidthScale = 0.7, -- of the screen width, capped below (the art has wide transparent margins)
	LogoMaxSize = Vector2.new(820, 410),
	LogoBounce = 10, -- pixels
	LogoBounceTime = 0.9,
	BarWidthScale = 0.42,
	BarMaxWidth = 420,
	BarHeight = 26,
	BarSweepTime = 1.6, -- seconds per sweep of the indeterminate fill
	BarFillScale = 0.35, -- fill width while sweeping
	Shade = 0.55, -- dark gradient under the text, for contrast
})

