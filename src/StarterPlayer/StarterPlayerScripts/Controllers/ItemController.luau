--!strict
-- The hotbar displays server inventory; button/key presses only request validated server effects.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local Config = ReplicatedStorage.Shared.Config
local Items = require(Config.Items)
local Shop = require(Config.Shop)
local Network = require(ReplicatedStorage.Shared.Network)
local NumberFormat = require(ReplicatedStorage.Shared.Util.NumberFormat)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local InputModeController = require(script.Parent.InputModeController)
local UiSkin = require(ReplicatedStorage.Shared.Util.UiSkin)
local UiTooltip = require(ReplicatedStorage.Shared.Util.UiTooltip)
local Viewport = require(ReplicatedStorage.Shared.Util.Viewport)
local ItemInventory = require(ReplicatedStorage.Shared.Util.ItemInventory)
local Localization = require(ReplicatedStorage.Shared.Util.Localization)
local UI = Shop.Ui
local HOTBAR = Items.Hotbar
-- Stage 18: slots use the UI pack hotbar frame (dark interior), so slot text is light and outlined.
local SLOT_TEXT_ON = Color3.fromRGB(160, 255, 190)
local SLOT_TEXT_OFF = Color3.fromRGB(228, 218, 238)

type Slot = { button: TextButton, count: TextLabel, key: TextLabel, name: TextLabel, icon: ImageLabel, id: string }

local ItemController = {
	Priority = 46,
	InventoryChanged = Signal.new() :: Signal.Signal<>,
	InventoryRequested = Signal.new() :: Signal.Signal<>,
	ShopRequested = Signal.new() :: Signal.Signal<>,
}

local player = Players.LocalPlayer
local counts: { [string]: number } = {}
local fishReady = false
local softPawsReady = false
local currentCategory = "All"
local pageButtons: { [string]: TextButton } = {}
local categories = { "All", table.unpack(Shop.Categories) }
local preferredSlots: { string } = {}
local visibleIds: { string } = {}
local visibleTotal = 0
local receivedSnapshot = false
local slots: { Slot } = {}
local gui: ScreenGui
local root: Frame
local pickupRoot: Frame
local bar: Frame
local pageBar: Frame
local moreButton: TextButton
local emptyLabel: TextLabel
local emptyShopButton: TextButton
local layout: UIGridLayout
local viewportConnection: RBXScriptConnection? = nil
local columns = #Shop.HotbarKeys
local useEvent: RemoteEvent
local lastUseAt = -math.huge
local metrics = { bottom = HOTBAR.Bottom, height = 0, width = 0, tabsHeight = HOTBAR.TabHeight, columns = HOTBAR.SlotCount }

