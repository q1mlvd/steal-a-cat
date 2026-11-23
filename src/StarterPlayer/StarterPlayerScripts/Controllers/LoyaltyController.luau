--!strict
-- Loyalty bars live on world cats, so character respawns do not remove them.
-- The server owns all loyalty changes; this controller only reads attributes and celebrates returns.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Localization = require(ReplicatedStorage.Shared.Util.Localization)
local TweenService = game:GetService("TweenService")

local Config = ReplicatedStorage.Shared.Config
local CatSchema = require(Config.CatSchema)
local Loyalty = require(Config.Loyalty)
local Tags = require(Config.Tags)
local Network = require(ReplicatedStorage.Shared.Network)
local UiSkin = require(ReplicatedStorage.Shared.Util.UiSkin)

local ATTR = CatSchema.Attributes
local rng = Random.new()

type Display = {
	gui: BillboardGui?,
	text: TextLabel?,
	fill: Frame?,
	badge: TextLabel?,
	connections: { RBXScriptConnection },
}

local LoyaltyController = {
	Priority = 45,
}

local displays: { [Model]: Display } = {}
local effectGui: ScreenGui
local banner: TextLabel
local bannerTween: Tween? = nil
local bannerToken = 0

local function finiteNumber(value: unknown, fallback: number): number
	if type(value) == "number" and value == value and value > -math.huge and value < math.huge then
		return value
	end
	return fallback
end

local function roundCorners(parent: Instance, radius: number): ()
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function makeDisplay(model: Model, display: Display): ()
	local head = model:FindFirstChild("Head")
	local root = model:FindFirstChild("HumanoidRootPart")
	local part = if head and head:IsA("BasePart") then head else if root and root:IsA("BasePart") then root else nil
	if part == nil then
		return
	end
	if display.gui and display.gui.Parent then
		display.gui.Adornee = nil -- Inherit the world part, matching the existing Nameplate.
		display.gui.Parent = part
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = Loyalty.HeartGuiName
	gui.Size = UDim2.fromScale(Loyalty.HeartSize.X / Loyalty.HeartPixelsPerStud, Loyalty.HeartSize.Y / Loyalty.HeartPixelsPerStud)
	gui.StudsOffsetWorldSpace = Loyalty.HeartOffset
	gui.MaxDistance = Loyalty.HeartMaxDistance
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Enabled = false

	local textHeight = Loyalty.HeartTextSize + Loyalty.HeartGap
	local text = Instance.new("TextLabel")
	text.Name = "Heart"
	text.Size = UDim2.fromScale(1, textHeight / Loyalty.HeartSize.Y)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextSize = Loyalty.HeartTextSize
	text.TextScaled = true
	text.TextColor3 = Loyalty.HeartColor
	text.TextStrokeColor3 = Loyalty.HeartBackground
	text.TextStrokeTransparency = 0
	text.Parent = gui

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.fromScale(0, (textHeight + Loyalty.HeartGap) / Loyalty.HeartSize.Y)
	bar.Size = UDim2.fromScale(1, Loyalty.HeartBarHeight / Loyalty.HeartSize.Y)
	bar.BackgroundColor3 = Loyalty.HeartBackground
	bar.BorderSizePixel = 0
	bar.ClipsDescendants = true
	roundCorners(bar, Loyalty.HeartCornerRadius)
	bar.Parent = gui

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Loyalty.HeartColor
	fill.BorderSizePixel = 0
	roundCorners(fill, Loyalty.HeartCornerRadius)
	fill.Parent = bar
	UiSkin.Bar(bar, fill, "Pink") -- UI pack bar art

	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.Position = UDim2.fromScale(0, (textHeight + Loyalty.HeartGap + Loyalty.HeartBarHeight + Loyalty.HeartGap) / Loyalty.HeartSize.Y)
	badge.Size = UDim2.fromScale(1, Loyalty.BadgeTextSize / Loyalty.HeartSize.Y)
	badge.BackgroundTransparency = 1
	badge.Font = Enum.Font.FredokaOne
	badge.TextSize = Loyalty.BadgeTextSize
	badge.TextScaled = true
	badge.TextColor3 = Loyalty.BannerTextColor
	badge.TextStrokeColor3 = Loyalty.HeartBackground
	badge.TextStrokeTransparency = 0
	badge.Parent = gui

	display.gui = gui
	display.text = text
	display.fill = fill
	display.badge = badge
	gui.Parent = part
