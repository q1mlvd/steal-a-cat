--!strict
-- Shows server notifications: small toasts at the top, and a big banner for announcements.
-- Stage 18 look: toasts on Frame_Toast and banners on Frame_Banner (UI pack), each a CanvasGroup sized to its
-- text so the frame, text and icon fade together. Banners can carry a cat portrait (rare cats) or an event
-- icon (Config/UIAssets.Events) on the left.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Localization = require(ReplicatedStorage.Shared.Util.Localization)
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Network = require(ReplicatedStorage.Shared.Network)
local Notifications = require(ReplicatedStorage.Shared.Config.Notifications)
local Cats = require(ReplicatedStorage.Shared.Config.Cats)
local UIAssets = require(ReplicatedStorage.Shared.Config.UIAssets)
local CatPortrait = require(ReplicatedStorage.Shared.Util.CatPortrait)
local UiSkin = require(ReplicatedStorage.Shared.Util.UiSkin)
local Viewport = require(ReplicatedStorage.Shared.Util.Viewport)

local GUI_NAME = "Notifications"
local TOAST_HEIGHT = 40
local TOAST_TEXT_SIZE = 20
local TOAST_SIDE = 28 -- text inset from the toast frame's rounded ends
local TOAST_GAP = 4
local BANNER_HEIGHT = 96 -- includes the frame art's transparent margin
local BANNER_TEXT_SIZE = 32
local BANNER_SIDE = 44
local BANNER_MAX_WIDTH = 0.94 -- of the viewport
local TOP_MARGIN = 116 -- below the coin panel and event pill (scaled with the HUD on small screens)
local PORTRAIT_SIZE = 84 -- rare-cat portrait / event icon, left of the banner text
local PORTRAIT_GAP = 10
local FONT = Enum.Font.FredokaOne

export type Extra = { catId: string?, mutation: string?, event: string? }

local NotificationController = {
	Priority = 10,
}

local gui: ScreenGui
local toastContainer: Frame
local toasts: { CanvasGroup } = {}
local currentBanner: CanvasGroup? = nil
local bannerToken = 0
local toastCounter = 0

local function textWidth(text: string, size: number): number
	return TextService:GetTextSize(text, size, FONT, Vector2.new(4000, 200)).X
end

