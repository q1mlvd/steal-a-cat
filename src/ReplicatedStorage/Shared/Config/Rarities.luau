--!strict
-- Rarity tiers, ordered from most common to rarest.
-- Every per-rarity tunable lives here; logic code must read from this module.

export type RarityId = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Secret"

export type Rarity = {
	id: RarityId,
	displayName: string,
	order: number, -- 1 = most common; use for sorting / comparisons
	color: Color3,
	spawnWeight: number, -- relative weight for the city spawner (weights need not sum to 100)
	tameTime: number, -- seconds a wild cat must spend at home before it is fully tamed
	carrySpeedPenalty: number, -- fraction of WalkSpeed lost while carrying (0.10 = 10% slower)
	catchZoneSize: number, -- fraction (0..1) of the catch minigame bar that is the green zone
	fleeSpeed: number, -- WalkSpeed of a wild cat running from a player (default player WalkSpeed is 16)
}

local list: { Rarity } = {
	{ id = "Common",    displayName = "Common",    order = 1, color = Color3.fromRGB(180, 180, 180), spawnWeight = 60,   tameTime = 30,  carrySpeedPenalty = 0.10, catchZoneSize = 0.40, fleeSpeed = 12 },
	{ id = "Uncommon",  displayName = "Uncommon",  order = 2, color = Color3.fromRGB(85, 200, 90),   spawnWeight = 25,   tameTime = 60,  carrySpeedPenalty = 0.15, catchZoneSize = 0.32, fleeSpeed = 14 },
	{ id = "Rare",      displayName = "Rare",      order = 3, color = Color3.fromRGB(60, 140, 255),  spawnWeight = 10,   tameTime = 120, carrySpeedPenalty = 0.20, catchZoneSize = 0.25, fleeSpeed = 16 },
	{ id = "Epic",      displayName = "Epic",      order = 4, color = Color3.fromRGB(170, 80, 255),  spawnWeight = 4,    tameTime = 240, carrySpeedPenalty = 0.25, catchZoneSize = 0.18, fleeSpeed = 18 },
	{ id = "Legendary", displayName = "Legendary", order = 5, color = Color3.fromRGB(255, 190, 40),  spawnWeight = 0.9,  tameTime = 420, carrySpeedPenalty = 0.30, catchZoneSize = 0.12, fleeSpeed = 20 },
	{ id = "Mythic",    displayName = "Mythic",    order = 6, color = Color3.fromRGB(255, 60, 110),  spawnWeight = 0.09, tameTime = 600, carrySpeedPenalty = 0.35, catchZoneSize = 0.08, fleeSpeed = 22 },
	{ id = "Secret",    displayName = "Secret",    order = 7, color = Color3.fromRGB(20, 20, 30),    spawnWeight = 0.01, tameTime = 900, carrySpeedPenalty = 0.40, catchZoneSize = 0.05, fleeSpeed = 24 },
}

local byId: { [string]: Rarity } = {}
for index, rarity in list do
	assert(byId[rarity.id] == nil, `Duplicate rarity id "{rarity.id}"`)
	assert(rarity.order == index, `Rarity "{rarity.id}" order must match its list position`)
	assert(rarity.fleeSpeed > 0, `Rarity "{rarity.id}" needs a positive fleeSpeed`)
	assert(rarity.spawnWeight > 0, `Rarity "{rarity.id}" needs a positive spawnWeight`)
	assert(rarity.catchZoneSize > 0 and rarity.catchZoneSize <= 1, `Rarity "{rarity.id}" catchZoneSize must be in (0, 1]`)
	byId[rarity.id] = table.freeze(rarity)
end

local Rarities = {
	List = table.freeze(list),
	ById = table.freeze(byId),
}

function Rarities.Get(id: string): Rarity?
	return byId[id]
end

return table.freeze(Rarities)

