--!strict
-- Door lock visuals and owner pass-through. While your own door is locked, your client turns the
-- barrier off locally so you can walk through; everyone else's client keeps it solid.
-- Shows "LOCKED 0:42" above locked doors.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Localization = require(ReplicatedStorage.Shared.Util.Localization)

local Doors = require(ReplicatedStorage.Shared.Config.Doors)
local Plots = require(ReplicatedStorage.Shared.Config.Plots)
local Tags = require(ReplicatedStorage.Shared.Config.Tags)

local REFRESH_INTERVAL = 0.2
local BILLBOARD_SIZE = UDim2.fromScale(8, 2)
local BILLBOARD_OFFSET = Vector3.new(0, 4, 0)
local MAX_DISTANCE = 80
local LOCKED_COLOR = Color3.fromRGB(255, 90, 90)
local SECONDS_PER_MINUTE = 60

local DoorController = {
	Priority = 50,
}

local player = Players.LocalPlayer
local container: Folder
local labels: { [BasePart]: TextLabel } = {}

local function getLabel(door: BasePart): TextLabel
	local label = labels[door]
	if label and label.Parent and label.Parent.Parent then
		return label
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Adornee = door
	billboard.Size = BILLBOARD_SIZE
	billboard.StudsOffsetWorldSpace = BILLBOARD_OFFSET
	billboard.MaxDistance = MAX_DISTANCE
	billboard.LightInfluence = 0
	billboard.Parent = container
	local newLabel = Instance.new("TextLabel")
	newLabel.Size = UDim2.fromScale(1, 1)
	newLabel.BackgroundTransparency = 1
	newLabel.Font = Enum.Font.FredokaOne
	newLabel.TextScaled = true
	newLabel.TextColor3 = LOCKED_COLOR
	newLabel.TextStrokeTransparency = 0.2
	newLabel.Parent = billboard
	labels[door] = newLabel
	return newLabel
end

local function refresh()
	local now = workspace:GetServerTimeNow()
	for _, plot in CollectionService:GetTagged(Tags.Plot) do
		local door = plot:FindFirstChild("Door")
		local barrier = plot:FindFirstChild("DoorBarrier")
		if door == nil or not door:IsA("BasePart") then
			continue -- not streamed in
		end
		local lockedUntil = plot:GetAttribute(Doors.LockedUntilAttribute)
		local locked = type(lockedUntil) == "number" and lockedUntil > now
		local isOwner = plot:GetAttribute(Plots.OwnerAttribute) == player.UserId

		if barrier and barrier:IsA("BasePart") and isOwner and barrier.CanCollide then
			barrier.CanCollide = false -- local only: the owner walks through their own locked door
		end

		local label = labels[door]
		if locked then
			local seconds = math.ceil((lockedUntil :: number) - now)
			local lockLabel = getLabel(door)
			lockLabel.Text = Localization.T("Door.Locked", {time = string.format("%d:%02d", seconds // SECONDS_PER_MINUTE, seconds % SECONDS_PER_MINUTE)});
			(lockLabel.Parent :: BillboardGui).Enabled = true
		elseif label and label.Parent then
			(label.Parent :: BillboardGui).Enabled = false
		end
	end
end

function DoorController:Init(): ()
	container = Instance.new("Folder")
	container.Name = "DoorDisplays"
	-- In Workspace (client-only), not PlayerGui: PlayerGui is cleared on respawn.
	container.Parent = workspace
end

function DoorController:Start(): ()
	while true do
		refresh()
		task.wait(REFRESH_INTERVAL)
	end
end

return DoorController


