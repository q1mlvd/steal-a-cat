--!strict
-- Merge Machine UI: lists your seated cats grouped by cat and tier, previews the merge result and asks the
-- server to merge. The server picks and validates the cats (PillowService.MergeCats).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Localization = require(ReplicatedStorage.Shared.Util.Localization)
local UserInputService = game:GetService("UserInputService")

local Config = ReplicatedStorage.Shared.Config
local Cats = require(Config.Cats)
local Mutations = require(Config.Mutations)
local Shop = require(Config.Shop)
local Network = require(ReplicatedStorage.Shared.Network)
local CatPortrait = require(ReplicatedStorage.Shared.Util.CatPortrait)
local UI = Shop.Ui
local PORTRAIT = UI.PurchaseHeight * 2 - UI.Gap -- square portrait on the left of each row
local TEXT_LEFT = PORTRAIT + UI.Gap * 1.5

local MergeController = {
	Priority = 49,
}

local player = Players.LocalPlayer
local gui: ScreenGui
local list: ScrollingFrame
local requestEvent: RemoteEvent
local CLOSE_ACTION = "CloseMergeMachine"

local function corner(parent: Instance)
	local result = Instance.new("UICorner")
	result.CornerRadius = UDim.new(0, UI.Corner)
	result.Parent = parent
end

local function text(parent: Instance, value: string, size: UDim2, position: UDim2, textSize: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Text = value
	label.TextColor3 = color
	label.TextSize = textSize
	label.Font = Enum.Font.GothamBold
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Size = size
	label.Position = position
	label.Parent = parent
	return label
end

local function close()
	gui.Enabled = false
	player:SetAttribute(Shop.UiStateAttribute, false)
	ContextActionService:UnbindAction(CLOSE_ACTION)
end

local function show(groups: unknown)
	if type(groups) ~= "table" then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, group in groups :: { any } do
		local catDef = Cats.Get(tostring(group.catId))
		if catDef == nil then continue end
		local tier = Mutations.GetTier(group.tier)
		local nextTier = Mutations.NextTier(tier.id)
		local mutation = Mutations.Get(tostring(group.mutation))
		local row = Instance.new("Frame")
		row.LayoutOrder = index
		row.Size = UDim2.new(1, -UI.Gap, 0, UI.PurchaseHeight * 2)
		row.BackgroundColor3 = UI.Surface
		row.BorderSizePixel = 0
		row:SetAttribute("UiSkin", "Card:" .. catDef.rarity) -- UI pack rarity card
		row.Parent = list
		corner(row)
		CatPortrait.Create(row, { catId = catDef.id, tier = tier.id, mutation = tostring(group.mutation), frameless = true,
			size = UDim2.fromOffset(PORTRAIT, PORTRAIT), anchor = Vector2.new(0, 0.5), position = UDim2.new(0, UI.Gap / 2, 0.5, 0) })
		local name = (if tier.displayName ~= "" then Localization.T("Tier." .. tier.id) .. " " else "") .. Localization.T("Cat." .. catDef.id .. ".Name")
		text(row, Localization.T("Merge.Count", {name = name, count = group.count}), UDim2.new(1, -(UI.PurchaseWidth + UI.Gap * 2 + TEXT_LEFT), 0, UI.TextSize + UI.Gap),
			UDim2.fromOffset(TEXT_LEFT, UI.Gap / 2), UI.TextSize, UI.Text)
		local preview = if nextTier == nil then Localization.T("Merge.Maximum")
			else Localization.T("Merge.Preview", {tier = Localization.T("Tier." .. nextTier.id), cat = Localization.T("Cat." .. catDef.id .. ".Name"), income = nextTier.multiplier * Mutations.Multiplier(group.mutation), size = nextTier.scale})
				.. (if mutation then Localization.T("Merge.Keeps", {mutation = Localization.T("Mutation." .. mutation.id)}) else "")
		local previewLabel = text(row, preview, UDim2.new(1, -(UI.PurchaseWidth + UI.Gap * 2 + TEXT_LEFT), 0, UI.SmallTextSize * 2 + UI.Gap),
			UDim2.fromOffset(TEXT_LEFT, UI.TextSize + UI.Gap * 1.5), UI.SmallTextSize, UI.Muted)
		previewLabel.TextWrapped = true
		previewLabel.TextYAlignment = Enum.TextYAlignment.Top
		local canMerge = nextTier ~= nil and group.count >= Mutations.MergeCount
		local button = Instance.new("TextButton")
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -UI.Gap, 0.5, 0)
		button.Size = UDim2.fromOffset(UI.PurchaseWidth, UI.PurchaseHeight)
		button.Font = Enum.Font.GothamBold
		button.TextSize = UI.SmallTextSize
		button.Text = if nextTier == nil then Localization.T("Common.Max") elseif canMerge then Localization.T("Merge.Button") else Localization.T("Common.Need", {count = Mutations.MergeCount})
		button.BackgroundColor3 = if canMerge then UI.Accent else UI.Background
		button.TextColor3 = if canMerge then UI.Background else UI.Muted
		button.AutoButtonColor = canMerge
		button.Active = canMerge
		button.Parent = row
		corner(button)
		local catId, tierId = catDef.id, tier.id
		button.Activated:Connect(function()
			if canMerge and gui.Enabled then
				requestEvent:FireServer(catId, tierId)
			end
		end)
	end
	gui.Enabled = true
	player:SetAttribute(Shop.UiStateAttribute, true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
		if UserInputService:GetFocusedTextBox() ~= nil then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then close() end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Shop.CloseKey, Shop.CloseGamepadKey)
