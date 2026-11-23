--!strict
-- Game feel: camera shake, screen confetti, heart bursts. Low graphics mode (Setting_LowGraphics) skips
-- particles/confetti but keeps the gameplay feedback (shake is small and cheap).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Network = require(ReplicatedStorage.Shared.Network)
local PlotPrompts = require(ReplicatedStorage.Shared.Config.PlotPrompts)

local JuiceController = {
	Priority = 3,
}

local CONFETTI_COLORS = { Color3.fromRGB(255, 95, 145), Color3.fromRGB(255, 225, 85), Color3.fromRGB(85, 225, 255), Color3.fromRGB(120, 255, 140) }
local player = Players.LocalPlayer
local gui: ScreenGui
local shakeUntil = 0
local shakeStrength = 0
local random = Random.new()

function JuiceController.IsLowGraphics(): boolean
	return player:GetAttribute("Setting_LowGraphics") == true
end

-- Camera shake for `duration` seconds (strength in studs).
function JuiceController.Shake(strength: number, duration: number)
	shakeStrength = math.max(shakeStrength, strength)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
end

-- Screen confetti burst.
function JuiceController.Confetti(count: number?)
	if JuiceController.IsLowGraphics() then return end
	local camera = workspace.CurrentCamera
	if camera == nil then return end
	local size = camera.ViewportSize
	for _ = 1, count or 50 do
		local piece = Instance.new("Frame")
		piece.BorderSizePixel = 0
		piece.Size = UDim2.fromOffset(random:NextInteger(8, 14), random:NextInteger(12, 20))
		piece.BackgroundColor3 = CONFETTI_COLORS[random:NextInteger(1, #CONFETTI_COLORS)]
		piece.Position = UDim2.fromOffset(size.X / 2 + random:NextNumber(-60, 60), size.Y * 0.35)
		piece.Rotation = random:NextNumber(0, 360)
		piece.Parent = gui
		local target = UDim2.fromOffset(size.X / 2 + random:NextNumber(-size.X * 0.45, size.X * 0.45), size.Y + 40)
		local duration = random:NextNumber(1.6, 2.6)
		TweenService:Create(piece, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = target, Rotation = piece.Rotation + random:NextNumber(-540, 540), BackgroundTransparency = 0.4 }):Play()
		task.delay(duration, function() piece:Destroy() end)
	end
end

-- Hearts rising from a world position (petting).
function JuiceController.Hearts(position: Vector3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = workspace
	local count = if JuiceController.IsLowGraphics() then 1 else 5
	for index = 1, count do
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(36, 36)
		billboard.LightInfluence = 0
		billboard.AlwaysOnTop = true
		billboard.StudsOffset = Vector3.new(random:NextNumber(-1.2, 1.2), 1, 0)
		billboard.Parent = anchor
		local heart = Instance.new("TextLabel")
		heart.BackgroundTransparency = 1
		heart.Size = UDim2.fromScale(1, 1)
		heart.TextScaled = true
		heart.Text = "\u{2764}"
		heart.TextColor3 = Color3.fromRGB(255, 95, 145)
		heart.Parent = billboard
		local delay = (index - 1) * 0.12
		task.delay(delay, function()
			TweenService:Create(billboard, TweenInfo.new(1.2), { StudsOffset = billboard.StudsOffset + Vector3.new(0, 4, 0) }):Play()
			TweenService:Create(heart, TweenInfo.new(1.2), { TextTransparency = 1 }):Play()
		end)
	end
	task.delay(2, function() anchor:Destroy() end)
end

function JuiceController:Init(): ()
	gui = Instance.new("ScreenGui")
	gui.Name = "Juice"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 45
	gui.Parent = player:WaitForChild("PlayerGui")
end

function JuiceController:Start(): ()
	RunService:BindToRenderStep("JuiceShake", Enum.RenderPriority.Camera.Value + 1, function()
		local now = os.clock()
		local camera = workspace.CurrentCamera
		if camera == nil or now >= shakeUntil then
			shakeStrength = 0
			return
		end
		local fade = math.clamp((shakeUntil - now) * 4, 0, 1)
		local s = shakeStrength * fade
		camera.CFrame *= CFrame.new(random:NextNumber(-s, s), random:NextNumber(-s, s), 0)
	end)
	-- Hearts when you pet a cat (local prompt trigger; the server still validates the pet).
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt:GetAttribute(PlotPrompts.KindAttribute) == PlotPrompts.Kinds.Pet then
			local parent = prompt.Parent
			if parent and parent:IsA("BasePart") then
				JuiceController.Hearts(parent.Position)
			end
		end
	end)
	-- A stolen cat coming home gets a celebration.
	Network.GetEvent("Notify").OnClientEvent:Connect(function(_message: unknown, style: unknown)
		if style == "Homecoming" then
			JuiceController.Confetti(40)
		end
	end)
end

return JuiceController

