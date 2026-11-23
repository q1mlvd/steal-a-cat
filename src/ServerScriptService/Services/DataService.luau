--!strict
-- Player save data, via ProfileStore (ServerScriptService/Packages/ProfileStore).
--
-- Why ProfileStore instead of raw DataStoreService: it already does everything this game needs and is
-- widely used in production -
--   * session locking: only one server owns a profile at a time; a second server asks the first to save
--     and release, and steals the lock only if the first is dead. This stops item duplication.
--   * DataStore calls retried with exponential backoff; the final save on release repeats until it succeeds.
--   * periodic autosave, and saving every active profile in game:BindToClose.
--
-- Rules for other services:
--   * Wait for data (WaitForData / DataLoaded) before giving the player anything that depends on it.
--   * Change data with Update(player, key, fn) or by editing GetData(player) - without yielding in between.
--   * Don't keep the data table across yields (it is dropped when the player leaves or a debug wipe runs).
--   * Values that depend on the clock are finalised in a save hook (RegisterSaveHook), which runs right
--     before every save, including the last one on leave / shutdown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local DataConfig = require(ReplicatedStorage.Shared.Config.Data)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local DataSchema = require(ServerScriptService.Data.DataSchema)
local ProfileStore = require(ServerScriptService.Packages.ProfileStore)

type PlayerData = DataSchema.PlayerData
export type SaveHook = (player: Player, data: PlayerData) -> ()

local DataService = {
	Priority = 5,

	-- (player, data) once a player's save is loaded and ready.
	DataLoaded = Signal.new() :: Signal.Signal<Player, PlayerData>,
}

local store: any -- ProfileStore<PlayerData>
local profiles: { [Player]: any } = {} -- active Profile per player
local loadFinished: { [Player]: boolean } = {} -- set when the load attempt ends (true = loaded)
local saveHooks: { { name: string, hook: SaveHook } } = {}

local function kick(player: Player, message: string)
	if player.Parent == Players then
		player:Kick(message)
	end
end

local function runSaveHooks(player: Player, data: PlayerData)
	for _, entry in saveHooks do
		local ok, err = pcall(entry.hook, player, data)
		if not ok then
			warn(`[DataService] Save hook "{entry.name}" failed for {player.Name}: {err}`)
		end
	end
end

-- Studio test-profile mode keeps solo tests off real saves (see Config/Data.StudioTestProfile).
function DataService.IsStudioTestProfile(): boolean
	return RunService:IsStudio() and DataConfig.StudioTestProfile == true
end

function DataService.GetProfileKey(userId: number): string
	local prefix = if DataService.IsStudioTestProfile() then DataConfig.StudioTestKeyPrefix else DataConfig.KeyPrefix
	return prefix .. userId
end

local function loadProfile(player: Player)
	local profile = store:StartSessionAsync(DataService.GetProfileKey(player.UserId), {
		Cancel = function(): boolean
			return player.Parent ~= Players -- stop retrying if they leave while we wait
		end,
	})

	if profile == nil then
		-- Never fall back to empty data: it would overwrite the real save later.
		loadFinished[player] = false
		warn(`[DataService] Could not load data for {player.Name} ({player.UserId})`)
		kick(player, DataConfig.LoadFailedKickMessage)
		return
	end

	profile:AddUserId(player.UserId) -- GDPR association

	local migrated, reason = DataSchema.Migrate(profile.Data)
	if not migrated then
		loadFinished[player] = false
		warn(`[DataService] Refusing data for {player.Name}: {reason}`)
		profile:EndSession()
		kick(player, DataConfig.NewerVersionKickMessage)
		return
	end
	profile:Reconcile() -- fill in fields added since this save was written

	profile.OnSave:Connect(function()
		runSaveHooks(player, profile.Data)
	end)
	profile.OnSessionEnd:Connect(function()
		-- Our own release on leave, or another server took the session: either way stop using it here.
		if profiles[player] == profile then
			profiles[player] = nil
			kick(player, DataConfig.SessionLostKickMessage)
		end
	end)

	if player.Parent ~= Players then
		profile:EndSession() -- left while loading
		loadFinished[player] = nil
		return
	end

	profiles[player] = profile
	loadFinished[player] = true
	DataService.DataLoaded:Fire(player, profile.Data)
