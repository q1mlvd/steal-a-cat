--!strict
-- Live event UI: a countdown pill under the coin HUD ("STARFALL 2:31", or the next event when idle), rain
-- particles around the camera and faded hiding cats during Rain. Reads EventService's workspace attributes.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local Events = require(Config.Events)
local Shop = require(Config.Shop)
local Tags = require(Config.Tags)
local UIAssets = require(Config.UIAssets)
local Viewport = require(ReplicatedStorage.Shared.Util.Viewport)
local UI = Shop.Ui
local L = require(ReplicatedStorage.Shared.Util.Localization)
local Layout = require(ReplicatedStorage.Shared.Util.HudLayout)
local LayoutConfig = require(Config.HudLayout)
local Hud = require(Config.Hud)
local InputMode = require(script.Parent.InputModeController)
local UiSkin = require(ReplicatedStorage.Shared.Util.UiSkin)
local Lighting = game:GetService("Lighting")

local EventController = {
	Priority = 57,
}

local SECONDS_PER_MINUTE = 60
local player = Players.LocalPlayer
local canvas: Frame
local header: Frame
local title: TextLabel
local bottom: Frame
local nextTimer: TextLabel
local dayTimer: TextLabel
local pill: TextLabel
local pillIcon: ImageLabel
local PILL_ICON = 34 -- event icon on the pill's left (UI pack event art; timer while waiting)
local rainPart: Part
local rainEmitter: ParticleEmitter
local faded: { [BasePart]: number } = {}

