--!strict
-- Sounds from Config/Sounds ("" = placeholder, skipped). Volumes follow the saved settings
-- (Setting_SfxVolume / Setting_MusicVolume). Hooks existing events: catch result, steal alarm, slap,
-- purchases (Success notifications), homecoming, UI clicks; purr loops near your own seated cats.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = ReplicatedStorage.Shared.Config
local CatSchema = require(Config.CatSchema)
local Sounds = require(Config.Sounds)
local Tags = require(Config.Tags)
local Network = require(ReplicatedStorage.Shared.Network)

local ATTR = CatSchema.Attributes

local SoundController = {
	Priority = 4,
}

local player = Players.LocalPlayer
local effects: { [string]: Sound } = {}
local music: Sound? = nil
local purrs: { [Model]: Sound } = {}

local function sfxVolume(): number
	local value = player:GetAttribute("Setting_SfxVolume")
	return if type(value) == "number" then value else Sounds.DefaultSfxVolume
end

local function musicVolume(): number
	local value = player:GetAttribute("Setting_MusicVolume")
	return if type(value) == "number" then value else Sounds.DefaultMusicVolume
end

function SoundController.Play(key: string)
	local sound = effects[key]
	local entry = (Sounds.Effects :: any)[key]
	if sound == nil or entry == nil then return end
	sound.Volume = entry.volume * sfxVolume()
	SoundService:PlayLocalSound(sound)
end

function SoundController.PlayId(id: string, volume: number)
	if id == "" then return end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume * sfxVolume()
	sound.Parent = SoundService
	SoundService:PlayLocalSound(sound)
	task.delay(5, function() sound:Destroy() end)
end

local function applyVolumes()
	if music then music.Volume = musicVolume() end
	for _, sound in purrs do sound.Volume = Sounds.PurrVolume * sfxVolume() end
end

local function trackPurr(instance: Instance)
	if Sounds.Purr == "" or not instance:IsA("Model") then return end
	local model = instance
	local function update()
		local mine = model:GetAttribute(ATTR.OwnerUserId) == player.UserId and model:GetAttribute(ATTR.State) == CatSchema.States.OnPillow
		local existing = purrs[model]
		if mine and existing == nil then
			local root = model:FindFirstChild("HumanoidRootPart")
			if root then
				local sound = Instance.new("Sound")
				sound.SoundId = Sounds.Purr
				sound.Looped = true
				sound.RollOffMaxDistance = Sounds.PurrDistance
				sound.Volume = Sounds.PurrVolume * sfxVolume()
				sound.Parent = root
				sound:Play()
				purrs[model] = sound
			end
		elseif not mine and existing then
			existing:Destroy()
			purrs[model] = nil
		end
	end
	model:GetAttributeChangedSignal(ATTR.State):Connect(update)
	model:GetAttributeChangedSignal(ATTR.OwnerUserId):Connect(update)
	update()
end

function SoundController:Init(): ()
	for key, entry in Sounds.Effects do
		if entry.id ~= "" then
			local sound = Instance.new("Sound")
			sound.Name = key
			sound.SoundId = entry.id
			sound.Volume = entry.volume
			sound.Parent = SoundService
			effects[key] = sound
		end
	end
	if Sounds.Music ~= "" then
		local sound = Instance.new("Sound")
		sound.Name = "Music"
		sound.SoundId = Sounds.Music
		sound.Looped = true
		sound.Volume = musicVolume()
		sound.Parent = SoundService
		music = sound
	end
end

function SoundController:Start(): ()
	if music then music:Play() end
	player:GetAttributeChangedSignal("Setting_SfxVolume"):Connect(applyVolumes)
	player:GetAttributeChangedSignal("Setting_MusicVolume"):Connect(applyVolumes)
	Network.GetEvent("CatchResult").OnClientEvent:Connect(function(_id: unknown, success: unknown)
		SoundController.Play(if success == true then "CatchSuccess" else "CatchFail")
	end)
	Network.GetEvent("StealAlert").OnClientEvent:Connect(function(active: unknown)
		if active == true then SoundController.Play("StealAlarm") end
	end)
	Network.GetEvent("SlapEffect").OnClientEvent:Connect(function(_position: unknown, hit: unknown)
		if hit == true then SoundController.Play("Slap") end
	end)
	Network.GetEvent("Notify").OnClientEvent:Connect(function(message: unknown, style: unknown)
		if style == "Homecoming" then
			SoundController.Play("Homecoming")
		elseif style == "Success" and type(message) == "string"
			and (string.find(message, "Bought", 1, true) or string.find(message, "upgraded", 1, true) or string.find(message, "Thanks", 1, true)) then
			SoundController.Play("Purchase")
		end
	end)
	CollectionService:GetInstanceAddedSignal(Tags.Cat):Connect(trackPurr)
	for _, instance in CollectionService:GetTagged(Tags.Cat) do trackPurr(instance) end
end

return SoundController

