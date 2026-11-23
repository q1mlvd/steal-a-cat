--!strict
-- One cartoon style for every game ScreenGui (built now or later):
--   * buttons: rounded (UICorner), soft outline (UIStroke), FredokaOne font, click sound
--   * fixed-size top-level panels (offset sizes) get a UIScale that follows the viewport, so HUD panels and
--     popups fit phones/tablets and grow a little on big screens (scale-sized modals already adapt).
--   * UI pack skins (Stage 18, Shared/Util/UiSkin): every element is skinned by its colour role, re-skinned
--     live when a controller changes that colour (selected tab, affordable buy button...):
--       top-level UI.Background frame -> Frame_MainPanel (Frame_Popup when short), nested UI.Surface /
--       UI.Background frame -> Frame_Card (small icon holders turn transparent), UI.Accent frame -> green card,
--       buttons: UI.Accent green, UI.Coin gold, UI.Danger red, UI.Surface / UI.Background gray, "×" -> UI_Close.
--     Attribute UiSkin overrides the role: None, Panel, Popup, Card, Card:<Rarity>, Button:<Color>, Tab, Slot,
--     Toast, Header, Banner, Tooltip, Clear. UiSkinSelected=true picks Tab_Selected / HotbarSlot_Selected.
--   * Studio phone preview: LocalPlayer attribute DebugViewport (Vector2) shows each ScreenGui inside a canvas
--     of that size (Shared/Util/Viewport), so phone layouts can be checked without a device.
-- Roblox core UI (chat, touch controls, prompts) is never touched.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local Config = ReplicatedStorage.Shared.Config
local Shop = require(Config.Shop)
local UIAssets = require(Config.UIAssets)
local UiSkin = require(ReplicatedStorage.Shared.Util.UiSkin)
local Viewport = require(ReplicatedStorage.Shared.Util.Viewport)
local SoundController = require(script.Parent.SoundController)
local UI = Shop.Ui

local UiStyleController = {
	Priority = 90,
}

local SKIP = { Freecam = true, ProximityPrompts = true, TouchGui = true, ContextActionGui = true, BubbleChat = true, Chat = true, Juice = true }
local NO_SKIN = { Tooltip = true, Loading = true, PhonePreviewMask = true } -- styled by hand
local ROLE_ATTRIBUTE = "UiSkin"
local SELECTED_ATTRIBUTE = "UiSkinSelected"
local TINT_ATTRIBUTE = "UiSkinTintColor" -- optional Color3 tint on the existing 9-slice art
local BASE_ATTRIBUTE = "UiSkinBaseTransparency" -- the controller's own background transparency
local CANVAS_NAME = "PhoneCanvas"
local player = Players.LocalPlayer
local scales: { UIScale } = {}
local styled: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local watched: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local applying: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local warned: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local guis: { ScreenGui } = {}

local function viewportScale(): number
	return Viewport.UiScale()
end

-- Skins -------------------------------------------------------------------------------------------

local function isTopLevel(object: GuiObject): boolean
	local parent = object.Parent
	return parent ~= nil and (parent:IsA("ScreenGui") or parent.Name == CANVAS_NAME)
end

local function baseTransparency(object: GuiObject): number
	local base = object:GetAttribute(BASE_ATTRIBUTE)
	return if type(base) == "number" then base else object.BackgroundTransparency
end

local function roleFor(object: GuiObject): string?
	local explicit = object:GetAttribute(ROLE_ATTRIBUTE)
	if type(explicit) == "string" then
		return if explicit == "None" then nil else explicit
	end
	local color = object.BackgroundColor3
	if object:IsA("GuiButton") then
		if object:IsA("TextButton") and object.Text == "×" then return "Close" end
		if baseTransparency(object) >= 0.5 or (object.Size.X.Scale >= 1 and object.Size.Y.Scale >= 1) then return nil end
		if color == UI.Accent then return "Button:Green" end
		if color == UI.Coin then return "Button:Gold" end
		if color == UI.Danger then return "Button:Red" end
		if color == UI.Surface or color == UI.Background then return "Button:Gray" end
		return nil
	end
	if object:IsA("ScrollingFrame") or baseTransparency(object) >= 0.9 then return nil end
	if isTopLevel(object) then
		if color ~= UI.Background then return nil end
		local short = object.Size.Y.Scale == 0 and object.Size.Y.Offset <= UI.PopupMaxHeight
		return if short then "Popup" else "Panel"
	end
	if color == UI.Background or color == UI.Surface then
		-- Small icon holders (an icon image or an initial inside) turn transparent; everything else is a card.
		local size = object.Size
		local small = size.X.Scale == 0 and size.Y.Scale == 0 and size.X.Offset <= UI.IconHolderMax
			and size.Y.Offset <= UI.IconHolderMax
		local holder = object:FindFirstChildWhichIsA("ImageLabel") ~= nil or string.find(object.Name, "Icon") ~= nil
		if small and holder then
			return "Clear"
		end
		return "Card"
	end
	if color == UI.Accent then return "Card:Uncommon" end
	return nil
