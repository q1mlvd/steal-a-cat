--!strict
-- Every catchable cat. `rarity` must be an id from Config/Rarities.

local Rarities = require(script.Parent.Rarities)

export type Cat = {
	id: string, -- stable key used in saves; never rename once shipped
	name: string, -- display name
	rarity: Rarities.RarityId,
	coinsPerSecond: number, -- income while sitting on a pillow
	season: string?, -- seasonal cat: only spawns while Config/Events.Season matches (never in ByRarity)
	-- Art (Stage 17): model in ServerStorage/CatModels (nil = CatTemplate), portrait and collection silhouette.
	modelName: string?,
	icon: string?,
	silhouette: string?,
	district: string?,
	exclusive: boolean?,
	indexExcluded: boolean?,
	spawnEnabled: boolean?,
	defaultMutation: string?,
}

local list: { Cat } = {
	-- Common
	{ id = "barsik",       name = "Barsik",       rarity = "Common",    coinsPerSecond = 1, modelName = "Barsik", icon = "rbxassetid://132400819303673", silhouette = "rbxassetid://123192678157233" },
	{ id = "murzik",       name = "Murzik",       rarity = "Common",    coinsPerSecond = 1, modelName = "Murzik", icon = "rbxassetid://74715647767411", silhouette = "rbxassetid://123192678157233" },
	{ id = "stripey",      name = "Stripey",      rarity = "Common",    coinsPerSecond = 2, modelName = "Stripey", icon = "rbxassetid://98507084697216", silhouette = "rbxassetid://132969750980910" },
	{ id = "ginger",       name = "Ginger",       rarity = "Common",    coinsPerSecond = 2, modelName = "Ginger", icon = "rbxassetid://78281538189793", silhouette = "rbxassetid://135934944083644" },
	{ id = "chubby",       name = "Chubby",       rarity = "Common",    coinsPerSecond = 3, modelName = "Chubby", icon = "rbxassetid://138097574764601", silhouette = "rbxassetid://89450742681388" },
	-- Uncommon
	{ id = "siamese",      name = "Siamese",      rarity = "Uncommon",  coinsPerSecond = 5, modelName = "Siamese", icon = "rbxassetid://128755144333721", silhouette = "rbxassetid://96496171277701" },
	{ id = "sock_cat",     name = "Sock Cat",     rarity = "Uncommon",  coinsPerSecond = 6, modelName = "SockCat", icon = "rbxassetid://71472757020903", silhouette = "rbxassetid://74628523530488" },
	{ id = "sleepy_cat",   name = "Sleepy Cat",   rarity = "Uncommon",  coinsPerSecond = 8, modelName = "SleepyCat", icon = "rbxassetid://128859592002163", silhouette = "rbxassetid://134458305599636" },
	{ id = "bread_cat",    name = "Bread Cat",    rarity = "Uncommon",  coinsPerSecond = 10, modelName = "BreadCat", icon = "rbxassetid://84232545467472", silhouette = "rbxassetid://79630307489447" },
	-- Rare
	{ id = "ninja_cat",    name = "Ninja Cat",    rarity = "Rare",      coinsPerSecond = 20, modelName = "NinjaCat", icon = "rbxassetid://107658001539067", silhouette = "rbxassetid://70515573700030" },
	{ id = "maine_coon",   name = "Maine Coon",   rarity = "Rare",      coinsPerSecond = 25, modelName = "MaineCoon", icon = "rbxassetid://71331656613061", silhouette = "rbxassetid://112723291190182" },
	{ id = "box_cat",      name = "Box Cat",      rarity = "Rare",      coinsPerSecond = 30, modelName = "BoxCat", icon = "rbxassetid://84273084033288", silhouette = "rbxassetid://88599643120146" },
	{ id = "pirate_cat",   name = "Pirate Cat",   rarity = "Rare",      coinsPerSecond = 40, modelName = "PirateCat", icon = "rbxassetid://72876160002656", silhouette = "rbxassetid://83046666080363" },
	{ id = "chef_cat",     name = "Chef Cat",     rarity = "Rare",      coinsPerSecond = 30, modelName = "ChefCat", icon = "rbxassetid://101548678981925", silhouette = "rbxassetid://98309755480240" },
	-- Epic
	{ id = "hacker_cat",   name = "Hacker Cat",   rarity = "Epic",      coinsPerSecond = 80, modelName = "HackerCat", icon = "rbxassetid://77782115762182", silhouette = "rbxassetid://101795303203393" },
	{ id = "vampire_cat",  name = "Vampire Cat",  rarity = "Epic",      coinsPerSecond = 100, modelName = "VampireCat", icon = "rbxassetid://84296572023046", silhouette = "rbxassetid://89305972477763" },
	{ id = "fire_cat",     name = "Fire Cat",     rarity = "Epic",      coinsPerSecond = 120, modelName = "FireCat", icon = "rbxassetid://103519139571548", silhouette = "rbxassetid://120002689564140" },
	{ id = "dj_cat",       name = "DJ Cat",       rarity = "Epic",      coinsPerSecond = 150, modelName = "DJCat", icon = "rbxassetid://122391858258499", silhouette = "rbxassetid://107176711179618" },
	-- Legendary
	{ id = "golden_cat",   name = "Golden Cat",   rarity = "Legendary", coinsPerSecond = 400, modelName = "GoldenCat", icon = "rbxassetid://98600415653155", silhouette = "rbxassetid://107821871510569" },
	{ id = "samurai_cat",  name = "Samurai Cat",  rarity = "Legendary", coinsPerSecond = 600, modelName = "SamuraiCat", icon = "rbxassetid://88061082983692", silhouette = "rbxassetid://140028730899933" },
	{ id = "ghost_cat",    name = "Ghost Cat",    rarity = "Legendary", coinsPerSecond = 800, modelName = "GhostCat", icon = "rbxassetid://138065293061824", silhouette = "rbxassetid://135129882439608" },
	{ id = "astronaut_cat", name = "Astronaut Cat", rarity = "Legendary", coinsPerSecond = 600, modelName = "AstronautCat", icon = "rbxassetid://101595148736681", silhouette = "rbxassetid://86635903576429" },
	-- Mythic
	{ id = "cosmic_cat",   name = "Cosmic Cat",   rarity = "Mythic",    coinsPerSecond = 2000, modelName = "CosmicCat", icon = "rbxassetid://126422208595176", silhouette = "rbxassetid://118066099291673" },
	{ id = "dragon_cat",   name = "Dragon Cat",   rarity = "Mythic",    coinsPerSecond = 5000, modelName = "DragonCat", icon = "rbxassetid://119026802828586", silhouette = "rbxassetid://74400198902984" },
	-- Secret
	{ id = "shlepa",       name = "Shlepa",       rarity = "Secret",    coinsPerSecond = 15000, modelName = "Shlepa", icon = "rbxassetid://86026183588394", silhouette = "rbxassetid://118671944025391" },
	-- Exclusive income is resolved from the owner's best regular cat, never from this placeholder.
	{ id="royal_cat", name="Royal Cat", rarity="Legendary", coinsPerSecond=1, modelName="GoldenCat", icon="rbxassetid://98600415653155", silhouette="rbxassetid://107821871510569", exclusive=true, indexExcluded=true, spawnEnabled=false, defaultMutation="Diamond", district="Exclusive" },
	{ id="admin_cat", name="Admin Cat", rarity="Secret", coinsPerSecond=1, modelName="HackerCat", icon="rbxassetid://77782115762182", silhouette="rbxassetid://101795303203393", exclusive=true, indexExcluded=true, spawnEnabled=false, defaultMutation="Rainbow", district="Exclusive" },
	-- Seasonal (Config/Events.Season)
	{ id = "pumpkin_cat",  name = "Pumpkin Cat",  rarity = "Rare",      coinsPerSecond = 45, season = "Halloween" },
	{ id = "witch_cat",    name = "Witch Cat",    rarity = "Epic",      coinsPerSecond = 170, season = "Halloween" },
	{ id = "santa_cat",    name = "Santa Cat",    rarity = "Epic",      coinsPerSecond = 170, season = "Christmas" },
	{ id = "snow_cat",     name = "Snow Cat",     rarity = "Rare",      coinsPerSecond = 45, season = "Christmas" },
}

