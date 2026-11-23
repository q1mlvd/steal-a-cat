--!strict
-- Slap input (F / gamepad Y / on-screen button on touch devices), local cooldown display, knockback
-- when we get slapped, and the "SLAP!" effect for everyone. The server validates every slap.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Localization = require(ReplicatedStorage.Shared.Util.Localization)
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Slap = require(ReplicatedStorage.Shared.Config.Slap)
local Network = require(ReplicatedStorage.Shared.Network)
local Shop = require(ReplicatedStorage.Shared.Config.Shop)
local InputModeController = require(script.Parent.InputModeController)
local JuiceController = require(script.Parent.JuiceController)

local ACTION_NAME = "Slap"
local TOUCH_BUTTON_POSITION = UDim2.new(1, -150, 1, -150)
local KNOCKDOWN_TIME = 0.6
local EFFECT_TIME = 0.7
local EFFECT_RISE = 3
local HIT_COLOR = Color3.fromRGB(255, 220, 80)
local MISS_COLOR = Color3.fromRGB(220, 220, 220)

local SlapController = {
	Priority = 60,
}

local player = Players.LocalPlayer
local slapEvent: RemoteEvent
local lastSlapAt = 0
local effectsFolder: Folder
local slapSound: Sound?
local touchButton: GuiButton? = nil
local touchParentConnections: { RBXScriptConnection } = {}
local viewportConnection: RBXScriptConnection? = nil
local boundWithTouchButton: boolean? = nil

local function findTouchButton(): GuiButton?
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local contextGui = if playerGui then playerGui:FindFirstChild("ContextActionGui") else nil
	local frame = if contextGui then contextGui:FindFirstChild("ContextButtonFrame") else nil
	if frame == nil then return nil end
	for _, instance in frame:GetChildren() do
		if instance:IsA("GuiButton") then
			local title = instance:FindFirstChild("ActionTitle")
			if title and title:IsA("TextLabel") and title.Text == Localization.T("Slap.Button") then
				return instance
			end
		end
	end
	return nil
end

local function updateTouchPosition()
	local camera = workspace.CurrentCamera
	local button = touchButton
	if not InputModeController.IsTouch() or camera == nil or button == nil or button.Parent == nil then
		return
	end
	local parent = button.Parent
	if not parent:IsA("GuiObject") then return end
	-- ContextActionService positions within its lower-right ContextButtonFrame.
	-- Subtract that frame's live origin to place the button at our screen target.
	local desired = Vector2.new(camera.ViewportSize.X - Shop.Ui.MobileSlapRight, Shop.Ui.MobileSlapTop)
	local offset = desired - parent.AbsolutePosition
	ContextActionService:SetPosition(ACTION_NAME, UDim2.fromOffset(offset.X, offset.Y))
end

local function observeTouchButton()
	if touchButton and touchButton.Parent then
		updateTouchPosition()
		return
	end
	local found = findTouchButton()
	if found == nil then return end
	touchButton = found
	for _, connection in touchParentConnections do connection:Disconnect() end
	table.clear(touchParentConnections)
	local parent = found.Parent
	if parent and parent:IsA("GuiObject") then
		table.insert(touchParentConnections, parent:GetPropertyChangedSignal("AbsolutePosition"):Connect(updateTouchPosition))
		table.insert(touchParentConnections, parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateTouchPosition))
	end
	table.insert(touchParentConnections, found.AncestryChanged:Connect(function()
		if found.Parent == nil then touchButton = nil end
		observeTouchButton()
	end))
	updateTouchPosition()
end

local function inputIsReserved(): boolean
	if UserInputService:GetFocusedTextBox() ~= nil then
		return true
	end
	if player:GetAttribute(Shop.UiStateAttribute) == true then
		return true
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local catchGui = if playerGui then playerGui:FindFirstChild(Shop.CatchGuiName) else nil
	return catchGui ~= nil and catchGui:IsA("ScreenGui") and catchGui.Enabled
end

