--!strict
-- Server snapshots own prices, entitlements and recipient locks. The client only selects a recipient
-- and opens the Roblox purchase prompt through the validated server route.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage.Shared
local Rules = require(Shared.Config.ExclusiveShop)
local Monetization = require(Shared.Config.Monetization)
local Cats = require(Shared.Config.Cats)
local UI = require(Shared.Config.Shop).Ui
local Network = require(Shared.Network)
local L = require(Shared.Util.Localization)
local NumberFormat = require(Shared.Util.NumberFormat)
local Window = require(Shared.Util.FeatureWindow)
local CatPortrait = require(Shared.Util.CatPortrait)
local Notification = require(script.Parent.NotificationController)
local C = Rules.Ui
local Controller = { Priority = 68 }
local player = Players.LocalPlayer
local window: any
local picker: any
local giftToggle: TextButton
local snapshot: any = { loaded = false, offers = {}, players = {}, serverLuck = { multiplier = 1, remaining = 0 } }
local giftMode = false
local recipientId: number? = nil
local snapshotBusy = false
local purchaseBusy = false
local countdownLabel: TextLabel? = nil
local render: () -> ()
local renderPicker: () -> ()
local requestSnapshot: () -> ()
type ScrollMemory = { position: Vector2, revision: number, restoring: boolean }
local scrollMemory: { [ScrollingFrame]: ScrollMemory } = {}

local function refreshScroll(body: ScrollingFrame): () -> ()
	local memory = scrollMemory[body]
	if memory == nil then
		memory = { position = body.CanvasPosition, revision = 0, restoring = false }
		scrollMemory[body] = memory
		local state = memory
		body:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			if not state.restoring then state.position = body.CanvasPosition end
		end)
	end
	if not memory.restoring then memory.position = body.CanvasPosition end
	memory.revision += 1 memory.restoring = true
	local revision = memory.revision
	local oldRows = {}
	for _, child in body:GetChildren() do if child:IsA("GuiObject") then table.insert(oldRows, child) end end
	local state = memory
	return function()
		-- Build replacements first. An empty AutomaticCanvasSize would clamp CanvasPosition to zero
		-- immediately, so retain the old rows until the complete replacement is parented.
		for _, row in oldRows do if row.Parent == body then row:Destroy() end end
		task.defer(function()
			-- UIListLayout and AutomaticCanvasSize settle across the frame boundary. A newer refresh
			-- owns restoration if a resize/snapshot arrived while this one was waiting.
			RunService.RenderStepped:Wait()
			RunService.RenderStepped:Wait()
			if state.revision ~= revision or body.Parent == nil then return end
			local maximum = math.max(0, body.AbsoluteCanvasSize.Y - body.AbsoluteWindowSize.Y)
			body.CanvasPosition = Vector2.new(state.position.X, math.clamp(state.position.Y, 0, maximum))
			state.position = body.CanvasPosition state.restoring = false
		end)
	end
end

local function recipientName(id: number?): string
	for _, other in snapshot.players do if other.userId == id then return other.displayName end end
	return if id then tostring(id) else L.T("ExclusiveShop.NoRecipient")
end

local function incomeText(offer: any): (string, any?)
	local income = offer.income
	local coins = offer.coins
	if giftMode and recipientId then
		for _, other in snapshot.players do
			if other.userId == recipientId then
				local cat = (Rules.CatOffers :: any)[offer.key]
				if cat then income = (other.bestRegularIncome or 1) * cat.factor * (other.incomeMultiplier or 1) end
				local pack = (Monetization.CoinPacks :: any)[offer.key]
				if pack then coins = math.floor(math.max(pack.base, (other.incomePerSecond or 0) * pack.incomeSeconds)) end
				break
			end
		end
	end
	if income ~= nil then return "ExclusiveShop.CatIncome", { income = NumberFormat.Format(income) } end
	if coins ~= nil then return "ExclusiveShop.CoinAmount", { coins = NumberFormat.Format(coins) } end
	return "", nil
end

local function updateCountdown()
	if countdownLabel == nil then return end
	local luck = snapshot.serverLuck or {}
	local remaining = if type(luck.endsAt) == "number" then math.max(0, math.ceil(luck.endsAt - workspace:GetServerTimeNow())) else 0
	if remaining > 0 then
		L.Bind(countdownLabel, "ExclusiveShop.LuckTimer", { multiplier = luck.multiplier or Rules.ServerLuckMultiplier,
			minutes = math.floor(remaining / 60), seconds = string.format("%02d", remaining % 60) })
	else L.Bind(countdownLabel, "ExclusiveShop.LuckInactive") end
