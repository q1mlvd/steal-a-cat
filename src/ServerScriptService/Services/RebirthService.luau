--!strict
-- Rebirth (Config/Rebirth). One validated, NO-YIELD update of the live profile:
--   rebirths +1, coins/bowl 0, every cat except the chosen 1 (3 with Keep 3 Cats) removed, upgrades 0,
--   consumables reset (Net, Guard Dog, unattached Bell tokens kept), then effects are re-applied and the
--   save is requested. Refused while any of the player's cats is stolen, returning, delivering or carried.
-- Also: permanent income bonus (MultiplierService "Rebirths"), leaderstats Rebirths, house styles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = ReplicatedStorage.Shared.Config
local Economy = require(Config.Economy)
local Monetization = require(Config.Monetization)
local Rebirth = require(Config.Rebirth)
local Network = require(ReplicatedStorage.Shared.Network)
local DataService = require(script.Parent.DataService)
local DefenseService = require(script.Parent.DefenseService)
local EconomyService = require(script.Parent.EconomyService)
local GateService = require(script.Parent.GateService)
local MonetizationService = require(script.Parent.MonetizationService)
local MultiplierService = require(script.Parent.MultiplierService)
local NameTagService = require(script.Parent.NameTagService)
local NotificationService = require(script.Parent.NotificationService)
local PillowService = require(script.Parent.PillowService)
local PlotService = require(script.Parent.PlotService)
local ShopService = require(script.Parent.ShopService)
local UpgradeService = require(script.Parent.UpgradeService)

local RebirthService = {
	Priority = 95,
}

local lastRequestAt: { [Player]: number } = {}
local skipPreparing: { [Player]: boolean } = {}
local openEvent: RemoteEvent

local function rebirthsOf(player: Player): number
	local data = DataService.GetData(player)
	local value = if data then data.rebirths else 0
	return if type(value) == "number" and value == value and value >= 0 then math.floor(value) else 0
end

function RebirthService.GetKeepCount(player: Player): number
	return if MonetizationService.OwnsPass(player, "Keep3Cats") then Monetization.KeepCatsWithPass else Rebirth.KeepCats
end

local function applyStyle(plot: Model, styleId: string)
	local style = Rebirth.GetStyle(styleId)
	for _, folderName in Rebirth.WallFolders do
		local folder = plot:FindFirstChild(folderName)
		if folder then
			for _, part in folder:GetChildren() do
				if part:IsA("BasePart") and Rebirth.WallNames[part.Name] then
					part.Color = style.wallColor
				elseif part:IsA("BasePart") and Rebirth.FloorNames[part.Name] then
					part.Color = style.floorColor
				end
			end
		end
	end
	local floor = plot:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		floor.Color = style.floorColor
	end
end

local function refreshStyle(player: Player)
	local plot = PlotService.GetPlot(player)
	local data = DataService.GetData(player)
	if plot and data then
		local style = Rebirth.GetStyle(data.houseStyle)
		applyStyle(plot, if rebirthsOf(player) >= style.requiredRebirths then style.id else Rebirth.DefaultStyle)
	end
end

