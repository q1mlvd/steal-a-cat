--!strict
-- The server sends this remote only to the owner of an attached bell.
-- Independent markers keep tracking a stolen cat even when Soft Paws hides the steal alert.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Localization = require(ReplicatedStorage.Shared.Util.Localization)
local RunService = game:GetService("RunService")

local Config = ReplicatedStorage.Shared.Config
local Shop = require(Config.Shop)
local Network = require(ReplicatedStorage.Shared.Network)
local UI = Shop.BellUi
local BellTrackingController = { Priority = 48 }
local player = Players.LocalPlayer

type Tracking = {
	model: Model?,
	position: Vector3?,
	anchor: Part,
	name: string,
	row: Frame,
	text: TextLabel,
	arrow: TextLabel,
	marker: BillboardGui,
	highlight: Highlight,
	connections: { RBXScriptConnection },
}

local tracks: { [string]: Tracking } = {}
local gui: ScreenGui
local panel: ScrollingFrame
local highlights: Folder
local elapsed = 0

local function rootOf(model: Model): BasePart?
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root end
	local fallback = model:FindFirstChildWhichIsA("BasePart", true)
	return if fallback and fallback:IsA("BasePart") then fallback else nil
end

local function positionPanel(): ()
	-- IgnoreGuiInset gives this GUI a different origin from the coin HUD.
	-- Keep the panel's actual viewport position below the coins on every device.
	panel.Position = UDim2.new(0.5, 0, 0, UI.Top - gui.AbsolutePosition.Y)
end

local function panelState(): ()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local catchGui = if playerGui then playerGui:FindFirstChild(Shop.CatchGuiName) else nil
	panel.Visible = next(tracks) ~= nil and player:GetAttribute(Shop.UiStateAttribute) ~= true
		and not (catchGui ~= nil and catchGui:IsA("ScreenGui") and catchGui.Enabled)
end

local function stop(uniqueId: string): ()
	local track = tracks[uniqueId]
	if track == nil then return end
	tracks[uniqueId] = nil
	for _, connection in track.connections do connection:Disconnect() end
	track.row:Destroy()
	track.marker:Destroy()
	track.highlight:Destroy()
	track.anchor:Destroy()
	panelState()
end

local function setModel(track: Tracking, model: Model?): ()
	if track.model == model then return end
	for _, connection in track.connections do connection:Disconnect() end
	table.clear(track.connections)
	track.model = model
	track.highlight.Adornee = model
	track.highlight.Enabled = model ~= nil
	if model == nil then return end
	-- Streaming can remove a local model while the cat still exists on the server.
	-- Keep the locator until an explicit stop; the server continues sending positions.
	table.insert(track.connections, model.Destroying:Connect(function() setModel(track, nil) end))
	table.insert(track.connections, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then setModel(track, nil) end
	end))
end

local function textLabel(parent: Instance, name: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = UI.Color
	label.TextSize = UI.TextSize
	label.TextStrokeTransparency = UI.OutlineTransparency
	label.TextStrokeColor3 = Shop.Ui.Background
	label.Parent = parent
	return label
end

local function update(): ()
	positionPanel()
	local camera = workspace.CurrentCamera
	local character = player.Character
	local origin = if character then character:FindFirstChild("HumanoidRootPart") else nil
	for _, track in tracks do
		local model = track.model
		if model and not model:IsDescendantOf(workspace) then setModel(track, nil) model = nil end
		local root = if model then rootOf(model) else nil
		if root then track.position = root.Position end
		local position = track.position
		track.marker.Enabled = position ~= nil
		if position == nil then
			track.text.Text = Localization.T("Bell.Tracking", {cat = Localization.Translate(track.name)})
			track.arrow.Visible = false
			continue
		end
		track.anchor.Position = position
		local distance = if origin and origin:IsA("BasePart") then math.round((position - origin.Position).Magnitude) else nil
		track.text.Text = if distance then Localization.T("Bell.Distance", {cat = Localization.Translate(track.name), distance = distance}) else Localization.T("Bell.Tracking", {cat = Localization.Translate(track.name)})
		track.arrow.Visible = camera ~= nil
		if camera then
			local offset = position - camera.CFrame.Position
			local forward = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
			local right = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)
			if forward.Magnitude > UI.DirectionEpsilon and right.Magnitude > UI.DirectionEpsilon then
				track.arrow.Rotation = math.deg(math.atan2(offset:Dot(right.Unit), offset:Dot(forward.Unit)))
			end
		end
	end
	panelState()
end

