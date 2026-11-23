--!strict
-- Current input mode (keyboard+mouse / touch / gamepad), from UserInputService.PreferredInput with a
-- LastInputType fallback, updated live when the player switches device. Other controllers read GetMode()
-- and listen to Changed: touch-only UI must check IsTouch(), never TouchEnabled (touch-screen PCs and
-- laptops report TouchEnabled with a keyboard attached).
-- Also shows a small key-hint panel on keyboard and gamepad.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Localization = require(ReplicatedStorage.Shared.Util.Localization)
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = ReplicatedStorage.Shared.Config
local Input = require(Config.Input)
local Loyalty = require(Config.Loyalty)
local PlotPrompts = require(Config.PlotPrompts)
local Shop = require(Config.Shop)
local Slap = require(Config.Slap)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local MODES = Input.Modes

local InputModeController = {
	Priority = 2,
	-- (newMode)
	Changed = Signal.new() :: Signal.Signal<Input.Mode>,
}

local player = Players.LocalPlayer
local mode: Input.Mode = MODES.KeyboardMouse
local hintGui: ScreenGui
local hintLines: { { row: Frame, key: TextLabel, keyboard: string, gamepad: string } } = {}

local function isMode(value: unknown): boolean
	return value == MODES.KeyboardMouse or value == MODES.Touch or value == MODES.Gamepad
end

local function classify(inputType: Enum.UserInputType): Input.Mode?
	if inputType == Enum.UserInputType.Touch then
		return MODES.Touch
	elseif string.sub(inputType.Name, 1, 7) == "Gamepad" then
		return MODES.Gamepad
	elseif inputType == Enum.UserInputType.Keyboard or string.sub(inputType.Name, 1, 5) == "Mouse" then
		return MODES.KeyboardMouse
	end
	return nil
end

local function preferred(): Input.Mode?
	local ok, value = pcall(function(): any
		return (UserInputService :: any).PreferredInput
	end)
	if not ok or typeof(value) ~= "EnumItem" then
		return nil
	end
	local name = (value :: EnumItem).Name
	return if name == "Touch" then MODES.Touch elseif name == "Gamepad" then MODES.Gamepad else MODES.KeyboardMouse
end

local function detect(): Input.Mode
	if RunService:IsStudio() then
		local forced = player:GetAttribute(Input.DebugModeAttribute)
		if isMode(forced) then
			return forced :: Input.Mode
		end
	end
	local fromPreferred = preferred()
	if fromPreferred then
		return fromPreferred
	end
	local fromLast = classify(UserInputService:GetLastInputType())
	if fromLast then
		return fromLast
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return MODES.Touch
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return MODES.Gamepad
	end
	return MODES.KeyboardMouse
end