end

local function refreshDisplay(model: Model): ()
	local display = displays[model]
	if display == nil then
		return
	end
	makeDisplay(model, display)
	local gui, text, fill, badge = display.gui, display.text, display.fill, display.badge
	if gui == nil or text == nil or fill == nil or badge == nil then
		return
	end
	local ownerId = model:GetAttribute(ATTR.OwnerUserId)
	gui.Enabled = model:IsDescendantOf(workspace) and type(ownerId) == "number"
		and ownerId ~= CatSchema.WildOwnerUserId and model:GetAttribute(ATTR.State) ~= CatSchema.States.Wild
	local value = math.clamp(finiteNumber(model:GetAttribute(ATTR.Loyalty), Loyalty.Min), Loyalty.Min, Loyalty.Max)
	local fraction = (value - Loyalty.Min) / (Loyalty.Max - Loyalty.Min)
	text.Text = `❤ {math.round(value)}/{Loyalty.Max}`
	fill.Size = UDim2.fromScale(fraction, 1)
	local returns = finiteNumber(model:GetAttribute(ATTR.TimesReturned), 0)
	if returns >= Loyalty.UnstealableReturns then
		badge.Text = Localization.T("Loyalty.Unstealable")
	elseif returns >= Loyalty.LoyalReturns then
		badge.Text = Localization.T("Loyalty.Bonus", {percent = math.round((Loyalty.LoyalIncomeMultiplier - 1) * 100)})
	else
		badge.Text = ""
	end
end

local function removeDisplay(model: Model): ()
	local display = displays[model]
	if display == nil then
		return
	end
	displays[model] = nil
	for _, connection in display.connections do
		connection:Disconnect()
	end
	if display.gui then
		display.gui:Destroy()
	end
end

local function track(instance: Instance): ()
	if not instance:IsA("Model") or displays[instance] then
		return
	end
	local model = instance
	local display: Display = { gui = nil, text = nil, fill = nil, badge = nil, connections = {} }
	displays[model] = display
	for _, attribute in { ATTR.Loyalty, ATTR.TimesReturned, ATTR.OwnerUserId, ATTR.State } do
		table.insert(display.connections, model:GetAttributeChangedSignal(attribute):Connect(function()
			refreshDisplay(model)
		end))
	end
	table.insert(display.connections, model.AncestryChanged:Connect(function()
		refreshDisplay(model)
	end))
	table.insert(display.connections, model.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("BasePart") then
			refreshDisplay(model)
		end
	end))
	table.insert(display.connections, model.Destroying:Connect(function()
		removeDisplay(model)
	end))
	refreshDisplay(model)
end

