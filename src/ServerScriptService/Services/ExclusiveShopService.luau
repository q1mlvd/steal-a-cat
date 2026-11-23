--!strict
-- Exclusive shop and recipient-bound gifts. A gift intent is saved before prompting; receipt delivery
-- writes the recipient grant and PurchaseId ledger together, confirms that save, then permits buyer ack.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Shared = ReplicatedStorage.Shared
local Config = Shared.Config
local Rules = require(Config.ExclusiveShop)
local Monetization = require(Config.Monetization)
local Network = require(Shared.Network)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local LuckService = require(script.Parent.LuckService)
local MonetizationService = require(script.Parent.MonetizationService)
local MultiplierService = require(script.Parent.MultiplierService)
local NotificationService = require(script.Parent.NotificationService)
local PillowService = require(script.Parent.PillowService)
local PlotService = require(script.Parent.PlotService)

local Service = { Priority = 104 }
local requestTimes: { [Player]: number } = {}
local stateEvent: RemoteEvent
local subscribers: { [Player]: boolean } = {}
local clearingIntents: { [Player]: { [string]: boolean } } = {}

local function preview(player: Player): boolean
	return RunService:IsStudio() and DataService.IsStudioTestProfile()
		and player:GetAttribute(Rules.GiftDebugAttribute) == true
end

local function allowed(player: Player): boolean
	if player.Parent ~= Players or DataService.GetData(player) == nil then return false end
	local now = os.clock()
	if now - (requestTimes[player] or -math.huge) < Rules.RequestCooldown then return false end
	requestTimes[player] = now
	return true
end

local function catOffer(key: string): any
	return (Rules.CatOffers :: any)[key]
end

local function listedOffer(key: string): boolean
	return Monetization.GetPass(key) ~= nil or table.find(Rules.ProductOfferKeys, key) ~= nil
		or table.find(Rules.CoinOfferKeys, key) ~= nil
end

-- This is used only when no native prompt API was attempted. A closed/canceled/errored native prompt
-- must keep its recipient lock because a delayed receipt cannot be correlated to an intent nonce.
local function clearPrePromptIntent(player: Player, data: any, key: string, intent: any): boolean
	if DataService.GetData(player) ~= data or data.giftIntents[key] ~= intent or intent.purchaseId ~= nil then return false end
	local clearing = clearingIntents[player] or {}
	clearingIntents[player] = clearing clearing[key] = true
	data.giftIntents[key] = nil
	local saved = DataService.SaveAndWait(player, function(savedData: any): boolean
		return type(savedData.giftIntents) == "table" and savedData.giftIntents[key] == nil
	end, Rules.GiftIntentSaveTimeout)
	if not saved and DataService.GetData(player) == data and data.giftIntents[key] == nil then
		data.giftIntents[key] = intent
	end
	clearing[key] = nil
	if next(clearing) == nil then clearingIntents[player] = nil end
	return saved
end

local function canReceive(recipient: Player?, product: Monetization.Product): (boolean, string)
	if recipient == nil or recipient.Parent ~= Players or DataService.GetData(recipient) == nil then
		return false, "ExclusiveShop.RecipientUnavailable"
	end
	if product.giftPassKey then
		if not MonetizationService.IsOwnershipReady(recipient, product.giftPassKey) then return false, "ExclusiveShop.Loading" end
		if MonetizationService.OwnsPass(recipient, product.giftPassKey) then return false, "ExclusiveShop.RecipientOwned" end
	elseif catOffer(product.giftBaseKey or product.key) then
		if PlotService.GetPlot(recipient) == nil or PillowService.GetFreePillow(recipient) == nil then
			return false, "ExclusiveShop.FreePillow"
		end
		local character = recipient.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid == nil or humanoid.Health <= 0 then return false, "ExclusiveShop.RecipientUnavailable" end
	end
	return true, "ExclusiveShop.PromptOpened"
end

local function giftIntent(player: Player, product: Monetization.Product): (any?, Player?, string?)
	local data = DataService.GetData(player)
	local intent = if data then data.giftIntents[product.key] else nil
	if intent == nil or intent.productId ~= product.productId or type(intent.recipientUserId) ~= "number" then
		return nil, nil, "ExclusiveShop.SelectRecipient"
	end
	local recipient = Players:GetPlayerByUserId(intent.recipientUserId)
	return intent, recipient, nil
end

