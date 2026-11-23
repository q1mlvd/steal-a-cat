--!strict
local Config = require(script.Parent.Parent.Config.WorldBillboards)
local watched = setmetatable({}, { __mode = "k" })
local WorldBillboard = {}

function WorldBillboard.Apply(gui: BillboardGui)
	if watched[gui] then return end
	local applying = false
	local function constrain()
		if applying then return end
		applying = true
		local size = gui.Size
		local scaled = size.X.Scale ~= 0 or size.Y.Scale ~= 0
		local target = if gui.Name == "Nameplate" then Config.CatSize else Config.DefaultSize
		local width = if scaled or size.X.Offset <= 0 then target.X else size.X.Offset
		local height = if scaled or size.Y.Offset <= 0 then target.Y else size.Y.Offset
		gui.Size = UDim2.fromOffset(math.min(width, Config.Maximum.X), math.min(height, Config.Maximum.Y))
		local distance = if gui.Name == "Nameplate" then Config.CatMaxDistance elseif gui.Name:find("Marker") then Config.MarkerMaxDistance else Config.MaxDistance
		gui.MaxDistance = if gui.MaxDistance > 0 then math.min(gui.MaxDistance, distance) else distance
		gui.LightInfluence = Config.LightInfluence
		gui.ClipsDescendants = true
		applying = false
	end
	watched[gui] = true
	constrain()
	gui:GetPropertyChangedSignal("Size"):Connect(constrain)
	gui:GetPropertyChangedSignal("MaxDistance"):Connect(constrain)
	gui:GetPropertyChangedSignal("LightInfluence"):Connect(constrain)
end

return WorldBillboard

