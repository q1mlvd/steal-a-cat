--!strict
-- Studio-only test bridge. Exists only when RunService:IsStudio() AND Config/Data.StudioTestProfile is on,
-- i.e. every profile in this session is a "StudioTest_" profile - real saves can't be touched.
-- ServerStorage.StudioDebug (BindableFunction, server only - clients can't reach ServerStorage):
--   Invoke("call", serviceName, methodName, ...)  -> {ok, ...results}   (live service modules)
--   Invoke("data", player)                         -> deep copy of the player's live data
--   Invoke("set", player, "a.b.c", value)         -> sets a data field (e.g. "coins", "upgrades.Speed")
-- Never active outside Studio.

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local DataService = require(script.Parent.DataService)

local StudioDebugService = {
	Priority = 99,
}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, inner in value do
		result[key] = deepCopy(inner)
	end
	return result
end

local function handle(command: string, ...: any): any
	if command == "call" then
		local serviceName, methodName = select(1, ...), select(2, ...)
		local module = script.Parent:FindFirstChild(serviceName)
		assert(module and module:IsA("ModuleScript"), `unknown service {serviceName}`)
		local service = require(module) :: any
		local method = service[methodName]
		assert(type(method) == "function", `unknown method {serviceName}.{methodName}`)
		return table.pack(pcall(method, select(3, ...)))
	elseif command == "data" then
		return deepCopy(DataService.GetData((...) :: Player))
	elseif command == "set" then
		local player, path, value = ...
		local node: any = DataService.GetData(player)
		assert(node, "data not loaded")
		local keys = string.split(path, ".")
		for index = 1, #keys - 1 do
			node = node[keys[index]]
		end
		node[keys[#keys]] = value
		return true
	end
	error(`unknown command {command}`)
end

function StudioDebugService:Init(): ()
	if not RunService:IsStudio() or not DataService.IsStudioTestProfile() then
		return
	end
	local existing = ServerStorage:FindFirstChild("StudioDebug")
	if existing then
		existing:Destroy()
	end
	local bindable = Instance.new("BindableFunction")
	bindable.Name = "StudioDebug"
	bindable.OnInvoke = handle
	bindable.Archivable = false
	bindable.Parent = ServerStorage
end

return StudioDebugService

