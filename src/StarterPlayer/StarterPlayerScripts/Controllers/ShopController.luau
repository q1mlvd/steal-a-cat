--!strict
-- The stall opens this modal. Purchases, upgrades and all inventory mutations remain on the server.
-- The Upgrades tab reads the server's UpgradeLevel_<id> player attributes (display mirrors only).
-- The Robux tab lists Game Passes / Developer Products (Config/Monetization); buttons only ask the server
-- to validate and prompt. It also opens from the HUD "Store" button without visiting the stall.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Localization = require(ReplicatedStorage.Shared.Util.Localization)
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")

local Config = ReplicatedStorage.Shared.Config
local Economy = require(Config.Economy)
local GameConfig = require(Config.Game)
local Items = require(Config.Items)
local Monetization = require(Config.Monetization)
local Pillows = require(Config.Pillows)
local Shop = require(Config.Shop)
local Upgrades = require(Config.Upgrades)
local UIAssets = require(Config.UIAssets)
local Network = require(ReplicatedStorage.Shared.Network)
local NumberFormat = require(ReplicatedStorage.Shared.Util.NumberFormat)
local InputModeController = require(script.Parent.InputModeController)
local ItemController = require(script.Parent.ItemController)
local UI = Shop.Ui

type Row = { id: string, button: TextButton, owned: TextLabel }
type UpgradeRow = { id: string, button: TextButton, title: TextLabel, preview: TextLabel }
type RobuxRow = { key: string, isPass: boolean, onSale: boolean, frame: Frame, button: TextButton }

local ShopController = { Priority = 47 }
local player = Players.LocalPlayer
local gui: ScreenGui
local tabButtons: { [string]: TextButton } = {}
local pages: { [string]: ScrollingFrame } = {}
local balance: TextLabel
local rows: { Row } = {}
local upgradeRows: { UpgradeRow } = {}
local robuxRows: { RobuxRow } = {}
local newRibbons: { [string]: TextLabel } = {}
local robuxEvent: RemoteEvent
local closeHint: TextLabel
local purchaseEvent: RemoteEvent
local upgradeEvent: RemoteEvent
local coins = 0
local currentTab = "Catching"

local function refreshNewItems(state: any)
	if type(state) ~= "table" or type(state.newShopItems) ~= "table" then return end
	for id, ribbon in newRibbons do ribbon.Visible = state.newShopItems[id] == true end
end

local function corner(parent: Instance)
	local result = Instance.new("UICorner")
	result.CornerRadius = UDim.new(0, UI.Corner)
	result.Parent = parent
end

local function label(parent: Instance, name: string, text: string, size: UDim2, position: UDim2, textSize: number, color: Color3): TextLabel
	local result = Instance.new("TextLabel")
	result.Name = name
	result.BackgroundTransparency = 1
	result.Text = text
	result.TextColor3 = color
	result.TextSize = textSize
	result.Font = Enum.Font.GothamBold
	result.TextXAlignment = Enum.TextXAlignment.Left
	result.Size = size
	result.Position = position
	result.Parent = parent
	return result
end

-- Stage 18: shop rows are rarity-coloured UI pack cards (colour per page, Config/UIAssets.CategoryCards).
local CARD_INSET = 6
local function cardStyle(row: Frame, page: string)
	row:SetAttribute("UiSkin", "Card:" .. ((UIAssets.CategoryCards :: any)[page] or ""))
	local padding = Instance.new("UIPadding")
	for _, side in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
		(padding :: any)[side] = UDim.new(0, CARD_INSET)
	end
	padding.Parent = row
end

local function formatNumber(value: number): string
	return if value == math.floor(value) then tostring(value) else string.format("%.1f", value)
end