function Service.GetSnapshot(player: Player): { [string]: any }
	local data = DataService.GetData(player)
	local debugPreview = preview(player)
	local offers = {}
	local function add(key: string, section: string)
		local pass = Monetization.GetPass(key)
		local product = Monetization.GetProduct(key)
		if pass == nil and product == nil then return end
		local definition: any = pass or product
		local configured = (if pass then pass.passId else (product :: Monetization.Product).productId) > 0
		local giftKey = if pass then "GiftPass_" .. key elseif key ~= "ServerLuck" then "Gift" .. key else nil
		local gift = if giftKey then Monetization.GetProduct(giftKey) else nil
		local giftConfigured = gift ~= nil and gift.productId > 0
		if not configured and not giftConfigured and not debugPreview then return end
		local price = if configured then MonetizationService.GetPrice(key) else nil
		local giftPrice = if giftConfigured then MonetizationService.GetPrice(giftKey :: string) else nil
		local cat = catOffer(key)
		local owned = pass ~= nil and MonetizationService.OwnsPass(player, key)
		local pending = if data and giftKey then data.giftIntents[giftKey] else nil
		table.insert(offers, {
			key = key, section = section, kind = if pass then "Pass" else "Product", icon = definition.icon,
			priceRobux = price, giftPriceRobux = giftPrice, previewPrice = definition.robux,
			available = configured and price ~= nil, giftAvailable = giftConfigured and giftPrice ~= nil,
			owned = owned, giftKey = giftKey, catId = if cat then cat.catId else nil,
			income = if cat then EconomyService.GetRegularCatIncomePerSecond(player) * cat.factor * MultiplierService.GetIncomeMultiplier(player) else nil,
			coins = if (Monetization.CoinPacks :: any)[key] then Monetization.CoinPackAmount(key, EconomyService.GetIncomePerSecond(player)) else nil,
			pendingRecipientUserId = if pending then pending.recipientUserId else nil,
		})
	end
	for _, key in Rules.ProductOfferKeys do add(key, if catOffer(key) then "SpecialCats" else "Offers") end
	for _, pass in Monetization.Passes do add(pass.key, "Passes") end
	for _, key in Rules.CoinOfferKeys do add(key, "Coins") end
	local players = {}
	for _, other in Players:GetPlayers() do
		if other ~= player and DataService.GetData(other) ~= nil then
			table.insert(players, { userId = other.UserId, displayName = other.DisplayName, name = other.Name,
				bestRegularIncome = EconomyService.GetRegularCatIncomePerSecond(other), incomeMultiplier = MultiplierService.GetIncomeMultiplier(other),
				incomePerSecond = EconomyService.GetIncomePerSecond(other) })
		end
	end
	table.sort(players, function(a, b) return a.userId < b.userId end)
	return { loaded = data ~= nil, offers = offers, players = players, debugPreview = debugPreview,
		serverLuck = LuckService.GetServerBoostState(), serverNow = workspace:GetServerTimeNow() }
end

local function createIntent(player: Player, offerKey: string, recipientUserId: number, debugOnly: boolean): (boolean, string, any?)
	local pass = Monetization.GetPass(offerKey)
	local base = Monetization.GetProduct(offerKey)
	local key = if pass then "GiftPass_" .. offerKey else "Gift" .. offerKey
	local clearing = clearingIntents[player]
	if clearing and clearing[key] then return false, "ExclusiveShop.SavePending", nil end
	local product = Monetization.GetProduct(key)
	if product == nil or not product.gift or (base and (base.key == "ServerLuck" or base.key == "SkipRebirth")) then
		return false, "ExclusiveShop.NotGiftable", nil
	end
	if not debugOnly and product.productId == 0 then return false, "ExclusiveShop.Unavailable", nil end
	-- A transient metadata failure must not create a new durable recipient lock.
	if not debugOnly and MonetizationService.GetPrice(product.key) == nil then
		return false, "ExclusiveShop.PriceUnavailable", nil
	end
	local recipient = Players:GetPlayerByUserId(recipientUserId)
	if recipient == player and not debugOnly then return false, "ExclusiveShop.SelectRecipient", nil end
	local valid, message = canReceive(recipient, product)
	if not valid then return false, message, nil end
	local data = DataService.GetData(player)
	if data == nil then return false, "ExclusiveShop.Loading", nil end
	clearing = clearingIntents[player]
	if clearing and clearing[key] then return false, "ExclusiveShop.SavePending", nil end
	local existing = data.giftIntents[key]
	-- Exactly one prompt per saved intent. Re-prompting even for the same recipient could create
	-- two outstanding same-SKU receipts; receipts carry no intent nonce and arrive out of order.
	if existing then return false, "ExclusiveShop.GiftPending", nil end
	local intent = { recipientUserId = recipientUserId, productId = product.productId,
		nonce = HttpService:GenerateGUID(false), createdAt = os.time() }
	data.giftIntents[key] = intent
	local saved = DataService.SaveAndWait(player, function(savedData: any): boolean
		local savedIntent = if type(savedData.giftIntents) == "table" then savedData.giftIntents[key] else nil
		return type(savedIntent) == "table" and savedIntent.nonce == intent.nonce
			and savedIntent.recipientUserId == recipientUserId and savedIntent.productId == product.productId
	end, Rules.GiftIntentSaveTimeout)
	if not saved or DataService.GetData(player) ~= data then return false, "ExclusiveShop.SavePending", nil end
	-- Recipient is resolved again by the immutable saved id. Leaving never redirects to another Player.
	valid, message = canReceive(Players:GetPlayerByUserId(recipientUserId), product)
	if not valid then
		local cleared = clearPrePromptIntent(player, data, key, intent)
		return false, if cleared then message else "ExclusiveShop.SavePending", nil
	end
	return true, "ExclusiveShop.PromptOpened", intent