end

local function sliceFor(object: GuiObject, role: string): UIAssets.Slice?
	local kind, variant = string.match(role, "^(%a+):?(%a*)$")
	local selected = object:GetAttribute(SELECTED_ATTRIBUTE) == true
	if kind == "Panel" then return UIAssets.Frames.MainPanel end
	if kind == "Popup" then return UIAssets.Frames.Popup end
	if kind == "Toast" then return UIAssets.Frames.Toast end
	if kind == "Header" then return UIAssets.Frames.Header end
	if kind == "Banner" then return UIAssets.Frames.Banner end
	if kind == "Tooltip" then return UIAssets.Frames.Tooltip end
	if kind == "Card" then return (UIAssets.Cards :: any)[variant or ""] or UIAssets.Frames.Card end
	if kind == "Button" then return (UIAssets.Buttons :: any)[variant or ""] or UIAssets.Buttons.Gray end
	if kind == "Tab" then
		return if selected or object.BackgroundColor3 == UI.Accent then UIAssets.Tabs.Selected else UIAssets.Tabs.Normal
	end
	if kind == "Slot" then
		return if selected then UIAssets.Frames.HotbarSlotSelected else UIAssets.Frames.HotbarSlot
	end
	return nil
end

-- Panels/popups: push content clear of the frame art's border, once (adds to a controller's own padding).
local function insetFor(object: GuiObject, role: string)
	local inset = (UIAssets.PanelInsets :: any)[role]
	if inset == nil or object:GetAttribute("UiSkinInset") then return end
	object:SetAttribute("UiSkinInset", true)
	local padding = object:FindFirstChildOfClass("UIPadding")
	if padding == nil then
		padding = Instance.new("UIPadding")
		padding.Name = "SkinPadding"
		padding.Parent = object
	end
	local p = padding :: UIPadding
	p.PaddingLeft = UDim.new(p.PaddingLeft.Scale, p.PaddingLeft.Offset + inset.side)
	p.PaddingRight = UDim.new(p.PaddingRight.Scale, p.PaddingRight.Offset + inset.side)
	p.PaddingTop = UDim.new(p.PaddingTop.Scale, p.PaddingTop.Offset + inset.top)
	p.PaddingBottom = UDim.new(p.PaddingBottom.Scale, p.PaddingBottom.Offset + inset.bottom)
end

local function applySkin(object: GuiObject)
	if applying[object] or object.Parent == nil then return end
	applying[object] = true
	local role = roleFor(object)
	local current = object:GetAttribute("UiSkinApplied")
	if role == nil then
		if current ~= nil then
			UiSkin.Remove(object)
			object.BackgroundTransparency = baseTransparency(object)
			object:SetAttribute("UiSkinApplied", nil)
		end
		applying[object] = nil
		return
	end
	if object:GetAttribute(BASE_ATTRIBUTE) == nil then
		object:SetAttribute(BASE_ATTRIBUTE, object.BackgroundTransparency)
	end
	local isText = object:IsA("TextLabel") or object:IsA("TextButton")
	if role == "Clear" then
		object.BackgroundTransparency = 1
	elseif role == "Close" then
		UiSkin.ApplyImage(object, UIAssets.Controls.Close)
		;(object :: TextButton).TextTransparency = 1
	else
		local slice = sliceFor(object, role)
		if slice then insetFor(object, role) end
		local image = if slice then UiSkin.Apply(object, slice) else nil
		if image == nil then
			if slice and RunService:IsStudio() and not warned[object] then
				warned[object] = true
				warn(`[UiStyle] {object:GetFullName()} has a layout child; skin it with an inner frame`)
			end
		else
			image.ImageTransparency = math.clamp(baseTransparency(object), 0, 1)
			local tint = object:GetAttribute(TINT_ATTRIBUTE)
			image.ImageColor3 = if typeof(tint) == "Color3" then tint else Color3.new(1, 1, 1)
			if isText then
				local coloured = (string.find(role, "^Button:") ~= nil and (role ~= "Button:Gray" or typeof(tint) == "Color3")) or role == "Tab"
				UiSkin.LiftText(object :: any, coloured, if coloured then UI.OnColor else nil)
			end
			if object:IsA("GuiButton") then
				UiSkin.WatchPress(object)
			end
		end
	end
	object:SetAttribute("UiSkinApplied", role)
	applying[object] = nil
