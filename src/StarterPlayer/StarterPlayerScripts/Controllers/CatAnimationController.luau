--!strict
-- Procedural animation for the art cats (no rigs): walk bob + roll, idle breathing + sway, a squash while
-- sitting on a pillow. Only this client's copy of BodyWeld.C0 / Body.Size changes; the server's values are
-- re-read whenever it changes them (e.g. Mega/Giga ScaleTo). Also switches baked cat effects off in Low graphics.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = ReplicatedStorage.Shared.Config
local CatSchema = require(Config.CatSchema)
local CatVisuals = require(Config.CatVisuals)
local Tags = require(Config.Tags)

local ATTR = CatSchema.Attributes
local LOW_GRAPHICS_ATTRIBUTE = "Setting_LowGraphics"

type Animated = {
	model: Model,
	root: BasePart,
	body: BasePart,
	weld: Weld,
	baseC0: CFrame,
	baseSize: Vector3,
	writtenC0: CFrame?,
	writtenSize: Vector3?,
	squashed: boolean,
	phase: number, -- desynchronises cats
	distance: number, -- studs walked (drives the walk cycle)
	connections: { RBXScriptConnection },
}

local CatAnimationController = {
	Priority = 56,
}

local player = Players.LocalPlayer
local animated: { [Model]: Animated } = {}
local waiting: { [Model]: RBXScriptConnection } = {} -- streamed in before its Body / weld arrived

local function lowGraphics(): boolean
	return player:GetAttribute(LOW_GRAPHICS_ATTRIBUTE) == true
end

local function applyFx(model: Model)
	local enabled = not lowGraphics()
	for _, descendant in model:GetDescendants() do
		if descendant:GetAttribute(CatVisuals.FxAttribute) == true
			and (descendant:IsA("ParticleEmitter") or descendant:IsA("Light")) then
			(descendant :: any).Enabled = enabled
		end
	end
end

local function setSize(entry: Animated, size: Vector3)
	if entry.body.Size ~= size then
		entry.writtenSize = size
		entry.body.Size = size
	end
end

local function untrack(model: Model)
	local pending = waiting[model]
	if pending then
		waiting[model] = nil
		pending:Disconnect()
	end
	local entry = animated[model]
	if entry == nil then
		return
	end
	animated[model] = nil
	for _, connection in entry.connections do
		connection:Disconnect()
	end
end

local function track(instance: Instance)
	if not instance:IsA("Model") or animated[instance] then
		return
	end
	local model = instance
	applyFx(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	local body = model:FindFirstChild(CatVisuals.BodyName)
	local weld = if body then body:FindFirstChild(CatVisuals.WeldName) else nil
	if root == nil or not root:IsA("BasePart") or body == nil or not body:IsA("BasePart")
		or weld == nil or not weld:IsA("Weld") then
		-- Template cats never get a BodyWeld; art cats may still be streaming in.
		if waiting[model] == nil and model:IsDescendantOf(workspace) then
			waiting[model] = model.DescendantAdded:Connect(function(descendant: Instance)
				if descendant.Name == CatVisuals.WeldName or descendant.Name == CatVisuals.BodyName
					or descendant.Name == "HumanoidRootPart" then
					local connection = waiting[model]
					waiting[model] = nil
					if connection then
						connection:Disconnect()
					end
					track(model)
				end
			end)
		end
		return
	end
	local entry: Animated = {
		model = model,
		root = root,
		body = body,
		weld = weld,
		baseC0 = weld.C0,
		baseSize = body.Size,
		writtenC0 = nil,
		writtenSize = nil,
		squashed = false,
		phase = math.random() * 10,
		distance = 0,
		connections = {},
	}
	-- Server changes (ScaleTo for tiers) win; our own writes are recognised and ignored.
	table.insert(entry.connections, weld:GetPropertyChangedSignal("C0"):Connect(function()
		if weld.C0 ~= entry.writtenC0 then
			entry.baseC0 = weld.C0
		end
	end))
	table.insert(entry.connections, body:GetPropertyChangedSignal("Size"):Connect(function()
		if body.Size ~= entry.writtenSize then
			entry.baseSize = body.Size
			entry.squashed = false
		end
	end))
	table.insert(entry.connections, model.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:GetAttribute(CatVisuals.FxAttribute) == true then
			applyFx(model)
		end
	end))
	table.insert(entry.connections, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			untrack(model)
		end
	end))
	animated[model] = entry
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local eye = camera.CFrame.Position
	local now = os.clock()
	for model, entry in animated do
		if not entry.body.Parent or not entry.root.Parent then
			continue
		end
		-- Sitting squash: applied once per seat, undone when the cat leaves the pillow.
		local sitting = CatVisuals.SitStates[model:GetAttribute(ATTR.State) :: any] == true
		if sitting ~= entry.squashed then
			entry.squashed = sitting
			local s = CatVisuals.SitSquash
			setSize(entry, if sitting then entry.baseSize * Vector3.new(1 + s / 2, 1 - s, 1 + s / 2) else entry.baseSize)
		end
		if (entry.root.Position - eye).Magnitude > CatVisuals.AnimateDistance then
			continue
		end

		local velocity = entry.root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local offset: CFrame
		if speed > CatVisuals.MovingSpeed and not sitting then
			entry.distance += speed * dt
			local cycle = (entry.distance * CatVisuals.WalkCyclesPerStud) % 1
			local wave = math.sin(cycle * 2 * math.pi)
			offset = CFrame.new(0, math.abs(wave) * CatVisuals.WalkBobHeight, 0)
				* CFrame.Angles(0, 0, math.rad(wave * CatVisuals.WalkRollDegrees))
		else
			local t = now + entry.phase
			local breath = math.sin(t / CatVisuals.BreathSeconds * 2 * math.pi)
			local sway = math.sin(t / CatVisuals.IdleSwaySeconds * 2 * math.pi)
			local drop = if sitting then -entry.baseSize.Y * CatVisuals.SitSquash / 2 else 0
			offset = CFrame.new(0, drop + breath * CatVisuals.BreathHeight, 0)
				* CFrame.Angles(0, math.rad(sway * CatVisuals.IdleSwayDegrees), 0)
		end
		local c0 = entry.baseC0 * offset
		entry.writtenC0 = c0
		entry.weld.C0 = c0
	end
end

function CatAnimationController:Start(): ()
	CollectionService:GetInstanceAddedSignal(Tags.Cat):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Tags.Cat):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			untrack(instance)
		end
	end)
	for _, instance in CollectionService:GetTagged(Tags.Cat) do
		track(instance)
	end
	player:GetAttributeChangedSignal(LOW_GRAPHICS_ATTRIBUTE):Connect(function()
		for model in animated do
			applyFx(model)
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return CatAnimationController

