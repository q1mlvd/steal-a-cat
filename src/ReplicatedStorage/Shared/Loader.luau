--!strict
-- Shared bootstrapper for server Services and client Controllers.
--
-- Each ModuleScript in the folder returns a table that may define:
--   Priority: number?  -- lower runs first (default DEFAULT_PRIORITY); ties sort by name
--   Init(self)         -- synchronous setup; must not yield. Runs for ALL modules before any Start.
--   Start(self)        -- runs in its own thread after every Init has finished; may yield/loop.

local DEFAULT_PRIORITY = 100

export type Module = {
	Priority: number?,
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
}

type Entry = {
	name: string,
	priority: number,
	module: Module,
}

local Loader = {}

local function collect(folder: Instance): { Entry }
	local entries: { Entry } = {}

	for _, child in folder:GetChildren() do
		if not child:IsA("ModuleScript") then
			continue
		end

		local result = require(child) :: any
		if type(result) ~= "table" then
			error(`[Loader] {child:GetFullName()} must return a table, got {typeof(result)}`)
		end

		local module = result :: Module
		table.insert(entries, {
			name = child.Name,
			priority = module.Priority or DEFAULT_PRIORITY,
			module = module,
		})
	end

	table.sort(entries, function(a: Entry, b: Entry): boolean
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		return a.name < b.name
	end)

	return entries
end

function Loader.Run(folder: Instance, label: string): ()
	local entries = collect(folder)

	for _, entry in entries do
		local init = entry.module.Init
		if init then
			init(entry.module)
		end
		print(`[{label}] Initialized {entry.name}`)
	end

	for _, entry in entries do
		local start = entry.module.Start
		if start then
			task.spawn(start, entry.module)
		end
	end

	local names = table.create(#entries)
	for _, entry in entries do
		table.insert(names, entry.name)
	end
	print(`[{label}] All {#entries} module(s) started: {table.concat(names, ", ")}`)
end

return table.freeze(Loader)