local function clock(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // SECONDS_PER_MINUTE, whole % SECONDS_PER_MINUTE)
end

local function setFaded(on: boolean)
	if not on then
		for part, transparency in faded do
			if part.Parent then part.LocalTransparencyModifier = transparency end
		end
		table.clear(faded)
		return
	end
	for _, model in CollectionService:GetTagged(Tags.Cat) do
		if model:GetAttribute(Events.Rain.HidingAttribute) == true then
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and faded[part] == nil then
					faded[part] = part.LocalTransparencyModifier
					part.LocalTransparencyModifier = Events.Rain.HiddenTransparency
				end
			end
		end
	end
end

local function update()
	local now = workspace:GetServerTimeNow()
	local active = workspace:GetAttribute(Events.ActiveAttribute)
	local endsAt = workspace:GetAttribute(Events.EndsAtAttribute)
	local schedule = if type(active) == "string" then (Events.Schedule :: any)[active] else nil
	local nextName=workspace:GetAttribute(Events.NextAttribute)
	local nextAt=workspace:GetAttribute(Events.NextAtAttribute)
	local nextSchedule=if type(nextName)=="string" then (Events.Schedule::any)[nextName] else nil
	local eventName=if schedule then active else nextName
	local remaining=if schedule and type(endsAt)=="number" then endsAt-now elseif nextSchedule and type(nextAt)=="number" then nextAt-now else 0
	title.Text=if eventName then L.T("Event."..tostring(eventName)) else ""
	pill.Text=clock(remaining)
	pill.TextColor3=UI.OnColor
	pillIcon.Image=(UIAssets.Events::any)[eventName] or UIAssets.Icons.Timer
	header.Visible=schedule~=nil or nextSchedule~=nil
	local n=math.max(0,math.ceil((if type(nextAt)=="number" then nextAt else now)-now))
	nextTimer.Text=L.T("Hud.NextEvent",{minutes=n//60,seconds=n%60})
	local anchor=workspace:GetAttribute(Hud.DayNightAnchorAttribute)
	local hours=if type(anchor)=="number" then ((now-anchor)%Hud.DayNightCycleSeconds)/Hud.DayNightCycleSeconds*24 else Lighting.ClockTime
	local isDay=hours>=Hud.DayStartHour and hours<Hud.NightStartHour
	local untilHour=if isDay then Hud.NightStartHour else Hud.DayStartHour
	local phaseSeconds=math.ceil(((untilHour-hours)%24)*Hud.DayNightCycleSeconds/24)
	dayTimer.Text=L.T(if isDay then "Hud.Day" else "Hud.Night",{time=clock(phaseSeconds)})
	local m=Layout.Get(canvas,InputMode.IsTouch())
	header.Position=UDim2.fromOffset(m.eventX,m.margin) header.Size=UDim2.fromOffset(m.eventWidth,m.topHeight)
	bottom.Size=UDim2.fromOffset(m.timerWidth,LayoutConfig.TimerHeight)
	bottom.Position=UDim2.fromOffset(m.timerX,m.timerY)
	local raining = active == "Rain"
	rainEmitter.Enabled = raining and player:GetAttribute("Setting_LowGraphics") ~= true
	local camera = workspace.CurrentCamera
	if raining and camera then
		rainPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 25, 0))
	end
	setFaded(raining)
end

function EventController:Init(): ()
	local gui = Instance.new("ScreenGui")
	gui.Name = "EventBar"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = UI.HotbarDisplayOrder
	gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets
	gui.ClipToDeviceSafeArea=true
	canvas=Instance.new("Frame") canvas.Name="EventCanvas" canvas.Size=UDim2.fromScale(1,1)
	canvas.BackgroundTransparency=1 canvas:SetAttribute("UiNoScale",true) canvas.Parent=gui
	header=Instance.new("Frame") header.Name="EventHeader" header.BackgroundColor3=UI.Background header:SetAttribute("UiSkin","Toast") header.Parent=canvas
	pillIcon=UiSkin.Icon(header,UIAssets.Icons.Timer,UDim2.fromScale(0.28,0.55),UDim2.fromScale(0.04,0.46),Vector2.new(0,0.5))
	local function label(parent:Instance,name:string,pos:UDim2,size:UDim2):TextLabel
		local label=Instance.new("TextLabel") label.Name=name label.BackgroundTransparency=1
		label.Position=pos label.Size=size label.Font=Enum.Font.FredokaOne label.TextScaled=true label.TextWrapped=true label.TextColor3=UI.OnColor
		local stroke=Instance.new("UIStroke") stroke.Color=UiSkin.Outline stroke.Thickness=LayoutConfig.TextStroke stroke.Parent=label
		label.Parent=parent return label
	end
	title=label(header,"EventName",UDim2.fromScale(0.30,0.08),UDim2.fromScale(0.65,0.25))
	pill=label(header,"Countdown",UDim2.fromScale(0.30,0.35),UDim2.fromScale(0.65,0.55))
	bottom=Instance.new("Frame") bottom.Name="WorldTimers" bottom.BackgroundTransparency=1 bottom.Parent=canvas
	nextTimer=label(bottom,"NextEvent",UDim2.fromScale(0,0),UDim2.fromScale(1,0.5))
	dayTimer=label(bottom,"DayNight",UDim2.fromScale(0,0.5),UDim2.fromScale(1,0.5))
	gui.Parent=player:WaitForChild("PlayerGui")

	rainPart = Instance.new("Part")
	rainPart.Name = "LocalRain"
	rainPart.Anchored = true
	rainPart.CanCollide = false
	rainPart.CanQuery = false
	rainPart.CanTouch = false
	rainPart.Transparency = 1
	rainPart.Size = Vector3.new(80, 1, 80)
	rainPart.Parent = workspace
	rainEmitter = Instance.new("ParticleEmitter")
	rainEmitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	rainEmitter.Color = ColorSequence.new(Color3.fromRGB(170, 190, 230))
	rainEmitter.Size = NumberSequence.new(0.15)
	rainEmitter.Transparency = NumberSequence.new(0.3)
	rainEmitter.Lifetime = NumberRange.new(1.2)
	rainEmitter.Speed = NumberRange.new(40)
	rainEmitter.EmissionDirection = Enum.NormalId.Bottom
	rainEmitter.Rate = 400
	rainEmitter.Enabled = false
	rainEmitter.Parent = rainPart
end

function EventController:Start(): ()
	while true do
		update()
		task.wait(LayoutConfig.EventTick)
	end
end

return EventController