end

local function wipeForDebug(player: Player)
	local profile = profiles[player]
	if profile == nil then
		return
	end
	profiles[player] = nil -- stop every service from writing to it this session
	profile.Data = DataSchema.Template()
	profile:EndSession()
	warn(`[DataService] Studio debug: wiped data for {player.Name}`)
	kick(player, DataConfig.DebugWipeKickMessage)
end

local function onPlayerAdded(player: Player)
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal(DataConfig.DebugWipeAttribute):Connect(function()
			if player:GetAttribute(DataConfig.DebugWipeAttribute) == true then
				wipeForDebug(player)
			end
		end)
	end
	loadProfile(player)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	profiles[player] = nil
	loadFinished[player] = nil
	if profile then
		profile:EndSession() -- final save (save hooks run first) and releases the session lock
	end
end

-- Public API -----------------------------------------------------------------

-- The player's live data table, or nil if it isn't loaded (yet / any more).
function DataService.GetData(player: Player): PlayerData?
	local profile = profiles[player]
	return if profile and profile:IsActive() then profile.Data else nil
end

function DataService.IsLoaded(player: Player): boolean
	return DataService.GetData(player) ~= nil
end

-- Yields until the player's data is loaded. Returns nil if loading failed or the player left.
function DataService.WaitForData(player: Player): PlayerData?
	while player.Parent == Players and loadFinished[player] == nil do
		task.wait(DataConfig.WaitPollInterval)
	end
	return DataService.GetData(player)
end

-- data[key] = transform(data[key]). Returns false if the player's data isn't loaded.
function DataService.Update(player: Player, key: string, transform: (any) -> any): boolean
	local data = DataService.GetData(player)
	if data == nil then
		return false
	end
	local raw = data :: any
	raw[key] = transform(raw[key])
	return true
end

-- Saves the player's profile now (non-blocking). Use right after important cross-player changes.
function DataService.SaveNow(player: Player)
	local profile = profiles[player]
	if profile and profile:IsActive() then
		profile:Save()
	end
end

-- Requests a save and YIELDS until a completed save satisfies `check(lastSavedData)` (e.g. it contains a
-- receipt id), or until `timeout`. Returns true only after a durable save matched. Use for receipts.
function DataService.SaveAndWait(player: Player, check: (savedData: any) -> boolean, timeout: number): boolean
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() then
		return false
	end
	if check(profile.LastSavedData) then
		return true
	end
	local done = false
	local deadline = os.clock() + timeout
	local connection = profile.OnAfterSave:Connect(function(savedData: any)
		if check(savedData) then
			done = true
		elseif os.clock() < deadline and profile:IsActive() then
			-- A save that started before our change finished first: request another one.
			task.defer(function()
				if profile:IsActive() then
					profile:Save()
				end
			end)
		end
	end)
	profile:Save()
	while not done and os.clock() < deadline and profile:IsActive() do
		task.wait(DataConfig.WaitPollInterval)
	end
	connection:Disconnect()
	return done
end

-- `hook` runs (without yielding) right before every save of every profile.
function DataService.RegisterSaveHook(name: string, hook: SaveHook)
	table.insert(saveHooks, { name = name, hook = hook })
end

-- Lifecycle ------------------------------------------------------------------

function DataService:Init(): ()
	ProfileStore.SetConstant("AUTO_SAVE_PERIOD", DataConfig.AutoSavePeriod)
	store = ProfileStore.New(DataConfig.StoreName, DataSchema.Template())
end

function DataService:Start(): ()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	-- Shutdown saving: ProfileStore binds game:BindToClose and saves + releases every active profile.
end

return DataService

