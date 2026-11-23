--!strict
-- Carrying cats.

return table.freeze({
	DefaultCapacity = 1, -- cats a player can hold at once without the Hands upgrade
	MaxCapacity = 4, -- hard cap: Hands upgrade (3) + Big Hands pass (+1)
	CapacityAttribute = "CarryCapacity", -- player attribute mirror for client prompt filtering (server decides)
	CarryOffset = CFrame.new(0, 0.6, -2.4), -- cat root relative to the HumanoidRootPart: chest height, in front
	StackSpacing = 1.8, -- extra height per additional carried cat
	MaxTotalSpeedPenalty = 0.6, -- cap when several cats' carrySpeedPenalty values are summed
	WeldName = "CarryWeld",
	CharacterLoadTimeout = 10,
})

