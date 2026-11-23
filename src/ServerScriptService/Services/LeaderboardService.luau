--!strict
-- Global leaderboards (OrderedDataStore), drawn on the square's LeaderboardSpot board and refreshed every
-- Retention.LeaderboardInterval: income per second, total cats stolen, most loyal cat. Studio sessions use
-- separately prefixed store names so tests never touch live boards. Every DataStore call is pcall'd.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = ReplicatedStorage.Shared.Config
local Retention = require(Config.Retention)
local Shop = require(Config.Shop)
local NumberFormat = require(ReplicatedStorage.Shared.Util.NumberFormat)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local UI = Shop.Ui

local LeaderboardService = {
	Priority = 100,
}

local stores: { [string]: OrderedDataStore } = {}
local names: { [number]: string } = {}
local columns: { [string]: { TextLabel } } = {}

local function value(player: Player, id: string): number
	local data = DataService.GetData(player)
	if data == nil then return 0 end
	if id == "Income" then
		return math.floor(EconomyService.GetIncomePerSecond(player))
	elseif id == "Stolen" then
		return math.floor(data.stats.catsStolen)
	end
	local best = 0
	for _, record in data.cats do
		best = math.max(best, math.floor(record.loyalty))
	end
	return best
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then return cached end
	local player = Players:GetPlayerByUserId(userId)
	local name = if player then player.DisplayName else nil
	if name == nil then
		local ok, result = pcall(Players.GetNameFromUserIdAsync, Players, userId)
		name = if ok and type(result) == "string" then result else `#{userId}`
	end
	names[userId] = name :: string
	return name :: string
end

local function buildBoard()
	local spot = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Square") and workspace.Map.Square:FindFirstChild("LeaderboardSpot")
	if spot == nil or not spot:IsA("BasePart") then
		warn("[LeaderboardService] No Workspace.Map.Square.LeaderboardSpot")
		return
	end
	for _, child in spot:GetChildren() do
		if child:IsA("BillboardGui") then
			child.Enabled = false -- the old placeholder label; the boards replace it
		end
	end
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = `Leaderboards{face.Name}`
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = spot
		local background = Instance.new("Frame")
		background.Size = UDim2.fromScale(1, 1)
		background.BackgroundColor3 = UI.Background
		background.Parent = gui
		for index, board in Retention.Leaderboards do
			local column = Instance.new("Frame")
			column.BackgroundTransparency = 1
			column.Position = UDim2.fromScale((index - 1) / #Retention.Leaderboards, 0)
			column.Size = UDim2.fromScale(1 / #Retention.Leaderboards, 1)
			column.Parent = background
			local layout = Instance.new("UIListLayout")
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Parent = column
			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.Size = UDim2.new(1, 0, 1 / (Retention.LeaderboardTop + 2), 0)
			title.Font = Enum.Font.FredokaOne
			title.TextScaled = true
			title.TextColor3 = UI.Coin
			title.Text = board.title
			title.LayoutOrder = 0
			title.Parent = column
			columns[board.id] = columns[board.id] or {}
			for rank = 1, Retention.LeaderboardTop do
				local row = Instance.new("TextLabel")
				row.BackgroundTransparency = 1
				row.Size = UDim2.new(1, 0, 1 / (Retention.LeaderboardTop + 2), 0)
				row.Font = Enum.Font.GothamBold
				row.TextScaled = true
				row.TextColor3 = UI.Text
				row.Text = ""
				row.LayoutOrder = rank
				row.Parent = column
				table.insert(columns[board.id], row)
			end
		end
	end
end

local function refresh()
	for _, board in Retention.Leaderboards do
		local store = stores[board.id]
		for _, player in Players:GetPlayers() do
			if DataService.GetData(player) then
				local score = value(player, board.id)
				pcall(store.SetAsync, store, tostring(player.UserId), score)
			end
		end
		local ok, pages = pcall(store.GetSortedAsync, store, false, Retention.LeaderboardTop)
		if not ok then
			warn(`[LeaderboardService] {board.id}: {tostring(pages)}`)
			continue
		end
		local entries = (pages :: DataStorePages):GetCurrentPage()
		local labels = columns[board.id] or {}
		for index, label in labels do
			local rank = (index - 1) % Retention.LeaderboardTop + 1
			local entry = entries[rank]
			local userId = if entry then tonumber(entry.key) else nil
			label.Text = if entry and userId then `{rank}. {nameOf(userId)}  {NumberFormat.Format(entry.value)}` else ""
		end
	end
end

function LeaderboardService:Init(): ()
	local prefix = if RunService:IsStudio() then Retention.LeaderboardStudioPrefix else ""
	for _, board in Retention.Leaderboards do
		stores[board.id] = DataStoreService:GetOrderedDataStore(prefix .. board.store)
	end
	buildBoard()
end

function LeaderboardService:Start(): ()
	task.spawn(function()
		task.wait(10) -- let saves load first
		while true do
			local ok, err = pcall(refresh)
			if not ok then warn(`[LeaderboardService] {tostring(err)}`) end
			task.wait(Retention.LeaderboardInterval)
		end
	end)
end

-- Studio test helper: refresh now.
function LeaderboardService.DebugRefresh(): boolean
	if not RunService:IsStudio() then return false end
	refresh()
	return true
end

return LeaderboardService

