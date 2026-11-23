--!strict
-- House door lock: the owner presses the lock button; for LockDuration seconds an invisible barrier in
-- the doorway blocks other players (the owner's own client turns the barrier off locally so they can
-- pass), and any non-owner inside is pushed out. The push-out also stops clients that remove the
-- barrier on their side.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local CatSpawning = require(Config.CatSpawning)
local Doors = require(Config.Doors)
local GameConfig = require(Config.Game)
local PlotPrompts = require(Config.PlotPrompts)
local Tags = require(Config.Tags)
local Monetization = require(Config.Monetization)
local MonetizationService = require(script.Parent.MonetizationService)
local AntiCheatService = require(script.Parent.AntiCheatService)
local NotificationService = require(script.Parent.NotificationService)
local PlotService = require(script.Parent.PlotService)

type DoorState = {
	plot: Model,
	door: BasePart,
	barrier: BasePart,
	button: BasePart,
	doorColor: Color3,
	doorTransparency: number,
	lockedUntil: number, -- server time; 0 = unlocked
	cooldownUntil: number,
}

local DoorService = {
	Priority = 80,
}

local doors: { [Model]: DoorState } = {}

local function requirePart(plot: Model, name: string): BasePart
	local part = plot:FindFirstChild(name)
	if part == nil or not part:IsA("BasePart") then
		error(`[DoorService] {plot:GetFullName()} is missing BasePart "{name}"`)
	end
	return part
end

local function setLocked(state: DoorState, locked: boolean)
	state.barrier.CanCollide = locked
	state.door.Color = if locked then Doors.LockedDoorColor else state.doorColor
	state.door.Transparency = if locked then Doors.LockedDoorTransparency else state.doorTransparency
	if not locked then
		state.lockedUntil = 0
		state.plot:SetAttribute(Doors.LockedUntilAttribute, nil)
	end
end

local function reset(state: DoorState)
	setLocked(state, false)
	state.cooldownUntil = 0
	state.plot:SetAttribute(Doors.CooldownUntilAttribute, nil)
end

local function outsideCFrame(state: DoorState): CFrame
	-- The door's LookVector (-Z) faces the square, i.e. outside the house.
	local outward = state.door.CFrame.LookVector
	local position = state.door.Position + Vector3.new(outward.X, 0, outward.Z).Unit * Doors.PushOutDistance
	return CFrame.lookAt(position, position + Vector3.new(outward.X, 0, outward.Z))
end

local function pushOutIntruders(state: DoorState)
	local owner = PlotService.GetOwner(state.plot)
	for _, player in Players:GetPlayers() do
		if player ~= owner and PlotService.IsInsidePlot(player, state.plot) and player.Character then
			AntiCheatService.Grace(player, Doors.PushOutInterval * 2)
			player.Character:PivotTo(outsideCFrame(state))
			NotificationService.Notify(player, "This house is locked!", "Error")
		end
	end
end

local function tryLock(player: Player, state: DoorState)
	if PlotService.GetOwner(state.plot) ~= player then
		return
	end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") or (root.Position - state.button.Position).Magnitude > GameConfig.InteractionMaxDistance then
		return
	end

	local now = workspace:GetServerTimeNow()
	if now < state.lockedUntil then
		return
	end
	if now < state.cooldownUntil then
		NotificationService.Notify(player, `The lock is recharging ({math.ceil(state.cooldownUntil - now)}s).`, "Info")
		return
	end

	-- Super Lock pass: longer lock, shorter cooldown (cooldown counts from locking, as before).
	local superLock = MonetizationService.OwnsPass(player, "SuperLock")
	local duration = if superLock then Monetization.SuperLockDuration else Doors.LockDuration
	local cooldown = if superLock then Monetization.SuperLockDuration + Monetization.SuperLockCooldown else Doors.Cooldown
	state.lockedUntil = now + duration
	state.cooldownUntil = now + cooldown
	state.plot:SetAttribute(Doors.LockedUntilAttribute, state.lockedUntil)
	state.plot:SetAttribute(Doors.CooldownUntilAttribute, state.cooldownUntil)
	setLocked(state, true)
	pushOutIntruders(state)
	NotificationService.Notify(player, `Door locked for {duration} seconds!`, "Success")
end

function DoorService.IsLocked(plot: Model): boolean
	local state = doors[plot]
	return state ~= nil and workspace:GetServerTimeNow() < state.lockedUntil
end

function DoorService:Init(): ()
	if not PhysicsService:IsCollisionGroupRegistered(Doors.BarrierCollisionGroup) then
		PhysicsService:RegisterCollisionGroup(Doors.BarrierCollisionGroup)
	end
	-- Stolen cats running home must still get through a locked door.
	PhysicsService:CollisionGroupSetCollidable(Doors.BarrierCollisionGroup, CatSpawning.CollisionGroup, false)

	for _, plot in PlotService.GetPlots() do
		local door = requirePart(plot, "Door")
		local barrier = requirePart(plot, "DoorBarrier")
		local button = requirePart(plot, "LockButton")
		barrier.CollisionGroup = Doors.BarrierCollisionGroup

		local existing = button:FindFirstChild(Doors.PromptName)
		if existing then
			existing:Destroy()
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = Doors.PromptName
		prompt.ActionText = Doors.ActionText
		prompt.KeyboardKeyCode = PlotPrompts.KeyCode
		prompt.GamepadKeyCode = PlotPrompts.GamepadKeyCode
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = PlotPrompts.MaxDistance
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute(PlotPrompts.KindAttribute, PlotPrompts.Kinds.Lock)
		CollectionService:AddTag(prompt, Tags.PlotPrompt)
		prompt.Parent = button

		local state: DoorState = {
			plot = plot,
			door = door,
			barrier = barrier,
			button = button,
			doorColor = door.Color,
			doorTransparency = door.Transparency,
			lockedUntil = 0,
			cooldownUntil = 0,
		}
		doors[plot] = state
		reset(state)
	end
end

function DoorService:Start(): ()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt.Name ~= Doors.PromptName then
			return
		end
		local plot = prompt:FindFirstAncestorOfClass("Model")
		local state = if plot then doors[plot] else nil
		if state then
			tryLock(player, state)
		end
	end)
	PlotService.PlotReleased:Connect(function(_player: Player, plot: Model)
		local state = doors[plot]
		if state then
			reset(state)
		end
	end)

	while true do
		task.wait(Doors.PushOutInterval)
		local now = workspace:GetServerTimeNow()
		for _, state in doors do
			if state.lockedUntil > 0 then
				if now >= state.lockedUntil then
					setLocked(state, false)
				else
					pushOutIntruders(state)
				end
			end
		end
	end
end

return DoorService

