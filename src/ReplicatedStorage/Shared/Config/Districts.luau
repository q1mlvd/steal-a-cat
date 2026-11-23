--!strict
-- City areas. Each is one or more invisible parts tagged Tags.District with a NameAttribute attribute.
-- The five main districts hold the rarer cats; Square and Paths are starter areas near the spawn.
-- Spawn rules per district live in Config/CatSpawning.

export type DistrictName = "Residential" | "Park" | "Industrial" | "Rooftops" | "Sewers" | "Square" | "Paths"

local list: { DistrictName } = { "Residential", "Park", "Industrial", "Rooftops", "Sewers", "Square", "Paths" }

local valid: { [string]: true } = {}
for _, name in list do
	valid[name] = true
end

local Districts = {
	NameAttribute = "DistrictName",
	List = table.freeze(list),
}

function Districts.IsValid(name: string): boolean
	return valid[name] == true
end

return table.freeze(Districts)

