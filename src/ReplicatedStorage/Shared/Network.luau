--!strict
-- Creates (server) and looks up (server + client) every RemoteEvent / RemoteFunction.
-- The list lives in Config/RemoteDefinitions. Nothing else should create remotes.
--
-- Server: Main calls Network.Setup() once before any service runs.
-- Both:   Network.GetEvent("Name") / Network.GetFunction("Name").

local RunService = game:GetService("RunService")

local Shared = script.Parent
local RemoteDefinitions = require(Shared.Config.RemoteDefinitions)
local GameConfig = require(Shared.Config.Game)

local REMOTES_FOLDER_NAME = "Remotes"

local Network = {}

local eventNames: { [string]: true } = {}
local functionNames: { [string]: true } = {}

for _, name in RemoteDefinitions.Events do
	assert(not eventNames[name], `[Network] Duplicate remote name "{name}"`)
	eventNames[name] = true
end
for _, name in RemoteDefinitions.Functions do
	assert(not eventNames[name] and not functionNames[name], `[Network] Duplicate remote name "{name}"`)
	functionNames[name] = true
end

local isSetUp = false

local function getFolder(): Instance
	local existing = Shared:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing then
		return existing
	end
	if RunService:IsServer() then
		local folder = Instance.new("Folder")
		folder.Name = REMOTES_FOLDER_NAME
		folder.Parent = Shared
		return folder
	end
	local waited = Shared:WaitForChild(REMOTES_FOLDER_NAME, GameConfig.RemoteWaitTimeout)
	if waited == nil then
		error(`[Network] Remotes folder did not replicate within {GameConfig.RemoteWaitTimeout}s`)
	end
	return waited
end

local function createAll(folder: Instance, className: string, names: { string })
	for _, name in names do
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
	end
end

-- Server only. Builds every remote from the definition list exactly once.
function Network.Setup(): ()
	assert(RunService:IsServer(), "[Network] Setup must be called on the server")
	assert(not isSetUp, "[Network] Setup was already called")

	local folder = getFolder()
	-- Drop anything left in the place file so the definition list stays the single source of truth.
	folder:ClearAllChildren()
	createAll(folder, "RemoteEvent", RemoteDefinitions.Events)
	createAll(folder, "RemoteFunction", RemoteDefinitions.Functions)

	isSetUp = true
end

local function getRemote(name: string, className: string, known: { [string]: true }): Instance
	if not known[name] then
		error(`[Network] Unknown {className} "{name}". Add it to Config/RemoteDefinitions.`, 3)
	end
	if RunService:IsServer() and not isSetUp then
		error("[Network] Network.Setup() must run before remotes are requested", 3)
	end

	local remote = getFolder():WaitForChild(name, GameConfig.RemoteWaitTimeout)
	if remote == nil or not remote:IsA(className) then
		error(`[Network] {className} "{name}" was not found`, 3)
	end
	return remote
end

function Network.GetEvent(name: string): RemoteEvent
	return getRemote(name, "RemoteEvent", eventNames) :: RemoteEvent
end

function Network.GetFunction(name: string): RemoteFunction
	return getRemote(name, "RemoteFunction", functionNames) :: RemoteFunction
end

return Network

