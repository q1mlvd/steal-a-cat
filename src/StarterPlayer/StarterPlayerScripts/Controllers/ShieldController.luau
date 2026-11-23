--!strict
-- Shield icon with a countdown above the sign of houses whose owner is still under new-player protection.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Localization = require(ReplicatedStorage.Shared.Util.Localization)

local Stealing = require(ReplicatedStorage.Shared.Config.Stealing)
local Tags = require(ReplicatedStorage.Shared.Config.Tags)

local REFRESH_INTERVAL = 0.5
local BILLBOARD_SIZE = UDim2.fromScale(9, 2.2)
local BILLBOARD_OFFSET = Vector3.new(0, 12.5, 0) -- above the second-floor walls
local MAX_DISTANCE = 150
local SHIELD_COLOR = Color3.fromRGB(110, 190, 255)
local SECONDS_PER_MINUTE = 60

local ShieldController = {
	Priority = 50,
}

local container: Folder
local labels: { [BasePart]: TextLabel } = {}

local function getLabel(sign: BasePart): TextLabel
	local label = labels[sign]
	if label and label.Parent and label.Parent.Parent then
		return label
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Adornee = sign
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
	newLabel.TextColor3 = SHIELD_COLOR
	newLabel.TextStrokeTransparency = 0.2
	newLabel.Parent = billboard
	labels[sign] = newLabel
	return newLabel
end

local function refresh()
	local now = workspace:GetServerTimeNow()
	for _, plot in CollectionService:GetTagged(Tags.Plot) do
		local sign = plot:FindFirstChild("Sign")
		if sign == nil or not sign:IsA("BasePart") then
			continue
		end
		local endsAt = plot:GetAttribute(Stealing.ShieldAttribute)
		local label = labels[sign]
		if type(endsAt) == "number" and endsAt > now then
			local seconds = math.ceil(endsAt - now)
			local shieldLabel = getLabel(sign)
			shieldLabel.Text = Localization.T("Shield.Protected", {time = string.format("%d:%02d", seconds // SECONDS_PER_MINUTE, seconds % SECONDS_PER_MINUTE)});
			(shieldLabel.Parent :: BillboardGui).Enabled = true
		elseif label and label.Parent then
			(label.Parent :: BillboardGui).Enabled = false
		end
	end
end

function ShieldController:Init(): ()
	container = Instance.new("Folder")
	container.Name = "ShieldDisplays"
	-- In Workspace (client-only), not PlayerGui: PlayerGui is cleared on respawn.
	container.Parent = workspace
end

function ShieldController:Start(): ()
	while true do
		refresh()
		task.wait(REFRESH_INTERVAL)
	end
end

return ShieldController


