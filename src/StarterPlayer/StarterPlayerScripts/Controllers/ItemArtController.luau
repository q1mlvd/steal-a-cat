--!strict
-- Client-only item art (Stage 17): procedural walk bob for Guard/Raid dog meshes (anchored, moved by the server
-- with PivotTo, so speed comes from position change) and a bell mesh on every cat with the bell attribute.
-- Purely cosmetic: nothing here is replicated or read by gameplay.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = ReplicatedStorage.Shared.Config
local CatVisuals = require(Config.CatVisuals)
local Defense = require(Config.Defense)
local ItemArtConfig = require(Config.ItemArt)
local Tags = require(Config.Tags)
local ItemArt = require(ReplicatedStorage.Shared.Util.ItemArt)

local BELL_ART_NAME = "BellArt"

type Dog = {
	model: Model,
	weld: Weld?,
	baseC0: CFrame,
	lastPosition: Vector3?,
	distance: number,
}

local ItemArtController = {
	Priority = 58,
}

local dogs: { [Model]: Dog } = {}
local bellWatch: { [Model]: { RBXScriptConnection } } = {}

local function trackDog(instance: Instance)
	if instance:IsA("Model") and dogs[instance] == nil then
		dogs[instance] = { model = instance, weld = nil, baseC0 = CFrame.new(), lastPosition = nil, distance = 0 }
	end
end

local function findWeld(dog: Dog): Weld?
	if dog.weld and dog.weld.Parent then
		return dog.weld
	end
	local weld = dog.model:FindFirstChild(ItemArtConfig.ArtWeldName, true)
	if weld and weld:IsA("Weld") then
		dog.weld = weld
		dog.baseC0 = weld.C0
		return weld
	end
	return nil
end

local function stepDogs(dt: number)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	for model, dog in dogs do
		if not model:IsDescendantOf(workspace) then
			dogs[model] = nil
			continue
		end
		local root = model.PrimaryPart
		local weld = findWeld(dog)
		if root == nil or weld == nil then
			continue
		end
		local position = root.Position
		local moved = if dog.lastPosition then Vector3.new(position.X - dog.lastPosition.X, 0, position.Z - dog.lastPosition.Z).Magnitude else 0
		dog.lastPosition = position
		if (position - camera.CFrame.Position).Magnitude > CatVisuals.AnimateDistance then
			continue
		end
		local offset: CFrame
		if dt > 0 and moved / dt > CatVisuals.MovingSpeed then
			dog.distance += moved
			local wave = math.sin((dog.distance * ItemArtConfig.DogCyclesPerStud % 1) * 2 * math.pi)
			offset = CFrame.new(0, math.abs(wave) * ItemArtConfig.DogBobHeight, 0)
				* CFrame.Angles(math.rad(wave * CatVisuals.WalkRollDegrees), 0, 0)
		else
			local breath = math.sin(os.clock() / CatVisuals.BreathSeconds * 2 * math.pi)
			offset = CFrame.new(0, breath * CatVisuals.BreathHeight, 0)
		end
		weld.C0 = dog.baseC0 * offset
	end
end

-- Bells ----------------------------------------------------------------------------------

local function refreshBell(model: Model)
	local existing = model:FindFirstChild(BELL_ART_NAME)
	if existing then
		existing:Destroy()
	end
	local head = model:FindFirstChild("Head")
	if model:GetAttribute(Defense.BellAttribute) ~= true or head == nil or not head:IsA("BasePart") then
		return
	end
	local bell = ItemArt.Clone(ItemArtConfig.BellModel, false)
	if bell == nil then
		return
	end
	local scale = model:GetScale() -- Mega/Giga cats are scaled by the server with ScaleTo
	bell:ScaleTo(ItemArtConfig.BellScale * scale)
	local offset = ItemArtConfig.BellOffset
	bell:PivotTo(head.CFrame * CFrame.new(offset.Position * scale) * offset.Rotation)
	ItemArt.WeldTo(bell, head)
	bell.Name = BELL_ART_NAME
	bell.Parent = model
end

local function unwatchBell(model: Model)
	local connections = bellWatch[model]
	if connections then
		bellWatch[model] = nil
		for _, connection in connections do
			connection:Disconnect()
		end
	end
end

local function watchBell(instance: Instance)
	if not instance:IsA("Model") or bellWatch[instance] then
		return
	end
	local model = instance
	local connections: { RBXScriptConnection } = {}
	bellWatch[model] = connections
	local headSizeConnection: RBXScriptConnection? = nil
	local function hookHead()
		local head = model:FindFirstChild("Head")
		if headSizeConnection == nil and head and head:IsA("BasePart") then
			headSizeConnection = head:GetPropertyChangedSignal("Size"):Connect(function()
				refreshBell(model)
			end)
			table.insert(connections, headSizeConnection :: RBXScriptConnection)
			refreshBell(model)
		end
	end
	table.insert(connections, model:GetAttributeChangedSignal(Defense.BellAttribute):Connect(function()
		refreshBell(model)
	end))
	table.insert(connections, model.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Head" then
			hookHead()
		end
	end))
	table.insert(connections, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			unwatchBell(model)
		end
	end))
	hookHead()
end

function ItemArtController:Start(): ()
	CollectionService:GetInstanceAddedSignal(ItemArtConfig.DogTag):Connect(trackDog)
	for _, instance in CollectionService:GetTagged(ItemArtConfig.DogTag) do
		trackDog(instance)
	end
	CollectionService:GetInstanceAddedSignal(Tags.Cat):Connect(watchBell)
	CollectionService:GetInstanceRemovedSignal(Tags.Cat):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			unwatchBell(instance)
		end
	end)
	for _, instance in CollectionService:GetTagged(Tags.Cat) do
		watchBell(instance)
	end
	RunService.RenderStepped:Connect(stepDogs)
end

return ItemArtController

