--!strict
-- Live events (Config/Events): a scheduler runs Starfall / Rain / Dog Raid automatically (one at a time),
-- announces start/end (NotificationService) and mirrors the active event + countdown on workspace
-- attributes for EventController. Admins can StartEvent/StopEvent any event (AdminService).
-- (Event API names differ from the Loader lifecycle method EventService:Start - same names would overwrite it.)
--   Starfall - bonus wild cats with the Starry mutation drop from the sky.
--   Rain     - wild cats hide (can't be caught, no new spawns); steal holds are halved.
--   DogRaid  - DefenseService raid dogs go for house bowls (coins only); slap them away for a reward.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local Events = require(Config.Events)
local Rarities = require(Config.Rarities)
local CatSpawnService = require(script.Parent.CatSpawnService)
local DefenseService = require(script.Parent.DefenseService)
local NotificationService = require(script.Parent.NotificationService)
local StealService = require(script.Parent.StealService)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local EventService = {
	Priority = 96,
	-- (eventName, active)
	EventChanged = Signal.new() :: Signal.Signal<string, boolean>,
}

local random = Random.new()
local active: string? = nil
local endsAt = 0 -- os.clock()
local nextAt: { [string]: number } = {} -- os.clock() per event
local nextStarAt = 0

local function serverTime(clockTime: number): number
	return workspace:GetServerTimeNow() + (clockTime - os.clock())
end

local function mirrorNext()
	local soonest: string? = nil
	for _, name in Events.Order do
		if soonest == nil or nextAt[name] < nextAt[soonest] then
			soonest = name
		end
	end
	workspace:SetAttribute(Events.NextAttribute, soonest)
	workspace:SetAttribute(Events.NextAtAttribute, if soonest then serverTime(nextAt[soonest]) else nil)
end

local function rollStarRarity(): string
	local total = 0
	for _, weight in Events.Starfall.RarityWeights do
		total += weight
	end
	local roll = random:NextNumber(0, total)
	local chosen = "Uncommon"
	for _, rarity in Rarities.List do
		local weight = (Events.Starfall.RarityWeights :: any)[rarity.id]
		if weight then
			roll -= weight
			chosen = rarity.id
			if roll <= 0 then break end
		end
	end
	return chosen
end

local function dropStarCat(): Model?
	local model = CatSpawnService.SpawnBonusCat(rollStarRarity(), Events.Starfall.MaxCats)
	if model then
		model:SetAttribute("Mutation", Events.Starfall.Mutation)
		model:PivotTo(model:GetPivot() + Vector3.new(0, Events.Starfall.DropHeight, 0))
	end
	return model
end

-- Studio only: make `name` come due in `seconds` (scheduler test).
function EventService.DebugSetNext(name: string, seconds: number): boolean
	if not game:GetService("RunService"):IsStudio() or nextAt[name] == nil then
		return false
	end
	nextAt[name] = os.clock() + seconds
	mirrorNext()
	return true
end

function EventService.GetActive(): string?
	return active
end

function EventService.StopEvent()
	local name = active
	if name == nil then
		return
	end
	active = nil
	if name == "Rain" then
		CatSpawnService.SetHiding(false)
		StealService.SetHoldMultiplier(1)
	elseif name == "DogRaid" then
		DefenseService.StopRaid()
	end
	workspace:SetAttribute(Events.ActiveAttribute, nil)
	workspace:SetAttribute(Events.EndsAtAttribute, nil)
	NotificationService.AnnounceEvent(`{(Events.Schedule :: any)[name].title} is over!`, name)
	EventService.EventChanged:Fire(name, false)
	mirrorNext()
end

-- Starts an event now (stops any running one). Returns false for unknown names.
function EventService.StartEvent(name: string, duration: number?): boolean
	local schedule = (Events.Schedule :: any)[name]
	if schedule == nil then
		return false
	end
	EventService.StopEvent()
	active = name
	endsAt = os.clock() + (duration or schedule.duration)
	nextAt[name] = os.clock() + schedule.interval
	if name == "Rain" then
		CatSpawnService.SetHiding(true)
		StealService.SetHoldMultiplier(Events.Rain.StealHoldMultiplier)
	elseif name == "DogRaid" then
		DefenseService.StartRaid()
	elseif name == "Starfall" then
		nextStarAt = 0
	end
	workspace:SetAttribute(Events.ActiveAttribute, name)
	workspace:SetAttribute(Events.EndsAtAttribute, serverTime(endsAt))
	NotificationService.AnnounceEvent(schedule.announce, name) -- the banner shows the event's icon art
	EventService.EventChanged:Fire(name, true)
	mirrorNext()
	return true
end

local function tick()
	local now = os.clock()
	if active then
		if now >= endsAt or (active == "DogRaid" and DefenseService.GetRaidDogCount() == 0 and now > endsAt - (Events.Schedule.DogRaid.duration - 5)) then
			EventService.StopEvent()
		elseif active == "Starfall" and now >= nextStarAt then
			nextStarAt = now + Events.Starfall.SpawnInterval
			dropStarCat()
		end
		return
	end
	for _, name in Events.Order do
		if now >= nextAt[name] then
			EventService.StartEvent(name)
			return
		end
	end
end

function EventService:Init(): ()
	CatSpawnService.SetSeason(Events.Season)
	workspace:SetAttribute("Season", Events.Season)
	local now = os.clock()
	for _, name in Events.Order do
		nextAt[name] = now + (Events.Schedule :: any)[name].interval
	end
end

function EventService:Start(): ()
	mirrorNext()
	task.spawn(function()
		while true do
			task.wait(Events.TickInterval)
			local ok, err = pcall(tick)
			if not ok then
				warn(`[EventService] tick failed: {tostring(err)}`)
			end
		end
	end)
end

return EventService