-- Label and value text of one effect level, e.g. ("Speed", "18"), ("Pillows", "10").
local function describeEffect(definition: Upgrades.UpgradeDefinition, value: number): (string, string)
	if definition.preview == "WalkSpeed" then
		return Localization.T("Effect.Speed"), formatNumber(StarterPlayer.CharacterWalkSpeed + value)
	elseif definition.preview == "JumpHeight" then
		return Localization.T("Effect.Jump"), formatNumber(StarterPlayer.CharacterJumpHeight + value)
	elseif definition.preview == "Capacity" then
		return Localization.T("Effect.Carry"), Localization.T(if value == 1 then "Common.CatOne" else "Common.CatCount", {count = formatNumber(value)})
	elseif definition.preview == "Radius" then
		return Localization.T("Effect.Magnet"), if value <= 0 then Localization.T("Common.Off") else Localization.T("Common.Studs", {count = formatNumber(value)})
	end
	local passBonus = if player:GetAttribute(Monetization.PassAttributePrefix .. "ExtraPillows") == true
		then Monetization.ExtraPillowsBonus else 0
	return Localization.T("Effect.Pillows"), formatNumber(math.min(GameConfig.StartingPillows + value + passBonus, GameConfig.MaxPillows))
end

local function refreshUpgrades()
	for _, row in upgradeRows do
		local definition = Upgrades.Get(row.id)
		if definition == nil then continue end
		local maxLevel = #definition.levels
		local level = Upgrades.SanitizeLevel(row.id, player:GetAttribute(Upgrades.LevelAttributePrefix .. row.id))
		local effectLabel, current = describeEffect(definition, Upgrades.EffectAt(row.id, level))
		-- Pillows also max out when the Extra Pillows pass already reaches the 30 pillow cap.
		local maxed = level >= maxLevel or (row.id == "Pillows" and current == tostring(GameConfig.MaxPillows))
		row.title.Text = Localization.T("Shop.Level", {name = Localization.T("Upgrade." .. definition.id .. ".Name"), level = level, max = maxLevel})
		if maxed then
			row.preview.Text = Localization.T("Shop.EffectMax", {effect = effectLabel, current = current})
		else
			local _, nextValue = describeEffect(definition, Upgrades.EffectAt(row.id, level + 1))
			row.preview.Text = Localization.T("Shop.EffectNext", {effect = effectLabel, current = current, next = nextValue}) -- e.g. "Pillows 8 → 10"
		end
		local cost = if maxed then 0 else definition.levels[level + 1].cost
		local buyable = definition.available and not maxed
		row.button.Text = if not definition.available then Localization.T("Shop.ComingSoon") elseif maxed then Localization.T("Common.Max")
			else Localization.T("Shop.Upgrade", {amount = NumberFormat.Format(cost)})
		row.button.BackgroundColor3 = if buyable and coins >= cost then UI.Accent else UI.Surface
		row.button.TextColor3 = if buyable and coins >= cost then UI.Background else UI.Muted
		row.button.Active = buyable
		row.button.AutoButtonColor = buyable
	end
end

local function refreshRobux()
	local freePillows = player:GetAttribute(Pillows.FreePillowsAttribute)
	for _, row in robuxRows do
		local owned = row.isPass and player:GetAttribute(Monetization.PassAttributePrefix .. row.key) == true
		local blocked = row.key == "CatBox" and type(freePillows) == "number" and freePillows <= 0
		local buyable = row.onSale and not owned and not blocked
		row.button.Text = if owned then Localization.T("Inventory.Owned") elseif not row.onSale then Localization.T("Shop.NotOnSale")
			elseif blocked then Localization.T("Shop.FreePillow") else Localization.T("Shop.Buy")
		row.button.BackgroundColor3 = if buyable then UI.Accent else UI.Surface
		row.button.TextColor3 = if buyable then UI.Background else (if owned then UI.Accent else UI.Muted)
		row.button.Active = buyable
		row.button.AutoButtonColor = buyable
	end
end

local function refreshCloseHint()
	local mode = InputModeController.GetMode()
	closeHint.Text = if mode == "KeyboardMouse" then Localization.T("Shop.CloseKey", {key = Shop.CloseKey.Name})
		elseif mode == "Gamepad" then Localization.T("Shop.CloseKey", {key = string.gsub(Shop.CloseGamepadKey.Name, "^Button", "")}) else Localization.T("Shop.CloseTouch")
end

