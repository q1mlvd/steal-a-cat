--!strict
-- Purchases and inventory edits share one loaded profile and never yield during their commit.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage.Shared.Config
local Items = require(Config.Items)
local Shop = require(Config.Shop)
local Tags = require(Config.Tags)
local Network = require(ReplicatedStorage.Shared.Network)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local NotificationService = require(script.Parent.NotificationService)

export type InventorySnapshot = {inventory: {[string]: number}, fishReady: boolean, softPawsReady: boolean}
type ShopSession = {zone: BasePart, expiresAt: number}
local ShopService = {Priority=85}
local prompts: {[ProximityPrompt]: BasePart} = {}
local sessions: {[Player]: ShopSession} = {}
local openTimes: {[Player]: number} = {}
local purchaseTimes: {[Player]: number} = {}
local requestTimes: {[Player]: number} = {}
local inventoryEvent: RemoteEvent
local openEvent: RemoteEvent
local purchaseListeners: {[string]: (Player, string) -> ()} = {}

local function count(player: Player, itemId: string): number
	local data = DataService.GetData(player)
	local item = Items.Get(itemId)
	if data == nil or item == nil then return 0 end
	local n = data.inventory[itemId]
	return if type(n)=="number" and n==n and n<math.huge then math.clamp(math.floor(n),0,item.maxStack) else 0
end

local function mirror(player: Player)
	local data = DataService.GetData(player)
	player:SetAttribute(Shop.NetOwnedAttribute, count(player,"Net")>0)
	player:SetAttribute(Shop.FishReadyAttribute, data~=nil and data.inventory[Shop.FishReadyInventoryKey]==1)
	player:SetAttribute(Shop.SoftPawsReadyAttribute, data~=nil and data.inventory[Shop.SoftPawsReadyInventoryKey]==1)
end

function ShopService.GetCount(player: Player, itemId: string): number
	return count(player,itemId)
end

function ShopService.GetSnapshot(player: Player): InventorySnapshot
	local inventory: {[string]: number} = {}
	for _, item in Items.List do inventory[item.id]=count(player,item.id) end
	local data = DataService.GetData(player)
	return {inventory=inventory,fishReady=data~=nil and data.inventory[Shop.FishReadyInventoryKey]==1,
		softPawsReady=data~=nil and data.inventory[Shop.SoftPawsReadyInventoryKey]==1}
end

function ShopService.Sync(player: Player): ()
	mirror(player)
	if player.Parent==Players then inventoryEvent:FireClient(player,ShopService.GetSnapshot(player)) end
end

-- Server services call these only after validating the corresponding gameplay effect.
function ShopService.Consume(player: Player, itemId: string): boolean
	local item=Items.Get(itemId)
	local data=DataService.GetData(player)
	local n=count(player,itemId)
	if item==nil or (item.type~="consumable" and item.permanentScope~="cat") or data==nil or n<1 then return false end
	data.inventory[itemId]=n-1
	ShopService.Sync(player)
	DataService.SaveNow(player)
	return true
end

function ShopService.ArmFish(player: Player): boolean
	local data=DataService.GetData(player)
	local n=count(player,"Fish")
	if data==nil or n<1 or data.inventory[Shop.FishReadyInventoryKey]==1 then return false end
	data.inventory.Fish=n-1
	data.inventory[Shop.FishReadyInventoryKey]=1
	ShopService.Sync(player)
	DataService.SaveNow(player)
	return true
end

function ShopService.ConsumeFishBoost(player: Player): boolean
	local data=DataService.GetData(player)
	if data==nil or data.inventory[Shop.FishReadyInventoryKey]~=1 then return false end
	data.inventory[Shop.FishReadyInventoryKey]=nil
	ShopService.Sync(player)
	DataService.SaveNow(player)
	return true
end

function ShopService.ArmSoftPaws(player: Player): boolean
	local data=DataService.GetData(player)
	local n=count(player,"SoftPaws")
	if data==nil or n<1 or data.inventory[Shop.SoftPawsReadyInventoryKey]==1 then return false end
	data.inventory.SoftPaws=n-1
	data.inventory[Shop.SoftPawsReadyInventoryKey]=1
	ShopService.Sync(player)
	DataService.SaveNow(player)
	return true
end

-- Called only by StealService's validated successful-steal hook.
function ShopService.ConsumeSoftPawsBoost(player: Player): boolean
	local data=DataService.GetData(player)
	if data==nil or data.inventory[Shop.SoftPawsReadyInventoryKey]~=1 then return false end
	data.inventory[Shop.SoftPawsReadyInventoryKey]=nil
	ShopService.Sync(player)
	DataService.SaveNow(player)
	return true
end

function ShopService.RegisterPurchaseListener(name: string, listener: (Player, string) -> ()): ()
	assert(purchaseListeners[name]==nil, "Duplicate purchase listener")
	purchaseListeners[name]=listener
end

local function aliveRoot(player: Player): BasePart?
	local character=player.Character
	local root=if character then character:FindFirstChild("HumanoidRootPart") else nil
	local h=if character then character:FindFirstChildOfClass("Humanoid") else nil
	return if root and root:IsA("BasePart") and h and h.Health>0 then root else nil
