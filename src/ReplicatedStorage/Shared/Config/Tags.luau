--!strict
-- CollectionService tag names. Use these constants instead of string literals.

return table.freeze({
	Plot = "Plot", -- Model: a player house
	Pillow = "Pillow", -- BasePart inside a plot's PillowsFolder
	District = "District", -- invisible zone part with a DistrictName attribute
	ShopZone = "ShopZone", -- invisible zone part in the central square
	Cat = "Cat", -- every cat Model (wild, carried, or on a pillow)
	PlotPrompt = "PlotPrompt", -- ProximityPrompts the client shows only when relevant (see Config/PlotPrompts)
})

