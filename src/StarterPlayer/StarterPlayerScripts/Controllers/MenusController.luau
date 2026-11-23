--!strict
-- HUD menus: Settings (music / SFX volume, low graphics - saved via SettingsUpdate), Inventory (items,
-- passes, pillows) and the Shop shortcut. Low graphics also turns off shadows locally.

local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = ReplicatedStorage.Shared.Config
local Items = require(Config.Items)
local Monetization = require(Config.Monetization)
local Pillows = require(Config.Pillows)
local Shop = require(Config.Shop)
local Sounds = require(Config.Sounds)
local UIAssets = require(Config.UIAssets)
local Network = require(ReplicatedStorage.Shared.Network)
local UiSkin = require(ReplicatedStorage.Shared.Util.UiSkin)
local Localization = require(ReplicatedStorage.Shared.Util.Localization)
local Viewport = require(ReplicatedStorage.Shared.Util.Viewport)
local HudButtonsController = require(script.Parent.HudButtonsController)
local ItemController = require(script.Parent.ItemController)
local NotificationController = require(script.Parent.NotificationController)
local ShopController = require(script.Parent.ShopController)
local UI = Shop.Ui

local MenusController = {
	Priority = 65,
}

local CLOSE_ACTION = "CloseMenus"
local VOLUME_STEP = 0.1
local player = Players.LocalPlayer
local settingsGui: ScreenGui
local inventoryGui: ScreenGui
local inventoryList: ScrollingFrame
local inventoryFooter: TextLabel
local inventoryEmpty: Frame
local assignBar: Frame
local assignmentButtons: { TextButton } = {}
local selectedItem: string? = nil
local inventoryBody: Frame
local inventoryGrid: UIGridLayout
local INVENTORY_CELL = Items.Hotbar.InventoryCard
local musicLabel: TextLabel
local sfxLabel: TextLabel
local lowButton: TextButton
local sfxIcon: ImageLabel
local updateEvent: RemoteEvent
local defaultShadows = true
local ROW_ICON = 34 -- settings row icons (UI pack)

local function corner(parent: Instance)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, UI.Corner)
	c.Parent = parent
end

local function setting(name: string, default: any): any
	local value = player:GetAttribute(name)
	return if value == nil then default else value
end

local function closeAll()
	settingsGui.Enabled = false
	inventoryGui.Enabled = false
	player:SetAttribute(Shop.UiStateAttribute, false)
	ContextActionService:UnbindAction(CLOSE_ACTION)
end

local function open(gui: ScreenGui)
	settingsGui.Enabled = gui == settingsGui
	inventoryGui.Enabled = gui == inventoryGui
	player:SetAttribute(Shop.UiStateAttribute, true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
		if UserInputService:GetFocusedTextBox() ~= nil then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then closeAll() end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Shop.CloseKey, Shop.CloseGamepadKey)
end

local function modal(name: string, title: string, height: number, width: number?): (ScreenGui, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.DisplayOrder = UI.DisplayOrder
	local shade = Instance.new("TextButton")
	shade.Text = ""
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = UI.ShadeTransparency
	shade.AutoButtonColor = false
	shade.Modal = true
	shade.Parent = gui
	shade.Activated:Connect(closeAll)
	local panel = Instance.new("Frame")
	panel.ZIndex = 2 -- keep the sliced background above the full-screen modal shade
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(width or 420, height)
	panel.BackgroundColor3 = UI.Background
	panel.Active = true
	panel.Parent = gui
	-- Close button (UI pack round × via UiStyleController) for touch players; Q / B and the shade still work.
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Text = "×"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(Items.Hotbar.MinTouchSlot, Items.Hotbar.MinTouchSlot)
	close.BackgroundColor3 = UI.Surface
	close.ZIndex = 2
	close.Parent = panel
	close.Activated:Connect(closeAll)
	corner(panel)
	local stroke = Instance.new("UIStroke")
	stroke.Color = UI.Accent
	stroke.Thickness = 2
	stroke.Parent = panel
	local padding = Instance.new("UIPadding")
	for _, side in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
		(padding :: any)[side] = UDim.new(0, UI.Padding)
	end
	padding.Parent = panel
	-- The list layout lives in an inner body so the panel can carry its UI pack frame (UiStyleController).
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.fromScale(1, 1)
	body.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, UI.Gap)
	layout.Parent = body
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, 0, 0, UI.TitleHeight)
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = UI.Text
	titleLabel.Text = title
	titleLabel.LayoutOrder = 0
	titleLabel.Parent = body
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui, body
end