local function refresh()
	for id, page in pages do page.Visible = currentTab == id end
	for id, button in tabButtons do
		button.BackgroundColor3 = if currentTab == id then UI.Accent else UI.Surface
		button.TextColor3 = if currentTab == id then UI.Background else UI.Text
	end
	balance.Text = Localization.T("Common.Coins", {count = NumberFormat.Format(coins)})
	for _, row in rows do
		local definition = Items.Get(row.id)
		if definition == nil then continue end
		local count = ItemController.GetCount(row.id)
		local full = count >= definition.maxStack
		local permanentPlayer = definition.type == "permanent" and definition.permanentScope ~= "cat"
		local ready = (row.id == "Fish" and ItemController.GetFishReady()) or (row.id == "SoftPaws" and ItemController.GetSoftPawsReady())
		row.owned.Text = if permanentPlayer then (if count > 0 then Localization.T("Shop.PermanentlyOwned") else Localization.T("Shop.PermanentItem"))
			elseif definition.permanentScope == "cat" then Localization.T("Shop.Unattached", {count = count, max = definition.maxStack})
			elseif ready then Localization.T("Shop.Armed", {count = count}) else Localization.T("Shop.OwnedCount", {count = count, max = definition.maxStack})
		row.button.Text = if full then (if permanentPlayer then Localization.T("Shop.Owned") else Localization.T("Shop.StackFull"))
			else Localization.T("Common.Buy", {amount = NumberFormat.Format(definition.price)})
		row.button.BackgroundColor3 = if full or coins < definition.price then UI.Surface else UI.Accent
		row.button.TextColor3 = if full or coins < definition.price then UI.Muted else UI.Background
		row.button.Active = not full
		row.button.AutoButtonColor = not full
	end
	refreshUpgrades()
	refreshRobux()
end

local function close()
	gui.Enabled = false
	player:SetAttribute(Shop.UiStateAttribute, false)
	-- Shop browsing does not replace the player's independently selected hotbar category.
	ContextActionService:UnbindAction("CloseCatShop")
end

local function open(snapshot: unknown)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local catchGui = if playerGui then playerGui:FindFirstChild(Shop.CatchGuiName) else nil
	if catchGui and catchGui:IsA("ScreenGui") and catchGui.Enabled then
		return
	end
	ItemController.ApplySnapshot(snapshot)
	ShopController.OpenTab("Catching")
end

-- Opens the shop on a tab (stall prompt: Catching; HUD Store button: Robux). Coin purchases are still
-- validated against the stall session on the server.
function ShopController.OpenTab(tab: string)
	if tab == Monetization.StoreTabName then
		close()
		require(script.Parent.ExclusiveShopController).Open()
		return
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local catchGui = if playerGui then playerGui:FindFirstChild(Shop.CatchGuiName) else nil
	if (catchGui and catchGui:IsA("ScreenGui") and catchGui.Enabled) or pages[tab] == nil then
		return
	end
	currentTab = tab
	gui.Enabled = true
	player:SetAttribute(Shop.UiStateAttribute, true)
	refresh()
	ContextActionService:BindActionAtPriority("CloseCatShop", function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
		if UserInputService:GetFocusedTextBox() ~= nil then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then close() end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Shop.CloseKey, Shop.CloseGamepadKey)
end

