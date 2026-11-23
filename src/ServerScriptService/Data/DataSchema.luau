--!strict
-- Shape, defaults, version and migrations of saved player data (server only).
--
-- Changing the schema later:
--   * Adding a field with a default: add it to Template() - Reconcile fills it in for old saves.
--   * Renaming / restructuring: bump VERSION and add migrations[oldVersion] that upgrades data in place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)

export type CatRecord = {
	catId: string,
	mutation: string, -- "" = none; Config/Mutations id
	tier: string, -- "Normal" | "Mega" | "Giga" (merging, Config/Mutations.Tiers)
	loyalty: number, -- toward originalOwnerUserId (loyalty: later stage)
	lastPetAt: number, -- os.time() of the last successful pet; cooldown persists across servers
	loyaltySeconds: number, -- partial seated growth interval; no offline growth
	originalOwnerUserId: number,
	timesReturned: number,
	bell: boolean, -- permanent attachment; follows this unique cat across ownership transfers
	tamed: boolean,
	tameRemaining: number, -- seconds of taming left; paused while off a pillow and while offline
	tameEndsAt: number?, -- session only: server time taming ends while on a pillow (turned into tameRemaining on save)
	pillowIndex: number?, -- nil = not on a pillow (was being carried); put on a free pillow on next join
}

export type SkipRebirthIntent = { rebirths: number, keepIds: { string } }
export type GiftIntent = { recipientUserId: number, productId: number, nonce: string, createdAt: number, purchaseId: string? }
export type GiftDelivery = { buyerUserId: number, productKey: string, grantedAt: number }
export type GiftReceipt = { recipientUserId: number, productKey: string, grantedAt: number }
export type CatIndexData = {
	discoveredByMutation: { [string]: { [string]: boolean } },
	claimedMilestones: { [string]: boolean },
}

export type PlayerData = {
	version: number,
	coins: number,
	bowlCoins: number,
	cats: { [string]: CatRecord }, -- keyed by the cat's UniqueId
	pillowCount: number, -- = Upgrades.PillowCount(upgrades.Pillows); kept consistent by migration 4 and UpgradeService
	stats: {
		catsCaught: number,
		coinsEarnedTotal: number,
		catsStolen: number, -- cats this player stole and placed
		catsLostToThieves: number,
	},

	upgrades: { [string]: number }, -- upgradeId -> level (Config/Upgrades)
	boosts: { [string]: number }, -- timed boost -> seconds remaining (paused while offline), e.g. LuckX3
	houseStyle: string, -- Config/Rebirth.HouseStyles id
	questDay: number, -- UTC day the current quests belong to (quests reset when it changes)
	lastSeen: number, -- os.time() of the last save (offline income)

	-- Reserved for later stages (defaults only for now)
	inventory: { [string]: number }, -- itemId -> count
	processedReceipts: { [string]: number }, -- PurchaseId -> os.time() when granted
	-- Gift records are durable ledgers. They must never be trimmed with ordinary receipt history.
	giftIntents: { [string]: GiftIntent }, -- gift product key -> immutable recipient until receipt acknowledgment
	giftDeliveries: { [string]: GiftDelivery }, -- PurchaseId -> recipient grant acknowledgment
	giftReceipts: { [string]: GiftReceipt }, -- PurchaseId -> buyer acknowledgment, retained permanently
	giftedPassEntitlements: { [string]: boolean }, -- pass key -> true, effective alongside native ownership
	rebirths: number,
	dailyReward: { lastClaimDay: number, streak: number, pendingCats: { string } }, -- pendingCats: catIds waiting for a free pillow
	quests: { [string]: { progress: number, claimed: boolean } },
	settings: { musicEnabled: boolean, sfxEnabled: boolean, musicVolume: number, sfxVolume: number,
		lowGraphics: boolean, tutorialDone: boolean, hotbarSlots: { string }, autoCollectEnabled: boolean, shopSeenRevision: number,
		pendingSkipRebirth: SkipRebirthIntent? },
	discovered: { [string]: boolean }, -- catId -> true once owned (cat index / collection)
	catIndex: CatIndexData,
}

local VERSION = 13
local INDEX_TABS = { "Normal", "Shiny", "Rainbow", "Diamond", "Starry" }

local function defaultCatIndex(): CatIndexData
	local buckets: { [string]: { [string]: boolean } } = {}
	for _, tab in INDEX_TABS do buckets[tab] = {} end
	return { discoveredByMutation = buckets, claimedMilestones = {} }
end