local function row(parent: Instance, order: number): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = UI.Surface
	frame.Size = UDim2.new(1, 0, 0, UI.PurchaseHeight)
	frame.LayoutOrder = order
	frame.Parent = parent
	corner(frame)
	return frame
end

local function smallButton(parent: Instance, text: string, xScale: number, xOffset: number, width: number): TextButton
	local b = Instance.new("TextButton")
	b.Text = text
	b.Font = Enum.Font.FredokaOne
	b.TextSize = UI.TextSize
	b.BackgroundColor3 = UI.Accent
	b.TextColor3 = UI.Background
	b.AnchorPoint = Vector2.new(0, 0.5)
	b.Position = UDim2.new(xScale, xOffset, 0.5, 0)
	b.Size = UDim2.fromOffset(width, UI.PurchaseHeight - 8)
	b.Parent = parent
	corner(b)
	return b
end

-- Round "+" / "-" buttons from the UI pack.
local function iconButton(parent: Instance, imageId: string, xOffset: number): ImageButton
	local b = Instance.new("ImageButton")
	b.BackgroundTransparency = 1
	b.Image = imageId
	b.ScaleType = Enum.ScaleType.Fit
	b.AnchorPoint = Vector2.new(0, 0.5)
	b.Position = UDim2.new(1, xOffset, 0.5, 0)
	b.Size = UDim2.fromOffset(UI.PurchaseHeight - 6, UI.PurchaseHeight - 6)
	b:SetAttribute("UiSkin", "None")
	b.Parent = parent
	return b
end

local function label(parent: Instance, text: string, iconId: string?): TextLabel
	if iconId then
		local icon = UiSkin.Icon(parent, iconId, UDim2.fromOffset(ROW_ICON, ROW_ICON), UDim2.new(0, UI.Gap, 0.5, 0), Vector2.new(0, 0.5))
		icon.ZIndex = 2
	end
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(UI.Gap + (if iconId then ROW_ICON + UI.Gap else 0), 0)
	l.Size = UDim2.new(0.55, 0, 1, 0)
	l.Font = Enum.Font.GothamBold
	l.TextSize = UI.TextSize
	l.TextColor3 = UI.Text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

local function applySettings()
	local music = setting("Setting_MusicVolume", Sounds.DefaultMusicVolume)
	local sfx = setting("Setting_SfxVolume", Sounds.DefaultSfxVolume)
	local low = setting("Setting_LowGraphics", false) == true
	musicLabel.Text = Localization.T("Settings.MusicVolume", {percent = math.floor(music * 100 + 0.5)})
	sfxLabel.Text = Localization.T("Settings.SfxVolume", {percent = math.floor(sfx * 100 + 0.5)})
	lowButton.Text = if low then Localization.T("Common.On") else Localization.T("Common.Off")
	lowButton.BackgroundColor3 = if low then UI.Accent else UI.Surface
	lowButton.TextColor3 = if low then UI.Background else UI.Text
	sfxIcon.Image = if sfx <= 0 then UIAssets.Controls.SoundOff else UIAssets.Controls.SoundOn
	Lighting.GlobalShadows = defaultShadows and not low -- local only
end

local function changeVolume(key: string, attribute: string, default: number, delta: number)
	local value = math.clamp(setting(attribute, default) + delta, 0, 1)
	updateEvent:FireServer({ [key] = value })
end

