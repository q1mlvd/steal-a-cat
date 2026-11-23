--!strict
-- Local mutation visuals on every streamed-in cat: Shiny sparkles, Rainbow colour cycle, Diamond glass +
-- particles, Starry stars, seasonal glow. Purely cosmetic; the server owns the Mutation attribute.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = ReplicatedStorage.Shared.Config
local CatSchema = require(Config.CatSchema)
local Mutations = require(Config.Mutations)
local Tags = require(Config.Tags)

local ATTR = CatSchema.Attributes
local VISUAL_PART_NAMES = { "Body", "Head", "Tail", "EarL", "EarR" }
local PARTICLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

type Applied = {
	id: string,
	instances: { Instance },
	original: { [BasePart]: { color: Color3, material: Enum.Material, reflectance: number } },
	connection: RBXScriptConnection?,
}

local MutationController = {
	Priority = 55,
}

local applied: { [Model]: Applied } = {}
local rainbow: { [Model]: { BasePart } } = {}

local function visualParts(model: Model): { BasePart }
	local parts = {}
	for _, name in VISUAL_PART_NAMES do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	return parts
end

local function clear(model: Model)
	local state = applied[model]
	if state == nil then
		return
	end
	applied[model] = nil
	rainbow[model] = nil
	for _, instance in state.instances do
		instance:Destroy()
	end
	for part, original in state.original do
		if part.Parent then
			part.Color = original.color
			part.Material = original.material
			part.Reflectance = original.reflectance
		end
	end
	if state.connection then
		state.connection:Disconnect()
	end
end

local function lowGraphics(): boolean
	return game:GetService("Players").LocalPlayer:GetAttribute("Setting_LowGraphics") == true
end

local function emitter(parent: Instance, color: Color3): ParticleEmitter
	local particles = Instance.new("ParticleEmitter")
	particles.Enabled = not lowGraphics()
	particles.Texture = PARTICLE_TEXTURE
	particles.Color = ColorSequence.new(color)
	particles.Rate = Mutations.ParticleRate
	particles.Lifetime = NumberRange.new(0.6, 1.2)
	particles.Speed = NumberRange.new(1, 2)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Size = NumberSequence.new(0.4, 0)
	particles.LightEmission = 1
	particles.Parent = parent
	return particles
end

-- Art cats are one textured MeshPart, whose Color doesn't show: tint a thin untextured shell instead.
local function shell(body: BasePart, material: Enum.Material, color: Color3, transparency: number): BasePart?
	if not body:IsA("MeshPart") or body.TextureID == "" then
		return nil
	end
	local copy = body:Clone()
	copy:ClearAllChildren()
	copy.Name = "MutationShell"
	copy.TextureID = ""
	copy.Size = body.Size * Mutations.ShellScale
	copy.Material = material
	copy.Color = color
	copy.Transparency = transparency
	copy.Reflectance = if material == Enum.Material.Glass then Mutations.DiamondReflectance else 0
	copy.CastShadow = false
	copy.CanCollide = false
	copy.CanTouch = false
	copy.CanQuery = false
	copy.Massless = true
	copy.Anchored = false
	copy.CFrame = body.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = copy
	weld.Parent = copy
	copy.Parent = body.Parent
	return copy
end

local function apply(model: Model)
	local id = model:GetAttribute(ATTR.Mutation)
	local current = applied[model]
	if current and current.id == id then
		return
	end
	clear(model)
	local mutation = if type(id) == "string" then Mutations.Get(id) else nil
	local body = model:FindFirstChild("Body")
	if mutation == nil or body == nil or not body:IsA("BasePart") then
		return
	end
	local state: Applied = { id = mutation.id, instances = {}, original = {}, connection = nil }
	local parts = visualParts(model)
	for _, part in parts do
		state.original[part] = { color = part.Color, material = part.Material, reflectance = part.Reflectance }
	end
	if mutation.visual == "Sparkles" then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = mutation.color
		sparkles.Enabled = not lowGraphics()
		sparkles.Parent = body
		table.insert(state.instances, sparkles)
	elseif mutation.visual == "Rainbow" then
		local overlay = shell(body, Enum.Material.ForceField, mutation.color, Mutations.RainbowShellTransparency)
		if overlay then
			table.insert(state.instances, overlay)
			table.insert(parts, overlay)
		end
		rainbow[model] = parts
	elseif mutation.visual == "Diamond" then
		local overlay = shell(body, Enum.Material.Glass, mutation.color, Mutations.DiamondShellTransparency)
		if overlay then
			table.insert(state.instances, overlay)
		else
			for _, part in parts do
				part.Material = Enum.Material.Glass
				part.Color = mutation.color
				part.Reflectance = Mutations.DiamondReflectance
			end
		end
		table.insert(state.instances, emitter(body, mutation.color))
	elseif mutation.visual == "Stars" then
		table.insert(state.instances, emitter(body, mutation.color))
	else
		local light = Instance.new("PointLight")
		light.Color = mutation.color
		light.Range = 8
		light.Parent = body
		table.insert(state.instances, light)
	end
	applied[model] = state
end

local function track(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local model = instance
	apply(model)
	local connection = model:GetAttributeChangedSignal(ATTR.Mutation):Connect(function()
		apply(model)
	end)
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			connection:Disconnect()
			clear(model)
		end
	end)
end

function MutationController:Start(): ()
	CollectionService:GetInstanceAddedSignal(Tags.Cat):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Tags.Cat):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			clear(instance)
		end
	end)
	for _, instance in CollectionService:GetTagged(Tags.Cat) do
		track(instance)
	end
	RunService.RenderStepped:Connect(function()
		local hue = (os.clock() / Mutations.RainbowCycleSeconds) % 1
		for _, parts in rainbow do
			for index, part in parts do
				part.Color = Color3.fromHSV((hue + index * 0.08) % 1, 0.7, 1)
			end
		end
	end)
end

return MutationController

