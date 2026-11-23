--!strict
-- Game Passes and Developer Products. IDs are PLACEHOLDERS (0): an item with id 0 is hidden from the store
-- and never owned (outside Studio debug overrides). Robux prices are display-only (Roblox charges the
-- price set on the website). Fill in real ids after creating the items on the Creator Dashboard.
--
-- Fairness: passes/products are convenience, speed-ups or cosmetics; every power they give is also
-- reachable for free (upgrades, catching, rebirths) - see ServerStorage/DevLog for the per-item list.

export type PassKey = "LuckX2" | "IncomeX2" | "FastLegs" | "BigHands" | "SuperLock" | "EternalLoyalty"
	| "AutoCollect" | "VIP" | "ExtraPillows" | "Keep3Cats"
export type ProductKey = string -- Config catalog remains the authoritative whitelist (includes separate gift SKUs).

export type Pass = { key: PassKey, passId: number, name: string, description: string, robux: number, icon: string }
export type Product = { key: ProductKey, productId: number, name: string, description: string, robux: number, icon: string,
	gift: boolean?, giftPassKey: PassKey?, giftBaseKey: string? }

local passes: { Pass } = {
	{ key = "LuckX2", passId = 0, name = "Luck x2", robux = 199, icon = "rbxassetid://94683126160656",
		description = "Rarer cats spawn near you twice as often." },
	{ key = "IncomeX2", passId = 0, name = "Income x2", robux = 399, icon = "rbxassetid://71952167997886",
		description = "Your cats earn double coins." },
	{ key = "FastLegs", passId = 0, name = "Fast Legs", robux = 149, icon = "rbxassetid://124687567504060",
		description = "+30% walk speed, stacks with the Speed upgrade." },
	{ key = "BigHands", passId = 0, name = "Big Hands", robux = 249, icon = "rbxassetid://131909513031128",
		description = "Carry one more cat on top of the Hands upgrade." },
	{ key = "SuperLock", passId = 0, name = "Super Lock", robux = 149, icon = "rbxassetid://135945773447151",
		description = "Your door locks for 2 minutes with a 2 minute cooldown." },
	{ key = "EternalLoyalty", passId = 0, name = "Eternal Loyalty", robux = 199, icon = "rbxassetid://96359758102020",
		description = "Cats you catch start with 50 loyalty." },
	{ key = "AutoCollect", passId = 0, name = "Auto Collect", robux = 149, icon = "rbxassetid://106026288506666",
		description = "Your bowl is collected automatically wherever you are." },
	{ key = "VIP", passId = 0, name = "VIP", robux = 299, icon = "rbxassetid://85597655828385",
		description = "+20% income, VIP name tag and the VIP lounge on the square." },
	{ key = "ExtraPillows", passId = 0, name = "Extra Pillows", robux = 249, icon = "rbxassetid://90843360335412",
		description = "+6 pillows right away (up to the 30 pillow maximum)." },
	{ key = "Keep3Cats", passId = 0, name = "Keep 3 Cats", robux = 199, icon = "rbxassetid://122177123623038",
		description = "Keep 3 cats instead of 1 when you rebirth." },
}

local products: { Product } = {
	{ key = "ServerLuck", productId = 0, name = "Server Luck x1 → x2", robux = 49, icon = "rbxassetid://94683126160656",
		description = "Double server luck for 15 minutes. Buying again adds time." },
	{ key = "RoyalCat", productId = 0, name = "Royal Cat", robux = 249, icon = "rbxassetid://73389021495547",
		description = "Earns 1.5 times your best regular cat's income. Requires a free pillow." },
	{ key = "AdminCat", productId = 0, name = "Admin Cat", robux = 499, icon = "rbxassetid://86645085743520",
		description = "Earns 3 times your best regular cat's income. Requires a free pillow." },
	{ key = "SkipRebirth", productId = 0, name = "Skip Rebirth", robux = 49, icon = "rbxassetid://122177123623038",
		description = "Rebirth without paying coins. The normal reset and keep rules still apply." },
	{ key = "LuckX3", productId = 0, name = "Luck x3 (15 min)", robux = 49, icon = "rbxassetid://94683126160656",
		description = "Triple luck for 15 minutes. Buying again adds time." },
	{ key = "InstantTame", productId = 0, name = "Instant Tame", robux = 25, icon = "rbxassetid://106950527147543",
		description = "Finishes taming every untamed cat on your pillows." },
	{ key = "CatBox", productId = 0, name = "Cat Box", robux = 99, icon = "rbxassetid://73389021495547",
		description = "A random cat walks to a free pillow. Chance for Legendary!" },
	{ key = "SummonMythic", productId = 0, name = "Summon Mythic Cat", robux = 199, icon = "rbxassetid://86645085743520",
		description = "A wild Mythic cat appears in the city for everyone." },
	{ key = "CoinsSmall", productId = 0, name = "Small Coin Pack", robux = 25, icon = "rbxassetid://103817162019925",
		description = "Coins (more when your income is higher)." },
	{ key = "CoinsMedium", productId = 0, name = "Medium Coin Pack", robux = 75, icon = "rbxassetid://124407138258299",
		description = "Coins (more when your income is higher)." },
	{ key = "CoinsLarge", productId = 0, name = "Large Coin Pack", robux = 199, icon = "rbxassetid://80097009481400",
		description = "Coins (more when your income is higher)." },
	{ key = "CoinsTiny", productId = 0, name = "Tiny Coin Pack", robux = 10, icon = "rbxassetid://103817162019925",
		description = "Coins (more when your income is higher)." },
	{ key = "CoinsHuge", productId = 0, name = "Huge Coin Pack", robux = 399, icon = "rbxassetid://124407138258299",
		description = "Coins (more when your income is higher)." },
	{ key = "CoinsMega", productId = 0, name = "Mega Coin Pack", robux = 799, icon = "rbxassetid://80097009481400",
		description = "Coins (more when your income is higher)." },
}

