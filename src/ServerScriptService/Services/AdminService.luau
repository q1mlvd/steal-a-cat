--!strict
-- Admin panel commands. Every command checks IsAdmin on the server (Config/Admin user ids + the creator).
--   event <name> | stopevent | spawncat <catId> <mutation> | secretrain <count> | luck <multiplier> <minutes>

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local Admin = require(Config.Admin)
local Cats = require(Config.Cats)
local Mutations = require(Config.Mutations)
local Network = require(ReplicatedStorage.Shared.Network)
local CatSpawnService = require(script.Parent.CatSpawnService)
local EventService = require(script.Parent.EventService)
local LuckService = require(script.Parent.LuckService)
local NotificationService = require(script.Parent.NotificationService)

local AdminService = {
	Priority = 97,
}

local lastCommandAt: { [Player]: number } = {}

function AdminService.IsAdmin(player: Player): boolean
	if table.find(Admin.UserIds, player.UserId) then
		return true
	end
	if Admin.IncludeCreator and game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	return false
end

local function finite(value: unknown, minimum: number, maximum: number): number?
	if type(value) ~= "number" or value ~= value then
		return nil
	end
	return math.clamp(value, minimum, maximum)
end

function AdminService.Run(player: Player, command: unknown, arg1: unknown, arg2: unknown): (boolean, string)
	if not AdminService.IsAdmin(player) then
		return false, "Not allowed."
	end
	if command == "event" and type(arg1) == "string" then
		local started = EventService.StartEvent(arg1)
		return started, if started then `Event {arg1} started.` else "Unknown event."
	elseif command == "stopevent" then
		EventService.StopEvent()
		return true, "Event stopped."
	elseif command == "spawncat" and type(arg1) == "string" then
		local catDef = Cats.Get(arg1)
		local mutation = if type(arg2) == "string" and Mutations.IsValid(arg2) then arg2 else ""
		if catDef == nil then
			return false, "Unknown cat."
		end
		local model: Model? = nil
		if catDef.rarity == "Secret" then
			if CatSpawnService.ForceSecret(1) > 0 then
				NotificationService.Announce("An admin released a Secret cat!")
			end
			return true, "Secret cat spawned (mutation not applied to Secret spawns)."
		end
		model = CatSpawnService.SpawnBonusCat(catDef.rarity, Admin.SpawnCatMax, catDef.id)
		if model == nil then
			return false, "No spawn point or too many bonus cats."
		end
		model:SetAttribute("Mutation", mutation)
		return true, `Spawned {mutation} {catDef.name}.`
	elseif command == "secretrain" then
		local count = finite(arg1, 1, Admin.SecretRainMax) or 1
		local spawned = CatSpawnService.ForceSecret(math.floor(count))
		NotificationService.Announce(`Secret cat rain! {spawned} Secret cats appeared!`)
		return true, `{spawned} Secret cats spawned.`
	elseif command == "luck" then
		local multiplier = finite(arg1, 1, Admin.ServerLuckMax)
		local minutes = finite(arg2, 1, Admin.ServerLuckMaxMinutes)
		if multiplier == nil or minutes == nil then
			return false, "luck <multiplier> <minutes>"
		end
		LuckService.SetServerBoost(multiplier, minutes * 60)
		NotificationService.Announce(`Server luck x{multiplier} for {minutes} minutes!`)
		return true, "Server luck set."
	end
	return false, "Unknown command."
end

function AdminService:Start(): ()
	local function mark(player: Player)
		player:SetAttribute(Admin.Attribute, if AdminService.IsAdmin(player) then true else nil)
	end
	Players.PlayerAdded:Connect(mark)
	for _, player in Players:GetPlayers() do
		mark(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		lastCommandAt[player] = nil
	end)
	Network.GetEvent("AdminCommand").OnServerEvent:Connect(function(player: Player, command: unknown, arg1: unknown, arg2: unknown)
		local now = os.clock()
		if now - (lastCommandAt[player] or -math.huge) < Admin.CommandCooldown then
			return
		end
		lastCommandAt[player] = now
		local ok, message = AdminService.Run(player, command, arg1, arg2)
		if AdminService.IsAdmin(player) then
			NotificationService.Notify(player, message, if ok then "Success" else "Error")
		end
	end)
end

return AdminService