end

local function applySnapshot(value: any)
	if type(value) ~= "table" or type(value.offers) ~= "table" or type(value.players) ~= "table" then return end
	snapshot = value
	-- A departed player remains the saved recipient of a pending gift, but stops being selectable.
	local found = false
	for _, other in snapshot.players do if other.userId == recipientId then found = true break end end
	if not found then recipientId = nil end
	if window:IsOpen() then render() end
	if picker:IsOpen() then renderPicker() end
end

requestSnapshot = function()
	if snapshotBusy then return end
	snapshotBusy = true
	task.spawn(function()
		local ok, value = pcall(function() return Network.GetFunction("ExclusiveShopSnapshot"):InvokeServer() end)
		snapshotBusy = false
		if ok then applySnapshot(value)
		else Notification.ShowLocal(L.T("ExclusiveShop.RequestFailed"), "Error") end
	end)
end

local function purchase(offer: any)
	if purchaseBusy then return end
	if giftMode and recipientId == nil then picker:Open() renderPicker() return end
	purchaseBusy = true
	local selectedRecipient = if giftMode then recipientId else nil
	render()
	task.spawn(function()
		local ok, success, message = pcall(function()
			return Network.GetFunction("ExclusiveShopPurchase"):InvokeServer(offer.key, selectedRecipient)
		end)
		purchaseBusy = false
		Notification.ShowLocal(L.T(if ok and type(message) == "string" then message else "ExclusiveShop.RequestFailed"),
			if ok and success then "Info" else "Error")
		if window:IsOpen() then render() end
		-- Server snapshots are authoritative; no counts or ownership are predicted after a prompt.
		task.delay(Rules.RequestCooldown, requestSnapshot)
	end)
end