-- Gifts are separate Developer Products. Roblox Game Passes themselves are never transferred.
-- Replace each gift productId independently when configuring the Creator Dashboard.
-- Keep gift SKUs off the external experience Store tab: they require an in-server recipient intent.
for _, base in table.clone(products) do
	if base.key == "RoyalCat" or base.key == "AdminCat" or string.sub(base.key, 1, 5) == "Coins" then
		table.insert(products, { key = "Gift" .. base.key, productId = 0, name = "Gift " .. base.name,
			description = base.description, robux = base.robux, icon = base.icon, gift = true, giftBaseKey = base.key })
	end
end
for _, pass in passes do
	table.insert(products, { key = "GiftPass_" .. pass.key, productId = 0, name = "Gift " .. pass.name,
		description = pass.description, robux = pass.robux, icon = pass.icon, gift = true, giftPassKey = pass.key })
end

local passByKey: { [string]: Pass } = {}
for _, pass in passes do
	passByKey[pass.key] = table.freeze(pass)
end
local productByKey: { [string]: Product } = {}
for _, product in products do
	productByKey[product.key] = table.freeze(product)
end

local Monetization = {
	Passes = table.freeze(passes),
	Products = table.freeze(products),
	PassAttributePrefix = "Pass_", -- player attribute mirror (last known state, UI only)
	DebugPassAttributePrefix = "DebugPass_", -- Studio only, server-side Player attribute: true grant / false revoke / nil Roblox
	OwnershipRetries = 3,
	OwnershipRetryDelay = 2,
	PurchaseRequestCooldown = 1, -- seconds between store prompt requests
	-- Paid processedReceipts are permanent: never trim acknowledged PurchaseIds.
	ReceiptSaveTimeout = 15, -- seconds ProcessReceipt waits for the profile save

	-- Pass effects
	LuckX2Multiplier = 2,
	IncomeX2Multiplier = 2,
	FastLegsMultiplier = 1.3,
	BigHandsBonus = 1,
	SuperLockDuration = 120,
	SuperLockCooldown = 120,
	EternalLoyaltyStart = 50,
	VipIncomeMultiplier = 1.2,
	ExtraPillowsBonus = 6,
	KeepCatsWithPass = 3,

	-- Product effects
	LuckX3Multiplier = 3,
	LuckX3Duration = 900, -- seconds added per purchase
	CatBoxWeights = table.freeze({ Common = 40, Uncommon = 30, Rare = 18, Epic = 9, Legendary = 3 }),
	SummonRarity = "Mythic",
	CoinPacks = table.freeze({
		CoinsTiny = table.freeze({ base = 1000, incomeSeconds = 60 }),
		CoinsSmall = table.freeze({ base = 5000, incomeSeconds = 300 }),
		CoinsMedium = table.freeze({ base = 25000, incomeSeconds = 1200 }),
		CoinsLarge = table.freeze({ base = 100000, incomeSeconds = 3600 }),
		CoinsHuge = table.freeze({ base = 500000, incomeSeconds = 10800 }),
		CoinsMega = table.freeze({ base = 2500000, incomeSeconds = 28800 }),
	}),
	StoreTabName = "Robux",
}

function Monetization.GetPass(key: string): Pass?
	return passByKey[key]
end

function Monetization.GetProduct(key: string): Product?
	return productByKey[key]
end

function Monetization.GetProductByProductId(productId: number): Product?
	if productId == 0 then
		return nil
	end
	for _, product in products do
		if product.productId == productId then
			return product
		end
	end
	return nil
end

function Monetization.GetPassByPassId(passId: number): Pass?
	if passId == 0 then
		return nil
	end
	for _, pass in passes do
		if pass.passId == passId then
			return pass
		end
	end
	return nil
end

-- Coins for a coin pack: the base amount or `incomeSeconds` of the buyer's current income, whichever is larger.
function Monetization.CoinPackAmount(key: string, incomePerSecond: number): number
	local pack = (Monetization.CoinPacks :: any)[key]
	if pack == nil then
		return 0
	end
	local income = if incomePerSecond == incomePerSecond and incomePerSecond > 0 and incomePerSecond < math.huge then incomePerSecond else 0
	return math.floor(math.max(pack.base, income * pack.incomeSeconds))
end

return table.freeze(Monetization)