-- Touch screens: the hotbar shrinks with the screen so it stays low, between thumbstick and jump button.
local function updateLayout()
	if root == nil then return end
	local mobile = InputModeController.IsTouch()
	local viewport = Viewport.Get()
	local portrait = mobile and viewport.Y > viewport.X
	local size = if Viewport.GetOverride() then viewport else root.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then size = viewport end
	local showKeys = InputModeController.GetMode() == "KeyboardMouse"
	for _, slot in slots do slot.key.Visible = showKeys end
	local left = if mobile and not portrait then HOTBAR.TouchSideReserve else HOTBAR.Bottom
	local right = size.X - left
	local controlRects: { GuiObject } = {}
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local touchGui = if playerGui then playerGui:FindFirstChild("TouchGui") else nil
	if mobile and touchGui and Viewport.GetOverride() == nil then
		for _, object in touchGui:GetDescendants() do
			if object:IsA("GuiObject") and object.Visible and (object.Name == "JumpButton" or object.Name == "ThumbstickFrame" or object.Name == "ThumbstickStart") then
				table.insert(controlRects, object)
				if not portrait then
					local position = object.AbsolutePosition - root.AbsolutePosition
					if position.X < size.X / 2 then left = math.max(left, position.X + object.AbsoluteSize.X + HOTBAR.Gap)
					else right = math.min(right, position.X - HOTBAR.Gap) end
				end
			end
		end
	end
	local available = math.max(HOTBAR.MinTouchSlot, right - left)
	columns = if portrait then HOTBAR.PortraitColumns else HOTBAR.SlotCount
	local desired = if mobile then HOTBAR.TouchSlot else UI.HotbarButtonSize
	local minimum = if mobile then HOTBAR.MinTouchSlot else desired
	local button = math.max(minimum, math.min(desired, math.floor((available - HOTBAR.Gap * (columns - 1)) / columns)))
	if not portrait and columns * button + HOTBAR.Gap * (columns - 1) > available then
		columns = math.max(1, math.floor((available + HOTBAR.Gap) / (minimum + HOTBAR.Gap)))
	end
	local shown = math.max(1, #visibleIds)
	local rows = math.ceil(shown / columns)
	local actualColumns = math.min(columns, shown)
	local width = actualColumns * button + HOTBAR.Gap * (actualColumns - 1)
	local height = button * rows + HOTBAR.Gap * (rows - 1)
	local bottom = HOTBAR.Bottom
	local center = (left + right) / 2
	if portrait then center = size.X / 2 end
	if portrait and #controlRects == 0 then bottom = HOTBAR.PortraitControlHeight end
	for _, object in controlRects do
		local position = object.AbsolutePosition - root.AbsolutePosition
		if position.X < center + width / 2 and position.X + object.AbsoluteSize.X > center - width / 2 then
			bottom = math.max(bottom, size.Y - position.Y + HOTBAR.Gap)
		end
	end
	local tabHeight = if mobile then HOTBAR.TouchTabHeight else HOTBAR.TabHeight
	local tabWidth = math.max(width, math.min(right - left, HOTBAR.SlotCount * HOTBAR.TouchSlot))
	bar.Position = UDim2.new(0, center, 1, -bottom)
	bar.Size = UDim2.fromOffset(width, height)
	local extra = if visibleTotal > HOTBAR.SlotCount then HOTBAR.MoreWidth + HOTBAR.Gap else 0
	pageBar.Position = UDim2.new(0, center - extra / 2, 1, -(bottom + height + HOTBAR.Gap))
	pageBar.Size = UDim2.fromOffset(tabWidth - extra, tabHeight)
	layout.FillDirectionMaxCells = columns
	layout.CellSize = UDim2.fromOffset(button, button)
	layout.CellPadding = UDim2.fromOffset(HOTBAR.Gap, HOTBAR.Gap)
	moreButton.Position = UDim2.new(0, center + tabWidth / 2 - HOTBAR.MoreWidth, 1, -(bottom + height + HOTBAR.Gap + tabHeight / 2))
	moreButton.Size = UDim2.fromOffset(HOTBAR.MoreWidth, if mobile then math.max(HOTBAR.MinTouchSlot,tabHeight) else tabHeight)
	emptyLabel.Position = bar.Position
	emptyLabel.Size = UDim2.fromOffset(math.min(size.X - HOTBAR.Bottom * 2, tabWidth), button)
	emptyShopButton.Position = UDim2.new(0, center, 1, -(bottom + button + HOTBAR.Gap))
	emptyShopButton.Size = UDim2.fromOffset(math.max(HOTBAR.MinTouchSlot * 2, tabWidth / 2), HOTBAR.MinTouchSlot)
	if #visibleIds == 0 then
		pageBar.Position = UDim2.new(0, center, 1, -(bottom + button + HOTBAR.MinTouchSlot + HOTBAR.Gap * 2))
	end
	metrics = { bottom = bottom, height = height, width = width, tabsHeight = tabHeight, columns = columns }
	root:SetAttribute("HotbarBottom", bottom)
	root:SetAttribute("HotbarHeight", height + HOTBAR.Gap + tabHeight + (if #visibleIds == 0 then HOTBAR.MinTouchSlot + HOTBAR.Gap else 0))
end

local function inputIsReserved(): boolean
	if player:GetAttribute(Shop.UiStateAttribute) == true or UserInputService:GetFocusedTextBox() ~= nil then
		return true
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local catchGui = if playerGui then playerGui:FindFirstChild(Shop.CatchGuiName) else nil
	return catchGui ~= nil and catchGui:IsA("ScreenGui") and catchGui.Enabled
end

local function rounded(parent: Instance)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UI.Corner)
	corner.Parent = parent
end

local function label(parent: Instance, name: string, text: string, size: UDim2, position: UDim2, color: Color3, textSize: number): TextLabel
	local result = Instance.new("TextLabel")
	result.Name = name
	result.BackgroundTransparency = 1
	result.Text = text
	result.Font = Enum.Font.GothamBold
	result.TextSize = textSize
	result.TextColor3 = color
	result.Size = size
	result.Position = position
	result.Parent = parent
	return result
end

function ItemController.GetCount(id: string): number
	return counts[id] or 0
end

function ItemController.GetFishReady(): boolean
	return fishReady
end

function ItemController.GetSoftPawsReady(): boolean
	return softPawsReady
end

function ItemController.GetCategory(): string
	return currentCategory
end

local function snapshot(): ItemInventory.Snapshot
	return { inventory = counts, fishReady = fishReady, softPawsReady = softPawsReady }
end

function ItemController.GetOwnedItems(category: string?): { string }
	return ItemInventory.OwnedIds(snapshot(), category)
end

function ItemController.GetHotbarIds(): { string }
	return table.clone(visibleIds)
end

function ItemController.GetLayoutMetrics(): { [string]: number }
	return table.clone(metrics)
end

function ItemController.IsUsable(id: string): boolean
	return ItemInventory.Usable(id)
end

function ItemController.GetItemState(id: string): string
	local definition = Items.Get(id)
	if ItemInventory.Ready(snapshot(), id) then return Localization.T("Inventory.Ready") end
	if definition and definition.type == "permanent" and definition.permanentScope ~= "cat" then
		return Localization.T("Inventory.Owned")
	end
	return Localization.T("Inventory.Count", { count = NumberFormat.Format(ItemController.GetCount(id)) })
end

function ItemController.AssignSlot(id: string, index: number): ()
	if index % 1 ~= 0 or index < 1 or index > HOTBAR.SlotCount or not ItemInventory.Usable(id)
		or not ItemInventory.Owned(snapshot(), id) then return end
	local ordered = ItemInventory.HotbarIds(snapshot(), preferredSlots, "All")
	for slot = 1, HOTBAR.SlotCount do if ordered[slot] == nil then ordered[slot] = "" end end
	local old = table.find(ordered, id)
	if old then ordered[old] = ordered[index] end
	ordered[index] = id
	-- The server validates ownership, duplicate IDs and slot count, then mirrors the saved settings.
	Network.GetEvent("SettingsUpdate"):FireServer({ hotbarSlots = ordered })
end

local function refresh()
	gui.Enabled = not inputIsReserved()
	visibleIds, visibleTotal = ItemInventory.HotbarIds(snapshot(), preferredSlots, currentCategory)
	for category, button in pageButtons do
		button.BackgroundColor3 = if category == currentCategory then UI.Accent else UI.Surface
		button.TextColor3 = if category == currentCategory then UI.Background else UI.Text
	end
	for index, slot in slots do
		slot.id = visibleIds[index] or ""
		local definition = Items.Get(slot.id)
		local ready = ItemInventory.Ready(snapshot(), slot.id)
		slot.button.Visible = definition ~= nil
		if definition == nil then continue end
		slot.name.Text = Localization.T("Item." .. slot.id .. ".Name")
		slot.icon.Image = definition.icon
		slot.name.Visible = definition.icon == ""
		slot.count.Text = ItemController.GetItemState(slot.id)
		slot.count.TextColor3 = SLOT_TEXT_ON
		slot.button.BackgroundTransparency = 0
		slot.button:SetAttribute("UiSkinSelected", if ready then true else nil) -- gold frame while armed
		slot.button.Active = not ready
		slot.button.AutoButtonColor = slot.button.Active
	end
	moreButton.Visible = visibleTotal > HOTBAR.SlotCount
	emptyLabel.Visible = #visibleIds == 0
	emptyShopButton.Visible = #visibleIds == 0
	updateLayout()
end

function ItemController.SetCategory(category: string): ()
	if pageButtons[category] == nil then return end
	currentCategory = category
	refresh()
end

local function pickupAnimation(id: string, amount: number)
	local definition = Items.Get(id)
	if definition == nil then return end
	local fly = Instance.new("TextLabel")
	fly.Name = "InventoryPickup"
	fly.BackgroundTransparency = 1
	fly.AnchorPoint = Vector2.new(0.5, 0.5)
	fly.Position = UDim2.fromScale(0.5, 0.55)
	fly.Size = UDim2.fromOffset(HOTBAR.PickupSize.X, HOTBAR.PickupSize.Y)
	fly.Font = Enum.Font.FredokaOne
	fly.TextSize = UI.TextSize
	fly.TextColor3 = UI.OnColor
	fly.TextStrokeColor3 = UiSkin.Outline
	fly.TextStrokeTransparency = 0
	fly.Text = Localization.T("Hotbar.Pickup", { count = amount })
	fly.ZIndex = 10
	fly:SetAttribute("UiNoScale", true)
	fly.Parent = pickupRoot
	local icon = UiSkin.Icon(fly, definition.icon, UDim2.fromOffset(HOTBAR.MinTouchSlot, HOTBAR.MinTouchSlot), UDim2.fromOffset(-HOTBAR.MinTouchSlot,0))
	icon.ZIndex = 10
	local destination = UDim2.fromScale(0.9, 0.5)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		for _, object in playerGui:GetDescendants() do
			if object:IsA("GuiButton") and object.Name == "Inventory" and object.Visible then
				local position = object.AbsolutePosition + object.AbsoluteSize / 2 - pickupRoot.AbsolutePosition
				destination = UDim2.fromOffset(position.X, position.Y)
				break
			end
		end
	end
	local tween = TweenService:Create(fly, TweenInfo.new(HOTBAR.PickupSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = destination, TextTransparency = 1, TextStrokeTransparency = 1 })
	TweenService:Create(icon, TweenInfo.new(HOTBAR.PickupSeconds), { ImageTransparency = 1 }):Play()
	tween.Completed:Once(function() fly:Destroy() end)
	tween:Play()
end

function ItemController.ApplySnapshot(snapshot: unknown): ()
	if type(snapshot) ~= "table" or type(snapshot.inventory) ~= "table" then
		return
	end
	local inventory = snapshot.inventory
	local old: { [string]: number } = {}
	for _, definition in Items.List do
		old[definition.id] = (counts[definition.id] or 0) + (if (definition.id == "Fish" and fishReady) or (definition.id == "SoftPaws" and softPawsReady) then 1 else 0)
	end
	for _, definition in Items.List do
		local amount = inventory[definition.id]
		counts[definition.id] = if type(amount) == "number" and amount == amount and math.abs(amount) < math.huge
			then math.clamp(math.floor(amount), 0, definition.maxStack) else 0
	end
	fishReady = snapshot.fishReady == true
	softPawsReady = snapshot.softPawsReady == true
	refresh()
	if receivedSnapshot then
		for _, definition in Items.List do
			local ready = ItemInventory.Ready({inventory=counts,fishReady=fishReady,softPawsReady=softPawsReady}, definition.id)
			local gained = (counts[definition.id] or 0) + (if ready then 1 else 0) - old[definition.id]
			if gained > 0 then pickupAnimation(definition.id, gained) end
		end
	end
	receivedSnapshot = true
	ItemController.InventoryChanged:Fire()
end

local function targetPosition(fromButton: boolean): Vector3?
	local camera = workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	if not fromButton and InputModeController.GetMode() == "KeyboardMouse" then
		return player:GetMouse().Hit.Position
	end
	local ray = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances = if player.Character then { player.Character } else {}
	local length = Shop.ThrowDistance
	local hit = workspace:Raycast(ray.Origin, ray.Direction * length, parameters)
	return if hit then hit.Position else ray.Origin + ray.Direction * length
end

local function use(id: string, fromButton: boolean)
	if inputIsReserved() or ItemController.GetCount(id) <= 0 then
		return
	end
	local definition = Items.Get(id)
	if definition == nil or (definition.type ~= "consumable" and definition.permanentScope ~= "cat")
		or (id == "Fish" and fishReady) or (id == "SoftPaws" and softPawsReady) then
		return
	end
	local now = os.clock()
	if now - lastUseAt < Shop.ClientUseCooldown then
		return
	end
	lastUseAt = now
	if id == "YarnBall" or id == "BaitCan" or id == "BoxTrap" then
		useEvent:FireServer(id, targetPosition(fromButton))
	else
		useEvent:FireServer(id)
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = Shop.HotbarGuiName
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ClipToDeviceSafeArea = true
	gui.DisplayOrder = UI.HotbarDisplayOrder
	local pickupGui = Instance.new("ScreenGui")
	pickupGui.Name = "ItemPickup"
	pickupGui.ResetOnSpawn = false
	pickupGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	pickupGui.DisplayOrder = UI.DisplayOrder + 1
	pickupRoot = Instance.new("Frame")
	pickupRoot.Name = "PickupCanvas"
	pickupRoot.BackgroundTransparency = 1
	pickupRoot.Size = UDim2.fromScale(1,1)
	pickupRoot:SetAttribute("UiNoScale",true)
	pickupRoot.Parent = pickupGui
	pickupGui.Parent = player:WaitForChild("PlayerGui")
	root = Instance.new("Frame")
	root.Name = "HotbarLayout"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1,1)
	root:SetAttribute("UiNoScale", true)
	root.Parent = gui
	pageBar = Instance.new("Frame")
	pageBar.Name = "Pages"
	pageBar.AnchorPoint = Vector2.new(0.5, 1)
	pageBar.BackgroundTransparency = 1
	pageBar:SetAttribute("UiNoScale", true) -- sized by updateLayout (touch scale)
	pageBar.Parent = root
	for index, category in categories do
		local button = Instance.new("TextButton")
		button.Name = category
		Localization.Bind(button, "Hotbar.Category." .. category)
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
		button.BorderSizePixel = 0
		local fraction = (index - 1) / #categories
		button.Position = UDim2.new(fraction, HOTBAR.Gap * fraction, 0, 0)
		button.Size = UDim2.new(1 / #categories, -HOTBAR.Gap * (#categories - 1) / #categories, 1, 0)
		button:SetAttribute("UiSkin", "Tab")
		button.Parent = pageBar
		rounded(button)
		local textSize = Instance.new("UITextSizeConstraint")
		textSize.MaxTextSize = UI.SmallTextSize
		textSize.Parent = button
		pageButtons[category] = button
		button.Activated:Connect(function() ItemController.SetCategory(category) end)
	end
	bar = Instance.new("Frame")
	bar.Name = "Slots"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -UI.HotbarBottom)
	bar.Size = UDim2.new(UI.HotbarWidthScale, 0, 0, UI.HotbarButtonSize)
	bar.BackgroundTransparency = 1
	bar:SetAttribute("UiNoScale", true) -- sized by updateLayout (touch scale)
	bar.Parent = root
	layout = Instance.new("UIGridLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.CellPadding = UDim2.fromOffset(UI.HotbarGap, UI.HotbarGap)
	layout.Parent = bar
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLayout)
	for index = 1, HOTBAR.SlotCount do
		local button = Instance.new("TextButton")
		button.Name = `Slot{index}`
		button.Text = ""
		button.LayoutOrder = index
		button.BackgroundColor3 = UI.Surface
		button.BorderSizePixel = 0
		button.Size = UDim2.new(1 / #Shop.HotbarKeys, -UI.HotbarGap * (#Shop.HotbarKeys - 1) / #Shop.HotbarKeys, 1, 0)
		button.Selectable = true
		button:SetAttribute("UiSkin", "Slot")
		button.Parent = bar
		rounded(button)
		local stroke = Instance.new("UIStroke")
		stroke.Color = UI.Accent
		stroke.Transparency = UI.StrokeTransparency
		stroke.Parent = button
		local keyLabel = label(button, "Key", tostring(index),
			UDim2.fromScale(0.3, 0.25), UDim2.fromScale(0, 0), UI.Muted, UI.SmallTextSize)
		local nameLabel = label(button, "Name", "", UDim2.fromScale(0.9, 0.5),
			UDim2.fromScale(0.05, 0.2), UI.Text, UI.SmallTextSize)
		nameLabel.TextWrapped = true
		nameLabel.TextScaled = true
		local textSize = Instance.new("UITextSizeConstraint")
		textSize.MaxTextSize = UI.SmallTextSize
		textSize.Parent = nameLabel
		local countLabel = label(button, "Count", "", UDim2.fromScale(1, 0.25),
			UDim2.fromScale(0, 0.72), SLOT_TEXT_OFF, UI.SmallTextSize)
		keyLabel.TextColor3 = SLOT_TEXT_OFF
		nameLabel.TextColor3 = SLOT_TEXT_ON
		for _, text in { keyLabel, nameLabel, countLabel } do
			local outline = Instance.new("UIStroke")
			outline.Color = UiSkin.Outline
			outline.Thickness = 1.5
			outline.Parent = text
			text.ZIndex = 3
		end
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.46)
		icon.Size = UDim2.fromScale(0.62, 0.56)
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = button
		local slot: Slot = { button = button, count = countLabel, key = keyLabel, name = nameLabel, icon = icon, id = "" }
		table.insert(slots, slot)
		UiTooltip.Attach(button, function()
			if slot.id == "" then return "" end
			return Localization.T("Item." .. slot.id .. ".Name") .. "\n" .. Localization.T("Item." .. slot.id .. ".Description")
		end)
		button.Activated:Connect(function()
			use(slot.id, true)
		end)
	end
	moreButton = Instance.new("TextButton")
	moreButton.Name = "More"
	Localization.Bind(moreButton,"Inventory.More")
	moreButton.Font = Enum.Font.FredokaOne
	moreButton.TextSize = UI.TextSize
	moreButton.BackgroundColor3 = UI.Surface
	moreButton.TextColor3 = UI.Text
	moreButton.AnchorPoint = Vector2.new(0,0.5)
	moreButton.Parent = root
	moreButton.Activated:Connect(function() ItemController.InventoryRequested:Fire() end)
	UiTooltip.Attach(moreButton, function() return Localization.T("Inventory.More") end)
	emptyLabel = label(root, "Empty", "", UDim2.new(), UDim2.new(), UI.Text, UI.SmallTextSize)
	emptyLabel.AnchorPoint = Vector2.new(0.5,1)
	emptyLabel.TextWrapped = true
	emptyLabel:SetAttribute("UiNoScale",true)
	Localization.Bind(emptyLabel,"Inventory.Empty")
	emptyShopButton = Instance.new("TextButton")
	emptyShopButton.Name = "EmptyShop"
	emptyShopButton.AnchorPoint = Vector2.new(0.5,1)
	emptyShopButton.BackgroundColor3 = UI.Accent
	emptyShopButton.TextColor3 = UI.OnColor
	emptyShopButton.Font = Enum.Font.FredokaOne
	emptyShopButton.TextSize = UI.SmallTextSize
	emptyShopButton.Parent = root
	Localization.Bind(emptyShopButton,"Inventory.OpenShop")
	emptyShopButton.Activated:Connect(function() ItemController.ShopRequested:Fire() end)
	gui.Parent = player:WaitForChild("PlayerGui")
	updateLayout()
	refresh()
end

function ItemController:Init(): ()
	useEvent = Network.GetEvent("ItemUse")
	build()
	-- This game uses the custom inventory; Roblox's default Tool hotbar also binds 1–6.
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end

function ItemController:Start(): ()
	Network.GetEvent("InventoryUpdate").OnClientEvent:Connect(ItemController.ApplySnapshot)
	local function applyHotbarSettings()
		local encoded = player:GetAttribute(HOTBAR.SettingsAttribute)
		local ok, values = pcall(function() return HttpService:JSONDecode(if type(encoded) == "string" then encoded else "[]") end)
		preferredSlots = {}
		if ok and type(values) == "table" then
			for index = 1, HOTBAR.SlotCount do
				preferredSlots[index] = if type(values[index]) == "string" then values[index] else ""
			end
		end
		refresh()
		ItemController.InventoryChanged:Fire()
	end
	player:GetAttributeChangedSignal(HOTBAR.SettingsAttribute):Connect(applyHotbarSettings)
	applyHotbarSettings()
	player:GetAttributeChangedSignal(Shop.UiStateAttribute):Connect(refresh)
	player:GetAttributeChangedSignal("DebugLocale"):Connect(refresh)
	local playerGui = player:WaitForChild("PlayerGui")
	local catchGui = playerGui:WaitForChild(Shop.CatchGuiName) :: ScreenGui
	catchGui:GetPropertyChangedSignal("Enabled"):Connect(refresh)
	local function observeCamera()
		if viewportConnection then viewportConnection:Disconnect() end
		local camera = workspace.CurrentCamera
		if camera then
			viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateLayout)
		end
		updateLayout()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(observeCamera)
	Viewport.Changed:Connect(updateLayout)
	InputModeController.Changed:Connect(updateLayout)
	local function observeTouchControl(object: Instance)
		if object:IsA("GuiObject") and (object.Name == "JumpButton" or object.Name == "ThumbstickFrame" or object.Name == "ThumbstickStart") then
			object:GetPropertyChangedSignal("AbsolutePosition"):Connect(updateLayout)
			object:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLayout)
			object:GetPropertyChangedSignal("Visible"):Connect(updateLayout)
			task.defer(updateLayout)
		end
	end
	for _, object in playerGui:GetDescendants() do observeTouchControl(object) end
	playerGui.DescendantAdded:Connect(observeTouchControl)
	observeCamera()
	-- One action owns each digit and resolves exactly the visible slot at key-down.
	for index, key in Shop.HotbarKeys do
		ContextActionService:BindAction(`UseCatItem{index}`, function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
				if UserInputService:GetFocusedTextBox() ~= nil then
					return Enum.ContextActionResult.Pass
				end
				if state == Enum.UserInputState.Begin then
					local id = visibleIds[index]
					if id then use(id, false) end
				end
				return Enum.ContextActionResult.Sink
			end, false, key)
	end
	Network.GetEvent("InventoryRequest"):FireServer()
end

return ItemController


