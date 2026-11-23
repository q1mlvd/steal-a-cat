--!strict
-- Permanent upgrades, bought at the shop stall's Upgrades tab. Saved levels live in PlayerData.upgrades
-- ({[upgradeId]: level}); the server mirrors them as player attributes (LevelAttributePrefix .. id).
-- levels[n] = cost to reach level n and the effect value at level n; `base` is the effect at level 0.

local Carrying = require(script.Parent.Carrying)
local GameConfig = require(script.Parent.Game)

export type Preview = "WalkSpeed" | "JumpHeight" | "Capacity" | "Radius" | "Pillows"
export type Level = { cost: number, value: number }
export type UpgradeDefinition = {
	id: string,
	name: string,
	description: string,
	icon: string, -- "" = placeholder initial
	base: number,
	levels: { Level },
	preview: Preview, -- how the shop formats the effect ("Speed 16 -> 18")
	available: boolean, -- false = listed but not purchasable yet
}

local list: { UpgradeDefinition } = {
	{
		id = "Speed", name = "Speed", icon = "rbxassetid://124687567504060",
		description = "Run faster. Carrying cats still slows you down on top of your upgraded speed.",
		base = 0, preview = "WalkSpeed", available = true, -- value = extra WalkSpeed
		levels = {
			{ cost = 2500, value = 2 }, { cost = 10000, value = 4 }, { cost = 35000, value = 6 },
			{ cost = 120000, value = 8 }, { cost = 400000, value = 10 },
		},
	},
	{
		id = "Jump", name = "Jump", icon = "rbxassetid://73950814414085",
		description = "Jump higher. Jump 3 lets you climb the Rooftops ladders.",
		base = 0, preview = "JumpHeight", available = true, -- value = extra JumpHeight (studs)
		levels = { { cost = 5000, value = 2 }, { cost = 40000, value = 4 }, { cost = 200000, value = 6 } },
	},
	{
		id = "Hands", name = "Hands", icon = "rbxassetid://131909513031128",
		description = "Carry more cats at once.",
		base = Carrying.DefaultCapacity, preview = "Capacity", available = true, -- value = carry capacity
		levels = { { cost = 30000, value = 2 }, { cost = 300000, value = 3 } },
	},
	{
		id = "BowlMagnet", name = "Bowl Magnet", icon = "rbxassetid://106026288506666",
		description = "Automatically collects your bowl while you are near your house.",
		base = 0, preview = "Radius", available = true, -- value = studs from your plot
		levels = { { cost = 8000, value = 15 }, { cost = 60000, value = 25 }, { cost = 250000, value = 40 } },
	},
	{
		id = "Pillows", name = "Pillows", icon = "rbxassetid://90843360335412",
		description = "+2 pillows on your second floor per level.",
		base = 0, preview = "Pillows", available = true, -- value = extra pillows over Game.StartingPillows
		levels = {
			{ cost = 15000, value = 2 }, { cost = 25000, value = 4 }, { cost = 40000, value = 6 },
			{ cost = 60000, value = 8 }, { cost = 90000, value = 10 }, { cost = 135000, value = 12 },
			{ cost = 200000, value = 14 }, { cost = 300000, value = 16 }, { cost = 450000, value = 18 },
			{ cost = 650000, value = 20 }, { cost = 950000, value = 22 }, { cost = 1400000, value = 24 },
			{ cost = 2000000, value = 26 }, -- 4 + 26 = Game.MaxPillows
		},
	},
}

local byId: { [string]: UpgradeDefinition } = {}
for _, definition in list do
	table.freeze(definition.levels)
	for _, level in definition.levels do
		table.freeze(level)
	end
	byId[definition.id] = table.freeze(definition)
end

local Upgrades = {
	List = table.freeze(list),
	TabName = "Upgrades", -- extra tab in the shop next to Config/Shop.Categories
	LevelAttributePrefix = "UpgradeLevel_", -- player attribute mirror, e.g. UpgradeLevel_Speed
	PurchaseCooldown = 0.25, -- seconds between upgrade purchase requests per player
	MagnetInterval = 1, -- seconds between Bowl Magnet checks
	JumpGateLevel = 3, -- Jump level needed for the Rooftops gate (Config/Gates)
}

function Upgrades.Get(id: string): UpgradeDefinition?
	return byId[id]
end

function Upgrades.MaxLevel(id: string): number
	local definition = byId[id]
	return if definition then #definition.levels else 0
end

-- Effect value at `level` (clamped). Level 0 = base.
function Upgrades.EffectAt(id: string, level: number): number
	local definition = byId[id]
	if definition == nil then
		return 0
	end
	local clamped = math.clamp(math.floor(level), 0, #definition.levels)
	return if clamped == 0 then definition.base else definition.levels[clamped].value
end

-- Saved PlayerData.pillowCount for a Pillows level (StartingPillows + value, capped at MaxPillows).
function Upgrades.PillowCount(level: number): number
	return math.clamp(GameConfig.StartingPillows + Upgrades.EffectAt("Pillows", level), GameConfig.StartingPillows, GameConfig.MaxPillows)
end

-- Sanitises a saved/mirrored level: non-numbers, NaN and out-of-range values become valid levels.
function Upgrades.SanitizeLevel(id: string, raw: unknown): number
	if type(raw) ~= "number" or raw ~= raw then
		return 0
	end
	return math.clamp(math.floor(raw), 0, Upgrades.MaxLevel(id))
end

return table.freeze(Upgrades)

