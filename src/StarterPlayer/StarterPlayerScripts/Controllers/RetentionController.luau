--!strict
-- Daily rewards panel (7-day streak), daily quests panel and the "Welcome back" offline-income popup.
-- HUD buttons "Daily" and "Quests". Everything is validated and granted by RetentionService.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Localization = require(ReplicatedStorage.Shared.Util.Localization)
local UserInputService = game:GetService("UserInputService")

local Config = ReplicatedStorage.Shared.Config
local Shop = require(Config.Shop)
local Items = require(Config.Items)
local Retention = require(Config.Retention)
local Network = require(ReplicatedStorage.Shared.Network)
local CatPortrait = require(ReplicatedStorage.Shared.Util.CatPortrait)
local UiSkin = require(ReplicatedStorage.Shared.Util.UiSkin)
local BAR_HEIGHT = 12 -- quest progress bar (UI pack bar art)
local NumberFormat = require(ReplicatedStorage.Shared.Util.NumberFormat)
local HudButtonsController = require(script.Parent.HudButtonsController)
local UI = Shop.Ui

local RetentionController = {
	Priority = 64,
}

type Modal = { gui: ScreenGui, body: Frame, title: TextLabel }

local CLOSE_ACTION = "CloseRetentionPanel"
local player = Players.LocalPlayer
local daily: Modal
local quests: Modal
local welcome: Modal
local request: RemoteEvent
local dailyClaim: RemoteEvent
local questClaim: RemoteEvent

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or UI.Corner)
	c.Parent = parent
end