local function start(uniqueId: string, model: Model?, catName: string, position: Vector3?): ()
	local existing = tracks[uniqueId]
	if existing then
		existing.name = catName
		if position then existing.position = position end
		if model and model:IsDescendantOf(workspace) then setModel(existing, model) end
		update()
		return
	end
	local row = Instance.new("Frame")
	row.Name = uniqueId
	row.Size = UDim2.new(1, 0, 0, UI.RowHeight)
	row.BackgroundTransparency = 1
	row.Parent = panel
	local arrow = textLabel(row, "Bearing")
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.new(0, UI.ArrowSize / 2, 0.5, 0)
	arrow.Size = UDim2.fromOffset(UI.ArrowSize, UI.ArrowSize)
	arrow.Text = "▲"
	arrow.TextScaled = true
	local text = textLabel(row, "Position")
	text.Position = UDim2.fromOffset(UI.ArrowSize + UI.Gap, 0)
	text.Size = UDim2.new(1, -(UI.ArrowSize + UI.Gap), 1, 0)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextTruncate = Enum.TextTruncate.AtEnd
	local marker = Instance.new("BillboardGui")
	marker.Name = `Bell_{uniqueId}`
	marker.ResetOnSpawn = false
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.Size = UDim2.fromOffset(UI.MarkerSize.X, UI.MarkerSize.Y)
	marker.StudsOffsetWorldSpace = UI.MarkerOffset
	local anchor = Instance.new("Part")
	anchor.Name = `BellPosition_{uniqueId}`
	anchor.Size = UI.AnchorSize
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Parent = highlights
	marker.Adornee = anchor
	marker.Parent = gui
	local markerText = textLabel(marker, "Label")
	markerText.Size = UDim2.fromScale(1, 1)
	markerText.Text = Localization.T("Bell.Marker", {cat = Localization.Translate(catName)})
	markerText.TextScaled = true
	local highlight = Instance.new("Highlight")
	highlight.Name = uniqueId
	highlight.Enabled = false
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = UI.Color
	highlight.OutlineColor = UI.Color
	highlight.FillTransparency = UI.FillTransparency
	highlight.OutlineTransparency = UI.OutlineTransparency
	highlight.Parent = highlights
	local track: Tracking = {
		model = nil, position = position, anchor = anchor, name = catName, row = row, text = text, arrow = arrow,
		marker = marker, highlight = highlight, connections = {},
	}
	tracks[uniqueId] = track
	if model and model:IsDescendantOf(workspace) then setModel(track, model) end
	update()
end

function BellTrackingController:Init(): ()
	gui = Instance.new("ScreenGui")
	gui.Name = UI.GuiName
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = UI.DisplayOrder
	panel = Instance.new("ScrollingFrame")
	panel.Name = "TrackedCats"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, UI.Top)
	panel.Size = UDim2.new(UI.WidthScale, 0, 0, UI.MaxPanelHeight)
	panel.CanvasSize = UDim2.fromScale(0, 0)
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	panel.ScrollingDirection = Enum.ScrollingDirection.Y
	panel.ScrollBarThickness = UI.Gap
	panel.ScrollBarImageColor3 = UI.Color
	panel.BackgroundColor3 = Shop.Ui.Background
	panel.BackgroundTransparency = Shop.Ui.ShadeTransparency
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(UI.Width, UI.MaxPanelHeight)
	constraint.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UI.Padding)
	corner.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, UI.Padding)
	padding.PaddingRight = UDim.new(0, UI.Padding)
	padding.PaddingTop = UDim.new(0, UI.Padding)
	padding.PaddingBottom = UDim.new(0, UI.Padding)
	padding.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.Name
	layout.Padding = UDim.new(0, UI.Gap)
	layout.Parent = panel
	highlights = Instance.new("Folder")
	highlights.Name = `{UI.GuiName}Highlights`
	highlights.Parent = workspace
	gui.Parent = player:WaitForChild("PlayerGui")
	gui:GetPropertyChangedSignal("AbsolutePosition"):Connect(positionPanel)
	positionPanel()
end

function BellTrackingController:Start(): ()
	Network.GetEvent("BellTracking").OnClientEvent:Connect(function(active: unknown, uniqueId: unknown, catModel: unknown, catName: unknown, position: unknown)
		if type(uniqueId) ~= "string" or uniqueId == "" then return end
		if active == false then stop(uniqueId) return end
		if active ~= true then return end
		local model = if typeof(catModel) == "Instance" and (catModel :: Instance):IsA("Model") then catModel :: Model else nil
		local point: Vector3? = nil
		if typeof(position) == "Vector3" then
			local vector = position :: Vector3
			if vector.X == vector.X and vector.Y == vector.Y and vector.Z == vector.Z
				and math.abs(vector.X) < math.huge and math.abs(vector.Y) < math.huge and math.abs(vector.Z) < math.huge then
				point = vector
			end
		end
		if model == nil and point == nil then return end
		start(uniqueId, model, if type(catName) == "string" then catName else "cat", point)
	end)
	player:GetAttributeChangedSignal(Shop.UiStateAttribute):Connect(panelState)
	player.CharacterAdded:Connect(update)
	player.AncestryChanged:Connect(function()
		if player.Parent ~= Players then
			for uniqueId in tracks do stop(uniqueId) end
			highlights:Destroy()
		end
	end)
	RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= UI.UpdateInterval then elapsed = 0 update() end
	end)
end

return BellTrackingController


