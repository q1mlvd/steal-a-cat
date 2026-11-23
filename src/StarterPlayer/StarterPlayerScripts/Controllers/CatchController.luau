--!strict
-- Catch mini-game UI. Draws the bar from the server's parameters and only reports *when* the player
-- pressed; the server decides whether that was inside the green zone.
-- Input: E / gamepad A or R2 (ContextActionService), or click / tap anywhere on screen.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Localization = require(ReplicatedStorage.Shared.Util.Localization)
local RunService = game:GetService("RunService")

local Network = require(ReplicatedStorage.Shared.Network)
local CatchMinigame = require(ReplicatedStorage.Shared.CatchMinigame)
local Catching = require(ReplicatedStorage.Shared.Config.Catching)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local InputModeController = require(script.Parent.InputModeController)
local JuiceController = require(script.Parent.JuiceController)
local SoundController = require(script.Parent.SoundController)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local UiSkin = require(ReplicatedStorage.Shared.Util.UiSkin)
local RARE_CATCH_ORDER = 4 -- Epic and rarer catches get confetti

local ACTION_NAME = "CatchMinigameStop"
local GUI_NAME = "CatchMinigame"

-- Layout
local PANEL_WIDTH_SCALE = 0.7
local PANEL_MAX_WIDTH = 520
local PANEL_HEIGHT = 150
local PANEL_BOTTOM_OFFSET = -40
local BAR_HEIGHT = 36
local MARKER_WIDTH = 6
local CORNER_RADIUS = 8

-- Colours
local PANEL_COLOR = Color3.fromRGB(25, 25, 35)
local BAR_COLOR = Color3.fromRGB(60, 60, 75)
local ZONE_COLOR = Color3.fromRGB(80, 220, 100)
local MARKER_COLOR = Color3.fromRGB(255, 255, 255)
local HINT_COLOR = Color3.fromRGB(62, 34, 74) -- dark text on the UI pack popup's cream interior
local SUCCESS_COLOR = Color3.fromRGB(80, 255, 120)
local FAIL_COLOR = Color3.fromRGB(255, 80, 80)

type Active = {
	params: CatchMinigame.Params,
	startedAt: number,
	stopped: boolean,
	renderConnection: RBXScriptConnection,
}

type Ui = {
	gui: ScreenGui,
	title: TextLabel,
	hint: TextLabel,
	zone: Frame,
	marker: Frame,
	tapCatcher: TextButton,
}

local CatchController = {
	Priority = 50,
}

local ui: Ui
local active: Active? = nil
local catchSubmitEvent: RemoteEvent

local function corner(parent: Instance)
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, CORNER_RADIUS)
	uiCorner.Parent = parent
end

local function buildUi(): Ui
	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.Enabled = false

	-- Full-screen invisible button: a click or tap anywhere stops the marker (PC + mobile).
	local tapCatcher = Instance.new("TextButton")
	tapCatcher.Name = "TapCatcher"
	tapCatcher.Size = UDim2.fromScale(1, 1)
	tapCatcher.BackgroundTransparency = 1
	tapCatcher.Text = ""
	tapCatcher.AutoButtonColor = false
	tapCatcher.ZIndex = 10
	tapCatcher.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, PANEL_BOTTOM_OFFSET)
	panel.Size = UDim2.new(PANEL_WIDTH_SCALE, 0, 0, PANEL_HEIGHT)
	panel.BackgroundColor3 = PANEL_COLOR
	panel:SetAttribute("UiSkin", "Popup") -- UI pack popup frame (UiStyleController)
	panel.Parent = gui
	corner(panel)
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(PANEL_MAX_WIDTH, PANEL_HEIGHT)
	sizeConstraint.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 34)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextStrokeTransparency = 1
	title.Parent = panel
	-- Rarity-coloured title on the cream popup: the pack's dark outline keeps light colours readable.
	local titleOutline = Instance.new("UIStroke")
	titleOutline.Color = UiSkin.Outline
	titleOutline.Thickness = 2
	titleOutline.Parent = title

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.55)
	bar.Size = UDim2.new(1, 0, 0, BAR_HEIGHT)
	bar.BackgroundColor3 = BAR_COLOR
	bar.ClipsDescendants = true
	bar.Parent = panel
	corner(bar)

	local zone = Instance.new("Frame")
	zone.Name = "GreenZone"
	zone.BackgroundColor3 = ZONE_COLOR
	zone.BorderSizePixel = 0
	zone.Size = UDim2.fromScale(0, 1)
	zone.Parent = bar

	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Size = UDim2.new(0, MARKER_WIDTH, 1.3, 0)
	marker.BackgroundColor3 = MARKER_COLOR
	marker.BorderSizePixel = 0
	marker.ZIndex = 2
	marker.Parent = bar
	local markerOutline = Instance.new("UIStroke")
	markerOutline.Color = UiSkin.Outline
	markerOutline.Thickness = 2
	markerOutline.Parent = marker
	-- UI pack bar: dark track, green fill as the target zone.
	UiSkin.Bar(bar, zone, "Green")

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.Position = UDim2.fromScale(0, 1)
	hint.Size = UDim2.new(1, 0, 0, 24)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamBold
	hint.TextScaled = true
	hint.TextColor3 = HINT_COLOR
	hint.Parent = panel

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	return {
		gui = gui,
		title = title,
		hint = hint,
		zone = zone,
		marker = marker,
		tapCatcher = tapCatcher,
	}
