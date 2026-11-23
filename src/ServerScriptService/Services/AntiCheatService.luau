--!strict
-- Server-side movement check for players carrying cats. Characters are simulated by their own client,
-- so a speed hack or teleport is only visible here. A carrier who moves much faster than their
-- WalkSpeed allows loses their cats: stolen cats go straight back to their owner's pillow, others are
-- dropped as usual.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Stealing = require(ReplicatedStorage.Shared.Config.Stealing)
local CarryService = require(script.Parent.CarryService)
local NotificationService = require(script.Parent.NotificationService)
local PillowService = require(script.Parent.PillowService)

type Track = {
	position: Vector3,
	at: number,
	strikes: number,
}

local AntiCheatService = {
	Priority = 67,
}

local tracks: { [Player]: Track } = {}
local graceUntil: { [Player]: number } = {}

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function punish(player: Player)
	warn(`[AntiCheatService] {player.Name} moved too fast while carrying; taking their cats`)
	for _, model in CarryService.GetCarried(player) do
		if PillowService.IsStolenBy(player, model) and CarryService.Release(player, model) then
			PillowService.ReturnHome(model)
		end
	end
	CarryService.DropAll(player, nil, false)
	NotificationService.Notify(player, "You moved too fast and dropped the cat!", "Error")
end

local function check()
	local now = os.clock()
	local carriers: { [Player]: true } = {}
	for _, player in CarryService.GetCarriers() do
		carriers[player] = true
	end

	for player in tracks do
		if not carriers[player] then
			tracks[player] = nil -- only carriers are tracked
		end
	end

	for player in carriers do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if root == nil or not root:IsA("BasePart") or humanoid == nil then
			continue
		end

		local track = tracks[player]
		if track == nil or now < (graceUntil[player] or 0) then
			tracks[player] = { position = root.Position, at = now, strikes = if track then track.strikes else 0 }
			continue
		end

		local elapsed = now - track.at
		local moved = flat(root.Position - track.position).Magnitude
		-- Per-player limit from the server's own numbers (saved Speed level + carry slowdown), never the
		-- client's Humanoid; the tolerance/slack stay global.
		local allowed = CarryService.GetExpectedWalkSpeed(player) * Stealing.SpeedTolerance * elapsed + Stealing.SpeedSlack
		if moved > allowed then
			track.strikes += 1
			if track.strikes >= Stealing.SpeedStrikesToDrop then
				tracks[player] = nil
				punish(player)
				continue
			end
		else
			track.strikes = 0
		end
		track.position = root.Position
		track.at = now
	end
end

-- Call before the server moves a player itself (push-outs, knockback) so it doesn't count as cheating.
function AntiCheatService.Grace(player: Player, seconds: number)
	graceUntil[player] = math.max(graceUntil[player] or 0, os.clock() + seconds)
	tracks[player] = nil
end

function AntiCheatService:Start(): ()
	Players.PlayerRemoving:Connect(function(player: Player)
		tracks[player] = nil
		graceUntil[player] = nil
	end)
	while true do
		task.wait(Stealing.SpeedCheckInterval)
		check()
	end
end

return AntiCheatService