local function card(offer: any, order: number, width: number)
	local compact = width < C.CompactWidth
	local pending = giftMode and offer.pendingRecipientUserId ~= nil
	local baseHeight = if compact then C.CompactRowHeight else C.RowHeight
	local height = baseHeight + (if pending then C.LockHeight else 0)
	local frame = Instance.new("Frame")
	frame.Name = offer.key frame.Size = UDim2.new(1, -C.Padding, 0, height)
	frame.BackgroundColor3 = UI.Surface frame.BorderSizePixel = 0 frame.LayoutOrder = order
	frame:SetAttribute("UiSkin", "Card") frame.Parent = window.Body
	local pad = C.Padding
	local icon = if compact then C.CompactIconSize else C.IconSize
	if type(offer.catId) == "string" then
		local definition = Cats.Get(offer.catId)
		CatPortrait.Create(frame, { catId = offer.catId, mutation = if definition then definition.defaultMutation else nil,
			discovered = true, frameless = true,
			size = UDim2.fromOffset(icon, icon), position = UDim2.fromOffset(pad, pad) })
	else Window.Image(frame, offer.icon or "", { Position = UDim2.fromOffset(pad, pad), Size = UDim2.fromOffset(icon, icon) }) end
	local x = icon + pad * 2
	local textWidth = math.max(C.ButtonHeight, width - x - pad * 2 - (if compact then 0 else C.ButtonWidth + pad))
	Window.Text(frame, "Store." .. offer.key .. ".Name", nil, { Name = "OfferName", Position = UDim2.fromOffset(x, pad),
		Size = UDim2.fromOffset(textWidth, C.TitleHeight), TextSize = C.FontSize, TextXAlignment = Enum.TextXAlignment.Left })
	Window.Text(frame, "Store." .. offer.key .. ".Description", nil, { Name = "Description", Position = UDim2.fromOffset(x, pad + C.TitleHeight),
		Size = UDim2.fromOffset(textWidth, if compact then C.CompactDescriptionHeight else C.DescriptionHeight),
		TextSize = C.SmallFontSize, TextColor3 = UI.Muted, TextXAlignment = Enum.TextXAlignment.Left })
	local infoKey, params = incomeText(offer)
	local detailTop = if compact then pad + math.max(icon, C.TitleHeight + C.CompactDescriptionHeight) + C.RowGap else baseHeight - C.DetailHeight - pad
	if infoKey ~= "" then
		Window.Text(frame, infoKey, params, { Name = "Income", Position = UDim2.fromOffset(pad, detailTop),
			Size = UDim2.fromOffset(if compact then width - pad * 3 else width - C.ButtonWidth - pad * 4, C.DetailHeight),
			TextSize = C.SmallFontSize, TextColor3 = UI.Coin, TextXAlignment = Enum.TextXAlignment.Left })
	elseif offer.key == "ServerLuck" then
		countdownLabel = Window.Text(frame, "ExclusiveShop.LuckInactive", nil, { Name = "LuckTimer", Position = UDim2.fromOffset(pad, detailTop),
			Size = UDim2.fromOffset(if compact then width - pad * 3 else width - C.ButtonWidth - pad * 4, C.DetailHeight),
			TextSize = C.SmallFontSize, TextColor3 = UI.Accent, TextXAlignment = Enum.TextXAlignment.Left })
	end
	local owned = not giftMode and offer.owned == true
	local price = if giftMode then offer.giftPriceRobux else offer.priceRobux
	local enabled = (if giftMode then offer.giftAvailable else offer.available) == true
		and not owned and not pending and not purchaseBusy and (not giftMode or recipientId ~= nil)
	local stateKey = if owned then "ExclusiveShop.Owned" elseif pending then "ExclusiveShop.GiftPendingButton"
		elseif giftMode and offer.giftKey == nil then "ExclusiveShop.NotGiftableButton"
		elseif giftMode and recipientId == nil then "ExclusiveShop.ChoosePlayer"
		elseif price == nil then "ExclusiveShop.Unavailable" else "ExclusiveShop.Price"
	local buttonY = if compact then baseHeight - C.ButtonHeight - pad else pad
	local buttonWidth = if compact then width - pad * 3 else C.ButtonWidth
	local button = Window.Button(frame, "", nil, function() purchase(offer) end,
		{ Name = "Purchase", AnchorPoint = if compact then Vector2.zero else Vector2.new(1, 0),
			Position = if compact then UDim2.fromOffset(pad, buttonY) else UDim2.new(1, -pad, 0, buttonY),
			Size = UDim2.fromOffset(buttonWidth, C.ButtonHeight), BackgroundColor3 = if enabled then UI.Accent else UI.Surface,
			TextColor3 = if enabled then UI.OnColor else UI.Muted })
	button:SetAttribute("UiSkin", if enabled then "Button:Green" else "Button:Gray")
	button.Active = enabled button.AutoButtonColor = enabled
	-- Even disabled price previews carry the official Roblox icon, never a letter/symbol substitute.
	Window.Image(button, Rules.RobuxIcon, { Name = "RobuxIcon", Position = UDim2.fromOffset(C.PriceIconPadding, (C.ButtonHeight - C.PriceIconSize) / 2),
		Size = UDim2.fromOffset(C.PriceIconSize, C.PriceIconSize), ImageColor3 = if enabled then UI.OnColor else UI.Muted,
		ImageTransparency = if enabled then 0 else C.DisabledIconTransparency })
	local label = Window.Text(button, stateKey, { price = if price ~= nil then NumberFormat.Format(price) else "" },
		{ Name = "PriceLabel", Position = UDim2.fromOffset(C.PriceIconSize + C.PriceIconPadding * 2, 0),
			Size = UDim2.new(1, -(C.PriceIconSize + C.PriceIconPadding * 3), 1, 0), TextSize = C.FontSize,
			TextColor3 = if enabled then UI.OnColor else UI.Muted })
	if snapshot.debugPreview and price == nil and not owned and not pending and (not giftMode or offer.giftKey ~= nil) then
		L.Bind(label, "ExclusiveShop.PreviewPrice", { price = NumberFormat.Format(offer.previewPrice or 0) })
	end
	if giftMode and offer.giftKey and recipientId == nil and offer.giftAvailable == true then
		button.Active = not purchaseBusy button.AutoButtonColor = not purchaseBusy
	end
	if pending then
		Window.Text(frame, "ExclusiveShop.PendingRecipient", { player = recipientName(offer.pendingRecipientUserId) },
			{ Name = "RecipientLock", Position = UDim2.fromOffset(pad, baseHeight - pad),
				Size = UDim2.fromOffset(if compact then width - pad * 3 else width - pad * 3, C.LockHeight),
				TextColor3 = UI.Danger, TextSize = C.SmallFontSize, TextXAlignment = Enum.TextXAlignment.Left })
	end
