--!strict
-- Onboarding tutorial (shown once; TutorialDone is saved on the server): catch -> carry home -> place on a
-- pillow -> collect the bowl -> buy a first item. A beam + bouncing marker point at the next target.
-- Steps are detected from replicated state only (cat attributes, remotes, inventory snapshots).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Localization = require(ReplicatedStorage.Shared.Util.Localization)
local TweenService = game:GetService("TweenService")

local Config = ReplicatedStorage.Shared.Config
local CatSchema = require(Config.CatSchema)
local Items = require(Config.Items)
local Pillows = require(Config.Pillows)
local Plots = require(Config.Plots)
local Shop = require(Config.Shop)
local Tags = require(Config.Tags)
local Network = require(ReplicatedStorage.Shared.Network)
local ItemController = require(script.Parent.ItemController)
local JuiceController = require(script.Parent.JuiceController)
local UI = Shop.Ui

local ATTR = CatSchema.Attributes

local TutorialController = {
	Priority = 66,
}

local STEPS = {
	"Tutorial.Step1",
	"Tutorial.Step2",
	"Tutorial.Step3",
	"Tutorial.Step4",
	"Tutorial.Step5",
}

local player = Players.LocalPlayer
local step = 0 -- 0 = not running
local panel: Frame
local textLabel: TextLabel
local anchor: Part
local beam: Beam
local marker: BillboardGui
local targetAttachment: Attachment
local seatedAtStart = 0
local trackedCat: string? = nil -- UniqueId of the cat caught in step 1
local itemsAtStart = 0
local collected = false

local function myPlot(): Model?
	for _, plot in CollectionService:GetTagged(Tags.Plot) do
		if plot:IsA("Model") and plot:GetAttribute(Plots.OwnerAttribute) == player.UserId then
			return plot
		end
	end
	return nil
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- Where the tracked cat is: "Carried" (by me), "Seated" (on my pillow) or nil (gone / not streamed).
local function trackedState(): string?
	for _, cat in CollectionService:GetTagged(Tags.Cat) do
		if trackedCat ~= nil and cat:GetAttribute(ATTR.UniqueId) == trackedCat then
			if cat:GetAttribute(ATTR.CarrierUserId) == player.UserId then return "Carried" end
			if cat:GetAttribute(ATTR.OwnerUserId) == player.UserId and cat:GetAttribute(ATTR.State) == CatSchema.States.OnPillow then
				return "Seated"
			end
		end
	end
	return nil
end

local function counts(): (number, number)
	local carried, seated = 0, 0
	for _, cat in CollectionService:GetTagged(Tags.Cat) do
		if cat:GetAttribute(ATTR.CarrierUserId) == player.UserId then
			carried += 1
			if step == 1 then trackedCat = cat:GetAttribute(ATTR.UniqueId) end
		end
		if cat:GetAttribute(ATTR.OwnerUserId) == player.UserId and cat:GetAttribute(ATTR.State) == CatSchema.States.OnPillow then
			seated += 1
		end
	end
	return carried, seated
end

local function itemTotal(): number
	local total = 0
	for _, item in Items.List do total += ItemController.GetCount(item.id) end
	return total
end

local function inside(part: BasePart, position: Vector3): boolean
	local localPosition = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(localPosition.X) <= half.X and math.abs(localPosition.Y) <= half.Y and math.abs(localPosition.Z) <= half.Z
end