local function text(parent: Instance, value: string, size: UDim2, color: Color3, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.TextWrapped = true
	label.TextColor3 = color
	label.Text = value
	label.Parent = parent
	return label
end

local function closeAll()
	for _, modal in { daily, quests, welcome } do
		modal.gui.Enabled = false
	end
	player:SetAttribute(Shop.UiStateAttribute, false)
	ContextActionService:UnbindAction(CLOSE_ACTION)
end

local function show(modal: Modal)
	for _, other in { daily, quests, welcome } do
		other.gui.Enabled = other == modal
	end
	player:SetAttribute(Shop.UiStateAttribute, true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
		if UserInputService:GetFocusedTextBox() ~= nil then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then closeAll() end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Shop.CloseKey, Shop.CloseGamepadKey)
end

local function makeModal(name: string, title: string, width: number, height: number): Modal
	local gui = Instance.new("ScreenGui")
	gui.Name = name
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
	shade.Activated:Connect(closeAll)
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(width, height)
	panel.BackgroundColor3 = UI.Background
	panel.Active = true
	panel.Parent = gui
	corner(panel)
	local scale = Instance.new("UISizeConstraint")
	scale.MaxSize = Vector2.new(width, height)
	scale.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = UI.Accent
	stroke.Thickness = 2
	stroke.Parent = panel
	local titleLabel = text(panel, title, UDim2.new(1, -UI.TitleHeight - UI.Padding * 2, 0, UI.TitleHeight), UI.Text, UI.TextSize + UI.Gap)
	titleLabel.Position = UDim2.fromOffset(UI.Padding, UI.Padding / 2)
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	local close = Instance.new("TextButton")
	close.Text = "×"
	close.Font = Enum.Font.GothamBold
	close.TextScaled = true
	close.Size = UDim2.fromOffset(UI.TitleHeight, UI.TitleHeight)
	close.Position = UDim2.new(1, -(UI.TitleHeight + UI.Padding / 2), 0, UI.Padding / 2)
	close.BackgroundColor3 = UI.Surface
	close.TextColor3 = UI.Text
	close.Parent = panel
	corner(close)
	close.Activated:Connect(closeAll)
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(UI.Padding, UI.TitleHeight + UI.Padding)
	body.Size = UDim2.new(1, -UI.Padding * 2, 1, -(UI.TitleHeight + UI.Padding * 2))
	body.Parent = panel
	gui.Parent = player:WaitForChild("PlayerGui")
	return { gui = gui, body = body, title = titleLabel }
end

local function clear(frame: Frame)
	for _, child in frame:GetChildren() do child:Destroy() end
end

local function button(parent: Instance, label: string, active: boolean): TextButton
	local b = Instance.new("TextButton")
	b.Text = label
	b.Font = Enum.Font.GothamBold
	b.TextSize = UI.SmallTextSize
	b.TextWrapped = true
	b.BackgroundColor3 = if active then UI.Accent else UI.Surface
	b.TextColor3 = if active then UI.Background else UI.Muted
	b.AutoButtonColor = active
	b.Active = active
	b.Parent = parent
	corner(b)
	return b
end

local function showDaily(info: any)
	if type(info) ~= "table" then return end
	clear(daily.body)
	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, 0, 1, -(UI.PurchaseHeight + UI.Gap * 2 + UI.SmallTextSize))
	grid.Parent = daily.body
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / 4, -UI.Gap, 0.5, -UI.Gap)
	layout.CellPadding = UDim2.fromOffset(UI.Gap, UI.Gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for day, reward in info.rewards do
		local tile = Instance.new("Frame")
		tile.LayoutOrder = day
		local done = (day < info.nextDay) or (not info.claimable and day == info.streak)
		local isNext = info.claimable and day == info.nextDay
		tile.BackgroundColor3 = if isNext then UI.Accent elseif done then UI.Surface else UI.Background
		tile.Parent = grid
		corner(tile)
		local stroke = Instance.new("UIStroke")
		stroke.Color = if day == 7 then UI.Coin else UI.Accent
		stroke.Transparency = if isNext or day == 7 then 0 else UI.StrokeTransparency
		stroke.Parent = tile
		-- Dark text on every tile: the UI pack cards are cream inside (the next day's card is green-rimmed).
		local label = text(tile, Localization.T("Daily.DayReward", {day = day, reward = Localization.Translate(reward)}) .. (if done then "\n✔" else ""), UDim2.fromScale(1, 1),
			UI.Text, UI.SmallTextSize)
		label.TextScaled = true
		-- Stage 17 art: a mystery portrait for the cat reward, the item icon for item rewards.
		local definition = Retention.Daily[day]
		local item = if definition and definition.kind == "Item" and definition.itemId then Items.Get(definition.itemId) else nil
		local visual: GuiObject? = nil
		if definition and definition.kind == "Cat" then
			visual = CatPortrait.Create(tile, { rarity = definition.rarity, size = UDim2.fromScale(0.5, 0.5),
				anchor = Vector2.new(0.5, 0), position = UDim2.fromScale(0.5, 0.06) })
		elseif item and item.icon ~= "" then
			local icon = Instance.new("ImageLabel")
			icon.BackgroundTransparency = 1
			icon.AnchorPoint = Vector2.new(0.5, 0)
			icon.Position = UDim2.fromScale(0.5, 0.06)
			icon.Size = UDim2.fromScale(0.5, 0.5)
			icon.ScaleType = Enum.ScaleType.Fit
			icon.Image = item.icon
			icon.Parent = tile
			local aspect = Instance.new("UIAspectRatioConstraint")
			aspect.Parent = icon
			visual = icon
		end
		if visual then
			label.AnchorPoint = Vector2.new(0, 1)
			label.Position = UDim2.fromScale(0, 1)
			label.Size = UDim2.fromScale(1, 0.42)
		end
	end
	local note = text(daily.body, if info.pending > 0 then Localization.T("Daily.Pending", {count = info.pending}) else Localization.T("Daily.StreakNote"),
		UDim2.new(1, 0, 0, UI.SmallTextSize + 4), UI.Muted, UI.SmallTextSize)
	note.Position = UDim2.new(0, 0, 1, -(UI.PurchaseHeight + UI.Gap + UI.SmallTextSize))
	local claim = button(daily.body, if info.claimable then Localization.T("Daily.ClaimDay", {day = info.nextDay}) else Localization.T("Daily.ClaimedToday"), info.claimable)
	claim.Size = UDim2.new(1, 0, 0, UI.PurchaseHeight)
	claim.Position = UDim2.new(0, 0, 1, -UI.PurchaseHeight)
	claim.Activated:Connect(function()
		if claim.Active then dailyClaim:FireServer() end
	end)
	show(daily)
end

local function showQuests(list: any)
	if type(list) ~= "table" then return end
	clear(quests.body)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, UI.Gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = quests.body
	for index, quest in list do
		local row = Instance.new("Frame")
		row.LayoutOrder = index
		row.Size = UDim2.new(1, 0, 0, UI.PurchaseHeight + UI.Gap * 2)
		row.BackgroundColor3 = UI.Surface
		row.Parent = quests.body
		corner(row)
		local title = text(row, Localization.T("Quest.Progress", {quest = Localization.T("Quest." .. quest.id), progress = NumberFormat.Format(quest.progress), target = NumberFormat.Format(quest.target)}),
			UDim2.new(1, -(UI.PurchaseWidth + UI.Gap * 3), 0.5, 0), UI.Text, UI.SmallTextSize)
		title.Position = UDim2.fromOffset(UI.Gap, 0)
		title.TextXAlignment = Enum.TextXAlignment.Left
		local reward = text(row, Localization.T("Quest.Reward", {reward = Localization.Translate(quest.reward)}), UDim2.new(1, -(UI.PurchaseWidth + UI.Gap * 3), 0.25, 0), UI.Coin, UI.SmallTextSize)
		reward.Position = UDim2.fromScale(0, 0.5)
		reward.Position = UDim2.new(0, UI.Gap, 0.5, 0)
		reward.TextXAlignment = Enum.TextXAlignment.Left
		local barBack = Instance.new("Frame")
		barBack.BackgroundColor3 = UI.Background
		barBack.AnchorPoint = Vector2.new(0, 0.5)
		barBack.Position = UDim2.new(0, UI.Gap, 0.84, 0)
		barBack.Size = UDim2.new(1, -(UI.PurchaseWidth + UI.Gap * 3), 0, BAR_HEIGHT)
		barBack:SetAttribute("UiSkin", "None")
		barBack.Parent = row
		local fill = Instance.new("Frame")
		fill.BackgroundColor3 = UI.Accent
		fill.Size = UDim2.fromScale(math.clamp(quest.progress / math.max(1, quest.target), 0, 1), 1)
		fill:SetAttribute("UiSkin", "None")
		fill.Parent = barBack
		UiSkin.Bar(barBack, fill, if quest.progress >= quest.target then "Gold" else "Green")
		local ready = not quest.claimed and quest.progress >= quest.target
		local claim = button(row, if quest.claimed then Localization.T("Common.Claimed") elseif ready then Localization.T("Common.Claim") else Localization.T("Common.InProgress"), ready)
		claim.AnchorPoint = Vector2.new(1, 0.5)
		claim.Position = UDim2.new(1, -UI.Gap, 0.5, 0)
		claim.Size = UDim2.fromOffset(UI.PurchaseWidth, UI.PurchaseHeight)
		claim.Activated:Connect(function()
			if claim.Active then questClaim:FireServer(quest.id) end
		end)
	end
	if quests.gui.Enabled or not daily.gui.Enabled then
		show(quests)
	end
end

local function showWelcome(coins: any, seconds: any)
	if type(coins) ~= "number" or type(seconds) ~= "number" then return end
	clear(welcome.body)
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	text(welcome.body, Localization.T("Welcome.Body", {hours = hours, minutes = minutes, coins = NumberFormat.Format(coins)}),
		UDim2.new(1, 0, 1, -(UI.PurchaseHeight + UI.Gap)), UI.Text, UI.TextSize)
	local ok = button(welcome.body, Localization.T("Welcome.Okay"), true)
	ok.Size = UDim2.new(1, 0, 0, UI.PurchaseHeight)
	ok.Position = UDim2.new(0, 0, 1, -UI.PurchaseHeight)
	ok.Activated:Connect(closeAll)
	show(welcome)
end

function RetentionController:Init(): ()
	request = Network.GetEvent("RetentionRequest")
	dailyClaim = Network.GetEvent("DailyClaim")
	questClaim = Network.GetEvent("QuestClaim")
	daily = makeModal("DailyRewards", Localization.T("Daily.Title"), 560, 380)
	quests = makeModal("DailyQuests", Localization.T("Quest.Title"), 560, 330)
	welcome = makeModal("WelcomeBack", Localization.T("Welcome.Title"), 420, 240)
	HudButtonsController.Add("Daily", Localization.T("Hud.Daily"), 10, nil, function() request:FireServer("Daily") end)
	HudButtonsController.Add("Quests", Localization.T("Hud.Quests"), 20, nil, function() request:FireServer("Quests") end)
end

function RetentionController:Start(): ()
	Network.GetEvent("DailyInfo").OnClientEvent:Connect(showDaily)
	Network.GetEvent("QuestInfo").OnClientEvent:Connect(function(list: any)
		-- Progress updates refresh an open panel; they never pop it open uninvited.
		if quests.gui.Enabled or player:GetAttribute("QuestPanelRequested") then
			player:SetAttribute("QuestPanelRequested", nil)
			showQuests(list)
		end
	end)
	Network.GetEvent("WelcomeBack").OnClientEvent:Connect(showWelcome)
	HudButtonsController.Add("Quests", Localization.T("Hud.Quests"), 20, nil, function()
		player:SetAttribute("QuestPanelRequested", true)
		request:FireServer("Quests")
	end)
end

return RetentionController


