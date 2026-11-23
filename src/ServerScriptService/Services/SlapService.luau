--!strict
-- Slap: the nearest player in front of you within range is knocked back; if they carry cats they drop
-- them (own cats go back to their pillow, stolen cats run home, wild cats go wild).
-- The remote is rate-limited server-side; the client only says "I slapped".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Slap = require(ReplicatedStorage.Shared.Config.Slap)
local Network = require(ReplicatedStorage.Shared.Network)
local AntiCheatService = require(script.Parent.AntiCheatService)
local CarryService = require(script.Parent.CarryService)
local NotificationService = require(script.Parent.NotificationService)

local SlapService = {
	Priority = 75,
}

local lastSlapAt: { [Player]: number } = {}
-- Non-player slap targets (e.g. Dog Raid dogs). Return true if the slap hit something.
export type SlapTarget = (player: Player, origin: Vector3, look: Vector3, range: number, facingDot: number) -> boolean
local slapTargets: { [string]: SlapTarget } = {}

function SlapService.RegisterSlapTarget(name: string, handler: SlapTarget)
	slapTargets[name] = handler
end
local slapHitEvent: RemoteEvent
local slapEffectEvent: RemoteEvent

local function aliveRoot(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root
	end
	return nil
end

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function onSlap(player: Player, ...: any)
	if select("#", ...) ~= 0 then
		return
	end
	local now = os.clock()
	if now - (lastSlapAt[player] or 0) < Slap.Cooldown - Slap.CooldownTolerance then
		return
	end
	lastSlapAt[player] = now

	local root = aliveRoot(player)
	if root == nil then
		return
	end
	local look = flat(root.CFrame.LookVector).Unit

	local target: Player? = nil
	local targetRoot: BasePart? = nil
	local best = Slap.Range
	for _, other in Players:GetPlayers() do
		local otherRoot = if other ~= player then aliveRoot(other) else nil
		if otherRoot then
			local offset = flat(otherRoot.Position - root.Position)
			local distance = offset.Magnitude
			if distance <= best and distance > 0 and look:Dot(offset.Unit) >= Slap.FacingDot then
				best = distance
				target = other
				targetRoot = otherRoot
			end
		end
	end

	if target == nil or targetRoot == nil then
		for name, handler in slapTargets do
			local ok, hit = pcall(handler, player, root.Position, look, Slap.Range, Slap.FacingDot)
			if not ok then
				warn(`[SlapService] Slap target "{name}" failed: {tostring(hit)}`)
			elseif hit then
				return
			end
		end
		slapEffectEvent:FireAllClients(root.Position + look * (Slap.Range / 2), false)
		return
	end

	local direction = flat(targetRoot.Position - root.Position).Unit
	slapEffectEvent:FireAllClients(targetRoot.Position, true)
	AntiCheatService.Grace(target, Slap.KnockbackGrace)
	-- The target's client owns its character physics, so it applies the knockback itself.
	slapHitEvent:FireClient(target, direction * Slap.KnockbackSpeed + Vector3.new(0, Slap.KnockbackUp, 0))

	if #CarryService.GetCarried(target) > 0 then
		CarryService.DropAll(target, nil, false)
		NotificationService.Notify(target, `{player.DisplayName} slapped you and you dropped the cat!`, "Error")
		NotificationService.Notify(player, "Slap! They dropped the cat!", "Success")
	end
end

function SlapService:Init(): ()
	slapHitEvent = Network.GetEvent("SlapHit")
	slapEffectEvent = Network.GetEvent("SlapEffect")
end

-- Plays the shared "SLAP!" effect at a position (used by non-player targets).
function SlapService.PlayEffect(position: Vector3)
	slapEffectEvent:FireAllClients(position, true)
end

function SlapService:Start(): ()
	Network.GetEvent("Slap").OnServerEvent:Connect(onSlap)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastSlapAt[player] = nil
	end)
end

return SlapService