local function onAction(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if UserInputService:GetFocusedTextBox() ~= nil then
		return Enum.ContextActionResult.Pass
	end
	if inputIsReserved() then
		return Enum.ContextActionResult.Sink
	end
	local now = os.clock()
	if now - lastSlapAt < Slap.Cooldown then
		return Enum.ContextActionResult.Sink
	end
	lastSlapAt = now
	slapEvent:FireServer()

	-- Cooldown countdown on the touch button title.
	task.spawn(function()
		while os.clock() - lastSlapAt < Slap.Cooldown do
			ContextActionService:SetTitle(ACTION_NAME, string.format("%.1f", Slap.Cooldown - (os.clock() - lastSlapAt)))
			task.wait(0.1)
		end
		ContextActionService:SetTitle(ACTION_NAME, Localization.T("Slap.Button"))
	end)
	return Enum.ContextActionResult.Sink
end

local function onHit(velocity: unknown)
	if typeof(velocity) ~= "Vector3" then
		return
	end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if root == nil or not root:IsA("BasePart") or humanoid == nil then
		return
	end
	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = velocity :: Vector3
	JuiceController.Shake(0.6, KNOCKDOWN_TIME)
	task.delay(KNOCKDOWN_TIME, function()
		humanoid.PlatformStand = false
	end)
end

local function showEffect(position: unknown, hit: unknown)
	if typeof(position) ~= "Vector3" then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = (position :: Vector3) + Vector3.new(0, 2, 0)
	anchor.Parent = effectsFolder

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(5, 2)
	billboard.LightInfluence = 0
	billboard.AlwaysOnTop = true
	billboard.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = if hit == true then Localization.T("Slap.Hit") else Localization.T("Slap.Miss")
	label.TextColor3 = if hit == true then HIT_COLOR else MISS_COLOR
	label.TextStrokeTransparency = 0
	label.Rotation = math.random(-15, 15)
	label.Parent = billboard

	TweenService:Create(anchor, TweenInfo.new(EFFECT_TIME), { Position = anchor.Position + Vector3.new(0, EFFECT_RISE, 0) }):Play()
	local fade = TweenService:Create(label, TweenInfo.new(EFFECT_TIME), { TextTransparency = 1, TextStrokeTransparency = 1 })
	fade.Completed:Connect(function()
		anchor:Destroy()
	end)
	fade:Play()
	if hit == true and slapSound then
		SoundService:PlayLocalSound(slapSound)
	end
end

function SlapController:Init(): ()
	slapEvent = Network.GetEvent("Slap")
	effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "SlapEffects"
	effectsFolder.Parent = workspace
	if Slap.SoundId ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = Slap.SoundId
		sound.Parent = SoundService
		slapSound = sound
	end
end

-- The on-screen Slap button exists only in touch mode; F / gamepad Y always work.
local function bindAction()
	local wantsButton = InputModeController.IsTouch()
	if boundWithTouchButton == wantsButton then
		return
	end
	boundWithTouchButton = wantsButton
	ContextActionService:UnbindAction(ACTION_NAME)
	touchButton = nil
	ContextActionService:BindAction(ACTION_NAME, onAction, wantsButton, Slap.Key, Slap.GamepadKey)
	if wantsButton then
		ContextActionService:SetTitle(ACTION_NAME, Localization.T("Slap.Button"))
		ContextActionService:SetPosition(ACTION_NAME, TOUCH_BUTTON_POSITION)
		observeTouchButton()
	end
end

function SlapController:Start(): ()
	bindAction()
	InputModeController.Changed:Connect(bindAction)
	local playerGui = player:WaitForChild("PlayerGui")
	playerGui.DescendantAdded:Connect(function(instance: Instance)
		if instance:IsA("GuiButton") then
			observeTouchButton()
		elseif instance:IsA("TextLabel") and instance.Name == "ActionTitle" then
			instance:GetPropertyChangedSignal("Text"):Connect(observeTouchButton)
			observeTouchButton()
		end
	end)
	local function observeCamera()
		if viewportConnection then viewportConnection:Disconnect() end
		local camera = workspace.CurrentCamera
		if camera then
			viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateTouchPosition)
		end
		observeTouchButton()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(observeCamera)
	player.CharacterAdded:Connect(observeTouchButton)
	observeCamera()
	Network.GetEvent("SlapHit").OnClientEvent:Connect(onHit)
	Network.GetEvent("SlapEffect").OnClientEvent:Connect(showEffect)
end

return SlapController


