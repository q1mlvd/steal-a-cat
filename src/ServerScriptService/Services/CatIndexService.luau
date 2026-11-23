--!strict
-- Preserves the legacy species union and records mutation discoveries without changing cat records.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local CollectionService=game:GetService("CollectionService")
local Config=ReplicatedStorage.Shared.Config
local Cats=require(Config.Cats)
local CatVisuals=require(Config.CatVisuals)
local CatSchema=require(Config.CatSchema)
local Tags=require(Config.Tags)
local Index=require(Config.CatIndex)
local Network=require(ReplicatedStorage.Shared.Network)
local DataService=require(script.Parent.DataService)
local EconomyService=require(script.Parent.EconomyService)
local LuckService=require(script.Parent.LuckService)
local CarryService=require(script.Parent.CarryService)
local PillowService=require(script.Parent.PillowService)
local CatIndexService={Priority=102}
local lastRequest:{[Player]:number}={}
local lastClaim:{[Player]:number}={}
local watches:{[Instance]:{RBXScriptConnection}}={}
local indexEvent:RemoteEvent

local function ensure(data:any):any
	if type(data.discovered)~="table" then data.discovered={} end
	if type(data.catIndex)~="table" then data.catIndex={} end
	local collection=data.catIndex
	if type(collection.discoveredByMutation)~="table" then collection.discoveredByMutation={} end
	if type(collection.claimedMilestones)~="table" then collection.claimedMilestones={} end
	for _,tab in Index.Tabs do if type(collection.discoveredByMutation[tab])~="table" then collection.discoveredByMutation[tab]={} end end
	return collection
end
local function mark(data:any,catId:string,mutation:unknown):boolean
	local cat=Cats.Get(catId)
	if cat==nil then return false end
	local collection=ensure(data)
	local changed=data.discovered[catId]~=true
	data.discovered[catId]=true -- this union remains compatible with existing collection consumers.
	local tab=Index.TabForMutation(mutation)
	if tab and Index.Includes(cat) and collection.discoveredByMutation[tab][catId]~=true then
		collection.discoveredByMutation[tab][catId]=true changed=true
	end
	return changed
end
function CatIndexService.GetBonuses(player:Player):(number,number)
	local data=DataService.GetData(player)
	if data==nil then return 0,0 end
	local claimed=ensure(data).claimedMilestones
	local luck,speed=0,0
	for _,tab in Index.Tabs do for _,milestone in Index.Milestones do
		if claimed[Index.MilestoneKey(tab,milestone.count)]==true then luck+=milestone.luck speed+=milestone.speed end
	end end
	return luck,speed
