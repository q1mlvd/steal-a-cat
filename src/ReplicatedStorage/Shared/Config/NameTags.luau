--!strict
-- Player name tags (server-built BillboardGui on the character's Head; replaces Roblox's default name).
return table.freeze({
	GuiName = "NameTag",
	Size = UDim2.fromOffset(220, 46),
	Offset = Vector3.new(0, 2.6, 0),
	MaxDistance = 80,
	NameColor = Color3.fromRGB(255, 255, 255),
	VipColor = Color3.fromRGB(255, 205, 80),
	BadgeColor = Color3.fromRGB(171, 184, 203),
	VipBadge = "\u{2B50} VIP",
	RebirthBadgeFormat = "\u{267B} %d", -- rebirth count (Stage 13)
	CharacterLoadTimeout = 10,
})