local function makeTab(parent: Instance, name: string, text: string, position: UDim2, size: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Size = size
	button.Position = position
	button.BorderSizePixel = 0
	button.Parent = parent
	corner(button)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = UI.TextSize
	constraint.Parent = button
	return button
end

local function buildRow(definition: Items.ItemDefinition, index: number)
	local row = Instance.new("Frame")
	row.Name = definition.id
	row.LayoutOrder = index
	row.Size = UDim2.new(1, -UI.Gap, 0, UI.RowHeight)
	row.BackgroundColor3 = UI.Surface
	row.BorderSizePixel = 0
	row.Parent = pages[definition.category]
	corner(row)
	cardStyle(row, definition.category)
	local icon = Instance.new("Frame")
	icon.Name = "IconPlaceholder"
	icon.Position = UDim2.fromOffset(UI.Gap, UI.Gap)
	icon.Size = UDim2.fromOffset(UI.IconSize, UI.IconSize)
	icon.BackgroundColor3 = UI.Background
	icon.BorderSizePixel = 0
	icon.Parent = row
	corner(icon)
	if definition.icon ~= "" then
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.Image = definition.icon
		image.Parent = icon
	else
		local placeholder = label(icon, "Initial", string.sub(Localization.T("Item." .. definition.id .. ".Name"), 1, 1), UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), UI.TextSize, UI.Accent)
		placeholder.TextXAlignment = Enum.TextXAlignment.Center
	end
	local title = label(row, "Name", Localization.T("Item." .. definition.id .. ".Name"), UDim2.new(1, -(UI.IconSize + UI.Gap * 3), 0, UI.TextSize + UI.Gap),
		UDim2.fromOffset(UI.IconSize + UI.Gap * 2, UI.Gap), UI.TextSize, UI.Text)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Size = UDim2.new(1, -(UI.IconSize + UI.Gap * 3 + UI.PurchaseWidth), 0, UI.TextSize + UI.Gap)
	local ribbon = Instance.new("TextLabel")
	ribbon.Name = "NewRibbon"
	ribbon.ZIndex = 2
	ribbon:SetAttribute("UiSkin", "Button:Red")
	ribbon.AnchorPoint = Vector2.new(1, 0)
	ribbon.Position = UDim2.new(1, -UI.Gap, 0, UI.Gap)
	ribbon.Size = UDim2.fromOffset(UI.PurchaseWidth, UI.TextSize + UI.Gap)
	ribbon.BackgroundColor3 = UI.Danger
	ribbon.TextColor3 = UI.OnColor
	ribbon.Font = Enum.Font.FredokaOne
	ribbon.TextSize = UI.SmallTextSize
	ribbon.TextStrokeTransparency = 0.3
	ribbon.Visible = false
	ribbon.Parent = row
	Localization.Bind(ribbon, "Hud.New")
	newRibbons[definition.id] = ribbon
	local description = label(row, "Description", Localization.T("Item." .. definition.id .. ".Description"),
		UDim2.new(1, -UI.Gap * 2, 0, UI.RowHeight - UI.IconSize - UI.PurchaseHeight - UI.Gap * 3),
		UDim2.fromOffset(UI.Gap, UI.IconSize + UI.Gap), UI.SmallTextSize, UI.Muted)
	description.Font = Enum.Font.Gotham
	description.TextWrapped = true
	description.TextYAlignment = Enum.TextYAlignment.Top
	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.AnchorPoint = Vector2.new(1, 1)
	buy.Position = UDim2.new(1, -UI.Gap, 1, -UI.Gap)
	buy.Size = UDim2.fromOffset(UI.PurchaseWidth, UI.PurchaseHeight)
	buy.Font = Enum.Font.GothamBold
	buy.TextSize = UI.SmallTextSize
	buy.BorderSizePixel = 0
	buy.Parent = row
	corner(buy)
	buy.Activated:Connect(function()
		if gui.Enabled then purchaseEvent:FireServer(definition.id) end
	end)
	local owned = label(row, "Owned", "", UDim2.new(1, -(UI.PurchaseWidth + UI.Gap * 3), 0, UI.PurchaseHeight),
		UDim2.new(0, UI.Gap, 1, -(UI.PurchaseHeight + UI.Gap)), UI.SmallTextSize, UI.Coin)
	owned.TextTruncate = Enum.TextTruncate.AtEnd
	table.insert(rows, { id = definition.id, button = buy, owned = owned })
end