end

local function coinGrid(order: number, width: number)
	local offers = {}
	for _, offer in snapshot.offers do if offer.section == "Coins" then table.insert(offers, offer) end end
	local columns = if width >= C.CoinWideBreakpoint then C.CoinWideColumns else C.CoinColumns
	local gridWidth = width - C.Padding
	if (gridWidth - C.RowGap * (columns - 1)) / columns < C.CoinMinimumWidth then columns = 1 end
	local cellWidth = math.floor((gridWidth - C.RowGap * (columns - 1)) / columns)
	local rows = math.ceil(#offers / columns)
	local group = Instance.new("Frame") group.Name = "CoinPacks" group.BackgroundTransparency = 1
	group:SetAttribute("UiSkin", "None") group.LayoutOrder = order
	group.Size = UDim2.new(1, -C.Padding, 0, rows * C.CoinCardHeight + math.max(0, rows - 1) * C.RowGap) group.Parent = window.Body
	local grid = Instance.new("UIGridLayout") grid.CellSize = UDim2.fromOffset(cellWidth, C.CoinCardHeight)
	grid.CellPadding = UDim2.fromOffset(C.RowGap, C.RowGap) grid.FillDirectionMaxCells = columns
	grid.SortOrder = Enum.SortOrder.LayoutOrder grid.Parent = group
	for index, offer in offers do
		local frame = Instance.new("Frame") frame.Name = offer.key frame.BackgroundColor3 = UI.Surface frame.BorderSizePixel = 0
		frame:SetAttribute("UiSkin", "Card") frame.LayoutOrder = index frame.Parent = group
		local icon = math.min(C.CoinIconSize, cellWidth - C.Padding * 2)
		Window.Image(frame, offer.icon or "", { AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, C.Padding), Size = UDim2.fromOffset(icon, icon) })
		Window.Text(frame, "Store." .. offer.key .. ".Name", nil, { Position = UDim2.fromOffset(C.Padding, C.Padding + C.CoinIconSize),
			Size = UDim2.new(1, -C.Padding * 2, 0, C.CoinTitleHeight), TextSize = C.SmallFontSize })
		local key, params = incomeText(offer)
		Window.Text(frame, "ExclusiveShop.CoinNumber", params, { Position = UDim2.fromOffset(C.Padding, C.Padding + C.CoinIconSize + C.CoinTitleHeight),
			Size = UDim2.new(1, -C.Padding * 2, 0, C.DetailHeight), TextSize = C.FontSize, TextColor3 = UI.Coin })
		local pending = giftMode and offer.pendingRecipientUserId ~= nil
		local price = if giftMode then offer.giftPriceRobux else offer.priceRobux
		local enabled = (if giftMode then offer.giftAvailable else offer.available) == true and not pending
			and not purchaseBusy and (not giftMode or recipientId ~= nil)
		local stateKey = if pending then "ExclusiveShop.GiftPendingButton" elseif giftMode and recipientId == nil then "ExclusiveShop.ChoosePlayer"
			elseif price == nil then "ExclusiveShop.Unavailable" else "ExclusiveShop.Price"
		local button = Window.Button(frame, "", nil, function() purchase(offer) end,
			{ Name = "Purchase", Position = UDim2.new(0, C.CoinButtonPadding, 1, -C.ButtonHeight - C.CoinButtonPadding),
				Size = UDim2.new(1, -C.CoinButtonPadding * 2, 0, C.ButtonHeight), BackgroundColor3 = if enabled then UI.Accent else UI.Surface })
		button:SetAttribute("UiSkin", if enabled then "Button:Green" else "Button:Gray") button.Active = enabled button.AutoButtonColor = enabled
		Window.Image(button, Rules.RobuxIcon, { Name = "RobuxIcon", Position = UDim2.fromOffset(C.CoinPriceIconPadding, (C.ButtonHeight - C.CoinPriceIconSize) / 2),
			Size = UDim2.fromOffset(C.CoinPriceIconSize, C.CoinPriceIconSize), ImageColor3 = if enabled then UI.OnColor else UI.Muted,
			ImageTransparency = if enabled then 0 else C.DisabledIconTransparency })
		local priceLabel = Window.Text(button, stateKey, { price = if price ~= nil then NumberFormat.Format(price) else "" },
			{ Name = "PriceLabel", Position = UDim2.fromOffset(C.CoinPriceIconSize + C.CoinPriceIconPadding * 2, 0),
				Size = UDim2.new(1, -(C.CoinPriceIconSize + C.CoinPriceIconPadding * 3), 1, 0), TextSize = C.SmallFontSize,
				TextColor3 = if enabled then UI.OnColor else UI.Muted })
		if snapshot.debugPreview and price == nil and not pending then
			L.Bind(priceLabel, "ExclusiveShop.PreviewPrice", { price = NumberFormat.Format(offer.previewPrice or 0) })
		end
		if giftMode and recipientId == nil and offer.giftAvailable then button.Active = not purchaseBusy end
		if pending then
			frame:SetAttribute("GiftRecipientUserId", offer.pendingRecipientUserId)
			local pendingLabel = Window.Text(frame, "ExclusiveShop.PendingRecipientShort", { player = recipientName(offer.pendingRecipientUserId) },
				{ Position = UDim2.new(0, C.CoinButtonPadding, 1, -C.ButtonHeight - C.CoinButtonPadding - C.CoinLockHeight),
					Size = UDim2.new(1, -C.CoinButtonPadding * 2, 0, C.CoinLockHeight), TextSize = C.SmallFontSize, TextColor3 = UI.Danger })
			-- The lock replaces the amount on compact coin cards so all text stays inside the card.
			pendingLabel.ZIndex = 3
			for _, child in frame:GetChildren() do
				if child:IsA("TextLabel") and child ~= pendingLabel and child.Position.Y.Offset == C.Padding + C.CoinIconSize + C.CoinTitleHeight then child.Visible = false end
			end
		end
	end
