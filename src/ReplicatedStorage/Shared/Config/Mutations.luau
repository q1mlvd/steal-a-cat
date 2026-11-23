--!strict
-- Cat mutations (rolled when a wild cat spawns; saved in CatRecord.mutation, "" = none) and merge tiers.
-- Roll: rarest first, each checked independently with chance x luck (luck = LuckService.GetLuckNear at the
-- spawn point); the first hit wins. chance = 0 means "never rolled" (event/seasonal mutations are applied
-- by EventService / admin instead). Income multipliers stack with every other per-cat source (e.g. Loyal).

export type Visual = "Sparkles" | "Rainbow" | "Diamond" | "Stars" | "Glow"
export type Mutation = {
	id: string,
	displayName: string,
	multiplier: number,
	chance: number, -- per spawn before luck (0 = event/seasonal only)
	color: Color3,
	visual: Visual,
	announce: boolean, -- server-wide announcement when it spawns
	season: string?, -- only rolled while this season is enabled (Config/Events)
}
export type Tier = { id: string, displayName: string, multiplier: number, scale: number }

local list: { Mutation } = {
	-- Rarest first (roll order).
	{ id = "Diamond", displayName = "Diamond", multiplier = 10, chance = 0.001, color = Color3.fromRGB(150, 230, 255), visual = "Diamond", announce = true },
	{ id = "Rainbow", displayName = "Rainbow", multiplier = 5, chance = 0.01, color = Color3.fromRGB(255, 120, 200), visual = "Rainbow", announce = false },
	{ id = "Shiny", displayName = "Shiny", multiplier = 2, chance = 0.05, color = Color3.fromRGB(255, 240, 150), visual = "Sparkles", announce = false },
	-- Event / seasonal (never from the normal roll).
	{ id = "Starry", displayName = "Starry", multiplier = 3, chance = 0, color = Color3.fromRGB(255, 230, 90), visual = "Stars", announce = false },
	{ id = "Spooky", displayName = "Spooky", multiplier = 3, chance = 0.02, color = Color3.fromRGB(255, 140, 30), visual = "Glow", announce = false, season = "Halloween" },
	{ id = "Frosty", displayName = "Frosty", multiplier = 3, chance = 0.02, color = Color3.fromRGB(170, 220, 255), visual = "Glow", announce = false, season = "Christmas" },
}

local tiers: { Tier } = {
	{ id = "Normal", displayName = "", multiplier = 1, scale = 1 },
	{ id = "Mega", displayName = "Mega", multiplier = 4, scale = 1.5 },
	{ id = "Giga", displayName = "Giga", multiplier = 20, scale = 2 },
}

local byId: { [string]: Mutation } = {}
for _, mutation in list do
	byId[mutation.id] = table.freeze(mutation)
end
local tierById: { [string]: Tier } = {}
local tierIndex: { [string]: number } = {}
for index, tier in tiers do
	tierById[tier.id] = table.freeze(tier)
	tierIndex[tier.id] = index
end

local Mutations = {
	List = table.freeze(list),
	Tiers = table.freeze(tiers),
	DefaultTier = "Normal",
	MaxChance = 0.5, -- cap on chance x luck
	MergeCount = 3, -- cats of the same CatId and tier per merge
	AnnounceRarityOrder = 5, -- Legendary and rarer spawns are announced (Secret has its own announcement)
	TierAttribute = "Tier", -- cat Model attribute (server-set)
	LocalVisualAttribute = "MutationVisual", -- client-only marker
	RainbowCycleSeconds = 3,
	DiamondReflectance = 0.35,
	ParticleRate = 6,
	-- Textured art meshes ignore Color: Rainbow / Diamond tint a slightly larger untextured shell copy.
	ShellScale = 1.04,
	RainbowShellTransparency = 0.35, -- ForceField material (shimmer)
	DiamondShellTransparency = 0.45, -- Glass material

	-- Merge Machine
	MachineTag = "MergeMachine",
	MachinePromptName = "MergePrompt",
	MachineActionText = "Merge cats",
	UseDistance = 14, -- studs (server check)
	SessionDuration = 120, -- seconds after opening the machine
	RequestCooldown = 0.5,
}

function Mutations.Get(id: string): Mutation?
	return byId[id]
end

function Mutations.IsValid(id: unknown): boolean
	return type(id) == "string" and (id == "" or byId[id] ~= nil)
end

function Mutations.Multiplier(id: unknown): number
	local mutation = if type(id) == "string" then byId[id] else nil
	return if mutation then mutation.multiplier else 1
end

function Mutations.GetTier(id: unknown): Tier
	return (if type(id) == "string" then tierById[id] else nil) or tierById.Normal
end

function Mutations.NextTier(id: string): Tier?
	local index = tierIndex[id]
	return if index then tiers[index + 1] else nil
end

-- Better = higher income multiplier ("" counts as 1).
function Mutations.Best(a: string, b: string): string
	return if Mutations.Multiplier(b) > Mutations.Multiplier(a) then b else a
end

-- Rolls a mutation id ("" = none). `season` enables that season's mutations.
function Mutations.Roll(random: Random, luck: number, season: string?): string
	for _, mutation in list do
		if mutation.chance > 0 and (mutation.season == nil or mutation.season == season)
			and random:NextNumber() < math.min(Mutations.MaxChance, mutation.chance * luck) then
			return mutation.id
		end
	end
	return ""
end

return table.freeze(Mutations)