end

function Service.Purchase(player: Player, offerKey: unknown, recipientUserId: unknown): (boolean, string)
	if not allowed(player) then return false, "Hud.PleaseWait" end
	if type(offerKey) ~= "string" then return false, "ExclusiveShop.UnknownOffer" end
	if not listedOffer(offerKey) then return false, "ExclusiveShop.UnknownOffer" end
	if recipientUserId == nil then
		local ok, message = MonetizationService.RequestPurchase(player, offerKey)
		return ok, message
	end
	if type(recipientUserId) ~= "number" or recipientUserId ~= recipientUserId or recipientUserId % 1 ~= 0 then
		return false, "ExclusiveShop.SelectRecipient"
	end
	local ok, message, intent = createIntent(player, offerKey, recipientUserId, false)
	if not ok then return false, message end
	local pass = Monetization.GetPass(offerKey)
	local giftKey = if pass then "GiftPass_" .. offerKey else "Gift" .. offerKey
	local prompted, reason, nativeAttempted = MonetizationService.PromptPreparedGift(player, giftKey, intent.nonce)
	if not prompted and nativeAttempted ~= true then
		local data = DataService.GetData(player)
		if data == nil or not clearPrePromptIntent(player, data, giftKey, intent) then return false, "ExclusiveShop.SavePending" end
	end
	return prompted, reason
end

-- Test-profile-only: prepares the real durable binding without a Marketplace prompt or valid ids.
-- Self-recipient is permitted only here so solo Studio can exercise the receipt/ledger path.
function Service.DebugPrepareGift(player: Player, offerKey: string, recipientUserId: number): (boolean, string)
	if not RunService:IsStudio() or not DataService.IsStudioTestProfile() then return false, "ExclusiveShop.Unavailable" end
	local ok, message = createIntent(player, offerKey, recipientUserId, true)
	return ok, message
end