local function keyName(key: Enum.KeyCode): string
	if key.Value >= Enum.KeyCode.Zero.Value and key.Value <= Enum.KeyCode.Nine.Value then
		return tostring(key.Value - Enum.KeyCode.Zero.Value) -- KeyCode.One -> "1"
	end
	local name = key.Name
	if string.sub(name, 1, #Input.GamepadPrefix) == Input.GamepadPrefix then
		return string.sub(name, #Input.GamepadPrefix + 1)
	end
	return name
end

local function refreshHints()
	hintGui.Enabled = mode ~= MODES.Touch
	local visible = 0
	for _, line in hintLines do
		local text = if mode == MODES.Gamepad then line.gamepad else line.keyboard
		line.key.Text = text
		line.row.Visible = text ~= ""
		if line.row.Visible then visible += 1 end
	end
	-- Fixed height (no AutomaticSize: the panel carries a UI pack frame child).
	local panel = hintGui:FindFirstChild("Panel", true)
	if panel and panel:IsA("Frame") then
		panel.Size = UDim2.fromOffset(Input.HintWidth,
			visible * Input.HintLineHeight + Input.HintMargin + Input.HintSkinInset * 2)
	end
end

local function update()
	local newMode = detect()
	if newMode == mode then
		return
	end
	mode = newMode
	player:SetAttribute(Input.ModeAttribute, mode)
	refreshHints()
	InputModeController.Changed:Fire(mode)
end

function InputModeController.GetMode(): Input.Mode
	return mode
end

-- Touch-only UI (on-screen buttons, portrait hotbar) checks this.
function InputModeController.IsTouch(): boolean
	return mode == MODES.Touch
end

local function buildHints()
	hintGui = Instance.new("ScreenGui")
	hintGui.Name = Input.HintGuiName
	hintGui.ResetOnSpawn = false
	hintGui.DisplayOrder = Input.HintDisplayOrder
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -Input.HintMargin, 1, -Input.HintMargin)
	panel.Size = UDim2.fromOffset(Input.HintWidth, 0)
	panel.BackgroundColor3 = Input.HintBackground
	panel.BackgroundTransparency = Input.HintBackgroundTransparency
	panel.BorderSizePixel = 0
	panel:SetAttribute("UiSkin", "Tooltip") -- UI pack tooltip frame (UiStyleController)
	panel.Parent = hintGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Input.HintMargin)
	corner.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, Input.HintMargin + Input.HintSkinInset)
	padding.PaddingRight = UDim.new(0, Input.HintMargin + Input.HintSkinInset)
	padding.PaddingTop = UDim.new(0, Input.HintMargin / 2 + Input.HintSkinInset)
	padding.PaddingBottom = UDim.new(0, Input.HintMargin / 2 + Input.HintSkinInset)
	padding.Parent = panel
	local lines = Instance.new("Frame")
	lines.Name = "Lines"
	lines.BackgroundTransparency = 1
	lines.Size = UDim2.fromScale(1, 1)
	lines.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = lines
	local entries = {
		{ keyboard = keyName(PlotPrompts.KeyCode), gamepad = keyName(PlotPrompts.GamepadKeyCode), action = "Input.Interact" },
		{ keyboard = keyName(Loyalty.PetKeyCode), gamepad = keyName(Loyalty.PetGamepadKeyCode), action = "Input.Pet" },
		{ keyboard = keyName(Slap.Key), gamepad = keyName(Slap.GamepadKey), action = "Slap.Button" },
		{ keyboard = `{keyName(Shop.HotbarKeys[1])}-{keyName(Shop.HotbarKeys[#Shop.HotbarKeys])}`, gamepad = "", action = "Input.UseItem" },
		{ keyboard = keyName(Shop.CloseKey), gamepad = keyName(Shop.CloseGamepadKey), action = "Input.CloseShop" },
	}
	for index, entry in entries do
		local row = Instance.new("Frame")
		row.Name = `Hint{index}`
		row.LayoutOrder = index
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, Input.HintLineHeight)
		row.Parent = lines
		local key = Instance.new("TextLabel")
		key.Name = "Key"
		key.BackgroundTransparency = 1
		key.Size = UDim2.new(0.3, 0, 1, 0)
		key.Font = Enum.Font.GothamBold
		key.TextSize = Input.HintTextSize
		key.TextColor3 = Input.HintKeyColor
		key.TextXAlignment = Enum.TextXAlignment.Left
		key.Parent = row
		local action = Instance.new("TextLabel")
		action.Name = "Action"
		action.BackgroundTransparency = 1
		action.Position = UDim2.fromScale(0.3, 0)
		action.Size = UDim2.new(0.7, 0, 1, 0)
		action.Font = Enum.Font.Gotham
		action.TextSize = Input.HintTextSize
		action.TextColor3 = Input.HintColor
		action.TextXAlignment = Enum.TextXAlignment.Left
		Localization.Bind(action, entry.action)
		action.Parent = row
		table.insert(hintLines, { row = row, key = key, keyboard = entry.keyboard, gamepad = entry.gamepad })
	end
	hintGui.Parent = player:WaitForChild("PlayerGui")
end

function InputModeController:Init(): ()
	mode = detect()
	player:SetAttribute(Input.ModeAttribute, mode)
	buildHints()
	refreshHints()
end

function InputModeController:Start(): ()
	pcall(function()
		UserInputService:GetPropertyChangedSignal("PreferredInput" :: any):Connect(update)
	end)
	UserInputService.LastInputTypeChanged:Connect(update)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(update)
	UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(update)
	UserInputService.GamepadConnected:Connect(update)
	UserInputService.GamepadDisconnected:Connect(update)
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal(Input.DebugModeAttribute):Connect(update)
	end
end

return InputModeController


