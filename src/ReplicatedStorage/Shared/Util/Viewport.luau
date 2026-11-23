--!strict
-- Client viewport size for UI layout. In Studio, the LocalPlayer attribute DebugViewport (Vector2) overrides it
-- and UiStyleController then shows every ScreenGui inside a canvas of that size (phone layout preview).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Signal = require(script.Parent.Signal)

local OVERRIDE_ATTRIBUTE = "DebugViewport"

local Viewport = {
	Changed = Signal.new() :: Signal.Signal<>,
	OverrideAttribute = OVERRIDE_ATTRIBUTE,
}

function Viewport.GetOverride(): Vector2?
	if not RunService:IsStudio() then
		return nil
	end
	local player = Players.LocalPlayer
	local value = if player then player:GetAttribute(OVERRIDE_ATTRIBUTE) else nil
	return if typeof(value) == "Vector2" and value.X > 0 and value.Y > 0 then value else nil
end

function Viewport.Get(): Vector2
	local override = Viewport.GetOverride()
	if override then
		return override
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

-- The UIScale UiStyleController gives fixed-size (offset) top-level panels: design resolution 1280x760.
local REFERENCE = Vector2.new(1280, 760)
local MIN_SCALE, MAX_SCALE = 0.75, 1.25 -- below 0.75 small text becomes unreadable on phones
function Viewport.UiScale(): number
	local size = Viewport.Get()
	return math.clamp(math.min(size.X / REFERENCE.X, size.Y / REFERENCE.Y), MIN_SCALE, MAX_SCALE)
end

-- Wire the signal once on the client.
if RunService:IsClient() then
	local cameraConnection: RBXScriptConnection? = nil
	local function watchCamera()
		if cameraConnection then cameraConnection:Disconnect() end
		local camera = workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				Viewport.Changed:Fire()
			end)
		end
		Viewport.Changed:Fire()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()
	local player = Players.LocalPlayer
	if player then
		player:GetAttributeChangedSignal(OVERRIDE_ATTRIBUTE):Connect(function()
			Viewport.Changed:Fire()
		end)
	end
end

return Viewport

