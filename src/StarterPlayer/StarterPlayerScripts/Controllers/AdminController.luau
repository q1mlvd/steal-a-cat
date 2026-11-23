--!strict
-- Admin panel (only shown when the server marks this player IsAdmin; every command is re-checked on the
-- server). Event triggers, cat spawner (cat id + mutation), secret cat rain, server luck boost.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Localization = require(ReplicatedStorage.Shared.Util.Localization)

local Config = ReplicatedStorage.Shared.Config
local Admin = require(Config.Admin)
local Shop = require(Config.Shop)
local UIAssets = require(Config.UIAssets)
local Network = require(ReplicatedStorage.Shared.Network)
local HudButtonsController = require(script.Parent.HudButtonsController)
local UI = Shop.Ui

local AdminController = {
	Priority = 63,
}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil

local function build(): ScreenGui
	local command = Network.GetEvent("AdminCommand")
	local screen = Instance.new("ScreenGui")
	screen.Name = "AdminPanel"
	screen.ResetOnSpawn = false
	screen.Enabled = false
	screen.DisplayOrder = UI.DisplayOrder
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -(UI.PurchaseWidth + UI.Gap * 2), 0.5, 0)
	panel.Size = UDim2.fromOffset(260, 0) -- height set after the entries are added
	panel.BackgroundColor3 = UI.Background
	panel.Parent = screen
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UI.Corner)
	corner.Parent = panel
	local padding = Instance.new("UIPadding")
	for _, side in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
		(padding :: any)[side] = UDim.new(0, UI.Gap)
	end
	padding.Parent = panel
	-- The list lives in an inner body so the panel can carry its UI pack frame (UiStyleController).
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.fromScale(1, 1)
	body.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, UI.Gap / 2)
	layout.Parent = body
	local order = 0
	local function add(instance: GuiObject)
		order += 1
		instance.LayoutOrder = order
		instance.Size = UDim2.new(1, 0, 0, UI.HotbarPageHeight - 8)
		instance.Parent = body
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, UI.Corner / 2)
		c.Parent = instance
	end
	local function button(text: string, ...: any)
		local args = table.pack(...)
		local b = Instance.new("TextButton")
		b.Text = Localization.T(text)
		b.Font = Enum.Font.GothamBold
		b.TextSize = UI.SmallTextSize
		b.BackgroundColor3 = UI.Surface
		b.TextColor3 = UI.Text
		add(b)
		b.Activated:Connect(function()
			command:FireServer(table.unpack(args, 1, args.n))
		end)
		return b
	end
	local function box(placeholder: string): TextBox
		local t = Instance.new("TextBox")
		t.PlaceholderText = Localization.T(placeholder)
		t.Text = ""
		t.Font = Enum.Font.Gotham
		t.TextSize = UI.SmallTextSize
		t.BackgroundColor3 = UI.Surface
		t.TextColor3 = UI.Text
		t.ClearTextOnFocus = false
		add(t)
		return t
	end
	button("Admin.Starfall", "event", "Starfall")
	button("Admin.Rain", "event", "Rain")
	button("Admin.DogRaid", "event", "DogRaid")
	button("Admin.StopEvent", "stopevent")
	button("Admin.SecretRain", "secretrain", 5)
	button("Admin.Luck", "luck", 3, 10)
	local catBox = box("Admin.CatId")
	local mutationBox = box("Admin.Mutation")
	local spawn = Instance.new("TextButton")
	Localization.Bind(spawn, "Admin.Spawn")
	spawn.Font = Enum.Font.GothamBold
	spawn.TextSize = UI.SmallTextSize
	spawn.BackgroundColor3 = UI.Accent
	spawn.TextColor3 = UI.Background
	add(spawn)
	spawn.Activated:Connect(function()
		command:FireServer("spawncat", catBox.Text, mutationBox.Text)
	end)
	-- Fixed height for the entries plus padding and the frame art's inset (tall enough to use the Panel frame).
	local inset = UIAssets.PanelInsets.Panel
	panel.Size = UDim2.fromOffset(260, order * (UI.HotbarPageHeight - 8) + (order - 1) * UI.Gap / 2
		+ UI.Gap * 2 + inset.top + inset.bottom)
	screen.Parent = player:WaitForChild("PlayerGui")
	return screen
end

local function refresh()
	if player:GetAttribute(Admin.Attribute) == true and gui == nil then
		gui = build()
		HudButtonsController.Add("Admin", Localization.T("Hud.Admin"), 200, nil, function()
			local screen = gui
			if screen then screen.Enabled = not screen.Enabled end
		end)
	end
end

function AdminController:Start(): ()
	player:GetAttributeChangedSignal(Admin.Attribute):Connect(refresh)
	refresh()
end

return AdminController


