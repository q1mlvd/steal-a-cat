--!strict
-- Game Passes (and, in RegisterProductHandler / ProcessReceipt, Developer Products).
-- Ownership is always verified with MarketplaceService; the cache only holds the last known state for
-- this session and the Pass_<Key> player attributes are UI mirrors. Pass ids of 0 are never owned.
-- Studio only: server-side Player attribute DebugPass_<Key> = true/false overrides ownership (nil = Roblox).
-- Pass effects plug into existing services: LuckService, MultiplierService, CarryService (speed/capacity);
-- DoorService, PillowService, UpgradeService and GateService ask OwnsPass.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local ExclusiveShop = require(ReplicatedStorage.Shared.Config.ExclusiveShop)
local Rebirth = require(ReplicatedStorage.Shared.Config.Rebirth)
local Network = require(ReplicatedStorage.Shared.Network)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local CarryService = require(script.Parent.CarryService)
local DataService = require(script.Parent.DataService)
local LuckService = require(script.Parent.LuckService)
local MultiplierService = require(script.Parent.MultiplierService)
local NotificationService = require(script.Parent.NotificationService)

local MonetizationService = {
	Priority = 14,
	-- (player, passKey, owned) whenever the effective ownership changes
	PassChanged = Signal.new() :: Signal.Signal<Player, string, boolean>,
}

local verified: { [Player]: { [string]: boolean } } = {}
local overrides: { [Player]: { [string]: boolean } } = {}
local lastRequestAt: { [Player]: number } = {}
local ownershipChecked: { [Player]: { [string]: boolean } } = {}
local receiptLocks: { [string]: boolean } = {}
local priceCache: { [string]: { expiresAt: number, price: number? } } = {}

-- Product handling (Stage 11 part 2) ------------------------------------------------
-- Validator: runs before the purchase prompt (e.g. Cat Box needs a free pillow).
-- Handler: grants the product into the live profile WITHOUT YIELDING and returns (granted, message).
-- ProcessReceipt records the PurchaseId in the same frame, then waits for a completed save.
export type ProductValidator = (player: Player) -> (boolean, string?)
export type ProductHandler = (player: Player, data: any, receipt: any?) -> (boolean, string?)
local productValidators: { [string]: ProductValidator } = {}
local productHandlers: { [string]: ProductHandler } = {}
local durableProductHandlers: { [string]: ProductHandler } = {}

function MonetizationService.RegisterProductValidator(key: string, validator: ProductValidator)
	productValidators[key] = validator
end

function MonetizationService.RegisterProductHandler(key: string, handler: ProductHandler)
	assert(productHandlers[key] == nil and durableProductHandlers[key] == nil, `Duplicate product handler {key}`)
	productHandlers[key] = handler
end

-- Gifts may yield while confirming a recipient save. Receipt locks prevent concurrent local grants;
-- the recipient's durable PurchaseId ledger prevents grants repeated on later retries/servers.
function MonetizationService.RegisterDurableProductHandler(key: string, handler: ProductHandler)
	assert(productHandlers[key] == nil and durableProductHandlers[key] == nil, `Duplicate product handler {key}`)
	durableProductHandlers[key] = handler
end

-- Display actual Roblox prices only. ID 0 is always unavailable, including diagnostic previews.
function MonetizationService.GetPrice(key: string): number?
	local pass = Monetization.GetPass(key)
	local product = Monetization.GetProduct(key)
	local id = if pass then pass.passId elseif product then product.productId else 0
	if id <= 0 then return nil end
	local now = os.clock()
	local cached = priceCache[key]
	if cached and cached.expiresAt > now then return cached.price end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(id, if pass then Enum.InfoType.GamePass else Enum.InfoType.Product)
	end)
	local price: number? = nil
	if ok and type(info) == "table" and info.IsForSale ~= false then
		local value = info.PriceInRobux
		if type(value) == "number" and value == value and value >= 0 and value < math.huge then price = math.floor(value) end
	end
	priceCache[key] = { price = price, expiresAt = now + (if price ~= nil then ExclusiveShop.PriceCacheSeconds else ExclusiveShop.FailedPriceCacheSeconds) }
	return price
end

function MonetizationService.CanBuyProduct(player: Player, key: string): (boolean, string?)
	local validator = productValidators[key]
	if validator then
		return validator(player)
	end
	return true, nil
end