local function spawnConfetti(): ()
	for _ = 1, Loyalty.ConfettiCount do
		local piece = Instance.new("Frame")
		piece.Name = "Confetti"
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Size = UDim2.fromOffset(Loyalty.ConfettiSize.X, Loyalty.ConfettiSize.Y)
		piece.BackgroundColor3 = Loyalty.ConfettiColors[rng:NextInteger(1, #Loyalty.ConfettiColors)]
		piece.BorderSizePixel = 0
		local startX = Loyalty.ConfettiSpread.X * (rng:NextNumber() - 0.5)
		local startY = Loyalty.BannerHeight / 2
		piece.Position = UDim2.new(0.5, startX, Loyalty.BannerTop, startY)
		piece.Rotation = rng:NextNumber(-Loyalty.ConfettiRotationRange, Loyalty.ConfettiRotationRange)
		piece.ZIndex = banner.ZIndex + 1
		piece.Parent = effectGui

		local destination = UDim2.new(0.5, startX + Loyalty.ConfettiSpread.X * (rng:NextNumber() - 0.5),
			Loyalty.BannerTop, startY + Loyalty.ConfettiSpread.Y * (1 + rng:NextNumber()))
		local tween = TweenService:Create(piece, TweenInfo.new(Loyalty.ConfettiDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = destination,
			Rotation = piece.Rotation + Loyalty.ConfettiTurns * 360,
		})
		tween.Completed:Connect(function()
			piece:Destroy()
		end)
		tween:Play()
		task.delay(Loyalty.ConfettiDuration * Loyalty.ConfettiFadeFraction, function()
			if piece.Parent then
				TweenService:Create(piece, TweenInfo.new(Loyalty.ConfettiDuration * (1 - Loyalty.ConfettiFadeFraction)), {
					BackgroundTransparency = 1,
				}):Play()
			end
		end)
	end
end

local function celebrate(catName: string): ()
	bannerToken += 1
	local token = bannerToken
	if bannerTween then
		bannerTween:Cancel()
	end
	banner.Text = Localization.T("Loyalty.Homecoming", {cat = Localization.Translate(catName)})
	banner.TextTransparency = 1
	banner.TextStrokeTransparency = 1
	banner.BackgroundTransparency = 1
	banner.Visible = true
	bannerTween = TweenService:Create(banner, TweenInfo.new(Loyalty.BannerFadeTime), {
		TextTransparency = 0,
		TextStrokeTransparency = 0,
		BackgroundTransparency = Loyalty.BannerBackgroundTransparency,
	})
	if bannerTween then
		bannerTween:Play()
	end
	spawnConfetti()
	task.delay(Loyalty.BannerDuration, function()
		if token ~= bannerToken then
			return
		end
		local tween = TweenService:Create(banner, TweenInfo.new(Loyalty.BannerFadeTime), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
			BackgroundTransparency = 1,
		})
		bannerTween = tween
		tween.Completed:Connect(function()
			if token == bannerToken then
				banner.Visible = false
			end
		end)
		tween:Play()
	end)
end

function LoyaltyController:Init(): ()
	effectGui = Instance.new("ScreenGui")
	effectGui.Name = Loyalty.EffectGuiName
	effectGui.ResetOnSpawn = false
	effectGui.IgnoreGuiInset = true
	effectGui.DisplayOrder = Loyalty.BannerDisplayOrder

	banner = Instance.new("TextLabel")
	banner.Name = "ReturnBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.fromScale(0.5, Loyalty.BannerTop)
	banner.Size = UDim2.new(1, -Loyalty.BannerPadding * 2, 0, Loyalty.BannerHeight)
	banner.BackgroundColor3 = Loyalty.HeartBackground
	banner.TextColor3 = Loyalty.BannerTextColor
	banner.TextStrokeColor3 = Loyalty.HeartColor
	banner.Font = Enum.Font.FredokaOne
	banner.TextScaled = true
	banner.TextWrapped = true
	banner.Visible = false
	roundCorners(banner, Loyalty.BannerCornerRadius)
	banner.Parent = effectGui
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(Loyalty.BannerWidth, Loyalty.BannerHeight)
	constraint.Parent = banner
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, Loyalty.BannerPadding)
	padding.PaddingRight = UDim.new(0, Loyalty.BannerPadding)
	padding.PaddingTop = UDim.new(0, Loyalty.BannerPadding)
	padding.PaddingBottom = UDim.new(0, Loyalty.BannerPadding)
	padding.Parent = banner
	effectGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function LoyaltyController:Start(): ()
	CollectionService:GetInstanceAddedSignal(Tags.Cat):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Tags.Cat):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			removeDisplay(instance)
		end
	end)
	for _, instance in CollectionService:GetTagged(Tags.Cat) do
		track(instance)
	end
	Network.GetEvent("CatLoyaltyReturned").OnClientEvent:Connect(function(catName: unknown, timesReturned: unknown)
		if type(catName) ~= "string" or type(timesReturned) ~= "number"
			or timesReturned ~= timesReturned or timesReturned < Loyalty.LoyalReturns or timesReturned >= math.huge
			or timesReturned % 1 ~= 0 then
			return
		end
		celebrate(catName)
	end)
end

return LoyaltyController



