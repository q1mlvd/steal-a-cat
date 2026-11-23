--!strict
-- Shared ordering/ownership rules. Counts and armed flags always come from a server snapshot.
local Items = require(script.Parent.Parent.Config.Items)

export type Snapshot = { inventory: { [string]: number }, fishReady: boolean, softPawsReady: boolean }
local ItemInventory = {}

function ItemInventory.Ready(snapshot: Snapshot, id: string): boolean
	return (id == "Fish" and snapshot.fishReady) or (id == "SoftPaws" and snapshot.softPawsReady)
end

function ItemInventory.Owned(snapshot: Snapshot, id: string): boolean
	return (snapshot.inventory[id] or 0) > 0 or ItemInventory.Ready(snapshot, id)
end

function ItemInventory.Usable(id: string): boolean
	local item = Items.Get(id)
	return item ~= nil and (item.type == "consumable" or item.permanentScope == "cat")
end

function ItemInventory.OwnedIds(snapshot: Snapshot, category: string?): { string }
	local result = {}
	for _, item in Items.List do
		if (category == nil or category == "All" or item.category == category) and ItemInventory.Owned(snapshot, item.id) then
			table.insert(result, item.id)
		end
	end
	return result
end

-- Preferred items retain their relative order; consumed items leave no empty/x0 slots.
function ItemInventory.HotbarIds(snapshot: Snapshot, preferred: { string }, category: string?): ({ string }, number)
	local result: { string } = {}
	local seen: { [string]: boolean } = {}
	local function include(id: string)
		local item = Items.Get(id)
		if item and not seen[id] and ItemInventory.Usable(id) and ItemInventory.Owned(snapshot, id)
			and (category == nil or category == "All" or item.category == category) then
			seen[id] = true
			table.insert(result, id)
		end
	end
	for _, id in preferred do include(id) end
	for _, item in Items.List do include(item.id) end
	local total = #result
	while #result > Items.Hotbar.SlotCount do table.remove(result) end
	return result, total
end

return table.freeze(ItemInventory)