-- Same row layout as items: icon, title (with level), description, effect preview and buy button.
local function buildUpgradeRow(definition: Upgrades.UpgradeDefinition, index: number)
	local row = Instance.new("Frame")
	row.Name = definition.id
	row.LayoutOrder = index
	row.Size = UDim2.new(1, -UI.Gap, 0, UI.RowHeight)
	row.BackgroundColor3 = UI.Surface
	row.BorderSizePixel = 0
	row.Parent = pages[Upgrades.TabName]
	corner(row)
	cardStyle(row, Upgrades.TabName)
	local icon = Instance.new("Frame")
	icon.Name = "IconPlaceholder"
	icon.Position = UDim2.fromOffset(UI.Gap, UI.Gap)
	icon.Size = UDim2.fromOffset(UI.IconSize, UI.IconSize)
	icon.BackgroundColor3 = UI.Background
	icon.BorderSizePixel = 0
	icon.Parent = row
	corner(icon)
	if definition.icon ~= "" then
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.Image = definition.icon
		image.Parent = icon
	else
		local placeholder = label(icon, "Initial", string.sub(Localization.T("Upgrade." .. definition.id .. ".Name"), 1, 1), UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), UI.TextSize, UI.Accent)
		placeholder.TextXAlignment = Enum.TextXAlignment.Center
	end
	local title = label(row, "Name", Localization.T("Upgrade." .. definition.id .. ".Name"), UDim2.new(1, -(UI.IconSize + UI.Gap * 3), 0, UI.TextSize + UI.Gap),
		UDim2.fromOffset(UI.IconSize + UI.Gap * 2, UI.Gap), UI.TextSize, UI.Text)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	local description = label(row, "Description", Localization.T("Upgrade." .. definition.id .. ".Description"),
		UDim2.new(1, -UI.Gap * 2, 0, UI.RowHeight - UI.IconSize - UI.PurchaseHeight - UI.Gap * 3),
		UDim2.fromOffset(UI.Gap, UI.IconSize + UI.Gap), UI.SmallTextSize, UI.Muted)
	description.Font = Enum.Font.Gotham
	description.TextWrapped = true
	description.TextYAlignment = Enum.TextYAlignment.Top
	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.AnchorPoint = Vector2.new(1, 1)
	buy.Position = UDim2.new(1, -UI.Gap, 1, -UI.Gap)
	buy.Size = UDim2.fromOffset(UI.PurchaseWidth, UI.PurchaseHeight)
	buy.Font = Enum.Font.GothamBold
	buy.TextSize = UI.SmallTextSize
	buy.TextWrapped = true
	buy.BorderSizePixel = 0
	buy.Parent = row
	corner(buy)
	buy.Activated:Connect(function()
		if gui.Enabled and buy.Active then upgradeEvent:FireServer(definition.id) end
	end)
	local preview = label(row, "Preview", "", UDim2.new(1, -(UI.PurchaseWidth + UI.Gap * 3), 0, UI.PurchaseHeight),
		UDim2.new(0, UI.Gap, 1, -(UI.PurchaseHeight + UI.Gap)), UI.SmallTextSize, UI.Coin)
	preview.TextTruncate = Enum.TextTruncate.AtEnd
	table.insert(upgradeRows, { id = definition.id, button = buy, title = title, preview = preview })
end

