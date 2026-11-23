--!strict
-- UI pack badges on every cat's name tag (Stage 18), client-side only: the rarity badge left of the rarity
-- line, mutation and Mega/Giga badges right of it. Positions are fractions of the text bounds, so they stay
-- right at any distance and after Mega/Giga ScaleTo. The server's Nameplate (Head) is otherwise untouched.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local CatSchema = require(Config.CatSchema)
local Mutations = require(Config.Mutations)
local Tags = require(Config.Tags)
local UIAssets = require(Config.UIAssets)

local ATTR = CatSchema.Attributes
local BADGE_HEIGHT = 0.5 -- of the nameplate height
local BADGE_GAP = 0.01 -- of the nameplate width
local BADGE_Y = 0.79 -- centre of the rarity line

local CatBadgeController = {
	Priority = 59,
}

local tracked: { [Model]: { RBXScriptConnection } } = {}

local function badge(parent: Instance, name: string): ImageLabel
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("ImageLabel") then
		return existing
	end
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Size = UDim2.fromScale(1, BADGE_HEIGHT)
	image.Visible = false
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = image
	image.Parent = parent
	return image
end

local function layout(model: Model)
	local nameplate = model:FindFirstChild("Nameplate", true)
	local rarityLabel = if nameplate then nameplate:FindFirstChild("RarityLabel") else nil
	if nameplate == nil or not nameplate:IsA("BillboardGui") or rarityLabel == nil or not rarityLabel:IsA("TextLabel") then
		return
	end
	local rarityBadge = badge(nameplate, "RarityBadge")
	local mutationBadge = badge(nameplate, "MutationBadge")
	local tierBadge = badge(nameplate, "TierBadge")
	local labelWidth = rarityLabel.AbsoluteSize.X
	local scale = nameplate.Size
	if labelWidth <= 0 or rarityLabel.TextBounds.X <= 0 or scale.X.Scale <= 0 then
		return -- not on screen yet; TextBounds changes when it renders
	end
	-- Both are fractions of the nameplate, independent of camera distance.
	local half = rarityLabel.TextBounds.X / labelWidth / 2
	local badgeWidth = BADGE_HEIGHT * scale.Y.Scale / scale.X.Scale

	local rarityImage = (UIAssets.RarityBadges :: any)[tostring(model:GetAttribute(ATTR.Rarity))]
	rarityBadge.Image = rarityImage or ""
	rarityBadge.Visible = rarityImage ~= nil
	rarityBadge.AnchorPoint = Vector2.new(1, 0.5)
	rarityBadge.Position = UDim2.fromScale(0.5 - half - BADGE_GAP, BADGE_Y)

	local x = 0.5 + half + BADGE_GAP
	local mutation = Mutations.Get(tostring(model:GetAttribute(ATTR.Mutation)))
	local mutationImage = if mutation then (UIAssets.MutationBadges :: any)[mutation.id] else nil
	mutationBadge.Image = mutationImage or ""
	mutationBadge.Visible = mutationImage ~= nil
	mutationBadge.AnchorPoint = Vector2.new(0, 0.5)
	mutationBadge.Position = UDim2.fromScale(x, BADGE_Y)
	if mutationImage then
		x += badgeWidth + BADGE_GAP
	end
	local tier = Mutations.GetTier(model:GetAttribute(ATTR.Tier))
	local tierImage = (UIAssets.TierBadges :: any)[tier.id]
	tierBadge.Image = tierImage or ""
	tierBadge.Visible = tierImage ~= nil
	tierBadge.AnchorPoint = Vector2.new(0, 0.5)
	tierBadge.Position = UDim2.fromScale(x, BADGE_Y)
end

local function untrack(model: Model)
	local connections = tracked[model]
	if connections then
		tracked[model] = nil
		for _, connection in connections do
			connection:Disconnect()
		end
	end
end

local function track(instance: Instance)
	if not instance:IsA("Model") or tracked[instance] then
		return
	end
	local model = instance
	local connections: { RBXScriptConnection } = {}
	tracked[model] = connections
	local hooked: Instance? = nil
	local function hook()
		local nameplate = model:FindFirstChild("Nameplate", true)
		local rarityLabel = if nameplate then nameplate:FindFirstChild("RarityLabel") else nil
		if rarityLabel and rarityLabel:IsA("TextLabel") and hooked ~= rarityLabel then
			hooked = rarityLabel
			table.insert(connections, rarityLabel:GetPropertyChangedSignal("Text"):Connect(function()
				task.defer(layout, model)
			end))
			-- First render (TextBounds becomes known) only; afterwards the fractions do not change.
			local first: RBXScriptConnection
			first = rarityLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
				if rarityLabel.TextBounds.X > 0 then
					first:Disconnect()
					layout(model)
				end
			end)
			table.insert(connections, first)
		end
		layout(model)
	end
	for _, attribute in { ATTR.Mutation, ATTR.Tier, ATTR.Rarity } do
		table.insert(connections, model:GetAttributeChangedSignal(attribute):Connect(hook))
	end
	table.insert(connections, model.DescendantAdded:Connect(function(descendant: Instance)
		if descendant.Name == "RarityLabel" or descendant.Name == "Nameplate" then
			hook()
		end
	end))
	table.insert(connections, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			untrack(model)
		end
	end))
	hook()
end

function CatBadgeController:Start(): ()
	CollectionService:GetInstanceAddedSignal(Tags.Cat):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Tags.Cat):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			untrack(instance)
		end
	end)
	for _, instance in CollectionService:GetTagged(Tags.Cat) do
		track(instance)
	end
end

return CatBadgeController