local function processReceipt(receipt: { [string]: any }, product: Monetization.Product?): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox retries when they rejoin
	end
	local data = DataService.GetData(player) or DataService.WaitForData(player)
	if data == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	-- Paid purchase acknowledgments never expire.
	-- Retaining this buyer ledger prevents a very old duplicate from consuming a new recipient intent.
	if data.giftReceipts[purchaseId] ~= nil then
		local saved = DataService.SaveAndWait(player, function(savedData: any): boolean
			return type(savedData.giftReceipts) == "table" and savedData.giftReceipts[purchaseId] ~= nil
		end, Monetization.ReceiptSaveTimeout)
		return if saved then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if data.processedReceipts[purchaseId] == nil then
		local resolved = product or Monetization.GetProductByProductId(receipt.ProductId)
		local handler = if resolved then (durableProductHandlers[resolved.key] or productHandlers[resolved.key]) else nil
		if resolved == nil or handler == nil then
			warn(`[MonetizationService] No handler for product {tostring(receipt.ProductId)}; not granted yet`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		-- Normal grants never yield; durable gift handlers confirm the recipient before returning true.
		local ok, granted, message = pcall(handler, player, data, receipt)
		if not ok or granted ~= true then
			if not ok then
				warn(`[MonetizationService] {resolved.key} handler failed: {tostring(granted)}`)
			end
			if ok and type(message) == "string" then
				NotificationService.Notify(player, message, "Info")
			else
				local itemKey = "Store." .. (resolved.giftPassKey or resolved.giftBaseKey or resolved.key) .. ".Name"
				NotificationService.NotifyLocalized(player, "ExclusiveShop.DeliveryPending", { itemKey = itemKey }, "Info")
			end
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if DataService.GetData(player) ~= data then return Enum.ProductPurchaseDecision.NotProcessedYet end
		data.processedReceipts[purchaseId] = os.time()
		if resolved.gift then
			local intent = data.giftIntents[resolved.key]
			if intent and intent.purchaseId == purchaseId then
				data.giftReceipts[purchaseId] = { recipientUserId = intent.recipientUserId,
					productKey = resolved.key, grantedAt = os.time() }
				data.giftIntents[resolved.key] = nil
			end
		end
		NotificationService.Notify(player, if type(message) == "string" then message else `Thanks for buying {resolved.name}!`, "Success")
	end
	-- PurchaseGranted only once a completed save contains this receipt.
	local giftAcknowledged = data.giftReceipts[purchaseId] ~= nil
	local saved = DataService.SaveAndWait(player, function(savedData: any): boolean
		return type(savedData) == "table" and type(savedData.processedReceipts) == "table"
			and savedData.processedReceipts[purchaseId] ~= nil
			and (not giftAcknowledged or (type(savedData.giftReceipts) == "table" and savedData.giftReceipts[purchaseId] ~= nil))
	end, Monetization.ReceiptSaveTimeout)
	return if saved then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
end

local function lockedReceipt(receipt: { [string]: any }, product: Monetization.Product?): Enum.ProductPurchaseDecision
	local purchaseId = tostring(receipt.PurchaseId)
	if receiptLocks[purchaseId] then return Enum.ProductPurchaseDecision.NotProcessedYet end
	receiptLocks[purchaseId] = true
	local ok, result = pcall(processReceipt, receipt, product)
	receiptLocks[purchaseId] = nil
	if not ok then
		warn(`[MonetizationService] ProcessReceipt error: {tostring(result)}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return result
end

-- Studio test profile only: runs the real receipt path for a product key (ids are placeholders).
function MonetizationService.DebugProcessReceipt(player: Player, productKey: string, purchaseId: string): string
	local product = Monetization.GetProduct(productKey)
	if not DataService.IsStudioTestProfile() or product == nil then
		return "refused"
	end
	local decision = lockedReceipt({ PlayerId = player.UserId, ProductId = product.productId, PurchaseId = purchaseId }, product)
	return decision.Name
end

-- Passes ----------------------------------------------------------------------------

function MonetizationService.OwnsPass(player: Player, key: string): boolean
	local override = overrides[player]
	if override and override[key] ~= nil then
		return override[key]
	end
	local data = DataService.GetData(player)
	if data and data.giftedPassEntitlements and data.giftedPassEntitlements[key] == true then return true end
	local pass = Monetization.GetPass(key)
	if pass == nil or pass.passId == 0 then
		return false
	end
	local known = verified[player]
	return known ~= nil and known[key] == true
end

function MonetizationService.IsOwnershipReady(player: Player, key: string): boolean
	local pass = Monetization.GetPass(key)
	if pass == nil then return false end
	if pass.passId == 0 or MonetizationService.OwnsPass(player, key) then return true end
	local checked = ownershipChecked[player]
	return checked ~= nil and checked[key] == true
end

local function mirror(player: Player)
	for _, pass in Monetization.Passes do
		player:SetAttribute(Monetization.PassAttributePrefix .. pass.key, MonetizationService.OwnsPass(player, pass.key))
	end
end

local function changed(player: Player, key: string, before: boolean)
	local after = MonetizationService.OwnsPass(player, key)
	mirror(player)
	if after ~= before then
		CarryService.RefreshPlayer(player) -- Fast Legs / Big Hands
		MonetizationService.PassChanged:Fire(player, key, after)
	end
end

-- Entitlement has already been written with the gift ledger in the caller's no-yield transaction.
function MonetizationService.RefreshGiftPass(player: Player, key: string, before: boolean): ()
	changed(player, key, before)
end

local function setVerified(player: Player, key: string, owned: boolean)
	local known = verified[player]
	if known == nil then
		return
	end
	local before = MonetizationService.OwnsPass(player, key)
	known[key] = owned
	local checked = ownershipChecked[player]
	if checked then checked[key] = true end
	changed(player, key, before)
end

local function checkOwnership(player: Player)
	for _, pass in Monetization.Passes do
		if pass.passId == 0 then
			continue
		end
		for attempt = 1, Monetization.OwnershipRetries do
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.passId)
			if player.Parent ~= Players then
				return
			end
			if ok then
				setVerified(player, pass.key, owns == true)
				break
			end
			if attempt < Monetization.OwnershipRetries then
				task.wait(Monetization.OwnershipRetryDelay * attempt)
			else
				warn(`[MonetizationService] Could not check {pass.key} for {player.Name}: {tostring(owns)}`)
			end
		end
	end
end

local function watchDebug(player: Player)
	if not RunService:IsStudio() then
		return
	end
	for _, pass in Monetization.Passes do
		local attribute = Monetization.DebugPassAttributePrefix .. pass.key
		local function apply()
			local value = player:GetAttribute(attribute)
			local before = MonetizationService.OwnsPass(player, pass.key)
			local set = overrides[player]
			if set == nil then
				return
			end
			set[pass.key] = if type(value) == "boolean" then value else nil
			changed(player, pass.key, before)
		end
		player:GetAttributeChangedSignal(attribute):Connect(apply)
		if player:GetAttribute(attribute) ~= nil then
			apply()
		end
	end
end

local function onPlayerAdded(player: Player)
	if verified[player] then
		return
	end
	verified[player] = {}
	ownershipChecked[player] = {}
	overrides[player] = {}
	mirror(player)
	watchDebug(player)
	task.spawn(checkOwnership, player)
end

-- Store prompts -------------------------------------------------------------------------

local function promptPurchase(player: Player, key: unknown, preparedGift: boolean): (boolean, string, boolean?)
	local now = os.clock()
	if player.Parent ~= Players or DataService.GetData(player) == nil then return false, "ExclusiveShop.Loading" end
	if type(key) ~= "string" then return false, "ExclusiveShop.UnknownOffer" end
	if now - (lastRequestAt[player] or -math.huge) < Monetization.PurchaseRequestCooldown then
		return false, "Hud.PleaseWait"
	end
	lastRequestAt[player] = now
	local pass = Monetization.GetPass(key)
	if pass then
		if MonetizationService.OwnsPass(player, pass.key) then
			return false, "ExclusiveShop.AlreadyOwned"
		elseif pass.passId == 0 then
			return false, "ExclusiveShop.Unavailable"
		end
		if not MonetizationService.IsOwnershipReady(player, pass.key) then return false, "ExclusiveShop.Loading" end
		if MonetizationService.GetPrice(pass.key) == nil then return false, "ExclusiveShop.PriceUnavailable" end
		if player.Parent ~= Players or DataService.GetData(player) == nil then return false, "ExclusiveShop.Loading" end
		if MonetizationService.OwnsPass(player, pass.key) then return false, "ExclusiveShop.AlreadyOwned" end
		local ok = pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, player, pass.passId)
		return ok, if ok then "ExclusiveShop.PromptOpened" else "ExclusiveShop.PromptFailed", true
	end
	local product = Monetization.GetProduct(key)
	if product == nil then
		return false, "ExclusiveShop.UnknownOffer"
	end
	if product.productId == 0 then return false, "ExclusiveShop.Unavailable" end
	if product.gift and not preparedGift then return false, "ExclusiveShop.SelectRecipient" end
	local validator = productValidators[product.key]
	if validator then
		local ok, message = validator(player)
		if not ok then
			return false, message or "ExclusiveShop.CannotBuy"
		end
	end
	if MonetizationService.GetPrice(product.key) == nil then return false, "ExclusiveShop.PriceUnavailable" end
	if player.Parent ~= Players then return false, "ExclusiveShop.Loading" end
	-- Recheck after price lookup yielded: cats/entitlements/recipient may have changed.
	local valid, message = MonetizationService.CanBuyProduct(player, product.key)
	if not valid then return false, message or "ExclusiveShop.CannotBuy" end
	local ok = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, product.productId)
	return ok, if ok then "ExclusiveShop.PromptOpened" else "ExclusiveShop.PromptFailed", true
end

-- Third value means the native prompt API was attempted; false/nil is explicitly pre-prompt.
-- Existing callers use the unchanged first two values. Intent owners may clear only pre-prompt failures.
function MonetizationService.RequestPurchase(player: Player, key: string): (boolean, string, boolean?)
	return promptPurchase(player, key, false)
end

-- Server-only route used after ExclusiveShopService confirms the exact durable intent.
function MonetizationService.PromptPreparedGift(player: Player, key: string, nonce: string): (boolean, string, boolean?)
	local data = DataService.GetData(player)
	local product = Monetization.GetProduct(key)
	local intent = if data then data.giftIntents[key] else nil
	if not product or not product.gift or not intent or intent.nonce ~= nonce or intent.productId ~= product.productId
		or intent.purchaseId ~= nil then return false, "ExclusiveShop.GiftPending" end
	return promptPurchase(player, key, true)
end

local function onPurchaseRequest(player: Player, key: unknown)
	if type(key) ~= "string" then return end
	-- Skip can only prompt through RebirthService's single persisted selection route.
	-- The generic client remote must not re-prompt an existing/canceled Skip selection.
	if key == Rebirth.SkipProductKey then
		NotificationService.Notify(player, "Rebirth.SkipChoose", "Info")
		return
	end
	local ok, message = MonetizationService.RequestPurchase(player, key)
	NotificationService.Notify(player, message, if ok then "Info" else "Error")
end

function MonetizationService:Init(): ()
	LuckService.RegisterLuckSource("LuckX2Pass", function(player: Player): number
		return if MonetizationService.OwnsPass(player, "LuckX2") then Monetization.LuckX2Multiplier else 1
	end)
	MultiplierService.RegisterIncomeSource("IncomeX2Pass", function(player: Player): number
		return if MonetizationService.OwnsPass(player, "IncomeX2") then Monetization.IncomeX2Multiplier else 1
	end)
	MultiplierService.RegisterIncomeSource("VIPPass", function(player: Player): number
		return if MonetizationService.OwnsPass(player, "VIP") then Monetization.VipIncomeMultiplier else 1
	end)
	CarryService.RegisterSpeedMultiplier("FastLegsPass", function(player: Player): number
		return if MonetizationService.OwnsPass(player, "FastLegs") then Monetization.FastLegsMultiplier else 1
	end)
	CarryService.RegisterCapacityBonus("BigHandsPass", function(player: Player): number
		return if MonetizationService.OwnsPass(player, "BigHands") then Monetization.BigHandsBonus else 0
	end)
end

function MonetizationService:Start(): ()
	DataService.DataLoaded:Connect(function(player: Player, data: any)
		onPlayerAdded(player)
		mirror(player)
		CarryService.RefreshPlayer(player)
		-- Persisted gifted entitlements must refresh all pass consumers on rejoin, including
		-- passes whose Roblox pass id is still 0 and therefore have no ownership query callback.
		for _, pass in Monetization.Passes do
			if data.giftedPassEntitlements[pass.key] == true and MonetizationService.OwnsPass(player, pass.key) then
				MonetizationService.PassChanged:Fire(player, pass.key, true)
			end
		end
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		verified[player] = nil
		ownershipChecked[player] = nil
		overrides[player] = nil
		lastRequestAt[player] = nil
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		local pass = Monetization.GetPassByPassId(passId)
		if purchased and pass and player.Parent == Players then
			setVerified(player, pass.key, true)
			NotificationService.Notify(player, `Thanks for buying {pass.name}!`, "Success")
		end
	end)
	Network.GetEvent("RobuxPurchaseRequest").OnServerEvent:Connect(onPurchaseRequest)
	-- The ONE ProcessReceipt callback for the whole game.
	MarketplaceService.ProcessReceipt = function(receipt: any): Enum.ProductPurchaseDecision
		return lockedReceipt(receipt, nil)
	end
end

return MonetizationService

