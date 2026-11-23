--!strict
-- Catch mini-game maths shared by the server (generates + verifies) and the client (draws).
-- The marker ping-pongs across a 0..1 bar; its position is a pure function of elapsed time,
-- so the server can recompute exactly where it was when the press arrived.

local Catching = require(script.Parent.Config.Catching)
local Rarities = require(script.Parent.Config.Rarities)

export type Params = {
	sessionId: string,
	catName: string,
	rarityId: string,
	zoneStart: number, -- bar units (0..1)
	zoneSize: number,
	markerStart: number, -- 0 or 1
	markerDirection: number, -- 1 or -1
	travelTime: number, -- seconds per full crossing
	timeout: number, -- seconds
	tolerance: number, -- bar units added to each zone edge by the server check
}

local CatchMinigame = {}

function CatchMinigame.MarkerPosition(params: Params, elapsed: number): number
	local unfolded = params.markerStart + params.markerDirection * elapsed / params.travelTime
	local folded = unfolded % 2
	return if folded > 1 then 2 - folded else folded
end

function CatchMinigame.IsHit(params: Params, elapsed: number): boolean
	if elapsed < 0 or elapsed > params.timeout then
		return false
	end
	local position = CatchMinigame.MarkerPosition(params, elapsed)
	return position >= params.zoneStart - params.tolerance
		and position <= params.zoneStart + params.zoneSize + params.tolerance
end

-- Server only: pick every parameter for one attempt.
function CatchMinigame.Generate(sessionId: string, catName: string, rarity: Rarities.Rarity, rng: Random): Params
	local travelTime = rng:NextNumber(Catching.MarkerTravelTimeMin, Catching.MarkerTravelTimeMax)
		* (1 - (rarity.order - 1) * Catching.TravelTimeRarityScale)
	local zoneSize = rarity.catchZoneSize
	local zoneStart = rng:NextNumber(0, 1 - zoneSize)

	-- Start the marker at the bar end farthest from the zone so an instant press never wins.
	local zoneCentre = zoneStart + zoneSize / 2
	local markerStart = if zoneCentre > 0.5 then 0 else 1
	local markerDirection = if markerStart == 0 then 1 else -1

	return {
		sessionId = sessionId,
		catName = catName,
		rarityId = rarity.id,
		zoneStart = zoneStart,
		zoneSize = zoneSize,
		markerStart = markerStart,
		markerDirection = markerDirection,
		travelTime = travelTime,
		timeout = Catching.Timeout,
		tolerance = math.min(Catching.LatencyTolerance / travelTime, zoneSize * Catching.MaxToleranceZoneFraction),
	}
end

return table.freeze(CatchMinigame)