end

render = function()
	if not window then return end
	local finishRefresh = refreshScroll(window.Body) countdownLabel = nil
	local bodyPadding = window.Body:FindFirstChildOfClass("UIPadding")
	local width = window.Body.AbsoluteSize.X - (if bodyPadding then bodyPadding.PaddingLeft.Offset + bodyPadding.PaddingRight.Offset else 0)
	if width <= 0 then width = Rules.PanelWidth - C.Padding * 2 end
	local headerWidth = window.Header.AbsoluteSize.X
	local giftWidth = math.clamp(headerWidth * C.GiftButtonWidthFraction, C.GiftButtonMinimumWidth, C.GiftButtonWidth)
	giftToggle.Size = UDim2.fromOffset(giftWidth, C.ButtonHeight)
	window.Title.Size = UDim2.new(1, -(C.GiftButtonRight + giftWidth + C.RowGap), 1, 0)
	L.Bind(giftToggle, if giftMode then "ExclusiveShop.GiftOn" else "ExclusiveShop.GiftOff")
	giftToggle.BackgroundColor3 = if giftMode then C.GiftPinkOn else C.GiftPinkOff
	giftToggle.TextColor3 = UI.OnColor
	giftToggle:SetAttribute("UiSkin", "Button:Gray")
	giftToggle:SetAttribute("UiSkinTintColor", if giftMode then C.GiftPinkOn else C.GiftPinkOff)
	local order = 0
	local function info(key: string, params: any?, height: number)
		order += 1
		Window.Text(window.Body, key, params, { LayoutOrder = order, Size = UDim2.new(1, -C.Padding, 0, height), TextSize = C.SmallFontSize })
	end
	if giftMode then
		order += 1
		Window.Button(window.Body, if recipientId then "ExclusiveShop.SelectedRecipient" else "ExclusiveShop.SelectRecipient", { player = recipientName(recipientId) },
			function() picker:Open() renderPicker() end,
			{ Name = "ChooseRecipient", LayoutOrder = order, Size = UDim2.new(1, -C.Padding, 0, C.GiftBarHeight),
				BackgroundColor3 = UI.Accent, TextSize = C.FontSize })
		info("ExclusiveShop.GiftRules", nil, C.GiftNoteHeight)
	end
	if snapshot.debugPreview then info("ExclusiveShop.DebugPreview", nil, C.NoticeHeight) end
	if not snapshot.loaded then info("ExclusiveShop.Loading", nil, C.NoticeHeight) finishRefresh() return end
	if #snapshot.offers == 0 then info("ExclusiveShop.NoOffers", nil, C.EmptyHeight) finishRefresh() return end
	local section = "" local coinsBuilt = false
	for _, offer in snapshot.offers do
		if offer.section ~= section then
			section = offer.section order += 1
			local header = Instance.new("Frame") header.Name = "Section" .. section
			header.LayoutOrder = order header.Size = UDim2.new(1, -C.Padding, 0, C.SectionHeight)
			header.BackgroundColor3 = (C.SectionColors :: any)[section] or UI.Accent header.BorderSizePixel = 0
			header:SetAttribute("UiSkin", "Header") header:SetAttribute("UiSkinTintColor", header.BackgroundColor3) header.Parent = window.Body
			Window.Text(header, "ExclusiveShop.Section." .. section, nil,
				{ Size = UDim2.fromScale(1, 1), TextSize = C.SectionFontSize, TextColor3 = UI.OnColor })
		end
		if offer.section == "Coins" then
			if not coinsBuilt then
				coinsBuilt = true order += 1 coinGrid(order, width)
			end
		else order += 1 card(offer, order, width) end
	end
	updateCountdown()
	finishRefresh()