-- One inventory card: icon, name and count/state on a UI pack card (UiStyleController skins UI.Surface frames).
local function inventoryCard(order: number, id: string, iconId: string, name: string, detail: string, highlight: boolean)
	local card = Instance.new("TextButton")
	card.Name = id
	card.Text = ""
	card.LayoutOrder = order
	card.BackgroundColor3 = if highlight then UI.Accent else UI.Surface
	card:SetAttribute("UiSkin", if highlight then "Card:Uncommon" else "Card")
	card:SetAttribute("UiSkinSelected", if selectedItem == id then true else nil)
	card.Active = ItemController.IsUsable(id)
	card.AutoButtonColor = card.Active
	card.Parent = inventoryList
	card.Activated:Connect(function()
		if not ItemController.IsUsable(id) then return end
		selectedItem = id
		inventoryFooter.Text = Localization.T("Inventory.SlotSelected", { item = Localization.T("Item." .. id .. ".Name") })
		for _, button in assignmentButtons do button.Active = true button.AutoButtonColor = true end
		for _, object in inventoryList:GetChildren() do
			if object:IsA("TextButton") then object.BackgroundColor3 = if object.Name == id then UI.Accent else UI.Surface end
		end
	end)
	if iconId ~= "" then
		UiSkin.Icon(card, iconId, UDim2.fromScale(0.5, 0.42), UDim2.fromScale(0.5, 0.1), Vector2.new(0.5, 0))
	end
	for index, text in { name, detail } do
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Position = UDim2.new(0.5, 0, if index == 1 then 0.55 else 0.73, 0)
		l.Size = UDim2.new(1, -16, 0.17, 0)
		l.Font = if index == 1 then Enum.Font.FredokaOne else Enum.Font.GothamBold
		l.TextScaled = true
		l.TextColor3 = if index == 1 then UI.Text else UI.Coin
		l.Text = text
		l.TextStrokeColor3 = UiSkin.Outline
		l.TextStrokeTransparency = if index == 1 then 0.7 else 0.5
		l.Parent = card
	end
end

local function refreshInventory()
	for _, child in inventoryList:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	local order = 0
	local owned = ItemController.GetOwnedItems()
	if selectedItem and not table.find(owned, selectedItem) then selectedItem = nil end
	for _, id in owned do
		local item = Items.Get(id)
		if item == nil then continue end
		order += 1
		local armed = (id == "Fish" and ItemController.GetFishReady()) or (id == "SoftPaws" and ItemController.GetSoftPawsReady())
		inventoryCard(order, id, item.icon, Localization.T("Item." .. id .. ".Name"), ItemController.GetItemState(id), armed or selectedItem == id)
	end
	inventoryEmpty.Visible = order == 0
	inventoryList.Visible = order > 0
	local hasUsable = false
	for _, id in owned do if ItemController.IsUsable(id) then hasUsable = true break end end
	assignBar.Visible = hasUsable
	inventoryFooter.Visible = hasUsable
	inventoryFooter.Text = if selectedItem then Localization.T("Inventory.SlotSelected", { item = Localization.T("Item." .. selectedItem .. ".Name") }) else Localization.T("Inventory.AssignHint")
	for _, button in assignmentButtons do button.Active = selectedItem ~= nil button.AutoButtonColor = button.Active end
end

function MenusController.OpenInventory(): ()
	refreshInventory()
	open(inventoryGui)
end

function MenusController.OpenSettings(): ()
	applySettings()
	open(settingsGui)
end

local function inventoryLayout()
	if inventoryBody == nil then return end
	local size = Viewport.Get()
	local panel = inventoryBody.Parent :: Frame
	local height = math.min(Items.Hotbar.InventoryHeight, size.Y - UI.Gap * 2)
	panel.Size = UDim2.fromOffset(math.min(Items.Hotbar.InventoryWidth, size.X - UI.Gap * 2), height)
	local width = math.max(1, inventoryBody.AbsoluteSize.X)
	local columns = if width < Items.Hotbar.MinTouchSlot * Items.Hotbar.SlotCount + UI.Gap * 5 then 3 else Items.Hotbar.SlotCount
	local assignHeight = Items.Hotbar.AssignHeight * math.ceil(Items.Hotbar.SlotCount / columns) + (if columns == 3 then UI.Gap / 2 else 0)
	assignBar.Size = UDim2.new(1,0,0,assignHeight)
	for index, button in assignmentButtons do
		local col, rowIndex = (index - 1) % columns, math.floor((index - 1) / columns)
		button.Position = UDim2.new(col / columns, UI.Gap * col / (2 * columns), 0, rowIndex * (Items.Hotbar.AssignHeight + UI.Gap / 2))
		button.Size = UDim2.new(1 / columns, -UI.Gap * (columns - 1) / (2 * columns), 0, Items.Hotbar.AssignHeight)
	end
	inventoryList.Size = UDim2.new(1,0,1,-(UI.TitleHeight + UI.Gap * 3 + UI.TextSize * 2 + assignHeight))
	inventoryEmpty.Size = inventoryList.Size
	local cardColumns = math.max(1, math.floor((width + UI.Gap / 2) / (INVENTORY_CELL.X + UI.Gap / 2)))
	inventoryGrid.FillDirectionMaxCells = cardColumns
	inventoryGrid.CellSize = UDim2.fromOffset(math.floor((width - UI.Gap / 2 * (cardColumns - 1)) / cardColumns), INVENTORY_CELL.Y)