local function outlinedLabel(parent: Instance, text: string, color: Color3, thickness: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = Localization.Translate(text)
	label.ZIndex = 2
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = UiSkin.Outline
	stroke.Thickness = thickness
	stroke.Parent = label
	return label
end

local function fadeOutAndDestroy(group: CanvasGroup)
	local tween = TweenService:Create(group, TweenInfo.new(Notifications.FadeTime), { GroupTransparency = 1 })
	tween.Completed:Connect(function()
		group:Destroy()
	end)
	tween:Play()
end

-- Banners and toasts shrink with the HUD on small screens (same scale UiStyleController uses).
local function layoutScale(): number
	return Viewport.UiScale()
end

local function showToast(message: string, style: Notifications.Style)
	message = Localization.Translate(message)
	local styleConfig = Notifications.Styles[style]
	local maxWidth = Viewport.Get().X * BANNER_MAX_WIDTH / layoutScale()
	local width = math.min(textWidth(message, TOAST_TEXT_SIZE) + TOAST_SIDE * 2, maxWidth)

	local group = Instance.new("CanvasGroup")
	group.Name = "Toast"
	group.BackgroundTransparency = 1
	group.Size = UDim2.fromOffset(width, TOAST_HEIGHT)
	toastCounter += 1
	group.LayoutOrder = toastCounter
	UiSkin.Apply(group, UIAssets.Frames.Toast)
	local label = outlinedLabel(group, message, styleConfig.color, 1.5)
	label.Position = UDim2.fromOffset(TOAST_SIDE, 6)
	label.Size = UDim2.new(1, -TOAST_SIDE * 2, 1, -12)
	group.Parent = toastContainer

	table.insert(toasts, group)
	while #toasts > Notifications.MaxToasts do
		table.remove(toasts, 1):Destroy()
	end

	task.delay(styleConfig.duration, function()
		local index = table.find(toasts, group)
		if index then
			table.remove(toasts, index)
			fadeOutAndDestroy(group)
		end
	end)
end

local function showBanner(message: string, style: Notifications.Style, extra: Extra?)
	message = Localization.Translate(message)
	local styleConfig = Notifications.Styles[style]
	bannerToken += 1
	local token = bannerToken
	if currentBanner then
		currentBanner:Destroy()
		currentBanner = nil
	end

	local eventIcon = if extra and extra.event then (UIAssets.Events :: any)[extra.event] else nil
	local hasCat = extra ~= nil and extra.catId ~= nil
	local visual = if hasCat or eventIcon then PORTRAIT_SIZE + PORTRAIT_GAP else 0
	local scale = layoutScale()
	local maxWidth = Viewport.Get().X * BANNER_MAX_WIDTH / scale
	local width = math.min(textWidth(message, BANNER_TEXT_SIZE) + visual + BANNER_SIDE * 2, maxWidth)

	local group = Instance.new("CanvasGroup")
	group.Name = "Banner"
	group.BackgroundTransparency = 1
	group.AnchorPoint = Vector2.new(0.5, 0)
	group.Position = UDim2.new(0.5, 0, 0, TOP_MARGIN * scale)
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = scale
	uiScale.Parent = group
	group.Size = UDim2.fromOffset(width, BANNER_HEIGHT)
	group.GroupTransparency = 1
	UiSkin.Apply(group, UIAssets.Frames.Banner)
	if extra and extra.catId then
		CatPortrait.Create(group, { catId = extra.catId, mutation = extra.mutation,
			size = UDim2.fromOffset(PORTRAIT_SIZE * 0.78, PORTRAIT_SIZE * 0.78), anchor = Vector2.new(0, 0.5),
			position = UDim2.new(0, BANNER_SIDE - 8, 0.5, 0) })
	elseif eventIcon then
		local icon = UiSkin.Icon(group, eventIcon, UDim2.fromOffset(PORTRAIT_SIZE * 0.82, PORTRAIT_SIZE * 0.82),
			UDim2.new(0, BANNER_SIDE - 10, 0.5, 0), Vector2.new(0, 0.5))
		icon.ZIndex = 2
	end
	local label = outlinedLabel(group, message, styleConfig.color, 2.5)
	label.Position = UDim2.new(0, BANNER_SIDE + visual, 0.22, 0)
	label.Size = UDim2.new(1, -(BANNER_SIDE * 2 + visual), 0.56, 0)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = BANNER_TEXT_SIZE
	limit.Parent = label
	group.Parent = gui
	currentBanner = group
	TweenService:Create(group, TweenInfo.new(Notifications.FadeTime), { GroupTransparency = 0 }):Play()

	task.delay(styleConfig.duration, function()
		if bannerToken ~= token then
			return
		end
		local tween = TweenService:Create(group, TweenInfo.new(Notifications.FadeTime), { GroupTransparency = 1 })
		tween.Completed:Connect(function()
			if currentBanner == group then
				currentBanner = nil
			end
			group:Destroy()
		end)
		tween:Play()
	end)
end

-- Client-only hint (e.g. "Need Jump 3" when walking into a gate). Server messages use the Notify remote.
function NotificationController.ShowLocal(message: string, style: Notifications.Style?)
	local resolvedStyle: Notifications.Style = style or "Info"
	if Notifications.Styles[resolvedStyle].banner then
		showBanner(message, resolvedStyle)
	else
		showToast(message, resolvedStyle)
	end
end

function NotificationController:Init(): ()
	gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20

	toastContainer = Instance.new("Frame")
	toastContainer.Name = "Toasts"
	toastContainer.AnchorPoint = Vector2.new(0.5, 0)
	toastContainer.Position = UDim2.new(0.5, 0, 0, TOP_MARGIN + BANNER_HEIGHT)
	toastContainer.Size = UDim2.new(1, 0, 0, (TOAST_HEIGHT + TOAST_GAP) * Notifications.MaxToasts)
	toastContainer.BackgroundTransparency = 1
	toastContainer.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, TOAST_GAP)
	layout.Parent = toastContainer
	local toastScale = Instance.new("UIScale")
	toastScale.Parent = toastContainer
	local function rescale()
		local scale = layoutScale()
		toastScale.Scale = scale
		toastContainer.Size = UDim2.new(1 / scale, 0, 0, (TOAST_HEIGHT + TOAST_GAP) * Notifications.MaxToasts)
		toastContainer.Position = UDim2.new(0.5, 0, 0, (TOP_MARGIN + BANNER_HEIGHT) * scale)
	end
	Viewport.Changed:Connect(rescale)
	rescale()

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function NotificationController:Start(): ()
	Network.GetEvent("Notify").OnClientEvent:Connect(function(message: unknown, style: unknown, payload: unknown)
		if type(message) == "table" then
			local raw = message :: any
			if type(raw.key) ~= "string" or type(raw.params) ~= "table" then return end
			local params = table.clone(raw.params)
			if type(params.itemKey) == "string" then params.item = Localization.T(params.itemKey) end
			message = Localization.T(raw.key, params)
		end
		if type(message) ~= "string" then
			return
		end
		local resolvedStyle: Notifications.Style = if Notifications.IsStyle(style) then style :: Notifications.Style else "Info"
		local extra: Extra? = nil
		if type(payload) == "table" then
			local raw = payload :: any
			if type(raw.catId) == "string" and Cats.Get(raw.catId) then
				extra = { catId = raw.catId, mutation = tostring(raw.mutation or "") }
			elseif type(raw.event) == "string" and (UIAssets.Events :: any)[raw.event] then
				extra = { event = raw.event }
			end
		end
		if Notifications.Styles[resolvedStyle].banner then
			showBanner(message, resolvedStyle, extra)
		else
			showToast(message, resolvedStyle)
		end
	end)
end

return NotificationController