local function setStep(newStep: number)
	step = newStep
	if step == 0 then
		panel.Visible = false
		beam.Enabled = false
		marker.Enabled = false
		return
	end
	local _, seated = counts()
	seatedAtStart = seated
	itemsAtStart = itemTotal()
	collected = false
	textLabel.Text = Localization.T("Tutorial.Title", {step = step, total = #STEPS, instruction = Localization.T(STEPS[step])})
	panel.Visible = true
end

local function finish(skipped: boolean)
	setStep(0)
	Network.GetEvent("TutorialComplete"):FireServer()
	if not skipped then
		JuiceController.Confetti(60)
	end
end

local function target(): Vector3?
	local plot = myPlot()
	local root = rootPart()
	if step == 1 and root then
		local best: Vector3? = nil
		local bestDistance = math.huge
		for _, cat in CollectionService:GetTagged(Tags.Cat) do
			if cat:IsA("Model") and cat:GetAttribute(ATTR.State) == CatSchema.States.Wild then
				local position = cat:GetPivot().Position
				local distance = (position - root.Position).Magnitude
				if distance < bestDistance then best, bestDistance = position, distance end
			end
		end
		return best
	elseif step == 2 and plot then
		local door = plot:FindFirstChild("Door")
		return if door and door:IsA("BasePart") then door.Position else nil
	elseif step == 3 and plot then
		local folder = plot:FindFirstChild("PillowsFolder")
		for _, pillow in if folder then folder:GetChildren() else {} do
			if pillow:IsA("BasePart") and pillow:GetAttribute(Pillows.OccupiedAttribute) ~= true
				and pillow:GetAttribute(Pillows.LockedAttribute) ~= true then
				return pillow.Position
			end
		end
	elseif step == 4 and plot then
		local bowl = plot:FindFirstChild("Bowl")
		return if bowl and bowl:IsA("BasePart") then bowl.Position else nil
	elseif step == 5 then
		local zone = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Square") and workspace.Map.Square:FindFirstChild("ShopZone")
		return if zone and zone:IsA("BasePart") then zone.Position else nil
	end
	return nil
end

local function update()
	if step == 0 then return end
	local carried = counts()
	local plot = myPlot()
	local root = rootPart()
	local tracked = if step == 2 or step == 3 then trackedState() else nil
	if step == 1 and carried > 0 then
		setStep(2)
	elseif step == 3 and tracked == "Seated" then
		setStep(4)
	elseif (step == 2 or step == 3) and tracked == nil then
		setStep(1) -- the caught cat was dropped or lost: catch another one
	elseif step == 2 and plot and root then
		local zone = plot:FindFirstChild("InteriorZone")
		if zone and zone:IsA("BasePart") and inside(zone, root.Position) then setStep(3) end
	elseif step == 4 and collected then
		setStep(5)
	elseif step == 5 and itemTotal() > itemsAtStart then
		finish(false)
		return
	end
	local position = target()
	local character = player.Character
	local rootAttachment = if root then root:FindFirstChild("RootAttachment") else nil
	if position and rootAttachment and rootAttachment:IsA("Attachment") then
		anchor.Position = position + Vector3.new(0, 3, 0)
		beam.Attachment0 = rootAttachment
		beam.Enabled = true
		marker.Enabled = true
	else
		beam.Enabled = false
		marker.Enabled = position ~= nil
		if position then anchor.Position = position + Vector3.new(0, 3, 0) end
	end
	local _ = character
end

function TutorialController:Init(): ()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Tutorial"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = UI.HotbarDisplayOrder + 1
	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 104)
	panel.Size = UDim2.fromOffset(520, 56)
	panel.BackgroundColor3 = UI.Background
	panel.BackgroundTransparency = 0.1
	panel.Visible = false
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UI.Corner)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = UI.Coin
	stroke.Thickness = 2
	stroke.Parent = panel
	textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1
	textLabel.Position = UDim2.fromOffset(UI.Gap, 0)
	textLabel.Size = UDim2.new(1, -(UI.Gap * 3 + 64), 1, 0)
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextWrapped = true
	textLabel.TextSize = UI.TextSize
	textLabel.TextColor3 = UI.Text
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.Parent = panel
	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 0.5)
	skip.Position = UDim2.new(1, -UI.Gap, 0.5, 0)
	skip.Size = UDim2.fromOffset(64, 36)
	Localization.Bind(skip, "Tutorial.Skip")
	skip.TextSize = UI.TextSize
	skip.BackgroundColor3 = UI.Surface
	skip.TextColor3 = UI.Muted
	skip.Parent = panel
	skip.Activated:Connect(function() finish(true) end)
	gui.Parent = player:WaitForChild("PlayerGui")

	anchor = Instance.new("Part")
	anchor.Name = "TutorialTarget"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Parent = workspace
	targetAttachment = Instance.new("Attachment")
	targetAttachment.Parent = anchor
	beam = Instance.new("Beam")
	beam.Attachment1 = targetAttachment
	beam.Color = ColorSequence.new(UI.Coin)
	beam.Width0 = 0.5
	beam.Width1 = 0.5
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Transparency = NumberSequence.new(0.2, 0.6)
	beam.Enabled = false
	beam.Parent = anchor
	marker = Instance.new("BillboardGui")
	marker.Size = UDim2.fromOffset(48, 48)
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.Enabled = false
	marker.Parent = anchor
	local arrow = Instance.new("TextLabel")
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromScale(1, 1)
	arrow.TextScaled = true
	arrow.Font = Enum.Font.FredokaOne
	arrow.Text = "\u{25BC}"
	arrow.TextColor3 = UI.Coin
	arrow.TextStrokeTransparency = 0.2
	arrow.Parent = marker
	TweenService:Create(marker, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ StudsOffset = Vector3.new(0, 1.5, 0) }):Play()
end

function TutorialController:Start(): ()
	Network.GetEvent("CoinsCollected").OnClientEvent:Connect(function()
		collected = true
	end)
	local function check()
		if player:GetAttribute("TutorialDone") == false and step == 0 then
			setStep(1)
		elseif player:GetAttribute("TutorialDone") == true and step ~= 0 then
			setStep(0)
		end
	end
	player:GetAttributeChangedSignal("TutorialDone"):Connect(check)
	check()
	while true do
		update()
		task.wait(0.3)
	end
end

-- Studio/test helper: current step (0 = not running).
function TutorialController.GetStep(): number
	return step
end

return TutorialController


