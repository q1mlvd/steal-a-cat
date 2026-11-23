--!strict
-- Victim side of a steal: a pulsing warning, a "THIEF!" marker over the thief, and an arrow around the
-- screen centre pointing at them until the server says the steal is over.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Localization = require(ReplicatedStorage.Shared.Util.Localization)
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Network = require(ReplicatedStorage.Shared.Network)

local ALERT_COLOR = Color3.fromRGB(255, 60, 60)
local ARROW_RADIUS = 140 -- pixels from screen centre
local ARROW_SIZE = 56
local PULSE_TIME = 0.4
local MARKER_SIZE = UDim2.fromOffset(120, 40)
local MARKER_OFFSET = Vector3.new(0, 3.5, 0)

local StealAlertController = {
	Priority = 40,
}

local player = Players.LocalPlayer
local gui: ScreenGui
local warning: TextLabel
local arrow: TextLabel
local marker: BillboardGui
local thief: Player? = nil
local renderConnection: RBXScriptConnection? = nil

local function stop()
	thief = nil
	gui.Enabled = false
	marker.Adornee = nil
	marker.Enabled = false
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
end

local function update()
	local target = thief
	local character = if target then target.Character else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local camera = workspace.CurrentCamera
	if root == nil or not root:IsA("BasePart") or camera == nil then
		arrow.Visible = false
		return
	end
	marker.Adornee = root
	marker.Enabled = true

	-- Angle of the thief around the camera's forward axis, flattened onto the ground plane.
	local cameraCFrame = camera.CFrame
	local offset = root.Position - cameraCFrame.Position
	local forward = Vector3.new(cameraCFrame.LookVector.X, 0, cameraCFrame.LookVector.Z).Unit
	local right = Vector3.new(cameraCFrame.RightVector.X, 0, cameraCFrame.RightVector.Z).Unit
	local angle = math.atan2(offset:Dot(right), offset:Dot(forward))
	arrow.Visible = true
	arrow.Position = UDim2.new(0.5, math.sin(angle) * ARROW_RADIUS, 0.5, -math.cos(angle) * ARROW_RADIUS)
	arrow.Rotation = math.deg(angle)
end

local function start(newThief: Player, catName: string)
	thief = newThief
	warning.Text = Localization.T("Steal.Warning", {cat = Localization.Translate(catName)})
	gui.Enabled = true
	if renderConnection == nil then
		renderConnection = RunService.RenderStepped:Connect(update)
	end
end

function StealAlertController:Init(): ()
	gui = Instance.new("ScreenGui")
	gui.Name = "StealAlert"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.Enabled = false

	warning = Instance.new("TextLabel")
	warning.AnchorPoint = Vector2.new(0.5, 0)
	warning.Position = UDim2.new(0.5, 0, 0, 140)
	warning.Size = UDim2.new(0.8, 0, 0, 40)
	warning.BackgroundTransparency = 1
	warning.Font = Enum.Font.FredokaOne
	warning.TextScaled = true
	warning.TextColor3 = ALERT_COLOR
	warning.TextStrokeTransparency = 0
	warning.Parent = gui
	TweenService:Create(warning, TweenInfo.new(PULSE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		TextTransparency = 0.5,
	}):Play()

	arrow = Instance.new("TextLabel")
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Size = UDim2.fromOffset(ARROW_SIZE, ARROW_SIZE)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBlack
	arrow.Text = "▲"
	arrow.TextScaled = true
	arrow.TextColor3 = ALERT_COLOR
	arrow.TextStrokeTransparency = 0
	arrow.Parent = gui

	marker = Instance.new("BillboardGui")
	marker.Name = "ThiefMarker"
	marker.ResetOnSpawn = false
	marker.Size = MARKER_SIZE
	marker.StudsOffsetWorldSpace = MARKER_OFFSET
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.Enabled = false
	local markerLabel = Instance.new("TextLabel")
	markerLabel.Size = UDim2.fromScale(1, 1)
	markerLabel.BackgroundTransparency = 1
	markerLabel.Font = Enum.Font.FredokaOne
	Localization.Bind(markerLabel, "Steal.Thief")
	markerLabel.TextScaled = true
	markerLabel.TextColor3 = ALERT_COLOR
	markerLabel.TextStrokeTransparency = 0
	markerLabel.Parent = marker

	local playerGui = player:WaitForChild("PlayerGui")
	marker.Parent = playerGui
	gui.Parent = playerGui
end

function StealAlertController:Start(): ()
	Network.GetEvent("StealAlert").OnClientEvent:Connect(function(active: unknown, newThief: unknown, catName: unknown)
		if active == true and typeof(newThief) == "Instance" and (newThief :: Instance):IsA("Player") then
			start(newThief :: Player, if type(catName) == "string" then catName else Localization.T("Common.Cat"))
		else
			stop()
		end
	end)
end

return StealAlertController


