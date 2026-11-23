--!strict
-- Shows house prompts only when they make sense for the local player:
--   Collect - your own bowl
--   Place   - a free pillow in your own house, while you carry a cat
--   PickUp  - your own cat on a pillow, while you can carry another cat
-- The server keeps these prompts enabled and validates every trigger; this is purely presentation.
-- Prompts shown at (nearly) the same spot stack upward via UIOffset so they never overlap.


local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = ReplicatedStorage.Shared.Config
local Carrying = require(Config.Carrying)
local CatSchema = require(Config.CatSchema)
local Catching = require(Config.Catching)
local Events = require(Config.Events)
local Items = require(Config.Items)
local Loyalty = require(Config.Loyalty)
local Pillows = require(Config.Pillows)
local PlotPrompts = require(Config.PlotPrompts)
local Plots = require(Config.Plots)
local Stealing = require(Config.Stealing)
local Shop = require(Config.Shop)
local Tags = require(Config.Tags)

local ATTR = CatSchema.Attributes

local PromptController = {
	Priority = 40,
}

local player = Players.LocalPlayer
local tracked: { [ProximityPrompt]: true } = {}
local held: ProximityPrompt? = nil

local function isManaged(prompt: ProximityPrompt): boolean
	return CollectionService:HasTag(prompt, Tags.PlotPrompt)
		or prompt.Name == Catching.PromptName or prompt.Name == Shop.PromptName
end

local function inputIsReserved(): boolean
	if player:GetAttribute(Shop.UiStateAttribute) == true or UserInputService:GetFocusedTextBox() ~= nil then
		return true
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local catchGui = if playerGui then playerGui:FindFirstChild(Shop.CatchGuiName) else nil
	return catchGui ~= nil and catchGui:IsA("ScreenGui") and catchGui.Enabled
end

local function positionOf(prompt: ProximityPrompt): Vector3?
	local parent = prompt.Parent
	if parent == nil then
		return nil
	elseif parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent:IsA("BasePart") then
		return parent.Position
	elseif parent:IsA("Model") then
		return parent:GetPivot().Position
	end
	return nil
end

local function carriedCount(): number
	local count = 0
	for _, instance in CollectionService:GetTagged(Tags.Cat) do
		if instance:GetAttribute(ATTR.CarrierUserId) == player.UserId then
			count += 1
		end
	end
	return count
end

-- Hands upgrade mirror; the server enforces the real capacity.
local function capacity(): number
	local value = player:GetAttribute(Carrying.CapacityAttribute)
	return if type(value) == "number" and value >= Carrying.DefaultCapacity then value else Carrying.DefaultCapacity
end

local stackRank: { [string]: number } = {}
for index, key in PlotPrompts.StackOrder do
	stackRank[key] = index
end

local function rankOf(prompt: ProximityPrompt): number
	local kind = prompt:GetAttribute(PlotPrompts.KindAttribute)
	return stackRank[if type(kind) == "string" then kind else prompt.Name] or #PlotPrompts.StackOrder + 1
end

-- Shown prompts within StackGroupDistance of each other form one stack, ordered by StackOrder.
local function layoutStacks(shown: { ProximityPrompt })
	local positions: { [ProximityPrompt]: Vector3 } = {}
	for _, prompt in shown do
		positions[prompt] = positionOf(prompt) or Vector3.zero
	end
	table.sort(shown, function(a: ProximityPrompt, b: ProximityPrompt): boolean
		local rankA, rankB = rankOf(a), rankOf(b)
		if rankA ~= rankB then return rankA < rankB end
		return a.Name < b.Name
	end)
	local stacks: { { anchor: Vector3, count: number } } = {}
	for _, prompt in shown do
		local position = positions[prompt]
		local slot = 0
		for _, stack in stacks do
			if (stack.anchor - position).Magnitude <= PlotPrompts.StackGroupDistance then
				slot = stack.count
				stack.count += 1
				break
			end
		end
		if slot == 0 then
			table.insert(stacks, { anchor = position, count = 1 })
		end
		local offset = Vector2.new(0, -slot * PlotPrompts.StackSpacing) -- negative Y = higher on screen
		if prompt.UIOffset ~= offset then
			prompt.UIOffset = offset
		end
	end
end

local function plotOf(instance: Instance): Model?
	local node: Instance? = instance
	while node do
		if node:IsA("Model") and CollectionService:HasTag(node, Tags.Plot) then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function ownsPlotOf(instance: Instance): boolean
	local plot = plotOf(instance)
	return plot ~= nil and plot:GetAttribute(Plots.OwnerAttribute) == player.UserId
end

