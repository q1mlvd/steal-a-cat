--!strict
-- Heart with a progress ring above every untamed cat sitting on a pillow.
-- Progress comes from the server's TameEndsAt / TameDuration attributes (server clock).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CatSchema = require(ReplicatedStorage.Shared.Config.CatSchema)
local Tags = require(ReplicatedStorage.Shared.Config.Tags)
local UIAssets = require(ReplicatedStorage.Shared.Config.UIAssets)

local ATTR = CatSchema.Attributes
local REFRESH_INTERVAL = 0.1
local RING_DOTS = 24
local RING_RADIUS = 0.42 -- fraction of the billboard size
local DOT_SIZE = 0.11
local BILLBOARD_SIZE = UDim2.fromScale(3.2, 3.2)
local BILLBOARD_OFFSET = Vector3.new(0, 4.2, 0)
local MAX_DISTANCE = 60
local HEART_COLOR = Color3.fromRGB(255, 90, 140)
local DOT_FILLED = Color3.fromRGB(255, 90, 140)
local DOT_EMPTY = Color3.fromRGB(60, 40, 50)
local TIME_COLOR = Color3.new(1, 1, 1)
local SECONDS_PER_MINUTE = 60

type Display = {
	billboard: BillboardGui,
	dots: { Frame },
	timeLabel: TextLabel,
}

local TamingController = {
	Priority = 30,
}

local container: Folder
local displays: { [Model]: Display } = {}

local function createDisplay(model: Model): Display?
	local head = model:FindFirstChild("Head")
	if head == nil or not head:IsA("BasePart") then
		return nil
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Taming"
	billboard.Adornee = head
	billboard.Size = BILLBOARD_SIZE
	billboard.StudsOffsetWorldSpace = BILLBOARD_OFFSET
	billboard.MaxDistance = MAX_DISTANCE
	billboard.LightInfluence = 0
	billboard.Parent = container

	local dots: { Frame } = {}
	for i = 1, RING_DOTS do
		local angle = (i - 1) / RING_DOTS * 2 * math.pi -- clockwise from the top
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5 + math.sin(angle) * RING_RADIUS, 0.5 - math.cos(angle) * RING_RADIUS)
		dot.Size = UDim2.fromScale(DOT_SIZE, DOT_SIZE)
		dot.BackgroundColor3 = DOT_EMPTY
		dot.BorderSizePixel = 0
		dot.Parent = billboard
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = dot
		table.insert(dots, dot)
	end

	-- UI pack heart icon (falls back to the tinted heart colour on the ring dots).
	local heart = Instance.new("ImageLabel")
	heart.Name = "Heart"
	heart.AnchorPoint = Vector2.new(0.5, 0.5)
	heart.Position = UDim2.fromScale(0.5, 0.42)
	heart.Size = UDim2.fromScale(0.46, 0.46)
	heart.BackgroundTransparency = 1
	heart.ScaleType = Enum.ScaleType.Fit
	heart.Image = UIAssets.Icons.Heart
	heart.ImageColor3 = Color3.new(1, 1, 1):Lerp(HEART_COLOR, 0)
	heart.Parent = billboard

	local timeLabel = Instance.new("TextLabel")
	timeLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	timeLabel.Position = UDim2.fromScale(0.5, 0.72)
	timeLabel.Size = UDim2.fromScale(0.7, 0.26)
	timeLabel.BackgroundTransparency = 1
	timeLabel.Font = Enum.Font.GothamBold
	timeLabel.TextScaled = true
	timeLabel.TextColor3 = TIME_COLOR
	timeLabel.TextStrokeTransparency = 0.3
	timeLabel.Parent = billboard

	return { billboard = billboard, dots = dots, timeLabel = timeLabel }
end

local function formatTime(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // SECONDS_PER_MINUTE, whole % SECONDS_PER_MINUTE)
end

local function refresh()
	local now = workspace:GetServerTimeNow()
	local seen: { [Model]: true } = {}

	for _, instance in CollectionService:GetTagged(Tags.Cat) do
		if not instance:IsA("Model") then
			continue
		end
		local endsAt = instance:GetAttribute(ATTR.TameEndsAt)
		local duration = instance:GetAttribute(ATTR.TameDuration)
		local taming = instance:GetAttribute(ATTR.State) == CatSchema.States.OnPillow
			and instance:GetAttribute(ATTR.Tamed) ~= true
			and type(endsAt) == "number" and type(duration) == "number" and duration > 0
		if not taming then
			continue
		end

		local display = displays[instance] or createDisplay(instance)
		if display == nil then
			continue
		end
		displays[instance] = display
		seen[instance] = true

		local remaining = (endsAt :: number) - now
		local progress = math.clamp(1 - remaining / (duration :: number), 0, 1)
		local filled = math.floor(progress * RING_DOTS + 0.5)
		for i, dot in display.dots do
			dot.BackgroundColor3 = if i <= filled then DOT_FILLED else DOT_EMPTY
		end
		display.timeLabel.Text = formatTime(remaining)
	end

	for model, display in displays do
		if not seen[model] then
			display.billboard:Destroy()
			displays[model] = nil
		end
	end
end

function TamingController:Init(): ()
	container = Instance.new("Folder")
	container.Name = "TamingDisplays"
	-- In Workspace (client-only), not PlayerGui: PlayerGui is cleared on respawn.
	container.Parent = workspace
end

function TamingController:Start(): ()
	while true do
		refresh()
		task.wait(REFRESH_INTERVAL)
	end
end

return TamingController