end

function MergeController.Open(): ()
	Network.GetFunction("HudMerge"):InvokeServer()
end

function MergeController:Init(): ()
	requestEvent = Network.GetEvent("MergeRequest")
	gui = Instance.new("ScreenGui")
	gui.Name = "MergeMachine"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.DisplayOrder = UI.DisplayOrder
	local shade = Instance.new("TextButton")
	shade.Text = ""
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = UI.ShadeTransparency
	shade.AutoButtonColor = false
	shade.Modal = true
	shade.Parent = gui
	shade.Activated:Connect(close)
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(UI.PanelWidthScale, UI.PanelHeightScale)
	panel.BackgroundColor3 = UI.Background
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Parent = gui
	corner(panel)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = UI.MinPanelSize
	constraint.MaxSize = Vector2.new(UI.PanelWidth, UI.PanelHeight)
	constraint.Parent = panel
	local title = text(panel, Localization.T("Merge.Title"), UDim2.new(1, -(UI.Padding * 3 + UI.TitleHeight), 0, UI.TitleHeight),
		UDim2.fromOffset(UI.Padding, UI.Padding), UI.TextSize + UI.Gap, UI.Text)
	title.Font = Enum.Font.FredokaOne
	text(panel, Localization.T("Merge.Help", {count = Mutations.MergeCount}),
		UDim2.new(1, -UI.Padding * 2, 0, UI.SmallTextSize + UI.Gap), UDim2.fromOffset(UI.Padding, UI.Padding + UI.TitleHeight),
		UI.SmallTextSize, UI.Muted)
	local closeButton = Instance.new("TextButton")
	closeButton.Text = "×"
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextScaled = true
	closeButton.Size = UDim2.fromOffset(UI.TitleHeight, UI.TitleHeight)
	closeButton.Position = UDim2.new(1, -(UI.Padding + UI.TitleHeight), 0, UI.Padding)
	closeButton.BackgroundColor3 = UI.Surface
	closeButton.TextColor3 = UI.Text
	closeButton.Parent = panel
	corner(closeButton)
	closeButton.Activated:Connect(close)
	local top = UI.Padding * 2 + UI.TitleHeight + UI.SmallTextSize + UI.Gap
	list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(UI.Padding, top)
	list.Size = UDim2.new(1, -UI.Padding * 2, 1, -(top + UI.Padding))
	list.CanvasSize = UDim2.fromScale(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = UI.Gap / 2
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, UI.Gap)
	layout.Parent = list
	gui.Parent = player:WaitForChild("PlayerGui")
end

function MergeController:Start(): ()
	Network.GetEvent("MergeOpen").OnClientEvent:Connect(show)
	player.CharacterAdded:Connect(function()
		if gui.Enabled then close() end
	end)
end

return MergeController


