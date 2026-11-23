--!strict
-- Cat portrait for any UI (Stage 17): the cat's icon on a rarity-coloured tile, a glowing ring + badge for
-- Mega/Giga, a tint overlay for mutations, and the silhouette for undiscovered cats. Client-side only.
-- Stage 18: the tile is the UI pack's rarity card frame, with image badges (rarity top-left, mutation
-- top-right, Mega/Giga bottom) from Config/UIAssets; text badges remain only where no art exists.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Localization = require(ReplicatedStorage.Shared.Util.Localization)

local Config = ReplicatedStorage.Shared.Config
local Cats = require(Config.Cats)
local CatVisuals = require(Config.CatVisuals)
local Mutations = require(Config.Mutations)
local Rarities = require(Config.Rarities)
local Shop = require(Config.Shop)
local UIAssets = require(Config.UIAssets)
local UiSkin = require(script.Parent.UiSkin)

local P = CatVisuals.Portrait
local RARITY_BADGE = 0.3 -- badge sizes, fraction of the portrait
local MUTATION_BADGE = 0.32
local TIER_BADGE = 0.4

local function badge(parent: Instance, name: string, imageId: string, size: number, position: UDim2, anchor: Vector2): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Image = imageId
	image.Size = UDim2.fromScale(size, size)
	image.Position = position
	image.AnchorPoint = anchor
	image.ZIndex = 5
	image.Parent = parent
	return image
end
local UI = Shop.Ui

export type Options = {
	catId: string?, -- nil with `rarity` = mystery cat of that rarity
	rarity: string?,
	tier: string?,
	mutation: string?,
	discovered: boolean?, -- false shows the silhouette (default true)
	frameless: boolean?, -- no card frame (the portrait already sits on a rarity card)
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
}