end

local function watch(object: GuiObject)
	if watched[object] or object.Name == "Skin" or object.Name == "SkinText" then return end
	local candidate = object:IsA("GuiButton") or object:GetAttribute(ROLE_ATTRIBUTE) ~= nil
		or ((object:IsA("Frame") or object:IsA("TextLabel")) and object.BackgroundTransparency < 0.9)
	if not candidate then return end
	watched[object] = true
	local function reapply() task.defer(applySkin, object) end
	object:GetPropertyChangedSignal("BackgroundColor3"):Connect(reapply)
	object:GetAttributeChangedSignal(ROLE_ATTRIBUTE):Connect(reapply)
	object:GetAttributeChangedSignal(SELECTED_ATTRIBUTE):Connect(reapply)
	object:GetAttributeChangedSignal(TINT_ATTRIBUTE):Connect(reapply)
	object:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
		-- A controller dims/shows the element: keep that as the skin's transparency.
		if applying[object] or object:GetAttribute("UiSkinApplied") == nil or object.BackgroundTransparency == 1 then return end
		object:SetAttribute(BASE_ATTRIBUTE, object.BackgroundTransparency)
		reapply()
	end)
	if object:IsA("TextButton") then
		object:GetPropertyChangedSignal("Text"):Connect(function()
			if (object.Text == "×") ~= (object:GetAttribute("UiSkinApplied") == "Close") then reapply() end
		end)
	end
	reapply()
end

local function styleButton(button: GuiButton)
	if styled[button] then return end
	styled[button] = true
	if button.Name == "Skin" or button.Name == "SkinText" then return end
	if button:FindFirstChildOfClass("UICorner") == nil then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, UI.Corner / 2)
		corner.Parent = button
	end
	-- Full-screen shades and invisible tap catchers stay invisible.
	if button.BackgroundTransparency < 0.5 and button.Size.X.Scale < 1 and button:FindFirstChildOfClass("UIStroke") == nil then
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = UI.Accent
		stroke.Transparency = UI.StrokeTransparency
		stroke.Parent = button
	end
	if button:IsA("TextButton") and button.Size.X.Scale < 1 then
		button.Font = Enum.Font.FredokaOne
		button.Activated:Connect(function()
			SoundController.Play("Click")
		end)
	end
end

-- Scale-sized panels keep their on-screen share: Size scale is divided by the UIScale (base kept here).
local baseSizes: { [UIScale]: UDim2 } = setmetatable({}, { __mode = "k" }) :: any

local function applyScale(scale: UIScale, value: number)
	scale.Scale = value
	local base = baseSizes[scale]
	local object = scale.Parent
	if base and object and object:IsA("GuiObject") then
		object.Size = UDim2.new(base.X.Scale / value, base.X.Offset, base.Y.Scale / value, base.Y.Offset)
	end
end

local function scaleTopLevel(object: GuiObject)
	if styled[object] then return end
	styled[object] = true
	if object:FindFirstChildOfClass("UIScale") ~= nil or object:GetAttribute("UiNoScale") == true then return end
	local size = object.Size
	if size.X.Scale >= 1 and size.Y.Scale >= 1 then return end -- full-screen shades / tap catchers
	-- Offset-sized panels just scale. Scale-sized panels (modals) also lay out at design resolution and
	-- shrink to fit, so phones show the same content as PC instead of a squeezed full-size layout.
	local scale = Instance.new("UIScale")
	if size.X.Scale > 0 or size.Y.Scale > 0 then
		baseSizes[scale] = size
	end
	scale.Parent = object
	applyScale(scale, viewportScale())
	table.insert(scales, scale)
end

-- Phone preview (Studio) ---------------------------------------------------------------------------

local function canvasOf(gui: ScreenGui): Frame?
	local canvas = gui:FindFirstChild(CANVAS_NAME)
	return if canvas and canvas:IsA("Frame") then canvas else nil
end

local function placeInCanvas(gui: ScreenGui, child: Instance)
	local canvas = canvasOf(gui)
	if canvas and child ~= canvas and child:IsA("GuiObject") and child.Parent == gui then
		child.Parent = canvas
	end
