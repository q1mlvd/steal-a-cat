--!strict
-- Hover tooltip (Frame_Tooltip) for mouse users: Attach(guiObject, text or function). Touch players never see
-- it (no hover). One shared ScreenGui, created on first use.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shop = require(ReplicatedStorage.Shared.Config.Shop)
local UIAssets = require(ReplicatedStorage.Shared.Config.UIAssets)
local UiSkin = require(script.Parent.UiSkin)

local UI = Shop.Ui
local MAX_WIDTH = 240
local PADDING = 12
local OFFSET = Vector2.new(16, 18)

local UiTooltip = {}

local gui: ScreenGui? = nil
local frame: Frame
local label: TextLabel
local owner: GuiObject? = nil

local function build()
	local created = Instance.new("ScreenGui")
	created.Name = "Tooltip"
	created.ResetOnSpawn = false
	created.IgnoreGuiInset = true
	created.DisplayOrder = 200
	frame = Instance.new("Frame")
	frame.Name = "Tip"
	frame.Size = UDim2.fromOffset(0, 0)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = created
	UiSkin.Apply(frame, UIAssets.Frames.Tooltip)
	label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(PADDING, PADDING * 0.7)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 0)
	label.Font = Enum.Font.GothamBold
	label.TextSize = UI.SmallTextSize
	label.TextColor3 = UI.Text
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = frame
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(MAX_WIDTH, math.huge)
	limit.Parent = label
	-- The frame follows the label (no AutomaticSize on the skinned frame itself).
	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		frame.Size = UDim2.fromOffset(label.AbsoluteSize.X + PADDING * 2, label.AbsoluteSize.Y + PADDING * 1.4)
	end)
	created.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = created
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseMovement and frame.Visible then
			local position = UserInputService:GetMouseLocation()
			frame.Position = UDim2.fromOffset(position.X + OFFSET.X, position.Y + OFFSET.Y)
		end
	end)
end

function UiTooltip.Attach(object: GuiObject, text: string | () -> string)
	object.MouseEnter:Connect(function()
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then return end
		if gui == nil then build() end
		local value = if type(text) == "function" then text() else text
		if value == "" then return end
		owner = object
		label.Text = value
		local position = UserInputService:GetMouseLocation()
		frame.Position = UDim2.fromOffset(position.X + OFFSET.X, position.Y + OFFSET.Y)
		frame.Visible = true
	end)
	local function hide()
		if owner == object and gui then
			frame.Visible = false
			owner = nil
		end
	end
	object.MouseLeave:Connect(hide)
	if object:IsA("GuiButton") then
		object.Activated:Connect(hide) -- clicking usually opens a menu over it
	end
	object:GetPropertyChangedSignal("Visible"):Connect(hide)
	object.AncestryChanged:Connect(hide)
end

return UiTooltip