local function grantGift(buyer: Player, buyerData: any, receipt: any, product: Monetization.Product): (boolean, string?)
	local purchaseId = tostring(receipt.PurchaseId)
	local intent, recipient, failure = giftIntent(buyer, product)
	if intent == nil then return false, failure end
	if intent.purchaseId ~= nil and intent.purchaseId ~= purchaseId then return false, "ExclusiveShop.GiftPending" end
	-- Persist binding to the receipt before any recipient mutation. Concurrent same-SKU receipts cannot
	-- consume/redirect this intent; the outer MonetizationService also locks this PurchaseId locally.
	intent.purchaseId = purchaseId
	local bound = DataService.SaveAndWait(buyer, function(savedData: any): boolean
		local saved = if type(savedData.giftIntents) == "table" then savedData.giftIntents[product.key] else nil
		return type(saved) == "table" and saved.nonce == intent.nonce and saved.purchaseId == purchaseId
			and saved.recipientUserId == intent.recipientUserId
	end, Rules.GiftIntentSaveTimeout)
	if not bound or DataService.GetData(buyer) ~= buyerData then return false, "ExclusiveShop.SavePending" end
	recipient = Players:GetPlayerByUserId(intent.recipientUserId)
	local recipientData = if recipient then DataService.GetData(recipient) else nil
	if recipient == nil or recipientData == nil then return false, "ExclusiveShop.RecipientUnavailable" end
	local ledger = recipientData.giftDeliveries[purchaseId]
	if ledger ~= nil and (ledger.buyerUserId ~= buyer.UserId or ledger.productKey ~= product.key) then
		return false, "ExclusiveShop.GiftPending"
	end
	if ledger == nil then
		local valid, message = canReceive(recipient, product)
		if not valid then return false, message end
		-- All grant operations below are no-yield, and the durable ledger is set in the same frame.
		if product.giftPassKey then
			local before = MonetizationService.OwnsPass(recipient, product.giftPassKey)
			recipientData.giftedPassEntitlements[product.giftPassKey] = true
			MonetizationService.RefreshGiftPass(recipient, product.giftPassKey, before)
		else
			local baseKey = product.giftBaseKey or ""
			local cat = catOffer(baseKey)
			if cat then
				if PillowService.GrantFreshPaidCat(recipient, cat.catId) == nil then return false, "ExclusiveShop.FreePillow" end
			elseif (Monetization.CoinPacks :: any)[baseKey] then
				EconomyService.AddCoins(recipient, Monetization.CoinPackAmount(baseKey, EconomyService.GetIncomePerSecond(recipient)))
			else return false, "ExclusiveShop.NotGiftable" end
		end
		recipientData.giftDeliveries[purchaseId] = { buyerUserId = buyer.UserId, productKey = product.key, grantedAt = os.time() }
	end
	-- A repeated receipt sees the same ledger and grants nothing again, even when its previous buyer save failed.
	local delivered = DataService.SaveAndWait(recipient, function(savedData: any): boolean
		local saved = if type(savedData.giftDeliveries) == "table" then savedData.giftDeliveries[purchaseId] else nil
		return type(saved) == "table" and saved.buyerUserId == buyer.UserId and saved.productKey == product.key
	end, Monetization.ReceiptSaveTimeout)
	if not delivered then return false, "ExclusiveShop.SavePending" end
	if ledger == nil and recipient.Parent == Players then
		local itemKey = "Store." .. (product.giftPassKey or product.giftBaseKey or product.key) .. ".Name"
		NotificationService.NotifyLocalized(recipient, "ExclusiveShop.GiftReceived", { player = buyer.DisplayName, itemKey = itemKey }, "Announcement")
	end
	return true, "ExclusiveShop.GiftDelivered"
end

function Service:Init(): ()
	stateEvent = Network.GetEvent("ExclusiveShopState")
	EconomyService.RegisterCatIncomeResolver("Exclusive", function(player: Player, record: any): number?
		for _, offer in Rules.CatOffers do
			if record.catId == offer.catId then return EconomyService.GetRegularCatIncomePerSecond(player) * offer.factor end
		end
		return nil
	end)
	for key, offer in Rules.CatOffers do
		MonetizationService.RegisterProductValidator(key, function(player: Player): (boolean, string?)
			local product = Monetization.GetProduct(key) :: Monetization.Product
			return canReceive(player, product)
		end)
		MonetizationService.RegisterProductHandler(key, function(player: Player): (boolean, string?)
			if PillowService.GrantFreshPaidCat(player, offer.catId) == nil then return false, "ExclusiveShop.FreePillow" end
			return true, "ExclusiveShop.CatDelivered"
		end)
	end
	for _, product in Monetization.Products do
		if not product.gift then continue end
		MonetizationService.RegisterProductValidator(product.key, function(player: Player): (boolean, string?)
			local intent, recipient, failure = giftIntent(player, product)
			if intent == nil then return false, failure end
			if intent.purchaseId ~= nil then return false, "ExclusiveShop.GiftPending" end
			return canReceive(recipient, product)
		end)
		MonetizationService.RegisterDurableProductHandler(product.key, function(player: Player, data: any, receipt: any): (boolean, string?)
			return grantGift(player, data, receipt, product)
		end)
	end
end

function Service:Start(): ()
	Network.GetFunction("ExclusiveShopSnapshot").OnServerInvoke = function(player: Player)
		subscribers[player] = true
		if not allowed(player) then return nil end
		return Service.GetSnapshot(player)
	end
	Network.GetFunction("ExclusiveShopPurchase").OnServerInvoke = Service.Purchase
	Players.PlayerRemoving:Connect(function(player: Player)
		requestTimes[player] = nil
		subscribers[player] = nil
		clearingIntents[player] = nil
	end)
	while true do
		task.wait(Rules.SnapshotInterval)
		for player in subscribers do
			if player.Parent == Players then stateEvent:FireClient(player, Service.GetSnapshot(player)) end
		end
	end
end

return Service
