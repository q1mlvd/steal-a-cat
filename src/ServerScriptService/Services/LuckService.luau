--!strict
-- The single place luck goes through (like MultiplierService for income). Sources multiply together.
-- See Config/Luck for how luck affects shared world spawns.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Luck = require(ReplicatedStorage.Shared.Config.Luck)
local ExclusiveShop = require(ReplicatedStorage.Shared.Config.ExclusiveShop)

export type LuckSource = (player: Player) -> number

local LuckService = {
	Priority = 13,
}

local sources: { [string]: LuckSource } = {}
local warned: { [string]: boolean } = {}
local serverBoost = 1
local serverBoostUntil = 0 -- os.clock()
local purchasedBoost = 1
local purchasedBoostUntil = 0 -- server-local effect; ends with this server, never restored from a buyer's save

local function mirrorServerBoost()
	local now = os.clock()
	local adminActive = now < serverBoostUntil
	local purchasedActive = now < purchasedBoostUntil
	local combined = (if adminActive then serverBoost else 1) * (if purchasedActive then purchasedBoost else 1)
	local remaining = math.max(0, serverBoostUntil - now, purchasedBoostUntil - now)
	workspace:SetAttribute("ServerLuck", combined)
	workspace:SetAttribute("ServerLuckEndsAt", if remaining > 0 then workspace:GetServerTimeNow() + remaining else nil)
	workspace:SetAttribute(ExclusiveShop.PurchasedLuckAttribute, if purchasedActive then purchasedBoost else 1)
	workspace:SetAttribute(ExclusiveShop.PurchasedLuckEndsAttribute,
		if purchasedActive then workspace:GetServerTimeNow() + purchasedBoostUntil - now else nil)
end

-- Server-wide luck boost for everyone (admin panel / events) for `seconds`.
function LuckService.SetServerBoost(multiplier: number, seconds: number)
	serverBoost = multiplier
	serverBoostUntil = os.clock() + seconds
	mirrorServerBoost()
end

-- Paid server luck extends time at a fixed multiplier; repeated purchases never multiply it again.
function LuckService.AddServerBoost(multiplier: number, seconds: number): boolean
	if multiplier ~= multiplier or multiplier < 1 or multiplier == math.huge
		or seconds ~= seconds or seconds <= 0 or seconds == math.huge then return false end
	purchasedBoost = multiplier
	purchasedBoostUntil = math.max(os.clock(), purchasedBoostUntil) + seconds
	mirrorServerBoost()
	return true
end

function LuckService.GetServerBoostState(): { [string]: number }
	local now = os.clock()
	local remaining = math.max(0, purchasedBoostUntil - now)
	return { multiplier = if remaining > 0 then purchasedBoost else 1, remaining = remaining,
		endsAt = if remaining > 0 then workspace:GetServerTimeNow() + remaining else 0 }
end

sources.ServerBoost = function(_player: Player): number
	return if os.clock() < serverBoostUntil then serverBoost else 1
end
sources.PurchasedServerBoost = function(_player: Player): number
	return if os.clock() < purchasedBoostUntil then purchasedBoost else 1
end

local function valid(value: unknown): boolean
	return type(value) == "number" and value == value and value > 0 and value < math.huge
end

function LuckService.RegisterLuckSource(name: string, source: LuckSource)
	sources[name] = source
	warned[name] = nil
end

function LuckService.UnregisterLuckSource(name: string)
	sources[name] = nil
end

-- Must not yield; sources must not yield.
function LuckService.GetLuckMultiplier(player: Player): number
	local multiplier = 1
	for name, source in sources do
		local ok, value = pcall(source, player)
		if ok and valid(value) then
			multiplier *= value :: number
		elseif not warned[name] then
			warned[name] = true
			warn(`[LuckService] Luck source "{name}" failed or returned an invalid value; ignoring it`)
		end
	end
	return math.clamp(multiplier, 1 / Luck.MaxMultiplier, Luck.MaxMultiplier)
end

-- Highest luck among living players within Luck.NearbyRadius of `point` (1 when nobody is near).
function LuckService.GetLuckNear(point: Vector3): number
	local best = 1
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0
			and (root.Position - point).Magnitude <= Luck.NearbyRadius then
			best = math.max(best, LuckService.GetLuckMultiplier(player))
		end
	end
	return best
end

function LuckService:Start(): ()
	-- Display mirror for UI.
	while true do
		mirrorServerBoost()
		for _, player in Players:GetPlayers() do
			player:SetAttribute(Luck.LuckAttribute, LuckService.GetLuckMultiplier(player))
		end
		task.wait(1)
	end
end

return LuckService

