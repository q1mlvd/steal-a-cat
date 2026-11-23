--!strict
-- Shows each house's bowl amount above the bowl with an animated count-up.
-- Reads the BowlCoins attribute the server mirrors onto every Bowl part.
-- Streaming-safe: plots and bowls may stream in/out at any time, so displays follow them.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Tags = require(ReplicatedStorage.Shared.Config.Tags)
local NumberFormat = require(ReplicatedStorage.Shared.Util.NumberFormat)

local BOWL_NAME = "Bowl"
local BILLBOARD_SIZE = UDim2.fromScale(5, 1.4)
local BILLBOARD_OFFSET = Vector3.new(0, 2.5, 0)
local MAX_DISTANCE = 60
local TEXT_COLOR = Color3.fromRGB(255, 215, 80)
local SNAP_EPSILON = 0.5

type BowlDisplay = {
	billboard: BillboardGui,
	label: TextLabel,
	displayed: number,
	ancestryConnection: RBXScriptConnection,
}

local BowlController = {
	Priority = 30,
}

local displays: { [BasePart]: BowlDisplay } = {}
local plotConnections: { [Instance]: RBXScriptConnection } = {}
local container: Folder

local function removeBowl(bowl: BasePart)
	local display = displays[bowl]
	if display then
		displays[bowl] = nil
		display.ancestryConnection:Disconnect()
		display.billboard:Destroy()
	end
end

local function addBowl(bowl: BasePart)
	if displays[bowl] then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BowlDisplay"
	billboard.Adornee = bowl
	billboard.Size = BILLBOARD_SIZE
	billboard.StudsOffsetWorldSpace = BILLBOARD_OFFSET
	billboard.MaxDistance = MAX_DISTANCE
	billboard.LightInfluence = 0
	billboard.Parent = container

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = TEXT_COLOR
	label.TextStrokeTransparency = 0.2
	label.Parent = billboard

	local value = bowl:GetAttribute(Economy.BowlAttribute)
	local initial = if type(value) == "number" then math.floor(value) else 0
	label.Text = NumberFormat.Format(initial)

	displays[bowl] = {
		billboard = billboard,
		label = label,
		displayed = initial,
		ancestryConnection = bowl.AncestryChanged:Connect(function()
			if not bowl:IsDescendantOf(workspace) then
				removeBowl(bowl) -- streamed out or destroyed; re-added when it streams back in
			end
		end),
	}
end

local function watchPlot(plot: Instance)
	if plotConnections[plot] then
		return
	end
	local bowl = plot:FindFirstChild(BOWL_NAME)
	if bowl and bowl:IsA("BasePart") then
		addBowl(bowl)
	end
	plotConnections[plot] = plot.ChildAdded:Connect(function(child: Instance)
		if child.Name == BOWL_NAME and child:IsA("BasePart") then
			addBowl(child)
		end
	end)
end

local function unwatchPlot(plot: Instance)
	local connection = plotConnections[plot]
	if connection then
		connection:Disconnect()
		plotConnections[plot] = nil
	end
end

local function render(dt: number)
	for bowl, display in displays do
		local value = bowl:GetAttribute(Economy.BowlAttribute)
		local target = if type(value) == "number" then math.floor(value) else 0
		if target < display.displayed then
			display.displayed = target -- collected: drop instantly
		elseif target ~= display.displayed then
			display.displayed += (target - display.displayed) * math.min(1, dt * Economy.CountUpSpeed)
			if target - display.displayed < SNAP_EPSILON then
				display.displayed = target
			end
		else
			continue
		end
		display.label.Text = NumberFormat.Format(display.displayed)
	end
end

function BowlController:Init(): ()
	container = Instance.new("Folder")
	container.Name = "BowlDisplays"
	-- In Workspace (client-only), not PlayerGui: PlayerGui is cleared on respawn.
	container.Parent = workspace
end

function BowlController:Start(): ()
	CollectionService:GetInstanceAddedSignal(Tags.Plot):Connect(watchPlot)
	CollectionService:GetInstanceRemovedSignal(Tags.Plot):Connect(unwatchPlot)
	for _, plot in CollectionService:GetTagged(Tags.Plot) do
		watchPlot(plot)
	end
	RunService.RenderStepped:Connect(render)
end

return BowlController