local function ensureStage176Fields(data: { [string]: any }): ()
	if type(data.catIndex) ~= "table" then data.catIndex = defaultCatIndex() end
	if type(data.catIndex.discoveredByMutation) ~= "table" then data.catIndex.discoveredByMutation = {} end
	for _, tab in INDEX_TABS do
		if type(data.catIndex.discoveredByMutation[tab]) ~= "table" then data.catIndex.discoveredByMutation[tab] = {} end
	end
	if type(data.catIndex.claimedMilestones) ~= "table" then data.catIndex.claimedMilestones = {} end
	for _, key in { "giftIntents", "giftDeliveries", "giftReceipts", "giftedPassEntitlements" } do
		if type(data[key]) ~= "table" then data[key] = {} end
	end
	if type(data.settings) ~= "table" then data.settings = {} end
	local intent = data.settings.pendingSkipRebirth
	if intent == nil then return end
	local valid = type(intent) == "table" and type(intent.rebirths) == "number"
		and intent.rebirths == intent.rebirths and intent.rebirths >= 0 and intent.rebirths < math.huge
		and intent.rebirths % 1 == 0 and type(intent.keepIds) == "table"
	if valid then
		local count = 0
		local seen: { [string]: boolean } = {}
		for index, id in intent.keepIds do
			count += 1
			if count > 3 or type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #intent.keepIds
				or type(id) ~= "string" or #id == 0 or #id > 80 or seen[id] then
				valid = false
				break
			end
			seen[id] = true
		end
		if count ~= #intent.keepIds then valid = false end
	end
	-- Reject malformed selections wholesale; truncating could discard a cat the buyer selected to keep.
	if not valid then data.settings.pendingSkipRebirth = nil end
end

local function defaultUpgrades(): { [string]: number }
	local levels: { [string]: number } = {}
	for _, definition in Upgrades.List do
		levels[definition.id] = 0
	end
	return levels
end

-- migrations[n] upgrades data from version n to n + 1, in place.
local migrations: { [number]: (data: { [string]: any }) -> () } = {
	[12] = function(data)
		ensureStage176Fields(data)
		local buckets = data.catIndex.discoveredByMutation
		-- The legacy union did not record mutations. Preserve that history in Normal and enrich it
		-- with the exact saved mutations of cats the player still owns; all cat records stay intact.
		if type(data.discovered) == "table" then
			for catId, discovered in data.discovered do
				if type(catId) == "string" and discovered == true then buckets.Normal[catId] = true end
			end
		end
		if type(data.cats) == "table" then
			for _, record in data.cats do
				if type(record) == "table" and type(record.catId) == "string" then
					local mutation = record.mutation
					local tab = if mutation == nil or mutation == "" then "Normal" else mutation
					if type(tab) == "string" and buckets[tab] ~= nil then buckets[tab][record.catId] = true end
				end
			end
		end
	end,
	[11] = function(data)
		if type(data.settings) ~= "table" then data.settings = {} end
		if type(data.settings.hotbarSlots) ~= "table" then data.settings.hotbarSlots = {} end
		if type(data.settings.autoCollectEnabled) ~= "boolean" then data.settings.autoCollectEnabled = true end
		if type(data.settings.shopSeenRevision) ~= "number" then data.settings.shopSeenRevision = 0 end
	end,
	[10] = function(data)
		-- Cat index: every cat already owned (or waiting as a daily reward) counts as discovered.
		if type(data.discovered) ~= "table" then data.discovered = {} end
		if type(data.cats) == "table" then
			for _, record in data.cats do
				if type(record) == "table" and type(record.catId) == "string" then data.discovered[record.catId] = true end
			end
		end
		local pending = if type(data.dailyReward) == "table" then data.dailyReward.pendingCats else nil
		if type(pending) == "table" then
			for _, catId in pending do
				if type(catId) == "string" then data.discovered[catId] = true end
			end
		end
	end,
	[9] = function(data)
		if type(data.settings) ~= "table" then data.settings = { musicEnabled = true, sfxEnabled = true } end
		local settings = data.settings
		if type(settings.musicVolume) ~= "number" then settings.musicVolume = 0.5 end
		if type(settings.sfxVolume) ~= "number" then settings.sfxVolume = 0.8 end
		if type(settings.lowGraphics) ~= "boolean" then settings.lowGraphics = false end
		if type(settings.tutorialDone) ~= "boolean" then
			-- Players who already caught or own cats skip the onboarding tutorial.
			local caught = type(data.stats) == "table" and type(data.stats.catsCaught) == "number" and data.stats.catsCaught > 0
			settings.tutorialDone = caught or (type(data.cats) == "table" and next(data.cats) ~= nil)
		end
	end,
	[8] = function(data)
		if type(data.questDay) ~= "number" then data.questDay = 0 end
		if type(data.lastSeen) ~= "number" then data.lastSeen = 0 end
		if type(data.dailyReward) ~= "table" then data.dailyReward = { lastClaimDay = 0, streak = 0 } end
		if type(data.dailyReward.pendingCats) ~= "table" then data.dailyReward.pendingCats = {} end
		if type(data.quests) ~= "table" then data.quests = {} end
	end,
	[7] = function(data)
		if type(data.houseStyle) ~= "string" then
			data.houseStyle = "Default"
		end
	end,
	[6] = function(data)
		-- Merge tier per cat; every existing cat is Normal. Other fields untouched.
		if type(data.cats) == "table" then
			for _, record in data.cats do
				if type(record) == "table" and type(record.tier) ~= "string" then
					record.tier = "Normal"
				end
			end
		end
	end,
	[5] = function(data)
		if type(data.boosts) ~= "table" then
			data.boosts = {}
		end
	end,
	[4] = function(data)
		-- pillowCount follows the Pillows upgrade level. Cats are never touched: any cat without an
		-- unlocked pillow stays in the save and waits (PillowService).
		local level = if type(data.upgrades) == "table" then data.upgrades.Pillows else nil
		data.pillowCount = Upgrades.PillowCount(Upgrades.SanitizeLevel("Pillows", level))
	end,
	[3] = function(data)
		-- Only fills missing upgrade levels; existing levels and unknown keys are kept as they are.
		if type(data.upgrades) ~= "table" then
			data.upgrades = {}
		end
		for _, definition in Upgrades.List do
			if type(data.upgrades[definition.id]) ~= "number" then
				data.upgrades[definition.id] = 0
			end
		end
	end,
	[2] = function(data)
		if type(data.cats) == "table" then
			for _, record in data.cats do
				if type(record) == "table" then record.bell = record.bell == true end
			end
		end
	end,
	[1] = function(data)
		-- Reconcile cannot fill individual records in a dynamic dictionary.
		if type(data.cats) == "table" then
			for _, record in data.cats do
				if type(record) == "table" then
					record.lastPetAt = 0
					record.loyaltySeconds = 0
				end
			end
		end
	end,
}