end

local function updatePreview(gui: ScreenGui)
	local size = Viewport.GetOverride()
	local canvas = canvasOf(gui)
	if size == nil then
		if canvas then
			for _, child in canvas:GetChildren() do child.Parent = gui end
			canvas:Destroy()
		end
		return
	end
	if canvas == nil then
		local created = Instance.new("Frame")
		created.Name = CANVAS_NAME
		created.BackgroundTransparency = 1
		created.ClipsDescendants = true
		created.AnchorPoint = Vector2.new(0.5, 0.5)
		created.Parent = gui
		canvas = created
	end
	local frame = canvas :: Frame
	-- Centre on the screen; guis that respect the top bar inset start lower.
	local inset = if gui.IgnoreGuiInset then 0 else GuiService:GetGuiInset().Y
	frame.Position = UDim2.new(0.5, 0, 0.5, -inset / 2)
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	for _, child in gui:GetChildren() do placeInCanvas(gui, child) end
end

local function updateMask()
	local size = Viewport.GetOverride()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local existing = if playerGui then playerGui:FindFirstChild("PhonePreviewMask") else nil
	if size == nil or playerGui == nil then
		if existing then existing:Destroy() end
		return
	end
	if existing then existing:Destroy() end
	local mask = Instance.new("ScreenGui")
	mask.Name = "PhonePreviewMask"
	mask.IgnoreGuiInset = true
	mask.DisplayOrder = 1000
	mask.ResetOnSpawn = false
	local half = size / 2
	for _, spec in {
		{ UDim2.new(0, 0, 0, 0), UDim2.new(0.5, -half.X, 1, 0) },
		{ UDim2.new(0.5, half.X, 0, 0), UDim2.new(0.5, -half.X, 1, 0) },
		{ UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0.5, -half.Y) },
		{ UDim2.new(0, 0, 0.5, half.Y), UDim2.new(1, 0, 0.5, -half.Y) },
	} do
		local bar = Instance.new("Frame")
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = Color3.fromRGB(20, 16, 26)
		bar.Position = spec[1]
		bar.Size = spec[2]
		bar.Parent = mask
	end
	mask.Parent = playerGui
end

local function styleGui(gui: Instance)
	if not gui:IsA("ScreenGui") or SKIP[gui.Name] or gui.Name == "PhonePreviewMask" then return end
	table.insert(guis, gui)
	-- Skins sit at ZIndex 0 inside their element; that needs per-parent (Sibling) ordering. Our guis never
	-- relied on Global ordering (full-screen catchers / badges are siblings with higher ZIndex).
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local skinned = not NO_SKIN[gui.Name]
	updatePreview(gui)
	local function topLevel(): { Instance }
		local canvas = canvasOf(gui)
		return if canvas then canvas:GetChildren() else gui:GetChildren()
	end
	for _, child in topLevel() do
		if child:IsA("GuiObject") and child.Name ~= CANVAS_NAME then scaleTopLevel(child) end
	end
	for _, descendant in gui:GetDescendants() do
		if descendant:IsA("GuiButton") then styleButton(descendant) end
		if skinned and descendant:IsA("GuiObject") then watch(descendant) end
	end
	gui.ChildAdded:Connect(function(child: Instance)
		if child.Name ~= CANVAS_NAME then task.defer(placeInCanvas, gui, child) end
	end)
	gui.DescendantAdded:Connect(function(descendant: Instance)
		if not descendant:IsA("GuiObject") or descendant.Name == CANVAS_NAME then return end
		if descendant:IsA("GuiButton") then
			task.defer(styleButton, descendant)
		elseif isTopLevel(descendant) then
			task.defer(scaleTopLevel, descendant)
		end
		if skinned then task.defer(watch, descendant) end
	end)
end

local function rescale()
	for index = #guis, 1, -1 do
		if guis[index].Parent then updatePreview(guis[index]) else table.remove(guis, index) end
	end
	updateMask()
	local value = viewportScale()
	for index = #scales, 1, -1 do
		local scale = scales[index]
		if scale.Parent then
			applyScale(scale, value)
		else
			table.remove(scales, index)
		end
	end
end

function UiStyleController:Start(): ()
	local playerGui = player:WaitForChild("PlayerGui")
	for _, gui in playerGui:GetChildren() do styleGui(gui) end
	playerGui.ChildAdded:Connect(styleGui)
	Viewport.Changed:Connect(rescale)
	rescale()
end

return UiStyleController