local function setLeaderstat(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats == nil then
		return
	end
	local value = leaderstats:FindFirstChild(Rebirth.LeaderstatName)
	if value == nil then
		local created = Instance.new("IntValue")
		created.Name = Rebirth.LeaderstatName
		created.Parent = leaderstats
		value = created
	end
	(value :: IntValue).Value = rebirthsOf(player)
end

local function info(player: Player): { [string]: any }
	local done = rebirthsOf(player)
	local styles = {}
	for _, style in Rebirth.HouseStyles do
		table.insert(styles, { id = style.id, name = style.name, requiredRebirths = style.requiredRebirths, unlocked = done >= style.requiredRebirths })
	end
	local data = DataService.GetData(player)
	local currentUnlocks = {}
	local nextUnlocks = {}
	if done >= Rebirth.SewersRebirths then table.insert(currentUnlocks,"Rebirth.UnlockSewers")
	elseif done+1>=Rebirth.SewersRebirths then table.insert(nextUnlocks,"Rebirth.UnlockSewers") end
	for _, style in Rebirth.HouseStyles do
		if style.requiredRebirths<=done then table.insert(currentUnlocks,"House." .. style.id)
		elseif style.requiredRebirths==done+1 then table.insert(nextUnlocks,"House." .. style.id) end
	end
	local skipProduct = Monetization.GetProduct(Rebirth.SkipProductKey)
	local skipPrice = MonetizationService.GetPrice(Rebirth.SkipProductKey)
	return {
		rebirths = done,
		cost = Rebirth.CostFor(done),
		coins = EconomyService.GetCoins(player),
		keepCount = RebirthService.GetKeepCount(player),
		cats = PillowService.GetSeatedCats(player),
		styles = styles,
		style = if data then data.houseStyle else Rebirth.DefaultStyle,
		blocked = PillowService.HasCatsInTransit(player),
		currentMultiplier = Rebirth.IncomeMultiplier(done),
		nextMultiplier = Rebirth.IncomeMultiplier(done + 1),
		currentUnlocks = currentUnlocks,
		nextUnlocks = nextUnlocks,
		skipAvailable = skipProduct ~= nil and skipProduct.productId > 0 and skipPrice ~= nil
			and data ~= nil and data.settings.pendingSkipRebirth == nil,
		skipRobux = skipPrice or 0,
		skipPending = data ~= nil and data.settings.pendingSkipRebirth ~= nil,
	}
end

local function validate(player: Player, keepIds: unknown, skipCost: boolean): (boolean, string, any, any)
	local data = DataService.GetData(player)
	if data == nil or player.Parent ~= Players then
		return false, "Notice.SaveLoading", nil, nil
	end
	if not skipCost and skipPreparing[player] then return false,"Hud.PleaseWait",nil,nil end
	if not skipCost and data.settings.pendingSkipRebirth ~= nil then return false,"Rebirth.SkipPending",nil,nil end
	local humanoid = if player.Character then player.Character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid==nil or humanoid.Health<=0 or PlotService.GetPlot(player)==nil then return false,"Rebirth.NotReady",nil,nil end
	local done = rebirthsOf(player)
	local cost = Rebirth.CostFor(done)
	if not skipCost and data.coins < cost then
		return false, "Notice.MoreCoinsRebirth", nil, nil
	end
	if PillowService.HasCatsInTransit(player) then
		return false, "Notice.RebirthTransit", nil, nil
	end
	if type(keepIds) ~= "table" then
		return false, "Notice.ChooseKeep", nil, nil
	end
	local seated: { [string]: true } = {}
	for _, cat in PillowService.GetSeatedCats(player) do
		seated[cat.uniqueId] = true
	end
	local keep: { [string]: true } = {}
	local count = 0
	for _, id in keepIds :: { any } do
		if type(id) ~= "string" or #id>Rebirth.MaxKeepIdLength or not seated[id] or keep[id] then
			return false, "Notice.KeepOwnOnly", nil, nil
		end
		keep[id] = true
		count += 1
		if count > RebirthService.GetKeepCount(player) then return false,"Rebirth.TooManyKeep",nil,nil end
	end
	if count > RebirthService.GetKeepCount(player) then
		return false, "Rebirth.TooManyKeep", nil, nil
	end
	return true,"",data,keep
end

local function performRebirth(player: Player, keepIds: unknown, skipCost: boolean): (boolean,string)
	local valid,message,data,keep=validate(player,keepIds,skipCost)
	if not valid then return false,message end
	local done=rebirthsOf(player)

	-- Single no-yield update of the live profile.
	data.rebirths = done + 1
	data.settings.pendingSkipRebirth = nil
	EconomyService.ResetForRebirth(player)
	PillowService.ApplyRebirth(player, keep)
	for id in data.upgrades do
		data.upgrades[id] = 0
	end
	for key in table.clone(data.inventory) do
		if not Rebirth.KeepItems[key] then
			data.inventory[key] = nil
		end
	end
	-- Re-apply effects (still no yields), then save.
	UpgradeService.ApplyAll(player) -- speed/jump/capacity, pillowCount -> re-seats kept cats
	ShopService.Sync(player)
	DefenseService.Sync(player)
	GateService.Refresh(player)
	NameTagService.Refresh(player)
	setLeaderstat(player)
	refreshStyle(player)
	DataService.SaveNow(player)
	NotificationService.Announce(`{player.DisplayName} reached Rebirth {data.rebirths}!`)
	return true, `Rebirth {data.rebirths}! Income is now x{Rebirth.IncomeMultiplier(data.rebirths)} forever.`
end

function RebirthService.Rebirth(player: Player, keepIds: unknown): (boolean,string)
	return performRebirth(player,keepIds,false)
end

function RebirthService.ValidateSkipPurchase(player: Player): (boolean,string)
	local data=DataService.GetData(player)
	local pending=if data then data.settings.pendingSkipRebirth else nil
	if type(pending)~="table" then return false,"Rebirth.SkipChoose" end
	if pending.rebirths~=rebirthsOf(player) then return false,"Rebirth.SkipChanged" end
	local ok,key=validate(player,pending.keepIds,true)
	return ok,key
end

-- Standard receipt handler: no yields. Receipt recording follows this grant in the same frame.
function RebirthService.GrantSkipPurchase(player: Player, _data: any?): (boolean,string)
	local ok,key=RebirthService.ValidateSkipPurchase(player)
	if not ok then return false,key end
	local data=DataService.GetData(player)
	return performRebirth(player,data.settings.pendingSkipRebirth.keepIds,true)
end

-- Clear only this confirmed preparation before any native prompt was attempted. Keep the per-player
-- operation lock until the cleared state is durable, so another selection/rebirth cannot replace it.
local function rollbackUnpromptedSkip(player: Player, data: any, intent: any): boolean
	if DataService.GetData(player)~=data or data.settings.pendingSkipRebirth~=intent
		or data.rebirths~=intent.rebirths then return false end
	local target=intent.rebirths
	local ids=intent.keepIds
	data.settings.pendingSkipRebirth=nil
	local waited,cleared=pcall(DataService.SaveAndWait,player,function(savedData: any): boolean
		return type(savedData)=="table" and type(savedData.settings)=="table"
			and savedData.rebirths==target and savedData.settings.pendingSkipRebirth==nil
	end,Rebirth.SkipIntentSaveTimeout)
	if waited and cleared and DataService.GetData(player)==data then return true end
	if DataService.GetData(player)==data and data.settings.pendingSkipRebirth==nil then
		-- A failed acknowledgment must not unlock an intent that may still exist in the durable save.
		intent.rebirths=target intent.keepIds=ids
		data.settings.pendingSkipRebirth=intent DataService.SaveNow(player)
	end
	return false
end

local function runSkipOperation(player: Player, operation: () -> (boolean,string)): (boolean,string)
	if skipPreparing[player] then return false,"Hud.PleaseWait" end
	skipPreparing[player]=true
	local executed,ok,key=pcall(operation)
	skipPreparing[player]=nil
	if not executed then
		warn(`[RebirthService] Skip preparation failed: {tostring(ok)}`)
		return false,"Rebirth.SkipSaving"
	end
	return ok,key
end

local function prepareSkip(player: Player, keepIds: unknown): (boolean,string,any?,any?)
	local ok,key,data=validate(player,keepIds,true)
	if not ok then return false,key,nil,nil end
	-- Developer-product receipts carry no selection nonce. Never rebind an outstanding SKU to
	-- different cats or re-prompt it, including after cancellation, until its receipt is granted.
	if data.settings.pendingSkipRebirth ~= nil then return false,"Rebirth.SkipPending",nil,nil end
	local ids={}
	for _, id in keepIds :: {any} do table.insert(ids,id) end
	table.sort(ids)
	local target=rebirthsOf(player)
	local intent={rebirths=target,keepIds=ids}
	data.settings.pendingSkipRebirth=intent
	-- Native prompting happens only after the complete keep-selection intent is durable.
	local saved=DataService.SaveAndWait(player,function(savedData: any): boolean
		local pending=if type(savedData)=="table" and type(savedData.settings)=="table" then savedData.settings.pendingSkipRebirth else nil
		if type(pending)~="table" or pending.rebirths~=target or type(pending.keepIds)~="table" or #pending.keepIds~=#ids then return false end
		for index,id in ids do if pending.keepIds[index]~=id then return false end end
		return true
	end,Rebirth.SkipIntentSaveTimeout)
	if not saved then return false,"Rebirth.SkipSaving",nil,nil end
	local valid,reason=RebirthService.ValidateSkipPurchase(player)
	if not valid then
		local cleared=rollbackUnpromptedSkip(player,data,intent)
		return false,if cleared then reason else "Rebirth.SkipSaving",nil,nil
	end
	return true,"",data,intent
end

function RebirthService.RequestSkip(player: Player, keepIds: unknown): (boolean,string)
	return runSkipOperation(player,function(): (boolean,string)
		local product=Monetization.GetProduct(Rebirth.SkipProductKey)
		if product==nil or product.productId<=0 then return false,"ExclusiveShop.Unavailable" end
		if MonetizationService.GetPrice(Rebirth.SkipProductKey)==nil then return false,"ExclusiveShop.PriceUnavailable" end
		local ok,key,data,intent=prepareSkip(player,keepIds)
		if not ok then return false,key end
		local prompted,message,nativeAttempted=MonetizationService.RequestPurchase(player,Rebirth.SkipProductKey)
		if not prompted and nativeAttempted~=true then
			if not rollbackUnpromptedSkip(player,data,intent) then return false,"Rebirth.SkipSaving" end
		end
		return prompted,message
	end)
end

-- Test-profile-only: saves the real keep selection for receipt QA with placeholder product IDs.
-- Saves run here in the service VM; callers never need to pass a closure over the Studio bridge.
function RebirthService.DebugPrepareSkip(player: Player, keepIds: unknown): (boolean,string)
	if not RunService:IsStudio() or not DataService.IsStudioTestProfile() then return false,"ExclusiveShop.Unavailable" end
	return runSkipOperation(player,function(): (boolean,string)
		local ok,key=prepareSkip(player,keepIds)
		return ok,key
	end)
end

function RebirthService.SetStyle(player: Player, styleId: unknown): (boolean, string)
	local data = DataService.GetData(player)
	local style = if type(styleId) == "string" then Rebirth.GetStyle(styleId) else nil
	if data == nil or style == nil or style.id ~= styleId then
		return false, "Unknown style."
	end
	if rebirthsOf(player) < style.requiredRebirths then
		return false, `Reach Rebirth {style.requiredRebirths} to unlock {style.name}.`
	end
	data.houseStyle = style.id
	refreshStyle(player)
	return true, `House style: {style.name}`
end

local function rateLimited(player: Player): boolean
	local now = os.clock()
	if now - (lastRequestAt[player] or -math.huge) < Rebirth.RequestCooldown then
		return true
	end
	lastRequestAt[player] = now
	return false
end

function RebirthService:Init(): ()
	openEvent = Network.GetEvent("RebirthOpen")
	MonetizationService.RegisterProductValidator(Rebirth.SkipProductKey,RebirthService.ValidateSkipPurchase)
	MonetizationService.RegisterProductHandler(Rebirth.SkipProductKey,RebirthService.GrantSkipPurchase)
	MultiplierService.RegisterIncomeSource("Rebirths", function(player: Player): number
		return Rebirth.IncomeMultiplier(rebirthsOf(player))
	end)
end

function RebirthService:Start(): ()
	Network.GetFunction("RebirthSkipRequest").OnServerInvoke=function(player: Player, keepIds: unknown)
		if rateLimited(player) then return false,"Hud.PleaseWait",info(player) end
		local ok,key=RebirthService.RequestSkip(player,keepIds)
		return ok,key,info(player)
	end
	PlotService.PlotAssigned:Connect(function(player: Player)
		refreshStyle(player)
	end)
	PlotService.PlotReleased:Connect(function(_player: Player, plot: Model)
		applyStyle(plot, Rebirth.DefaultStyle)
	end)
	local function watchLeaderstats(player: Player)
		task.spawn(function()
			local leaderstats = player:WaitForChild("leaderstats", math.huge)
			if leaderstats then
				(leaderstats :: Instance):WaitForChild(Economy.LeaderstatName, math.huge)
				setLeaderstat(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(watchLeaderstats)
	for _, player in Players:GetPlayers() do
		watchLeaderstats(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		lastRequestAt[player] = nil
		skipPreparing[player] = nil
	end)
	Network.GetEvent("RebirthOpenRequest").OnServerEvent:Connect(function(player: Player)
		if not rateLimited(player) and DataService.GetData(player) then
			openEvent:FireClient(player, info(player))
		end
	end)
	Network.GetEvent("RebirthRequest").OnServerEvent:Connect(function(player: Player, keepIds: unknown)
		if rateLimited(player) then
			return
		end
		local ok, message = RebirthService.Rebirth(player, keepIds)
		NotificationService.Notify(player, message, if ok then "Success" else "Error")
		openEvent:FireClient(player, info(player))
	end)
	Network.GetEvent("SetHouseStyle").OnServerEvent:Connect(function(player: Player, styleId: unknown)
		local ok, message = RebirthService.SetStyle(player, styleId)
		NotificationService.Notify(player, message, if ok then "Success" else "Error")
		openEvent:FireClient(player, info(player))
	end)
end

return RebirthService