local DataSchema = {
	Version = VERSION,
}

function DataSchema.Template(): PlayerData
	return {
		version = VERSION,
		coins = GameConfig.StartingCoins,
		bowlCoins = 0,
		cats = {},
		pillowCount = GameConfig.StartingPillows,
		stats = {
			catsCaught = 0,
			coinsEarnedTotal = 0,
			catsStolen = 0,
			catsLostToThieves = 0,
		},
		upgrades = defaultUpgrades(),
		boosts = {},
		houseStyle = "Default",
		inventory = {},
		processedReceipts = {},
		giftIntents = {},
		giftDeliveries = {},
		giftReceipts = {},
		giftedPassEntitlements = {},
		rebirths = 0,
		dailyReward = { lastClaimDay = 0, streak = 0, pendingCats = {} },
		questDay = 0,
		lastSeen = 0,
		quests = {},
		settings = { musicEnabled = true, sfxEnabled = true, musicVolume = 0.5, sfxVolume = 0.8, lowGraphics = false, tutorialDone = false,
			hotbarSlots = {}, autoCollectEnabled = true, shopSeenRevision = 0 },
		discovered = {},
		catIndex = defaultCatIndex(),
	}
end

-- Upgrades `data` to the current version. Returns false (and a reason) if it can't, e.g. the save was
-- written by a newer server - in that case the caller must not let this server modify it.
function DataSchema.Migrate(data: { [string]: any }): (boolean, string?)
	if type(data.version) ~= "number" then
		data.version = 1 -- no save predates versioning
	end
	if data.version > VERSION then
		return false, `save version {data.version} is newer than this server's {VERSION}`
	end
	while data.version < VERSION do
		local migrate = migrations[data.version]
		if migrate == nil then
			return false, `no migration from version {data.version}`
		end
		migrate(data)
		data.version += 1
	end
	ensureStage176Fields(data) -- validate optional purchase intent on every join, including current saves
	return true, nil
end

function DataSchema.NewCatRecord(catId: string, ownerUserId: number, tameTime: number): CatRecord
	return {
		catId = catId,
		mutation = "",
		tier = "Normal",
		loyalty = 0,
		lastPetAt = 0,
		loyaltySeconds = 0,
		originalOwnerUserId = ownerUserId,
		timesReturned = 0,
		bell = false,
		tamed = false,
		tameRemaining = tameTime,
		tameEndsAt = nil,
		pillowIndex = nil,
	}
end

return table.freeze(DataSchema)


