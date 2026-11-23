--!strict
-- Gate barriers (Config/Gates). If the local player qualifies (Jump level / rebirths mirrors), their client
-- turns the barrier off locally; otherwise it stays solid with a hint billboard, and walking into it
-- shows the hint. GateService re-checks positions on the server.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Localization = require(ReplicatedStorage.Shared.Util.Localization)

local Config = ReplicatedStorage.Shared.Config
local Gates = require(Config.Gates)
local Monetization = require(Config.Monetization)
local Upgrades = require(Config.Upgrades)

local GateController = {
	Priority = 52,
}

type Barrier = { part: BasePart, gateId: string, billboard: BillboardGui, touched: RBXScriptConnection, hintUntil: number }

local player = Players.LocalPlayer
local container: Folder
local barriers: { [BasePart]: Barrier } = {}
local lastHintAt = -math.huge

local function canPass(gateId: string): boolean
	local gate = (Gates.Gates :: any)[gateId] :: Gates.GateDefinition?
	if gate == nil then
		return false
	end
	if gate.requiredUpgrade then
		local attribute = Upgrades.LevelAttributePrefix .. gate.requiredUpgrade
		if Upgrades.SanitizeLevel(gate.requiredUpgrade, player:GetAttribute(attribute)) < (gate.requiredLevel or 0) then
			return false
		end
	end
	if gate.requiredRebirths then
		local rebirths = player:GetAttribute(Gates.RebirthsAttribute)
		if type(rebirths) ~= "number" or rebirths < gate.requiredRebirths then
			return false
		end
	end
	if gate.requiredPass and player:GetAttribute(Monetization.PassAttributePrefix .. gate.requiredPass) ~= true then
		return false
	end
	return true
end

local function apply(barrier: Barrier)
	local open = canPass(barrier.gateId)
	local gate = (Gates.Gates :: any)[barrier.gateId] :: Gates.GateDefinition
	barrier.part.CanCollide = not open -- local only
	barrier.part.Transparency = if open then 1 else gate.barrierTransparency
	barrier.billboard.Enabled = not open and os.clock() < barrier.hintUntil
end

local function track(instance: Instance)
	if not instance:IsA("BasePart") or barriers[instance] then
		return
	end
	local gateId = instance:GetAttribute(Gates.GateIdAttribute)
	if type(gateId) ~= "string" or (Gates.Gates :: any)[gateId] == nil then
		return
	end
	local gate = (Gates.Gates :: any)[gateId] :: Gates.GateDefinition
	local billboard = Instance.new("BillboardGui")
	billboard.Name = `{instance.Name}Hint`
	billboard.Adornee = instance
	billboard.Size = Gates.HintSize
	billboard.StudsOffsetWorldSpace = Gates.HintOffset
	billboard.MaxDistance = Gates.HintMaxDistance
	billboard.LightInfluence = 0
	billboard.Enabled = false
	billboard:SetAttribute("WorldLabel", true)
	billboard:SetAttribute("WorldLabelPriority", 120)
	billboard.Parent = container
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Gates.HintColor
	label.TextStrokeTransparency = 0.2
	Localization.Bind(label, "Gate.LockedHint", function() return { hint = Localization.Translate(gate.hint) } end)
	label.Parent = billboard
	local barrier: Barrier = {
		part = instance,
		gateId = gateId,
		billboard = billboard,
		hintUntil = 0,
		touched = instance.Touched:Connect(function(hit: BasePart)
			local character = player.Character
			local now = os.clock()
			if character and hit:IsDescendantOf(character) and not canPass(gateId) and now - lastHintAt >= Gates.NotifyCooldown then
				lastHintAt = now
				for _, other in barriers do other.hintUntil = 0 apply(other) end
				local current = barriers[instance]
				if current then current.hintUntil = now + Gates.HintDuration apply(current) end
			end
		end),
	}
	barriers[instance] = barrier
	apply(barrier)
end

local function untrack(instance: Instance)
	local barrier = if instance:IsA("BasePart") then barriers[instance] else nil
	if barrier then
		barrier.touched:Disconnect()
		barrier.billboard:Destroy()
		barriers[instance :: BasePart] = nil
	end
end

local function refreshAll()
	for _, barrier in barriers do
		apply(barrier)
	end
end

function GateController:Init(): ()
	container = Instance.new("Folder")
	container.Name = "GateDisplays"
	-- In Workspace (client-only), not PlayerGui: PlayerGui is cleared on respawn.
	container.Parent = workspace
end

function GateController:Start(): ()
	CollectionService:GetInstanceAddedSignal(Gates.BarrierTag):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Gates.BarrierTag):Connect(untrack)
	for _, instance in CollectionService:GetTagged(Gates.BarrierTag) do
		track(instance)
	end
	player:GetAttributeChangedSignal(Gates.RebirthsAttribute):Connect(refreshAll)
	for _, pass in Monetization.Passes do
		player:GetAttributeChangedSignal(Monetization.PassAttributePrefix .. pass.key):Connect(refreshAll)
	end
	for _, definition in Upgrades.List do
		player:GetAttributeChangedSignal(Upgrades.LevelAttributePrefix .. definition.id):Connect(refreshAll)
	end
	RunService.Heartbeat:Connect(refreshAll)
end

return GateController