end

renderPicker = function()
	local finishRefresh = refreshScroll(picker.Body)
	if #snapshot.players == 0 then
		Window.Text(picker.Body, "ExclusiveShop.NoPlayers", nil, { Size = UDim2.new(1, -C.Padding, 0, C.EmptyHeight) })
	end
	for order, other in snapshot.players do
		Window.Button(picker.Body, "ExclusiveShop.PlayerChoice", { displayName = other.displayName, name = other.name }, function()
			recipientId = other.userId picker:Close() window:Open() render()
		end, { Name = "Player" .. tostring(other.userId), LayoutOrder = order,
			Size = UDim2.new(1, -C.Padding, 0, C.PlayerRowHeight), BackgroundColor3 = UI.Accent, TextSize = C.FontSize })
	end
	Window.Button(picker.Body, "ExclusiveShop.Back", nil, function() picker:Close() window:Open() render() end,
		{ Name = "Back", LayoutOrder = #snapshot.players + 1, Size = UDim2.new(1, -C.Padding, 0, C.PlayerRowHeight), BackgroundColor3 = UI.Surface, TextColor3 = UI.Text })
	finishRefresh()
end

function Controller.Open()
	window:Open() render() requestSnapshot()
end
function Controller.Close() window:Close() picker:Close() end
function Controller.SetGiftMode(enabled: boolean)
	giftMode = enabled render()
end
function Controller.GetState(): any
	return { open = window:IsOpen(), giftMode = giftMode, recipientUserId = recipientId, snapshot = snapshot }
end
function Controller:Init(): ()
	window = Window.Create(Rules.GuiName, "ExclusiveShop.Title", { width = Rules.PanelWidth, height = Rules.PanelHeight,
		displayOrder = Rules.DisplayOrder, headerExtra = Rules.HeaderExtra })
	picker = Window.Create(Rules.GuiName .. "Recipients", "ExclusiveShop.RecipientTitle", { width = Rules.PickerWidth,
		height = Rules.PickerHeight, displayOrder = Rules.DisplayOrder + 1 })
	giftToggle = Window.Button(window.Header, "ExclusiveShop.GiftOff", nil, function() Controller.SetGiftMode(not giftMode) end,
		{ Name = "GiftMode", AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -C.GiftButtonRight, .5, 0),
			Size = UDim2.fromOffset(C.GiftButtonWidth, C.ButtonHeight), BackgroundColor3 = UI.Surface, TextColor3 = UI.Text })
	window.SizeChanged:Connect(function() if window:IsOpen() then task.defer(render) end end)
	window.Body:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if window:IsOpen() then render() end end)
end
function Controller:Start(): ()
	Network.GetEvent("ExclusiveShopState").OnClientEvent:Connect(applySnapshot)
	L.Changed:Connect(function() if window:IsOpen() then render() end if picker:IsOpen() then renderPicker() end end)
	while true do task.wait(C.CountdownTick) if window:IsOpen() then updateCountdown() end end
end
return Controller