local byId: { [string]: Cat } = {}
local byRarity: { [string]: { Cat } } = {}
local seasonal: { [string]: { [string]: { Cat } } } = {} -- season -> rarity -> cats
for _, rarity in Rarities.List do
	byRarity[rarity.id] = {}
end

for _, cat in list do
	assert(byId[cat.id] == nil, `Duplicate cat id "{cat.id}"`)
	assert(Rarities.Get(cat.rarity) ~= nil, `Cat "{cat.id}" has unknown rarity "{cat.rarity}"`)
	assert(cat.coinsPerSecond > 0, `Cat "{cat.id}" needs a positive coinsPerSecond`)
	if cat.district == nil then
		cat.district = ({Common="Residential",Uncommon="Residential",Rare="Park",Epic="Industrial",Legendary="Rooftops",Mythic="Sewers",Secret="Sewers"} :: {[string]:string})[cat.rarity]
	end
	table.freeze(cat)
	byId[cat.id] = cat
	if cat.season then
		seasonal[cat.season] = seasonal[cat.season] or {}
		seasonal[cat.season][cat.rarity] = seasonal[cat.season][cat.rarity] or {}
		table.insert(seasonal[cat.season][cat.rarity], cat)
	elseif cat.spawnEnabled ~= false then
		table.insert(byRarity[cat.rarity], cat)
	end
end

for id, cats in byRarity do
	assert(#cats > 0, `Rarity "{id}" has no cats`)
	table.freeze(cats)
end

local Cats = {
	List = table.freeze(list),
	ById = table.freeze(byId),
	ByRarity = table.freeze(byRarity),
}

function Cats.Get(id: string): Cat?
	return byId[id]
end

-- Seasonal cats of a rarity for a season (empty when none).
function Cats.GetSeasonal(season: string?, rarityId: string): { Cat }
	local bySeason = if season then seasonal[season] else nil
	return (if bySeason then bySeason[rarityId] else nil) or {}
end

return table.freeze(Cats)