local function shouldShow(prompt: ProximityPrompt, carrying: boolean, handsFull: boolean): boolean
	local kind = prompt:GetAttribute(PlotPrompts.KindAttribute)
	local parent = prompt.Parent
	if parent == nil then
		return false
	end
	if prompt.Name == Catching.PromptName then
		local model = prompt:FindFirstAncestorOfClass("Model")
		return not handsFull and model ~= nil and CollectionService:HasTag(model, Tags.Cat)
			and model:GetAttribute(ATTR.State) == CatSchema.States.Wild
			and model:GetAttribute(Shop.CatchLockedAttribute) ~= true
			and model:GetAttribute(Events.Rain.HidingAttribute) ~= true
	elseif prompt.Name == Shop.PromptName then
		return CollectionService:HasTag(parent, Tags.ShopZone)
	end
	if kind == PlotPrompts.Kinds.Collect then
		return ownsPlotOf(parent)
	elseif kind == PlotPrompts.Kinds.Place then
		return carrying and ownsPlotOf(parent) and parent:GetAttribute(Pillows.OccupiedAttribute) ~= true
			and parent:GetAttribute(Pillows.LockedAttribute) ~= true
	elseif kind == PlotPrompts.Kinds.Steal then
		local model = parent:FindFirstAncestorOfClass("Model")
		local ownerId = if model then model:GetAttribute(ATTR.OwnerUserId) else nil
		local timesReturned = if model then model:GetAttribute(ATTR.TimesReturned) else nil
		if handsFull or model == nil or model:GetAttribute(ATTR.State) ~= CatSchema.States.OnPillow
			or (type(timesReturned) == "number" and timesReturned >= Loyalty.UnstealableReturns)
			or type(ownerId) ~= "number" or ownerId == CatSchema.WildOwnerUserId or ownerId == player.UserId then
			return false
		end
		local plot = plotOf(parent)
		local shield = if plot then plot:GetAttribute(Stealing.ShieldAttribute) else nil
		return not (type(shield) == "number" and shield > workspace:GetServerTimeNow())
	elseif kind == PlotPrompts.Kinds.Lock or kind == PlotPrompts.Kinds.Merge then
		return ownsPlotOf(parent)
	elseif kind == PlotPrompts.Kinds.PickUp then
		local model = parent:FindFirstAncestorOfClass("Model")
		return not handsFull and model ~= nil and model:GetAttribute(ATTR.OwnerUserId) == player.UserId
			and model:GetAttribute(ATTR.State) == CatSchema.States.OnPillow
	elseif kind == Loyalty.PetKind then
		local model = parent:FindFirstAncestorOfClass("Model")
		if model == nil or model:GetAttribute(ATTR.State) ~= CatSchema.States.OnPillow
			or model:GetAttribute(ATTR.OwnerUserId) ~= player.UserId
			or model:GetAttribute(ATTR.OriginalOwnerUserId) ~= player.UserId then
			return false
		end
		local availableAt = model:GetAttribute(Loyalty.PetAvailableAtAttribute)
		return type(availableAt) ~= "number" or availableAt <= workspace:GetServerTimeNow()
	end
	return false
end

local function refresh()
	local count = carriedCount()
	local carrying = count > 0
	local handsFull = count >= capacity()
	local reserved = inputIsReserved()
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local origin = if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then root.Position else nil
	local candidates: { { prompt: ProximityPrompt, distance: number } } = {}
	for prompt in tracked do
		if prompt.Parent == nil then
			tracked[prompt] = nil
			continue
		end
		if prompt.Name == Catching.PromptName then
			prompt.MaxActivationDistance = if player:GetAttribute(Shop.NetOwnedAttribute) == true
				then Items.Effects.Net.CatchDistance else Catching.PromptMaxDistance
		end
		local position = positionOf(prompt)
		if not reserved and origin and position and shouldShow(prompt, carrying, handsFull) then
			local distance = (origin - position).Magnitude
			if distance <= prompt.MaxActivationDistance then
				table.insert(candidates, { prompt = prompt, distance = distance })
			end
		end
	end
	-- At most one eligible prompt owns each keyboard/gamepad key. A server-timed
	-- hold keeps its target selected until the hold ends or becomes invalid.
	table.sort(candidates, function(a, b): boolean
		if a.prompt == b.prompt then return false end
		if a.prompt == held then return true end
		if b.prompt == held then return false end
		return a.distance < b.distance
	end)
	local chosen: { [ProximityPrompt]: true } = {}
	local keyboardKeys: { [Enum.KeyCode]: true } = {}
	local gamepadKeys: { [Enum.KeyCode]: true } = {}
	for _, candidate in candidates do
		local prompt = candidate.prompt
		local key = prompt.KeyboardKeyCode
		local pad = prompt.GamepadKeyCode
		if not keyboardKeys[key] and not gamepadKeys[pad] then
			chosen[prompt] = true
			keyboardKeys[key] = true
			gamepadKeys[pad] = true
		end
	end
	local shown: { ProximityPrompt } = {}
	for prompt in tracked do
		local show = chosen[prompt] == true
		if prompt.Enabled ~= show then
			prompt.Enabled = show -- local presentation; each service validates its own trigger
		end
		if show then
			table.insert(shown, prompt)
		end
	end
	layoutStacks(shown)
end

function PromptController:Init(): ()
	local function track(instance: Instance)
		if instance:IsA("ProximityPrompt") and isManaged(instance) then
			tracked[instance] = true
			instance.Enabled = false
		end
	end
	for _, instance in workspace:GetDescendants() do
		track(instance)
	end
	workspace.DescendantAdded:Connect(track)
	CollectionService:GetInstanceAddedSignal(Tags.PlotPrompt):Connect(track)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt: ProximityPrompt)
		if tracked[prompt] then
			held = prompt
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt: ProximityPrompt)
		if held == prompt then
			held = nil
		end
	end)
	player:GetAttributeChangedSignal(Shop.UiStateAttribute):Connect(refresh)
	player:GetAttributeChangedSignal(Carrying.CapacityAttribute):Connect(refresh)
end

function PromptController:Start(): ()
	while true do
		refresh()
		task.wait(PlotPrompts.ClientRefreshInterval)
	end
end

return PromptController

