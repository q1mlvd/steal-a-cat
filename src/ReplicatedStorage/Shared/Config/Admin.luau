--!strict
-- Admin panel access (checked on the server). The game's creator is always an admin.
return table.freeze({
	UserIds = table.freeze({}), -- extra admin UserIds
	IncludeCreator = true,
	Attribute = "IsAdmin", -- player attribute mirror (shows the panel button)
	CommandCooldown = 0.5,
	SecretRainMax = 10,
	SpawnCatMax = 20, -- bonus cats alive at once via admin spawns
	ServerLuckMax = 10,
	ServerLuckMaxMinutes = 120,
})

