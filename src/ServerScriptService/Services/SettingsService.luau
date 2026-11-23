--!strict
-- Player settings (PlayerData.settings): music/SFX volume, low graphics, tutorial and hotbar preferences.
-- Mirrored as player attributes Setting_MusicVolume / Setting_SfxVolume / Setting_LowGraphics / TutorialDone
-- for the client controllers. Updates are validated and rate-limited.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Network = require(ReplicatedStorage.Shared.Network)
local DataService = require(script.Parent.DataService)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Shop = require(ReplicatedStorage.Shared.Config.Shop)
local ItemInventory = require(ReplicatedStorage.Shared.Util.ItemInventory)

local SettingsService = {
	Priority = 101,
}

local UPDATE_COOLDOWN = Items.Hotbar.SettingsCooldown
local lastUpdateAt: { [Player]: number } = {}

local function mirror(player: Player)
	local data = DataService.GetData(player)
	if data == nil then return end
	local settings = data.settings
	player:SetAttribute("Setting_MusicVolume", settings.musicVolume)
	player:SetAttribute("Setting_SfxVolume", settings.sfxVolume)
	player:SetAttribute("Setting_LowGraphics", settings.lowGraphics)
	player:SetAttribute("TutorialDone", settings.tutorialDone)
	player:SetAttribute(Items.Hotbar.SettingsAttribute, HttpService:JSONEncode(settings.hotbarSlots))
end

local function hotbarSlots(data: any, value: unknown): { string }?
	if type(value) ~= "table" then return nil end
	local result: { string } = {}
	local seen: { [string]: boolean } = {}
	for index = 1, Items.Hotbar.SlotCount do
		local id = value[index]
		if id == nil or id == "" then
			result[index] = ""
		elseif type(id) == "string" and #id <= Shop.MaxIdLength and not seen[id] and ItemInventory.Usable(id) then
			local count = data.inventory[id]
			local armed = (id == "Fish" and data.inventory[Shop.FishReadyInventoryKey] == 1)
				or (id == "SoftPaws" and data.inventory[Shop.SoftPawsReadyInventoryKey] == 1)
			if not ((type(count) == "number" and count > 0) or armed) then return nil end
			result[index] = id
			seen[id] = true
		else
			return nil
		end
	end
	return result
end

local function volume(value: unknown): number?
	if type(value) ~= "number" or value ~= value then return nil end
	return math.clamp(math.floor(value * 100 + 0.5) / 100, 0, 1)
end

function SettingsService.Update(player: Player, changes: unknown): boolean
	local data = DataService.GetData(player)
	if data == nil or type(changes) ~= "table" then return false end
	local now = os.clock()
	if now - (lastUpdateAt[player] or -math.huge) < UPDATE_COOLDOWN then return false end
	lastUpdateAt[player] = now
	local input = changes :: { [string]: any }
	local slots = if input.hotbarSlots ~= nil then hotbarSlots(data, input.hotbarSlots) else nil
	if input.hotbarSlots ~= nil and slots == nil then return false end
	local music = volume(input.musicVolume)
	local sfx = volume(input.sfxVolume)
	if music then data.settings.musicVolume = music end
	if sfx then data.settings.sfxVolume = sfx end
	if type(input.lowGraphics) == "boolean" then data.settings.lowGraphics = input.lowGraphics end
	if input.hotbarSlots ~= nil then
		data.settings.hotbarSlots = slots :: { string }
	end
	mirror(player)
	if input.hotbarSlots ~= nil then DataService.SaveNow(player) end
	return true
end

function SettingsService:Start(): ()
	DataService.DataLoaded:Connect(mirror)
	for _, player in Players:GetPlayers() do mirror(player) end
	Players.PlayerRemoving:Connect(function(player: Player) lastUpdateAt[player] = nil end)
	Network.GetEvent("SettingsUpdate").OnServerEvent:Connect(function(player: Player, changes: unknown)
		SettingsService.Update(player, changes)
	end)
	Network.GetEvent("TutorialComplete").OnServerEvent:Connect(function(player: Player)
		local data = DataService.GetData(player)
		if data and not data.settings.tutorialDone then
			data.settings.tutorialDone = true
			mirror(player)
			DataService.SaveNow(player)
		end
	end)
end

return SettingsService