end

local function hintText(): string
	local mode = InputModeController.GetMode()
	if mode == "Touch" then
		return Localization.T("Catch.HintTouch")
	elseif mode == "Gamepad" then
		return Localization.T("Catch.HintGamepad")
	end
	return Localization.T("Catch.HintKeyboard", {key = Catching.PromptKey.Name})
end

local function cleanup()
	local current = active
	if current == nil then
		return
	end
	active = nil
	current.renderConnection:Disconnect()
	ContextActionService:UnbindAction(ACTION_NAME)
	ui.gui.Enabled = false
	ProximityPromptService.Enabled = true
end

local function stop()
	local current = active
	if current == nil or current.stopped then
		return
	end
	if os.clock() - current.startedAt < Catching.MinInputDelay then
		return
	end
	current.stopped = true
	ui.hint.Text = "..."
	catchSubmitEvent:FireServer(current.params.sessionId)
end

local function onCatchStart(params: CatchMinigame.Params)
	cleanup()

	local rarity = Rarities.Get(params.rarityId)
	ui.title.Text = Localization.T("Catch.Title", {cat = Localization.Translate(params.catName)})
	ui.title.TextColor3 = if rarity then rarity.color else MARKER_COLOR
	ui.hint.Text = hintText()
	ui.zone.Position = UDim2.fromScale(params.zoneStart, 0)
	ui.zone.Size = UDim2.fromScale(params.zoneSize, 1)
	ui.marker.BackgroundColor3 = MARKER_COLOR
	ui.marker.Position = UDim2.fromScale(params.markerStart, 0.5)
	ui.gui.Enabled = true
	ProximityPromptService.Enabled = false -- the prompt key (E) is the stop key now

	local startedAt = os.clock()
	local current: Active
	current = {
		params = params,
		startedAt = startedAt,
		stopped = false,
		renderConnection = RunService.RenderStepped:Connect(function()
			if not current.stopped then
				ui.marker.Position = UDim2.fromScale(CatchMinigame.MarkerPosition(params, os.clock() - startedAt), 0.5)
			end
		end),
	}
	active = current

	ContextActionService:BindActionAtPriority(ACTION_NAME, function(_name: string, state: Enum.UserInputState, _input: InputObject)
		if state == Enum.UserInputState.Begin then
			stop()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Catching.PromptKey, Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonR2)

	-- Safety net if the result never arrives.
	task.delay(params.timeout + Catching.MaxLatencyCompensation + Catching.ResultDisplayTime * 2, function()
		if active == current then
			cleanup()
		end
	end)
end

local function onCatchResult(sessionId: unknown, success: unknown)
	local current = active
	if current == nil or sessionId ~= current.params.sessionId then
		return
	end
	current.stopped = true
	ui.marker.BackgroundColor3 = if success == true then SUCCESS_COLOR else FAIL_COLOR
	ui.title.Text = if success == true then Localization.T("Catch.Success") else Localization.T("Catch.Failed")
	ui.title.TextColor3 = if success == true then SUCCESS_COLOR else FAIL_COLOR
	ui.hint.Text = ""
	if success == true then
		local rarity = Rarities.Get(current.params.rarityId)
		SoundController.PlayId((Sounds.Meow :: any)[current.params.rarityId] or "", Sounds.MeowVolume)
		if rarity and rarity.order >= RARE_CATCH_ORDER then
			JuiceController.Confetti()
		end
	end
	task.delay(Catching.ResultDisplayTime, function()
		if active == current then
			cleanup()
		end
	end)
end

function CatchController:Init(): ()
	ui = buildUi()
	catchSubmitEvent = Network.GetEvent("CatchSubmit")
end

function CatchController:Start(): ()
	ui.tapCatcher.Activated:Connect(stop)
	Network.GetEvent("CatchStart").OnClientEvent:Connect(onCatchStart)
	Network.GetEvent("CatchResult").OnClientEvent:Connect(onCatchResult)
	InputModeController.Changed:Connect(function()
		local current = active
		if current and not current.stopped then
			ui.hint.Text = hintText()
		end
	end)
end

return CatchController


