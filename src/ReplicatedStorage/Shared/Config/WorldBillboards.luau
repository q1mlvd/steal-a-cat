--!strict
-- Pixel dimensions are independent of camera distance. Every world label is bounded by this policy.
return table.freeze({
	Maximum = Vector2.new(200, 80),
	DefaultSize = Vector2.new(180, 40),
	CatSize = Vector2.new(190, 52),
	MaxDistance = 80,
	CatMaxDistance = 65,
	MarkerMaxDistance = 100,
	LightInfluence = 0,
})

