--!strict
-- Collect feedback: a burst of coins from the bowl, a floating "+amount", a sound, and a HUD pulse.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Network = require(ReplicatedStorage.Shared.Network)
local NumberFormat = require(ReplicatedStorage.Shared.Util.NumberFormat)
local HudController = require(script.Parent.HudController)

local COIN_COUNT = 12
local COIN_SIZE = Vector3.new(0.3, 1.2, 1.2)
local COIN_COLOR = Color3.fromRGB(255, 200, 50)
local BURST_HEIGHT_MIN = 4
local BURST_HEIGHT_MAX = 8
local BURST_SPREAD = 4
local BURST_TIME = 0.5
local FADE_TIME = 0.3
local TEXT_RISE = 4
local TEXT_TIME = 1.2
local TEXT_COLOR = Color3.fromRGB(255, 225, 90)

local CoinEffectsController = {
	Priority = 50,
}

local random = Random.new()
local effectsFolder: Folder
local collectSound: Sound?

local function burst(origin: Vector3)
	for _ = 1, COIN_COUNT do
		local coin = Instance.new("Part")
		coin.Shape = Enum.PartType.Cylinder
		coin.Size = COIN_SIZE
		coin.Color = COIN_COLOR
		coin.Material = Enum.Material.Neon
		coin.Anchored = true
		coin.CanCollide = false
		coin.CanQuery = false
		coin.CanTouch = false
		coin.CastShadow = false
		coin.CFrame = CFrame.new(origin) * CFrame.Angles(0, random:NextNumber(0, 2 * math.pi), 0)
		coin.Parent = effectsFolder

		local target = origin + Vector3.new(
			random:NextNumber(-BURST_SPREAD, BURST_SPREAD),
			random:NextNumber(BURST_HEIGHT_MIN, BURST_HEIGHT_MAX),
			random:NextNumber(-BURST_SPREAD, BURST_SPREAD)
		)
		local fly = TweenService:Create(coin, TweenInfo.new(BURST_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(target) * CFrame.Angles(random:NextNumber(0, math.pi), random:NextNumber(0, math.pi), 0),
		})
		fly.Completed:Connect(function()
			local fade = TweenService:Create(coin, TweenInfo.new(FADE_TIME), { Transparency = 1, Size = COIN_SIZE * 0.3 })
			fade.Completed:Connect(function()
				coin:Destroy()
			end)
			fade:Play()
		end)
		fly:Play()
	end
end

local function floatingText(origin: Vector3, amount: number)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = origin + Vector3.new(0, 3, 0)
	anchor.Parent = effectsFolder

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(6, 1.6)
	billboard.LightInfluence = 0
	billboard.AlwaysOnTop = true
	billboard.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = TEXT_COLOR
	label.TextStrokeTransparency = 0.1
	label.Text = `+{NumberFormat.Format(amount)}`
	label.Parent = billboard

	TweenService:Create(anchor, TweenInfo.new(TEXT_TIME), { Position = anchor.Position + Vector3.new(0, TEXT_RISE, 0) }):Play()
	local fade = TweenService:Create(label, TweenInfo.new(TEXT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 })
	fade.Completed:Connect(function()
		anchor:Destroy()
	end)
	fade:Play()
end

function CoinEffectsController:Init(): ()
	effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "ClientEffects"
	effectsFolder.Parent = workspace

	if Economy.CollectSoundId ~= "" then
		local sound = Instance.new("Sound")
		sound.Name = "CollectSound"
		sound.SoundId = Economy.CollectSoundId
		sound.Parent = SoundService
		collectSound = sound
	end
end

function CoinEffectsController:Start(): ()
	Network.GetEvent("CoinsCollected").OnClientEvent:Connect(function(amount: unknown, position: unknown)
		if type(amount) ~= "number" or typeof(position) ~= "Vector3" then
			return
		end
		burst(position :: Vector3)
		floatingText(position :: Vector3, amount)
		if collectSound then
			SoundService:PlayLocalSound(collectSound)
		end
		HudController.Pulse()
	end)
end

return CoinEffectsController

