--!strict
-- Mutations income + Merge Machine.
-- * Per-cat income: "Mutation" (Shiny x2, Rainbow x5, Diamond x10, ...) and "Tier" (Mega x4, Giga x20)
--   are EconomyService cat income sources; they stack with Loyal and each other.
-- * Merge Machine (tag Mutations.MachineTag in each house): the owner's prompt opens a session and sends
--   the merge groups; MergeRequest(catId, tier) runs PillowService.MergeCats (one no-yield update).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local CatSchema = require(Config.CatSchema)
local Mutations = require(Config.Mutations)
local PlotPrompts = require(Config.PlotPrompts)
local Tags = require(Config.Tags)
local Network = require(ReplicatedStorage.Shared.Network)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local NotificationService = require(script.Parent.NotificationService)
local PillowService = require(script.Parent.PillowService)
local PlotService = require(script.Parent.PlotService)

local ATTR = CatSchema.Attributes

local MergeService = {
	Priority = 94,
}

type Session = { machine: BasePart, expiresAt: number }
local sessions: { [Player]: Session } = {}
local lastRequestAt: { [Player]: number } = {}
local openEvent: RemoteEvent

local function machineOf(player: Player): BasePart?
	local plot = PlotService.GetPlot(player)
	if plot == nil then
		return nil
	end
	for _, instance in CollectionService:GetTagged(Mutations.MachineTag) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(plot) then
			return instance
		end
	end
	return nil
end

local function near(player: Player, part: BasePart): boolean
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return root ~= nil and root:IsA("BasePart") and humanoid ~= nil and humanoid.Health > 0
		and (root.Position - part.Position).Magnitude <= Mutations.UseDistance
end

local function setupMachine(instance: Instance)
	if not instance:IsA("BasePart") or instance:FindFirstChild(Mutations.MachinePromptName) then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = Mutations.MachinePromptName
	prompt.ActionText = Mutations.MachineActionText
	prompt.ObjectText = "Merge Machine"
	prompt.KeyboardKeyCode = PlotPrompts.KeyCode
	prompt.GamepadKeyCode = PlotPrompts.GamepadKeyCode
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PlotPrompts.MaxDistance
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute(PlotPrompts.KindAttribute, PlotPrompts.Kinds.Merge)
	CollectionService:AddTag(prompt, Tags.PlotPrompt)
	prompt.Parent = instance
end

local function sendGroups(player: Player)
	openEvent:FireClient(player, PillowService.GetMergeGroups(player))
end

-- HUD entry point: preview is available anywhere. Executing a merge still requires the existing
-- server session, proximity and ownership checks in Request below.
function MergeService.OpenMenu(player: Player): boolean
	if player.Parent ~= Players or DataService.GetData(player) == nil then return false end
	local machine = machineOf(player)
	if machine and machine:IsDescendantOf(workspace) and near(player, machine) then
		sessions[player] = { machine = machine, expiresAt = os.clock() + Mutations.SessionDuration }
	else
		sessions[player] = nil
	end
	sendGroups(player)
	return true
end

function MergeService.Request(player: Player, catId: unknown, tier: unknown): (boolean, string)
	local now = os.clock()
	if now - (lastRequestAt[player] or -math.huge) < Mutations.RequestCooldown then
		return false, "Please wait."
	end
	lastRequestAt[player] = now
	if type(catId) ~= "string" or type(tier) ~= "string" or #catId > 40 or #tier > 20 then
		return false, "Invalid merge."
	end
	local session = sessions[player]
	if session == nil or now > session.expiresAt or machineOf(player) ~= session.machine or not near(player, session.machine) then
		return false, "Use the Merge Machine in your house."
	end
	local ok, message = PillowService.MergeCats(player, catId, tier)
	if ok then
		sendGroups(player) -- refresh the open UI
	end
	return ok, message
end

function MergeService:Init(): ()
	openEvent = Network.GetEvent("MergeOpen")
	EconomyService.RegisterCatIncomeSource("Mutation", function(_owner: Player, model: Model): number
		return Mutations.Multiplier(model:GetAttribute(ATTR.Mutation))
	end)
	EconomyService.RegisterCatIncomeSource("Tier", function(_owner: Player, model: Model): number
		return Mutations.GetTier(model:GetAttribute(ATTR.Tier)).multiplier
	end)
	for _, instance in CollectionService:GetTagged(Mutations.MachineTag) do
		setupMachine(instance)
	end
end

function MergeService:Start(): ()
	CollectionService:GetInstanceAddedSignal(Mutations.MachineTag):Connect(setupMachine)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt.Name ~= Mutations.MachinePromptName then
			return
		end
		local machine = prompt.Parent
		if machine == nil or not machine:IsA("BasePart") or machineOf(player) ~= machine or not near(player, machine) then
			return
		end
		sessions[player] = { machine = machine, expiresAt = os.clock() + Mutations.SessionDuration }
		sendGroups(player)
	end)
	Network.GetEvent("MergeRequest").OnServerEvent:Connect(function(player: Player, catId: unknown, tier: unknown)
		local ok, message = MergeService.Request(player, catId, tier)
		NotificationService.Notify(player, message, if ok then "Success" else "Error")
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		sessions[player] = nil
		lastRequestAt[player] = nil
	end)
end

return MergeService


