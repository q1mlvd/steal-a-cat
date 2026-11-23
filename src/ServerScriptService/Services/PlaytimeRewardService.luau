--!strict
-- Session-only playtime rewards. Monotonic server time is authoritative; grants and claim flags change
-- in one no-yield frame. A full pillow/item stack leaves the reward ready for a later claim.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = ReplicatedStorage.Shared.Config
local Rewards = require(Config.PlaytimeRewards)
local Cats = require(Config.Cats)
local Items = require(Config.Items)
local Network = require(ReplicatedStorage.Shared.Network)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PillowService = require(script.Parent.PillowService)
local ShopService = require(script.Parent.ShopService)
local Service = {Priority=104}
type Session = {started: number, offset: number, claimed: {[string]: boolean}, busy: boolean}
local sessions: {[Player]: Session} = {}
local requestAt: {[Player]: number} = {}
local stateEvent: RemoteEvent
local random = Random.new()

local function sessionOf(player: Player): Session?
	if player.Parent ~= Players or DataService.GetData(player) == nil then return nil end
	local session = sessions[player]
	if session == nil then
		session = {started=os.clock(),offset=0,claimed={},busy=false}
		sessions[player] = session
	end
	return session
end
local function elapsedOf(session: Session): number
	return math.max(0,os.clock()-session.started+session.offset)
end
local function coinsFor(player: Player, amount: number, incomeSeconds: number?): number
	return math.floor(math.max(amount,EconomyService.GetIncomePerSecond(player)*(incomeSeconds or 0)))
end
function Service.GetState(player: Player): {[string]: any}
	local session = sessionOf(player)
	local elapsed = if session then elapsedOf(session) else 0
	local now = workspace:GetServerTimeNow()
	local list = {}
	local claimable = 0
	for _, reward in Rewards.Rewards do
		local claimed = session ~= nil and session.claimed[reward.id] == true
		local remaining = math.max(0,reward.seconds-elapsed)
		local ready = session ~= nil and not claimed and remaining <= 0
		if ready then claimable += 1 end
		table.insert(list,{id=reward.id,kind=reward.kind,amount=if reward.kind=="Coins" then coinsFor(player,reward.amount,reward.incomeSeconds) else reward.amount,
			itemId=reward.itemId,rarity=reward.rarity,bonusCoins=if reward.bonusCoins then coinsFor(player,reward.bonusCoins,reward.bonusIncomeSeconds) else 0,
			unlockAt=now+remaining,remaining=remaining,ready=ready,claimed=claimed})
	end
	return {loaded=session~=nil,elapsed=elapsed,serverNow=now,rewards=list,claimableCount=claimable,sessionReset=true}
end
function Service.GetHudState(player: Player): {[string]: any}
	local state = Service.GetState(player)
	local nextAt: number? = nil
	for _, reward in state.rewards do
		if not reward.claimed and not reward.ready and (nextAt==nil or reward.unlockAt<nextAt) then nextAt=reward.unlockAt end
	end
	return {freeGiftClaimable=state.claimableCount>0,playtimeClaimableCount=state.claimableCount,playtimeNextAt=nextAt}
end
function Service.Sync(player: Player): ()
	if player.Parent==Players then stateEvent:FireClient(player,Service.GetState(player)) end
end
function Service.Claim(player: Player, id: unknown): (boolean,string,{[string]: any})
	local session = sessionOf(player)
	local data = DataService.GetData(player)
	if session==nil or data==nil then return false,"Playtime.Loading",Service.GetState(player) end
	if type(id)~="string" or #id>Rewards.MaxIdLength then return false,"Playtime.Invalid",Service.GetState(player) end
	local reward = Rewards.Get(id)
	if reward==nil then return false,"Playtime.Invalid",Service.GetState(player) end
	if session.claimed[id] then return false,"Playtime.AlreadyClaimed",Service.GetState(player) end
	if session.busy or os.clock()-(requestAt[player] or -math.huge)<Rewards.RequestCooldown then
		return false,"Hud.PleaseWait",Service.GetState(player)
	end
	requestAt[player]=os.clock()
	if elapsedOf(session)<reward.seconds then return false,"Playtime.Locked",Service.GetState(player) end
	if reward.kind=="Item" then
		local item=Items.Get(reward.itemId or "")
		if item==nil then return false,"Playtime.Invalid",Service.GetState(player) end
		if (data.inventory[item.id] or 0)+reward.amount>item.maxStack then return false,"Playtime.StackFull",Service.GetState(player) end
	elseif reward.kind=="Cat" and PillowService.CountFreePillows(player)<1 then
		return false,"Playtime.FreePillow",Service.GetState(player)
	end
	session.busy=true
	if reward.kind=="Cat" then
		local pool=Cats.ByRarity[reward.rarity or "Rare"]
		local cat=if pool and #pool>0 then pool[random:NextInteger(1,#pool)] else nil
		if cat==nil or PillowService.GrantFreshPaidCat(player,cat.id)==nil then
			session.busy=false
			return false,"Playtime.FreePillow",Service.GetState(player)
		end
	elseif reward.kind=="Item" then
		local itemId=reward.itemId or ""
		data.inventory[itemId]= (data.inventory[itemId] or 0)+reward.amount
	else
		EconomyService.AddCoins(player,coinsFor(player,reward.amount,reward.incomeSeconds))
	end
	if reward.bonusCoins then EconomyService.AddCoins(player,coinsFor(player,reward.bonusCoins,reward.bonusIncomeSeconds)) end
	session.claimed[id]=true
	session.busy=false
	ShopService.Sync(player)
	DataService.SaveNow(player)
	Service.Sync(player)
	return true,"Playtime.ClaimSuccess",Service.GetState(player)
end
function Service.DebugSetElapsed(player: Player, seconds: number): boolean
	if not RunService:IsStudio() or not DataService.IsStudioTestProfile() or type(seconds)~="number" or seconds~=seconds or math.abs(seconds)==math.huge then return false end
	local session=sessionOf(player)
	if session==nil then return false end
	session.offset=math.max(0,seconds)-(os.clock()-session.started)
	Service.Sync(player)
	return true
end
function Service.DebugReset(player: Player): boolean
	if not RunService:IsStudio() or not DataService.IsStudioTestProfile() then return false end
	sessions[player]=nil requestAt[player]=nil
	Service.Sync(player)
	return true
end
function Service:Init(): ()
	stateEvent=Network.GetEvent("PlaytimeRewardState")
end
function Service:Start(): ()
	DataService.DataLoaded:Connect(function(player: Player) sessionOf(player) Service.Sync(player) end)
	Players.PlayerRemoving:Connect(function(player: Player) sessions[player]=nil requestAt[player]=nil end)
	Network.GetFunction("PlaytimeRewardsGet").OnServerInvoke=function(player: Player) return Service.GetState(player) end
	Network.GetFunction("PlaytimeRewardsClaim").OnServerInvoke=Service.Claim
	for _, player in Players:GetPlayers() do sessionOf(player) end
	while true do
		for _, player in Players:GetPlayers() do if DataService.GetData(player) then Service.Sync(player) end end
		task.wait(Rewards.TickInterval)
	end
end
return Service