-- Pass/product row: icon, name + Robux price, description, Buy / OWNED button.
local function buildRobuxRow(key: string, name: string, description: string, robux: number, iconId: string,
	isPass: boolean, onSale: boolean, index: number)
	local row = Instance.new("Frame")
	row.Name = key
	row.LayoutOrder = index
	row.Size = UDim2.new(1, -UI.Gap, 0, UI.RowHeight)
	row.BackgroundColor3 = UI.Surface
	row.BorderSizePixel = 0
	row.Parent = pages[Monetization.StoreTabName]
	corner(row)
	cardStyle(row, Monetization.StoreTabName)
	local icon = Instance.new("Frame")
	icon.Name = "IconPlaceholder"
	icon.Position = UDim2.fromOffset(UI.Gap, UI.Gap)
	icon.Size = UDim2.fromOffset(UI.IconSize, UI.IconSize)
	icon.BackgroundColor3 = UI.Background
	icon.BorderSizePixel = 0
	icon.Parent = row
	corner(icon)
	if iconId ~= "" then
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.Image = iconId
		image.Parent = icon
	else
		local placeholder = label(icon, "Initial", if isPass then "P" else "R$", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), UI.SmallTextSize, UI.Coin)
		placeholder.TextXAlignment = Enum.TextXAlignment.Center
	end
	local title = label(row, "Name", Localization.T("Shop.RobuxTitle", {name = Localization.T("Store." .. key .. ".Name"), robux = robux}), UDim2.new(1, -(UI.IconSize + UI.Gap * 3), 0, UI.TextSize + UI.Gap),
		UDim2.fromOffset(UI.IconSize + UI.Gap * 2, UI.Gap), UI.TextSize, UI.Text)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	local body = label(row, "Description", Localization.T("Store." .. key .. ".Description"),
		UDim2.new(1, -UI.Gap * 2, 0, UI.RowHeight - UI.IconSize - UI.PurchaseHeight - UI.Gap * 3),
		UDim2.fromOffset(UI.Gap, UI.IconSize + UI.Gap), UI.SmallTextSize, UI.Muted)
	body.Font = Enum.Font.Gotham
	body.TextWrapped = true
	body.TextYAlignment = Enum.TextYAlignment.Top
	local kind = label(row, "Kind", if isPass then Localization.T("Shop.PassKind") else Localization.T("Shop.ProductKind"),
		UDim2.new(1, -(UI.PurchaseWidth + UI.Gap * 3), 0, UI.PurchaseHeight),
		UDim2.new(0, UI.Gap, 1, -(UI.PurchaseHeight + UI.Gap)), UI.SmallTextSize, UI.Coin)
	kind.TextTruncate = Enum.TextTruncate.AtEnd
	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.AnchorPoint = Vector2.new(1, 1)
	buy.Position = UDim2.new(1, -UI.Gap, 1, -UI.Gap)
	buy.Size = UDim2.fromOffset(UI.PurchaseWidth, UI.PurchaseHeight)
	buy.Font = Enum.Font.GothamBold
	buy.TextSize = UI.SmallTextSize
	buy.TextWrapped = true
	buy.BorderSizePixel = 0
	buy.Parent = row
	corner(buy)
	buy.Activated:Connect(function()
		if gui.Enabled and buy.Active then robuxEvent:FireServer(key) end
	end)
	-- Items without a real id are hidden outside Studio (shown greyed in Studio for testing).
	row.Visible = onSale or RunService:IsStudio()
	table.insert(robuxRows, { key = key, isPass = isPass, onSale = onSale, frame = row, button = buy })
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = Shop.GuiName
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.DisplayOrder = UI.DisplayOrder
	local shade = Instance.new("TextButton")
	shade.Name = "Shade"
	shade.Text = ""
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = UI.ShadeTransparency
	shade.AutoButtonColor = false
	shade.Modal = true
	shade.Parent = gui
	shade.Activated:Connect(close)
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(UI.PanelWidthScale, UI.PanelHeightScale)
	panel.BackgroundColor3 = UI.Background
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Parent = gui
	corner(panel)
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = UI.MinPanelSize
	sizeConstraint.MaxSize = Vector2.new(UI.PanelWidth, UI.PanelHeight)
	sizeConstraint.Parent = panel
	local title = label(panel, "Title", Localization.T("Shop.Title"), UDim2.new(1, -(UI.Padding * 3 + UI.TitleHeight), 0, UI.TitleHeight),
		UDim2.fromOffset(UI.Padding, UI.Padding), UI.TextSize + UI.Gap, UI.Text)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	local titleConstraint = Instance.new("UITextSizeConstraint")
	titleConstraint.MaxTextSize = UI.TextSize + UI.Gap
	titleConstraint.Parent = title
	local closeButton = makeTab(panel, "Close", "×", UDim2.new(1, -(UI.Padding + UI.TitleHeight), 0, UI.Padding), UDim2.fromOffset(UI.TitleHeight, UI.TitleHeight))
	closeButton.BackgroundColor3 = UI.Surface
	closeButton.TextColor3 = UI.Text
	closeButton.Activated:Connect(close)
	local tabTop = UI.Padding + UI.TitleHeight + UI.Gap
	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(UI.Padding, tabTop)
	tabs.Size = UDim2.new(1, -UI.Padding * 2, 0, UI.TabHeight)
	tabs.Parent = panel
	-- Item categories (shared with the hotbar) plus the Upgrades tab.
	local tabNames = table.clone(Shop.Categories)
	table.insert(tabNames, Upgrades.TabName)
	table.insert(tabNames, Monetization.StoreTabName)
	for index, category in tabNames do
		local fraction = (index - 1) / #tabNames
		local button = makeTab(tabs, category, Localization.T("Shop." .. category), UDim2.new(fraction, UI.Gap * fraction, 0, 0),
			UDim2.new(1 / #tabNames, -UI.Gap * (#tabNames - 1) / #tabNames, 1, 0))
		button:SetAttribute("UiSkin", "Tab")
		tabButtons[category] = button
		button.Activated:Connect(function() if category == Monetization.StoreTabName then ShopController.OpenTab(category) else currentTab = category refresh() end end)
	end
	local bodyTop = tabTop + UI.TabHeight + UI.Gap
	local bodyBottom = UI.Padding * 2 + UI.TextSize
	for _, category in tabNames do
		local page = Instance.new("ScrollingFrame")
		page.Name = `{category}Items`
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.Position = UDim2.fromOffset(UI.Padding, bodyTop)
		page.Size = UDim2.new(1, -UI.Padding * 2, 1, -(bodyTop + bodyBottom))
		page.CanvasSize = UDim2.fromScale(0, 0)
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		page.ScrollBarThickness = UI.Gap / 2
		page.ScrollBarImageColor3 = UI.Accent
		page.ScrollingDirection = Enum.ScrollingDirection.Y
		page.Parent = panel
		pages[category] = page
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, UI.Gap)
		layout.Parent = page
	end
	for index, definition in Items.List do buildRow(definition, index) end
	for index, definition in Upgrades.List do buildUpgradeRow(definition, index) end
	for index, pass in Monetization.Passes do
		buildRobuxRow(pass.key, pass.name, pass.description, pass.robux, pass.icon, true, pass.passId ~= 0, index)
	end
	for index, product in Monetization.Products do
		if product.gift then continue end
		buildRobuxRow(product.key, product.name, product.description, product.robux, product.icon, false,
			product.productId ~= 0, #Monetization.Passes + index)
	end
	-- The HUD "R$ Store" button lives in HudButtonsController and calls ShopController.OpenTab.
	balance = label(panel, "Balance", Localization.T("Common.Coins", {count = 0}), UDim2.new(0.5, -UI.Padding, 0, UI.TextSize),
		UDim2.new(0, UI.Padding, 1, -(UI.Padding + UI.TextSize)), UI.SmallTextSize, UI.Coin)
	closeHint = label(panel, "CloseHint", "", UDim2.new(0.5, -UI.Padding, 0, UI.TextSize),
		UDim2.new(0.5, 0, 1, -(UI.Padding + UI.TextSize)), UI.SmallTextSize, UI.Muted)
	closeHint.TextXAlignment = Enum.TextXAlignment.Right
	refreshCloseHint()
	gui.Parent = player:WaitForChild("PlayerGui")
	player:SetAttribute(Shop.UiStateAttribute, false)
	refresh()
end

function ShopController:Init(): ()
	purchaseEvent = Network.GetEvent("ShopPurchase")
	upgradeEvent = Network.GetEvent("UpgradePurchase")
	robuxEvent = Network.GetEvent("RobuxPurchaseRequest")
	build()
end

function ShopController:Start(): ()
	Network.GetEvent("HudState").OnClientEvent:Connect(refreshNewItems)
	task.spawn(function()
		local ok, state = pcall(function() return Network.GetFunction("HudSnapshot"):InvokeServer() end)
		if ok then refreshNewItems(state) end
	end)
	Network.GetEvent("ShopOpen").OnClientEvent:Connect(open)
	ItemController.InventoryChanged:Connect(refresh)
	InputModeController.Changed:Connect(refreshCloseHint)
	player:GetAttributeChangedSignal(Pillows.FreePillowsAttribute):Connect(refreshRobux)
	for _, pass in Monetization.Passes do
		player:GetAttributeChangedSignal(Monetization.PassAttributePrefix .. pass.key):Connect(refresh)
	end
	for _, definition in Upgrades.List do
		player:GetAttributeChangedSignal(Upgrades.LevelAttributePrefix .. definition.id):Connect(refreshUpgrades)
	end
	player.CharacterAdded:Connect(close)
	local playerGui = player:WaitForChild("PlayerGui")
	local catchGui = playerGui:WaitForChild(Shop.CatchGuiName) :: ScreenGui
	catchGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if catchGui.Enabled then close() end
	end)
	task.spawn(function()
		local leaderstats = player:WaitForChild("leaderstats", math.huge)
		local value = (leaderstats :: Instance):WaitForChild(Economy.LeaderstatName, math.huge) :: NumberValue
		coins = value.Value
		refresh()
		value.Changed:Connect(function(newValue: number)
			coins = newValue
			refresh()
		end)
	end)
end

return ShopController