local CatPortrait = {}

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function sequence(colors: { Color3 }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keys = {}
	for index, color in colors do
		table.insert(keys, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(keys)
end

local function centeredText(parent: Instance, text: string, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = Localization.Translate(text)
	label.ZIndex = 2
	label.Parent = parent
	return label
end

function CatPortrait.Create(parent: Instance, options: Options): Frame
	local catDef = if options.catId then Cats.Get(options.catId) else nil
	local rarity = Rarities.Get(if catDef then catDef.rarity else options.rarity or "Common") or Rarities.List[1]
	local discovered = options.discovered ~= false and catDef ~= nil
	local tier = Mutations.GetTier(options.tier)
	local mutation = if discovered and options.mutation then Mutations.Get(options.mutation) else nil

	local frame = Instance.new("Frame")
	frame.Name = "CatPortrait"
	frame.Size = options.size
	frame.Position = options.position or UDim2.new()
	frame.AnchorPoint = options.anchor or Vector2.zero
	frame.LayoutOrder = options.layoutOrder or 0
	frame.BackgroundColor3 = rarity.color:Lerp(UI.Background, P.BackgroundDarken)
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = false
	corner(frame, P.Corner)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = rarity.color
	stroke.Thickness = P.Stroke
	stroke.Parent = frame

	local tierColors = (P.TierColors :: any)[tier.id] :: { Color3 }?
	if tierColors then
		-- Mega / Giga: thicker gradient ring and a soft inner glow behind the art
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Thickness = (P.TierStroke :: any)[tier.id] or P.Stroke
		local ring = Instance.new("UIGradient")
		ring.Color = sequence(tierColors)
		ring.Rotation = 45
		ring.Parent = stroke
		local glow = Instance.new("Frame")
		glow.Name = "TierGlow"
		glow.Size = UDim2.fromScale(1, 1)
		glow.BackgroundColor3 = Color3.new(1, 1, 1)
		glow.BackgroundTransparency = P.GlowTransparency
		glow.BorderSizePixel = 0
		glow.Parent = frame
		corner(glow, P.Corner)
		local glowGradient = Instance.new("UIGradient")
		glowGradient.Color = sequence(tierColors)
		glowGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 0.9), NumberSequenceKeypoint.new(1, 0.2) })
		glowGradient.Rotation = 90
		glowGradient.Parent = glow
	end

	local image = if catDef then (if discovered then catDef.icon else catDef.silhouette) else nil
	if image then
		local art = Instance.new("ImageLabel")
		art.Name = "Art"
		art.BackgroundTransparency = 1
		art.Size = UDim2.fromScale(1, 1)
		art.ScaleType = Enum.ScaleType.Fit
		art.Image = image
		art.ZIndex = 2
		art.Parent = frame
	else
		centeredText(frame, if catDef and discovered then P.NoArtText else P.MysteryText,
			if discovered then UI.Text else rarity.color)
	end

	-- UI pack rarity card frame (replaces the flat tile + stroke; the tier ring keeps its glow frame).
	if options.frameless then
		frame.BackgroundTransparency = 1
		stroke.Enabled = tierColors ~= nil -- keep only the Mega/Giga ring
	else
		UiSkin.Apply(frame, (UIAssets.Cards :: any)[rarity.id] or UIAssets.Frames.Card)
	end
	local rarityBadge = (UIAssets.RarityBadges :: any)[rarity.id]
	if rarityBadge then
		badge(frame, "RarityBadge", rarityBadge, RARITY_BADGE, UDim2.fromScale(-0.06, -0.06), Vector2.zero)
	end

	if mutation then
		local overlay = Instance.new("Frame")
		overlay.Name = "MutationOverlay"
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.BackgroundColor3 = Color3.new(1, 1, 1)
		overlay.BackgroundTransparency = P.MutationTransparency
		overlay.BorderSizePixel = 0
		overlay.ZIndex = 3
		overlay.Parent = frame
		corner(overlay, P.Corner)
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 35
		if mutation.visual == "Rainbow" then
			gradient.Color = sequence(P.Rainbow)
		else
			-- Diagonal sheen band in the mutation colour (keeps dark cats readable)
			gradient.Color = ColorSequence.new(mutation.color)
			gradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.85),
				NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.85) })
		end
		gradient.Parent = overlay
		local mutationBadge = (UIAssets.MutationBadges :: any)[mutation.id]
		if mutationBadge then
			badge(frame, "MutationBadge", mutationBadge, MUTATION_BADGE, UDim2.fromScale(1.06, -0.06), Vector2.new(1, 0))
		end
		local chip = Instance.new("TextLabel")
		chip.Name = "MutationChip"
		chip.BackgroundTransparency = 1
		chip.Size = UDim2.fromScale(1, P.BadgeHeightScale)
		chip.Font = Enum.Font.FredokaOne
		chip.TextScaled = true
		chip.TextColor3 = mutation.color
		chip.TextStrokeTransparency = 0
		chip.Text = Localization.T("Mutation." .. mutation.id)
		chip.ZIndex = 4
		chip.Visible = mutationBadge == nil -- text only for mutations without badge art
		chip.Parent = frame
	end

	local tierBadge = (UIAssets.TierBadges :: any)[tier.id]
	if tierBadge then
		badge(frame, "TierBadge", tierBadge, TIER_BADGE, UDim2.fromScale(0.5, 1.08), Vector2.new(0.5, 1))
	elseif tierColors then
		local badge = Instance.new("TextLabel")
		badge.Name = "TierBadge"
		badge.AnchorPoint = Vector2.new(0.5, 1)
		badge.Position = UDim2.fromScale(0.5, 1)
		badge.Size = UDim2.fromScale(0.7, P.BadgeHeightScale)
		badge.BackgroundColor3 = Color3.new(1, 1, 1)
		badge.Font = Enum.Font.FredokaOne
		badge.TextScaled = true
		badge.TextColor3 = UI.Background
		badge.Text = Localization.T("Tier." .. tier.id)
		badge.ZIndex = 4
		badge.Parent = frame
		corner(badge, P.Corner)
		local badgeGradient = Instance.new("UIGradient")
		badgeGradient.Color = sequence(tierColors)
		badgeGradient.Parent = badge
	end

	frame.Parent = parent
	return frame
end

return CatPortrait


