--!strict
-- Locked areas (Config/Gates): Rooftops need Jump level 3, Sewers need at least one rebirth.
-- Barriers are solid on the server; a qualified player's client turns them off locally (GateController).
-- Every CheckInterval the server moves non-qualified players out of gate areas and barrier volumes, so
-- deleting a barrier on the client gains nothing.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local CatSpawning = require(Config.CatSpawning)
local Gates = require(Config.Gates)
local AntiCheatService = require(script.Parent.AntiCheatService)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local NotificationService = require(script.Parent.NotificationService)
local UpgradeService = require(script.Parent.UpgradeService)

local GateService = {
	Priority = 90,
}

local lastNotifyAt: { [Player]: number } = {}

local function gateIdOf(part: Instance): string?
	local id = part:GetAttribute(Gates.GateIdAttribute)
	return if type(id) == "string" and Gates.Gates[id] ~= nil then id else nil
end

local function rebirthsOf(player: Player): number
	local data = DataService.GetData(player)
	local rebirths = if data then data.rebirths else nil
	return if type(rebirths) == "number" and rebirths == rebirths and rebirths >= 0 then math.floor(rebirths) else 0
end

-- Server truth from saved data: upgrade level and rebirths.
function GateService.CanPass(player: Player, gateId: string): boolean
	local gate = (Gates.Gates :: any)[gateId] :: Gates.GateDefinition?
	if gate == nil or DataService.GetData(player) == nil then
		return false
	end
	if gate.requiredUpgrade and UpgradeService.GetLevel(player, gate.requiredUpgrade) < (gate.requiredLevel or 0) then
		return false
	end
	if gate.requiredRebirths and rebirthsOf(player) < gate.requiredRebirths then
		return false
	end
	if gate.requiredPass and not MonetizationService.OwnsPass(player, gate.requiredPass) then
		return false
	end
	return true
end

-- Re-mirrors the rebirth count after it changes (RebirthService).
function GateService.Refresh(player: Player)
	player:SetAttribute(Gates.RebirthsAttribute, rebirthsOf(player))
end

local function inside(part: BasePart, position: Vector3): boolean
	local localPosition = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(localPosition.X) <= half.X and math.abs(localPosition.Y) <= half.Y and math.abs(localPosition.Z) <= half.Z
end

local function nearestExit(gateId: string, position: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, exit in CollectionService:GetTagged(Gates.ExitTag) do
		if exit:IsA("BasePart") and gateIdOf(exit) == gateId then
			local distance = (exit.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = exit, distance
			end
		end
	end
	return best
end

local function notifyHint(player: Player, gateId: string)
	local now = os.clock()
	if now - (lastNotifyAt[player] or -math.huge) < Gates.NotifyCooldown then
		return
	end
	lastNotifyAt[player] = now
	NotificationService.Notify(player, (Gates.Gates :: any)[gateId].hint, "Error")
end

local function eject(player: Player, character: Model, gateId: string, position: Vector3)
	local exit = nearestExit(gateId, position)
	if exit == nil then
		return
	end
	AntiCheatService.Grace(player, Gates.CheckInterval * 2)
	character:PivotTo(CFrame.new(exit.Position + Vector3.new(0, Gates.ExitLift, 0)) * exit.CFrame.Rotation)
	notifyHint(player, gateId)
end

local function check()
	local volumes: { BasePart } = {}
	for _, tag in { Gates.AreaTag, Gates.BarrierTag } do
		for _, part in CollectionService:GetTagged(tag) do
			if part:IsA("BasePart") and gateIdOf(part) and part:IsDescendantOf(workspace) then
				table.insert(volumes, part)
			end
		end
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if character == nil or root == nil or not root:IsA("BasePart") or humanoid == nil or humanoid.Health <= 0 then
			continue
		end
		for _, volume in volumes do
			local gateId = gateIdOf(volume) :: string
			if inside(volume, root.Position) and not GateService.CanPass(player, gateId) then
				eject(player, character, gateId, root.Position)
				break
			end
		end
	end
end

local function setupBarrier(part: Instance)
	if not part:IsA("BasePart") or gateIdOf(part) == nil then
		return
	end
	part.Anchored = true
	part.CanCollide = true
	part.CollisionGroup = Gates.CollisionGroup
	part.Transparency = (Gates.Gates :: any)[gateIdOf(part) :: string].barrierTransparency
	-- Cat return paths may pass through: cats don't collide with this group.
	if part:FindFirstChildOfClass("PathfindingModifier") == nil then
		local modifier = Instance.new("PathfindingModifier")
		modifier.PassThrough = true
		modifier.Parent = part
	end
	-- Hint when a blocked player walks into it (the client also shows a billboard).
	part.Touched:Connect(function(hit: BasePart)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = if character then Players:GetPlayerFromCharacter(character) else nil
		local gateId = gateIdOf(part)
		if player and gateId and not GateService.CanPass(player, gateId) then
			notifyHint(player, gateId)
		end
	end)
end

local function mirrorRebirths(player: Player)
	player:SetAttribute(Gates.RebirthsAttribute, rebirthsOf(player))
end

function GateService:Init(): ()
	if not PhysicsService:IsCollisionGroupRegistered(Gates.CollisionGroup) then
		PhysicsService:RegisterCollisionGroup(Gates.CollisionGroup)
	end
	PhysicsService:CollisionGroupSetCollidable(Gates.CollisionGroup, CatSpawning.CollisionGroup, false)
	for _, part in CollectionService:GetTagged(Gates.BarrierTag) do
		setupBarrier(part)
	end
end

function GateService:Start(): ()
	CollectionService:GetInstanceAddedSignal(Gates.BarrierTag):Connect(setupBarrier)
	DataService.DataLoaded:Connect(mirrorRebirths)
	for _, player in Players:GetPlayers() do
		if DataService.GetData(player) then
			mirrorRebirths(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		lastNotifyAt[player] = nil
	end)
	while true do
		task.wait(Gates.CheckInterval)
		check()
	end
end

return GateService