end

function MenusController:Init(): ()
	updateEvent = Network.GetEvent("SettingsUpdate")
	defaultShadows = Lighting.GlobalShadows
	local panel
	settingsGui, panel = modal("Settings", Localization.T("Settings.Title"), 290) -- room for the popup frame's border
	local musicRow = row(panel, 1)
	musicLabel = label(musicRow, Localization.T("Settings.Music"), UIAssets.Controls.Music)
	local musicMinus = iconButton(musicRow, UIAssets.Controls.Minus, -96)
	musicMinus.Name = "MusicMinus"
	musicMinus.Activated:Connect(function()
		changeVolume("musicVolume", "Setting_MusicVolume", Sounds.DefaultMusicVolume, -VOLUME_STEP)
	end)
	local musicPlus = iconButton(musicRow, UIAssets.Controls.Plus, -50)
	musicPlus.Name = "MusicPlus"
	musicPlus.Activated:Connect(function()
		changeVolume("musicVolume", "Setting_MusicVolume", Sounds.DefaultMusicVolume, VOLUME_STEP)
	end)
	local sfxRow = row(panel, 2)
	sfxLabel = label(sfxRow, Localization.T("Settings.Sfx"), UIAssets.Controls.SoundOn)
	sfxIcon = sfxRow:FindFirstChild("Icon") :: ImageLabel
	iconButton(sfxRow, UIAssets.Controls.Minus, -96).Activated:Connect(function()
		changeVolume("sfxVolume", "Setting_SfxVolume", Sounds.DefaultSfxVolume, -VOLUME_STEP)
	end)
	iconButton(sfxRow, UIAssets.Controls.Plus, -50).Activated:Connect(function()
		changeVolume("sfxVolume", "Setting_SfxVolume", Sounds.DefaultSfxVolume, VOLUME_STEP)
	end)
	local lowRow = row(panel, 3)
	label(lowRow, Localization.T("Settings.LowGraphics"), UIAssets.Controls.Graphics)
	lowButton = smallButton(lowRow, Localization.T("Common.Off"), 1, -100, 92)
	lowButton.Activated:Connect(function()
		updateEvent:FireServer({ lowGraphics = not (setting("Setting_LowGraphics", false) == true) })
	end)

	local inventoryPanel
	inventoryGui, inventoryPanel = modal("Inventory", Localization.T("Inventory.Title"), Items.Hotbar.InventoryHeight, Items.Hotbar.InventoryWidth)
	inventoryBody = inventoryPanel
	local inventoryOuter = inventoryPanel.Parent :: Frame
	inventoryOuter:SetAttribute("UiNoScale",true)
	for _, object in inventoryPanel:GetChildren() do
		if object:IsA("TextLabel") then Localization.Bind(object,"Inventory.Title") end
	end
	inventoryList = Instance.new("ScrollingFrame")
	inventoryList.Name = "Items"
	inventoryList.BackgroundTransparency = 1
	inventoryList.BorderSizePixel = 0
	inventoryList.Size = UDim2.new(1, 0, 1, -(UI.TitleHeight + UI.TextSize + UI.Gap * 3))
	inventoryList.CanvasSize = UDim2.new()
	inventoryList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	inventoryList.ScrollBarThickness = UI.Gap / 2
	inventoryList.ScrollBarImageColor3 = UI.Coin
	inventoryList.LayoutOrder = 1
	inventoryList.Parent = inventoryPanel
	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.CellSize = UDim2.fromOffset(INVENTORY_CELL.X, INVENTORY_CELL.Y)
	grid.CellPadding = UDim2.fromOffset(UI.Gap / 2, UI.Gap / 2)
	grid.Parent = inventoryList
	inventoryGrid = grid
	inventoryEmpty = Instance.new("Frame")
	inventoryEmpty.Name = "Empty"
	inventoryEmpty.BackgroundTransparency = 1
	inventoryEmpty.LayoutOrder = 1
	inventoryEmpty.Parent = inventoryPanel
	local emptyText = Instance.new("TextLabel")
	emptyText.BackgroundTransparency = 1
	emptyText.Size = UDim2.new(1,0,0.5,0)
	emptyText.Font = Enum.Font.FredokaOne
	emptyText.TextSize = UI.TextSize
	emptyText.TextColor3 = UI.Text
	emptyText.TextWrapped = true
	emptyText.Parent = inventoryEmpty
	Localization.Bind(emptyText,"Inventory.Empty")
	local shopButton = smallButton(inventoryEmpty,"",0.5,-UI.PurchaseWidth / 2,UI.PurchaseWidth)
	shopButton.Size = UDim2.fromOffset(UI.PurchaseWidth, Items.Hotbar.MinTouchSlot)
	shopButton.Position = UDim2.fromScale(0.5,0.65)
	shopButton.AnchorPoint = Vector2.new(0.5,0.5)
	Localization.Bind(shopButton,"Inventory.OpenShop")
	shopButton.Activated:Connect(function()
		closeAll()
		ShopController.OpenTab("Catching")
	end)
	assignBar = Instance.new("Frame")
	assignBar.Name = "AssignSlots"
	assignBar.BackgroundTransparency = 1
	assignBar.LayoutOrder = 2
	assignBar.Parent = inventoryPanel
	for index = 1, Items.Hotbar.SlotCount do
		local button = Instance.new("TextButton")
		button.Name = `AssignSlot{index}`
		button.BackgroundColor3 = UI.Surface
		button.TextColor3 = UI.Text
		button.Font = Enum.Font.FredokaOne
		button.TextSize = UI.SmallTextSize
		button.Parent = assignBar
		Localization.Bind(button,"Inventory.AssignSlot",{slot=index})
		button.Activated:Connect(function()
			if selectedItem then ItemController.AssignSlot(selectedItem,index) end
		end)
		table.insert(assignmentButtons,button)
	end
	inventoryFooter = Instance.new("TextLabel")
	inventoryFooter.Name = "Footer"
	inventoryFooter.BackgroundTransparency = 1
	inventoryFooter.Size = UDim2.new(1, 0, 0, UI.TextSize * 2)
	inventoryFooter.Font = Enum.Font.GothamBold
	inventoryFooter.TextSize = UI.SmallTextSize + 1
	inventoryFooter.TextColor3 = UI.Muted
	inventoryFooter.LayoutOrder = 3
	inventoryFooter.TextWrapped = true
	inventoryFooter.Parent = inventoryPanel
	inventoryBody:GetPropertyChangedSignal("AbsoluteSize"):Connect(inventoryLayout)
	Viewport.Changed:Connect(inventoryLayout)
	inventoryLayout()
	ItemController.InventoryRequested:Connect(MenusController.OpenInventory)
	ItemController.ShopRequested:Connect(function() ShopController.OpenTab("Catching") end)

	HudButtonsController.Add("Shop", Localization.T("Hud.Shop"), 40, nil, function()
		ShopController.OpenTab("Catching")
		NotificationController.ShowLocal(Localization.T("Shop.BrowseOnly"), "Info")
	end)
	HudButtonsController.Add("Inventory", Localization.T("Hud.Inventory"), 50, nil, function()
		MenusController.OpenInventory()
	end)
	HudButtonsController.Add("Settings", Localization.T("Hud.Settings"), 90, nil, function()
		MenusController.OpenSettings()
	end)
end

function MenusController:Start(): ()
	for _, name in { "Setting_MusicVolume", "Setting_SfxVolume", "Setting_LowGraphics" } do
		player:GetAttributeChangedSignal(name):Connect(applySettings)
	end
	applySettings()
	ItemController.InventoryChanged:Connect(function()
		if inventoryGui.Enabled then refreshInventory() end
	end)
end

return MenusController


