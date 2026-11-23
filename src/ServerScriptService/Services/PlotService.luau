--!strict
-- Owns player houses ("plots"): assignment on join, release on leave, spawning players at home.
-- Plot ownership lives only in this module's tables. The OwnerUserId attribute is a display mirror for clients.
--
-- Plot Model layout (validated at Init):
--   Door, EntranceTrigger, InteriorZone, SpawnPoint, Bowl : BasePart
--   PillowsFolder : Folder of BaseParts tagged Tags.Pillow with a PillowIndex attribute
--   Sign : BasePart with SurfaceGui > NameLabel (TextLabel)
--   SecondFloor : Folder (slab, upper walls, stairs ramp, rails). InteriorZone covers both floors;
--   pillows 5..30 stand on the second floor and are unlocked by pillowCount (PillowService).
-- PlotService adds a "Runtime" Folder per plot for spawned content; it is emptied when the plot is freed.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage.Shared.Config.Tags)
local PlotConfig = require(ReplicatedStorage.Shared.Config.Plots)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Maid = require(ReplicatedStorage.Shared.Util.Maid)
local DataService = require(script.Parent.DataService)

local RUNTIME_FOLDER_NAME = "Runtime"

type PlotInfo = {
	model: Model,
	index: number,
	interiorZone: BasePart,
	spawnPoint: BasePart,
	nameLabel: TextLabel,
	pillows: { BasePart },
	runtime: Folder,
}

local PlotService = {
	Priority = 20,

	-- (player, plot) after a plot is assigned.
	PlotAssigned = Signal.new() :: Signal.Signal<Player, Model>,
	-- (player, plot) when the owner leaves, before the Runtime folder is cleared.
	PlotReleased = Signal.new() :: Signal.Signal<Player, Model>,
}

local plotInfos: { PlotInfo } = {} -- sorted by index
local infoByModel: { [Model]: PlotInfo } = {}
local ownerByPlot: { [Model]: Player } = {}
local plotByPlayer: { [Player]: Model } = {}
local playerMaids: { [Player]: Maid.Maid } = {}

local function requirePart(plot: Model, name: string): BasePart
	local part = plot:FindFirstChild(name)
	if part == nil or not part:IsA("BasePart") then
		error(`[PlotService] {plot:GetFullName()} is missing BasePart "{name}"`)
	end
	return part
end

local function buildPlotInfo(plot: Model): PlotInfo
	local index = plot:GetAttribute(PlotConfig.IndexAttribute)
	if type(index) ~= "number" then
		error(`[PlotService] {plot:GetFullName()} needs a numeric "{PlotConfig.IndexAttribute}" attribute`)
	end

	requirePart(plot, "Door")
	requirePart(plot, "EntranceTrigger")
	requirePart(plot, "Bowl")

	local sign = requirePart(plot, "Sign")
	local nameLabel = sign:FindFirstChild("NameLabel", true)
	if nameLabel == nil or not nameLabel:IsA("TextLabel") then
		error(`[PlotService] {plot:GetFullName()}.Sign needs a SurfaceGui with a TextLabel "NameLabel"`)
	end

	local pillowsFolder = plot:FindFirstChild("PillowsFolder")
	if pillowsFolder == nil then
		error(`[PlotService] {plot:GetFullName()} is missing "PillowsFolder"`)
	end
	local pillows: { BasePart } = {}
	for _, child in pillowsFolder:GetChildren() do
		if child:IsA("BasePart") and CollectionService:HasTag(child, Tags.Pillow) then
			table.insert(pillows, child)
		end
	end
	table.sort(pillows, function(a: BasePart, b: BasePart): boolean
		local ia = a:GetAttribute(PlotConfig.PillowIndexAttribute)
		local ib = b:GetAttribute(PlotConfig.PillowIndexAttribute)
		return (if type(ia) == "number" then ia else math.huge) < (if type(ib) == "number" then ib else math.huge)
	end)

	local runtime = plot:FindFirstChild(RUNTIME_FOLDER_NAME)
	if runtime == nil or not runtime:IsA("Folder") then
		local folder = Instance.new("Folder")
		folder.Name = RUNTIME_FOLDER_NAME
		folder.Parent = plot
		runtime = folder
	end

	return {
		model = plot,
		index = index,
		interiorZone = requirePart(plot, "InteriorZone"),
		spawnPoint = requirePart(plot, "SpawnPoint"),
		nameLabel = nameLabel,
		pillows = pillows,
		runtime = runtime :: Folder,
	}
end

local function isPointInPart(point: Vector3, part: BasePart): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