end
local function buildSnapshot(player:Player):any
	local data=DataService.GetData(player)
	local catalog=Index.GetCatalog()
	local snapshot:any={loaded=data~=nil,total=#catalog,discoveredByMutation={},counts={},milestones={},claimableCount=0,luckBonus=0,speedBonus=0}
	if data==nil then return snapshot end
	local collection=ensure(data)
	for _,tab in Index.Tabs do
		local discovered={} local count=0 local rewards={}
		for _,cat in catalog do if collection.discoveredByMutation[tab][cat.id]==true then discovered[cat.id]=true count+=1 end end
		for _,milestone in Index.Milestones do
			local claimed=collection.claimedMilestones[Index.MilestoneKey(tab,milestone.count)]==true
			local claimable=count>=milestone.count and not claimed
			if claimable then snapshot.claimableCount+=1 end
			table.insert(rewards,{count=milestone.count,coins=milestone.coins*(Index.RewardCoinMultipliers::any)[tab],
				luck=milestone.luck,speed=milestone.speed,claimed=claimed,claimable=claimable})
		end
		snapshot.discoveredByMutation[tab]=discovered snapshot.counts[tab]=count snapshot.milestones[tab]=rewards
	end
	snapshot.luckBonus,snapshot.speedBonus=CatIndexService.GetBonuses(player)
	return snapshot
end
local function publish(player:Player,data:any,changed:boolean)
	local ids={}
	for _,cat in Cats.List do if data.discovered[cat.id]==true then table.insert(ids,cat.id) end end
	local value=table.concat(ids,",")
	if player:GetAttribute(CatVisuals.Index.DiscoveredAttribute)~=value then player:SetAttribute(CatVisuals.Index.DiscoveredAttribute,value) end
	local snapshot=buildSnapshot(player)
	player:SetAttribute(Index.RewardsReadyAttribute,snapshot.claimableCount>0)
	player:SetAttribute(Index.LuckBonusAttribute,snapshot.luckBonus)
	player:SetAttribute(Index.SpeedBonusAttribute,snapshot.speedBonus)
	if changed and indexEvent and player.Parent==Players then indexEvent:FireClient(player,snapshot) end
end
function CatIndexService.Discover(player:Player,catId:string,mutation:unknown):boolean
	local data=DataService.GetData(player)
	if data==nil then return false end
	local changed=mark(data,catId,mutation)
	if changed then publish(player,data,true) DataService.SaveNow(player) end
	return changed
end
function CatIndexService.Sweep(player:Player):boolean
	local data=DataService.GetData(player)
	if data==nil then return false end
	ensure(data)
	local changed=false
	for _,record in data.cats do
		if type(record)=="table" and type(record.catId)=="string" then
			if mark(data,record.catId,record.mutation) then changed=true end
		end
	end
	publish(player,data,changed)
	return changed
end
function CatIndexService.IsDiscovered(player:Player,catId:string,mutation:string?):boolean
	local data=DataService.GetData(player)
	if data==nil then return false end
	if mutation==nil then return data.discovered[catId]==true end
	local tab=Index.TabForMutation(mutation)
	return tab~=nil and ensure(data).discoveredByMutation[tab][catId]==true
end
function CatIndexService.GetSnapshot(player:Player):any
	if CatIndexService.Sweep(player) then DataService.SaveNow(player) end
	return buildSnapshot(player)
end
-- All eligible rewards in one selected tab, or a single milestone. Ledger+coins commit without yielding.
function CatIndexService.ClaimRewards(player:Player,tabId:unknown,threshold:unknown):(boolean,string,any)
	local data=DataService.GetData(player)
	if data==nil then return false,"CatIndex.Loading",buildSnapshot(player) end
	if type(tabId)~="string" or #tabId>Index.MaxTabIdLength or not table.find(Index.Tabs,tabId)
		or (threshold~=nil and (type(threshold)~="number" or threshold%1~=0)) then
		return false,"CatIndex.InvalidReward",buildSnapshot(player)
	end
	CatIndexService.Sweep(player)
	local snapshot=buildSnapshot(player)
	local collection=ensure(data)
	local coins,count=0,0
	for _,reward in snapshot.milestones[tabId] do
		if reward.claimable and (threshold==nil or reward.count==threshold) then
			collection.claimedMilestones[Index.MilestoneKey(tabId,reward.count)]=true
			coins+=reward.coins count+=1
		end
	end
	if count==0 then return false,"CatIndex.NoRewards",snapshot end
	EconomyService.AddCoins(player,coins)
	CarryService.RefreshPlayer(player)
	publish(player,data,true)
	DataService.SaveNow(player)
	return true,"CatIndex.RewardsClaimed",buildSnapshot(player)
end
function CatIndexService.DebugDiscover(player:Player,catId:string,mutation:string?):boolean
	if not RunService:IsStudio() or not DataService.IsStudioTestProfile() then return false end
	return CatIndexService.Discover(player,catId,mutation or "")
end
function CatIndexService.DebugDiscoverTab(player:Player,tab:string):number
	if not RunService:IsStudio() or not DataService.IsStudioTestProfile() or not table.find(Index.Tabs,tab) then return 0 end
	local data=DataService.GetData(player)
	if data==nil then return 0 end
	local count=0
	for _,cat in Index.GetCatalog() do if mark(data,cat.id,tab) then count+=1 end end
	publish(player,data,true) DataService.SaveNow(player)
	return count
end
local function watch(instance:Instance)
	if not instance:IsA("Model") or watches[instance] then return end
	local function sweepOwner()
		task.defer(function()
			local ownerId=instance:GetAttribute(CatSchema.Attributes.OwnerUserId)
			local owner=if type(ownerId)=="number" then Players:GetPlayerByUserId(ownerId) else nil
			if owner and CatIndexService.Sweep(owner) then DataService.SaveNow(owner) end
		end)
	end
	watches[instance]={instance:GetAttributeChangedSignal(CatSchema.Attributes.Mutation):Connect(sweepOwner),
		instance:GetAttributeChangedSignal(CatSchema.Attributes.OwnerUserId):Connect(sweepOwner),instance.Destroying:Connect(function()
			local connections=watches[instance] watches[instance]=nil
			if connections then for _,connection in connections do connection:Disconnect() end end
		end)}
end
function CatIndexService:Init():()
	indexEvent=Network.GetEvent("IndexUpdated")
	DataService.RegisterSaveHook("CatIndex",function(player:Player) CatIndexService.Sweep(player) end)
	LuckService.RegisterLuckSource("CatIndex",function(player:Player):number local luck=CatIndexService.GetBonuses(player) return 1+luck end)
	CarryService.RegisterSpeedBonus("CatIndex",function(player:Player):number local _,speed=CatIndexService.GetBonuses(player) return speed end)
end
function CatIndexService:Start():()
	local function loaded(player:Player)
		CatIndexService.Sweep(player)
		local data=DataService.GetData(player)
		if data then publish(player,data,true) CarryService.RefreshPlayer(player) end
	end
	DataService.DataLoaded:Connect(loaded)
	for _,player in Players:GetPlayers() do loaded(player) end
	PillowService.CatPlaced:Connect(function(player:Player,_model:Model) if CatIndexService.Sweep(player) then DataService.SaveNow(player) end end)
	CollectionService:GetInstanceAddedSignal(Tags.Cat):Connect(watch)
	for _,instance in CollectionService:GetTagged(Tags.Cat) do watch(instance) end
	Network.GetFunction("GetIndex").OnServerInvoke=function(player:Player)
		local now=os.clock()
		if now-(lastRequest[player] or -math.huge)>=Index.RequestCooldown then
			lastRequest[player]=now
			if CatIndexService.Sweep(player) then DataService.SaveNow(player) end
		end
		return buildSnapshot(player)
	end
	Network.GetFunction("ClaimIndexRewards").OnServerInvoke=function(player:Player,tab:unknown,threshold:unknown)
		local now=os.clock()
		if now-(lastClaim[player] or -math.huge)<Index.ClaimCooldown then return false,"CatIndex.Wait",buildSnapshot(player) end
		lastClaim[player]=now return CatIndexService.ClaimRewards(player,tab,threshold)
	end
	Players.PlayerRemoving:Connect(function(player:Player) lastRequest[player]=nil lastClaim[player]=nil end)
	local elapsed=0
	RunService.Heartbeat:Connect(function(dt:number)
		elapsed+=dt if elapsed<Index.SweepInterval then return end elapsed=0
		for _,player in Players:GetPlayers() do if CatIndexService.Sweep(player) then DataService.SaveNow(player) end end
	end)
end
return CatIndexService
