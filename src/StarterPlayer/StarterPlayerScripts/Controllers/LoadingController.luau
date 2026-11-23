--!strict
-- "Loading your save..." screen, shown until the server gives the player a house (which happens only after
-- their save is loaded - including a slow session-lock takeover).
-- Stage 18 look: UI pack LoadingBackground + bouncing Logo, outlined title and a sweeping gold progress bar;
-- everything sits in one CanvasGroup so it fades out as a whole.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Localization = require(ReplicatedStorage.Shared.Util.Localization)
local TweenService = game:GetService("TweenService")

local Loading = require(ReplicatedStorage.Shared.Config.Loading)
local Plots = require(ReplicatedStorage.Shared.Config.Plots)
local UIAssets = require(ReplicatedStorage.Shared.Config.UIAssets)
local UiSkin = require(ReplicatedStorage.Shared.Util.UiSkin)

local DOT_INTERVAL = 0.4
local MAX_DOTS = 3
local HINT_COLOR = Color3.fromRGB(255, 240, 215)

local LoadingController = {
	Priority = 1,
}

local player = Players.LocalPlayer
local gui: ScreenGui
local root: CanvasGroup
local title: TextLabel
local hint: TextLabel

local function outlined(label: TextLabel, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = UiSkin.Outline
	stroke.Thickness = thickness
	stroke.Parent = label
end

-- Every UI pack image id (frames, icons, badges...) so menus never open with blank frames.
local function uiImageIds(): { string }
	local ids: { string } = {}
	local function collect(value: any)
		if type(value) == "string" and string.find(value, "^rbxassetid://") then
			table.insert(ids, value)
		elseif type(value) == "table" then
			for _, inner in value do collect(inner) end
		end
	end
	collect(UIAssets)
	return ids
end

local function hide()
	if gui.Enabled == false then
		return
	end
	local fade = TweenService:Create(root, TweenInfo.new(Loading.FadeTime), { GroupTransparency = 1 })
	fade.Completed:Connect(function()
		gui.Enabled = false
	end)
	fade:Play()
end

local function buildBar(parent: Instance)
	local track = Instance.new("Frame")
	track.Name = "Bar"
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.fromScale(0.5, 0.78)
	track.Size = UDim2.new(Loading.BarWidthScale, 0, 0, Loading.BarHeight)
	track.BackgroundTransparency = 1
	track.ClipsDescendants = true
	track.Parent = parent
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(Loading.BarMaxWidth, Loading.BarHeight)
	limit.Parent = track
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundTransparency = 1
	fill.Size = UDim2.fromScale(Loading.BarFillScale, 1)
	fill.Position = UDim2.fromScale(-Loading.BarFillScale, 0)
	fill.Parent = track
	UiSkin.Bar(track, fill, "Gold")
	track.ClipsDescendants = true -- the fill sweeps across and leaves at the right end
	TweenService:Create(fill, TweenInfo.new(Loading.BarSweepTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1),
		{ Position = UDim2.fromScale(1, 0) }):Play()
end

function LoadingController:Init(): ()
	gui = Instance.new("ScreenGui")
	gui.Name = "Loading"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100

	root = Instance.new("CanvasGroup")
	root.Name = "Background"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(255, 170, 110)
	root.BorderSizePixel = 0
	root.Parent = gui
	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.Size = UDim2.fromScale(1, 1)
	art.BackgroundTransparency = 1
	art.ScaleType = Enum.ScaleType.Crop
	art.Image = UIAssets.LoadingBackground
	art.Parent = root
	-- Darker band at the bottom so the text reads on the bright art.
	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.fromScale(1, 0.45)
	shade.BackgroundColor3 = Color3.fromRGB(40, 15, 45)
	shade.BorderSizePixel = 0
	shade.Parent = root
	local shadeGradient = Instance.new("UIGradient")
	shadeGradient.Rotation = 90
	shadeGradient.Transparency = NumberSequence.new(1, Loading.Shade)
	shadeGradient.Parent = shade
	-- Eat clicks/taps so nothing behind the screen reacts.
	local blocker = Instance.new("TextButton")
	blocker.Size = UDim2.fromScale(1, 1)
	blocker.BackgroundTransparency = 1
	blocker.Text = ""
	blocker.AutoButtonColor = false
	blocker.Parent = root

	local logo = Instance.new("ImageLabel")
	logo.Name = "Logo"
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Position = UDim2.fromScale(0.5, 0.38)
	logo.Size = UDim2.fromScale(Loading.LogoWidthScale, Loading.LogoWidthScale / 2)
	logo.BackgroundTransparency = 1
	logo.ScaleType = Enum.ScaleType.Fit
	logo.Image = UIAssets.Logo
	logo.Parent = root
	local logoAspect = Instance.new("UIAspectRatioConstraint")
	logoAspect.AspectRatio = 2
	logoAspect.Parent = logo
	local logoLimit = Instance.new("UISizeConstraint")
	logoLimit.MaxSize = Loading.LogoMaxSize
	logoLimit.Parent = logo
	TweenService:Create(logo, TweenInfo.new(Loading.LogoBounceTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Position = UDim2.new(0.5, 0, 0.38, -Loading.LogoBounce),
	}):Play()

	title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 1) -- sits just above the bar on any screen height
	title.Position = UDim2.new(0.5, 0, 0.78, -8)
	title.Size = UDim2.new(0.8, 0, 0, 44)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	Localization.Bind(title, "Loading.Title")
	title.Parent = root
	outlined(title, 3)
	local titleSize = Instance.new("UITextSizeConstraint")
	titleSize.MaxTextSize = 40
	titleSize.Parent = title

	buildBar(root)

	hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0.78, Loading.BarHeight + 12)
	hint.Size = UDim2.new(0.8, 0, 0, 26)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.FredokaOne
	hint.TextScaled = true
	hint.TextColor3 = HINT_COLOR
	hint.Text = ""
	hint.Parent = root
	outlined(hint, 2)
	local hintSize = Instance.new("UITextSizeConstraint")
	hintSize.MaxTextSize = 20
	hintSize.Parent = hint

	gui.Parent = player:WaitForChild("PlayerGui")
end

function LoadingController:Start(): ()
	task.spawn(function()
		ContentProvider:PreloadAsync({ UIAssets.LoadingBackground, UIAssets.Logo })
		ContentProvider:PreloadAsync(uiImageIds())
	end)
	if player:GetAttribute(Plots.PlayerPlotAttribute) ~= nil then
		hide()
		return
	end
	local connection: RBXScriptConnection
	connection = player:GetAttributeChangedSignal(Plots.PlayerPlotAttribute):Connect(function()
		if player:GetAttribute(Plots.PlayerPlotAttribute) ~= nil then
			connection:Disconnect()
			hide()
		end
	end)

	local started = os.clock()
	local dots = 0
	while gui.Enabled do
		dots = dots % MAX_DOTS + 1
		local base = Localization.T("Loading.Title")
		title.Text = base .. string.rep(".", dots)
		if os.clock() - started >= Loading.SlowHintDelay then
			Localization.Bind(hint, "Loading.Slow")
		end
		task.wait(DOT_INTERVAL)
	end
end

return LoadingController