local function getRootPart(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function resetPlot(info: PlotInfo)
	info.model:SetAttribute(PlotConfig.OwnerAttribute, nil)
	info.nameLabel.Text = PlotConfig.SignEmptyText
	info.runtime:ClearAllChildren()
end

local function assignPlot(player: Player): Model?
	local existing = plotByPlayer[player]
	if existing then
		return existing
	end

	for _, info in plotInfos do
		if ownerByPlot[info.model] == nil then
			ownerByPlot[info.model] = player
			plotByPlayer[player] = info.model
			info.model:SetAttribute(PlotConfig.OwnerAttribute, player.UserId)
			info.nameLabel.Text = string.format(PlotConfig.SignOwnerFormat, player.DisplayName)
			player:SetAttribute(PlotConfig.PlayerPlotAttribute, info.index)
			PlotService.PlotAssigned:Fire(player, info.model)
			return info.model
		end
	end

	return nil
end

local function releasePlot(player: Player)
	local plot = plotByPlayer[player]
	if plot == nil then
		return
	end

	PlotService.PlotReleased:Fire(player, plot)

	plotByPlayer[player] = nil
	ownerByPlot[plot] = nil
	resetPlot(infoByModel[plot])
end

local function onCharacterAdded(player: Player, character: Model)
	local plot = plotByPlayer[player]
	if plot == nil then
		return
	end

	local root = character:WaitForChild("HumanoidRootPart", PlotConfig.CharacterLoadTimeout)
	-- Re-check after yielding: the player may have left or respawned meanwhile.
	if root == nil or plotByPlayer[player] ~= plot or player.Character ~= character then
		return
	end

	character:PivotTo(PlotService.GetSpawnCFrame(plot))
end

local function onPlayerAdded(player: Player)
	if playerMaids[player] then
		return
	end
	local maid = Maid.new()
	playerMaids[player] = maid

	-- A house shows saved cats and bowl coins, so hand one out only once the player's data is loaded.
	if DataService.WaitForData(player) == nil or playerMaids[player] ~= maid then
		return -- left, or kicked because loading failed
	end

	if assignPlot(player) == nil then
		warn(`[PlotService] No free plot for {player.Name}; kicking`)
		player:Kick(PlotConfig.NoFreePlotKickMessage)
		return
	end

	maid:Add(player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end))
	local character = player.Character
	if character then
		task.spawn(onCharacterAdded, player, character)
	end
end

local function onPlayerRemoving(player: Player)
	local maid = playerMaids[player]
	if maid then
		maid:Clean()
		playerMaids[player] = nil
	end
	releasePlot(player)
end

-- Public API -----------------------------------------------------------------

function PlotService.GetPlot(player: Player): Model?
	return plotByPlayer[player]
end

function PlotService.GetOwner(plot: Model): Player?
	return ownerByPlot[plot]
end

function PlotService.IsInsidePlot(player: Player, plot: Model): boolean
	local info = infoByModel[plot]
	local root = getRootPart(player)
	if info == nil or root == nil then
		return false
	end
	return isPointInPart(root.Position, info.interiorZone)
end

function PlotService.GetPlots(): { Model }
	local models = table.create(#plotInfos)
	for _, info in plotInfos do
		table.insert(models, info.model)
	end
	return models
end

-- Pillow parts ordered by PillowIndex.
function PlotService.GetPillows(plot: Model): { BasePart }
	local info = infoByModel[plot]
	return if info then table.clone(info.pillows) else {}
end

-- Folder for runtime content in this plot (placed cats, effects). Emptied when the plot is freed.
function PlotService.GetRuntimeFolder(plot: Model): Folder?
	local info = infoByModel[plot]
	return if info then info.runtime else nil
end

function PlotService.GetSpawnCFrame(plot: Model): CFrame
	local info = infoByModel[plot]
	assert(info, "[PlotService] Unknown plot")
	return info.spawnPoint.CFrame + Vector3.new(0, PlotConfig.SpawnHeightOffset, 0)
end

-- Lifecycle ------------------------------------------------------------------

function PlotService:Init(): ()
	for _, instance in CollectionService:GetTagged(Tags.Plot) do
		if not instance:IsA("Model") or not instance:IsDescendantOf(workspace) then
			continue
		end
		local info = buildPlotInfo(instance)
		table.insert(plotInfos, info)
		infoByModel[instance] = info
		resetPlot(info)
	end

	table.sort(plotInfos, function(a: PlotInfo, b: PlotInfo): boolean
		return a.index < b.index
	end)

	if #plotInfos == 0 then
		warn(`[PlotService] No Models tagged "{Tags.Plot}" found in Workspace`)
	end
	print(`[PlotService] Found {#plotInfos} plot(s)`)
end

function PlotService:Start(): ()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PlotService

