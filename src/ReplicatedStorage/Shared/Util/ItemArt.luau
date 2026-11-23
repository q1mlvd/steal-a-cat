--!strict
-- Clones imported item art (ReplicatedStorage/ItemModels) for server and client visuals. Purely cosmetic:
-- every clone is non-colliding, non-touching and non-queryable so it never changes gameplay checks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemArtConfig = require(ReplicatedStorage.Shared.Config.ItemArt)

local ItemArt = {}

local function folder(): Instance?
	return ReplicatedStorage:FindFirstChild(ItemArtConfig.ModelsFolder)
end

-- A fresh copy of an item model, or nil if the art is missing (callers keep their old visuals then).
function ItemArt.Clone(name: string, anchored: boolean): Model?
	local models = folder()
	local source = if models then models:FindFirstChild(name) else nil
	if source == nil or not source:IsA("Model") then
		return nil
	end
	local model = source:Clone()
	model.Name = ItemArtConfig.ArtName
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = anchored
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
	return model
end

-- Welds every part of `model` to `part` in their current placement.
function ItemArt.WeldTo(model: Model, part: BasePart)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end
end

-- Puts an item model in the character's right hand (replacing any held item). Returns it, or nil.
function ItemArt.Hold(character: Model, name: string): Model?
	local hand: BasePart? = nil
	for _, handName in ItemArtConfig.HandNames do
		local found = character:FindFirstChild(handName)
		if found and found:IsA("BasePart") then
			hand = found
			break
		end
	end
	if hand == nil then
		return nil
	end
	ItemArt.Release(character)
	local model = ItemArt.Clone(name, false)
	if model == nil then
		return nil
	end
	model.Name = ItemArtConfig.HeldName
	model:SetAttribute(ItemArtConfig.HeldItemAttribute, name)
	local grip = ItemArtConfig.Grips[name] or CFrame.new()
	model:PivotTo(hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, 0) * grip)
	ItemArt.WeldTo(model, hand)
	model.Parent = character
	return model
end

-- Removes the held item; with `name`, only when that item is the one held.
function ItemArt.Release(character: Model, name: string?)
	local held = character:FindFirstChild(ItemArtConfig.HeldName)
	if held and (name == nil or held:GetAttribute(ItemArtConfig.HeldItemAttribute) == name) then
		held:Destroy()
	end
end

return ItemArt