end

local function isNear(player: Player, zone: BasePart, distance: number): boolean
	local root=aliveRoot(player)
	return root~=nil and zone:IsDescendantOf(workspace) and CollectionService:HasTag(zone,Tags.ShopZone)
		and (root.Position-zone.Position).Magnitude<=distance
end

-- True while the player has an open stall session, is still near that stall and isn't catching.
-- UpgradeService purchases reuse this session.
function ShopService.HasSession(player: Player): boolean
	local session=sessions[player]
	return session~=nil and os.clock()<=session.expiresAt and isNear(player,session.zone,Shop.PurchaseDistance)
		and player:GetAttribute(Shop.CatchingAttribute)~=true
end

function ShopService.Purchase(player: Player, itemId: unknown): (boolean,string)
	local now=os.clock()
	if now-(purchaseTimes[player] or -math.huge)<Shop.PurchaseCooldown then return false,"Please wait." end
	purchaseTimes[player]=now
	if type(itemId)~="string" or #itemId>Shop.MaxIdLength then return false,"Unknown item." end
	local item=Items.Get(itemId)
	if item==nil then return false,"Unknown item." end
	local session=sessions[player]
	if session==nil or now>session.expiresAt or not isNear(player,session.zone,Shop.PurchaseDistance)
		or player:GetAttribute(Shop.CatchingAttribute)==true then return false,"Visit the shop stall to buy supplies." end
	local data=DataService.GetData(player)
	if data==nil then return false,"Your save is still loading." end
	local n=count(player,item.id)
	if n>=item.maxStack then return false,if item.type=="permanent" and item.permanentScope~="cat" then "You already own this item." else "This stack is full." end
	-- TrySpend, increment and save request are one non-yielding transaction in this same profile.
	if not EconomyService.TrySpend(player,item.price) then return false,"Not enough coins." end
	data.inventory[item.id]=n+1
	ShopService.Sync(player)
	DataService.SaveNow(player)
	for name,listener in purchaseListeners do
		local ok,message=pcall(listener,player,item.id)
		if not ok then warn(`[ShopService] {name}: {tostring(message)}`) end
	end
	return true,`Bought {item.name}!`
end

local function setup(zone: Instance)
	if not zone:IsA("BasePart") or not zone:IsDescendantOf(workspace) then return end
	for prompt,part in prompts do if part==zone then return end end
	local prompt=Instance.new("ProximityPrompt")
	prompt.Name=Shop.PromptName
	prompt.ActionText=Shop.PromptActionText
	prompt.ObjectText=Shop.PromptObjectText
	prompt.KeyboardKeyCode=Shop.PromptKey
	prompt.GamepadKeyCode=Shop.PromptGamepadKey
	prompt.MaxActivationDistance=Shop.OpenDistance
	prompt.RequiresLineOfSight=false
	prompt.HoldDuration=0
	prompt.Exclusivity=Enum.ProximityPromptExclusivity.OnePerButton
	-- PromptController also arbitrates it with wild-cat and house prompts.
	prompt.Parent=zone
	prompts[prompt]=zone
	zone.Destroying:Connect(function() prompts[prompt]=nil end)
end

local function loaded(player: Player)
	if DataService.GetData(player)==nil then return end
	ShopService.Sync(player)
end

function ShopService:Init(): ()
	openEvent=Network.GetEvent("ShopOpen")
	inventoryEvent=Network.GetEvent("InventoryUpdate")
	for _,zone in CollectionService:GetTagged(Tags.ShopZone) do setup(zone) end
end

function ShopService:Start(): ()
	CollectionService:GetInstanceAddedSignal(Tags.ShopZone):Connect(setup)
	DataService.DataLoaded:Connect(function(player: Player) loaded(player) end)
	for _,player in Players:GetPlayers() do loaded(player) end
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt,player: Player)
		local zone=prompts[prompt]
		if zone==nil or prompt.Parent~=zone or not isNear(player,zone,Shop.OpenDistance)
			or DataService.GetData(player)==nil or player:GetAttribute(Shop.CatchingAttribute)==true then return end
		local now=os.clock()
		if now-(openTimes[player] or -math.huge)<Shop.OpenCooldown then return end
		openTimes[player]=now
		sessions[player]={zone=zone,expiresAt=now+Shop.SessionDuration}
		openEvent:FireClient(player,ShopService.GetSnapshot(player))
	end)
	Network.GetEvent("ShopPurchase").OnServerEvent:Connect(function(player: Player,id: unknown)
		local success,message=ShopService.Purchase(player,id)
		NotificationService.Notify(player,message,if success then "Success" else "Error")
	end)
	Network.GetEvent("InventoryRequest").OnServerEvent:Connect(function(player: Player)
		local now=os.clock()
		if now-(requestTimes[player] or -math.huge)<Shop.InventoryRequestCooldown then return end
		requestTimes[player]=now
		if DataService.GetData(player) then
			ShopService.Sync(player)
		else
			task.spawn(function()
				if DataService.WaitForData(player) then ShopService.Sync(player) end
			end)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		sessions[player]=nil openTimes[player]=nil purchaseTimes[player]=nil requestTimes[player]=nil
	end)
end
return ShopService

