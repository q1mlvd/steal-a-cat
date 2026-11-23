--!strict
-- Short number formatting for UI: 999, 1.2K, 3.4M, 5.6B, ...
-- Rounds DOWN so the UI never shows more coins than the player has.

local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local THOUSAND = 1000
local DECIMALS_SCALE = 10 -- one decimal place

local NumberFormat = {}

function NumberFormat.Format(value: number): string
	if value ~= value then -- NaN
		return "0"
	end
	local sign = if value < 0 then "-" else ""
	local magnitude = math.abs(value)
	if magnitude < THOUSAND then
		return sign .. tostring(math.floor(magnitude))
	end

	local tier = math.min(math.floor(math.log10(magnitude) / 3), #SUFFIXES)
	local scaled = magnitude / THOUSAND ^ tier
	if scaled >= THOUSAND and tier < #SUFFIXES then -- guard against log10 rounding
		tier += 1
		scaled /= THOUSAND
	end

	local truncated = math.floor(scaled * DECIMALS_SCALE) / DECIMALS_SCALE
	local text = if truncated % 1 == 0 then string.format("%d", truncated) else string.format("%.1f", truncated)
	return sign .. text .. SUFFIXES[tier]
end

return table.freeze(NumberFormat)

