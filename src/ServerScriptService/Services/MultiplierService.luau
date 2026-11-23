--!strict
-- The single place every income multiplier goes through.
-- Later systems (game passes, boosts, rebirths, mutations) register a source here; EconomyService only
-- ever asks GetIncomeMultiplier. Sources multiply together.

local MultiplierService = {
	Priority = 12,
}

export type IncomeSource = (player: Player) -> number

local incomeSources: { [string]: IncomeSource } = {}

-- `name` identifies the source so it can be replaced or removed (e.g. "Rebirths", "VIPPass").
function MultiplierService.RegisterIncomeSource(name: string, source: IncomeSource)
	incomeSources[name] = source
end

function MultiplierService.UnregisterIncomeSource(name: string)
	incomeSources[name] = nil
end

function MultiplierService.GetIncomeMultiplier(player: Player): number
	local multiplier = 1
	for _, source in incomeSources do
		multiplier *= source(player)
	end
	return multiplier
end

return MultiplierService

