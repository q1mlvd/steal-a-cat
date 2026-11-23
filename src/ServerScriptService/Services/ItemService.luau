--!strict
-- Clients request an item ID/aim point; the server owns counts, eligible cats and effect parameters.
local Debris=game:GetService("Debris")
local CollectionService=game:GetService("CollectionService")
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Config=ReplicatedStorage.Shared.Config
local Catching=require(Config.Catching)
local CatSpawning=require(Config.CatSpawning)
local Items=require(Config.Items)
local Defense=require(Config.Defense)
local CatSchema=require(Config.CatSchema)
local Tags=require(Config.Tags)
local Shop=require(Config.Shop)
local ItemArtConfig=require(Config.ItemArt)
local ItemArt=require(ReplicatedStorage.Shared.Util.ItemArt)
local Network=require(ReplicatedStorage.Shared.Network)
local DataService=require(script.Parent.DataService)
local ShopService=require(script.Parent.ShopService)
local CatSpawnService=require(script.Parent.CatSpawnService)
local CatchDeliveryService=require(script.Parent.CatchDeliveryService)
local AntiCheatService=require(script.Parent.AntiCheatService)
local NotificationService=require(script.Parent.NotificationService)
local DefenseService=require(script.Parent.DefenseService)
local StealService=require(script.Parent.StealService)
local PillowService=require(script.Parent.PillowService)
local LoyaltyService=require(script.Parent.LoyaltyService)
local PlotService=require(script.Parent.PlotService)
local ATTR=CatSchema.Attributes

local ItemService={Priority=86}
local lastUse: {[Player]: number}={}
local effectsFolder: Folder

function ItemService.HasItem(player: Player,id: string): boolean
	return ShopService.GetCount(player,id)>0
end

function ItemService.GetCatchDistance(player: Player): number
	return if ItemService.HasItem(player,"Net") then Items.Effects.Net.CatchDistance else Catching.PromptMaxDistance
end

function ItemService.ConsumeFishBoost(player: Player): boolean
	return ShopService.ConsumeFishBoost(player)
end

local function aliveRoot(player: Player): BasePart?
	local character=player.Character
	local root=if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid=if character then character:FindFirstChildOfClass("Humanoid") else nil
	return if root and root:IsA("BasePart") and humanoid and humanoid.Health>0 then root else nil
end

local function finiteVector(value: Vector3): boolean
	return value.X==value.X and value.Y==value.Y and value.Z==value.Z
		and math.abs(value.X)<=Shop.MaxAimCoordinate and math.abs(value.Y)<=Shop.MaxAimCoordinate
		and math.abs(value.Z)<=Shop.MaxAimCoordinate
end

local function groundTarget(player: Player,root: BasePart,aim: unknown): Vector3?
	if not finiteVector(root.Position) then return nil end
	if aim~=nil and (typeof(aim)~="Vector3" or not finiteVector(aim :: Vector3)) then return nil end
	local wanted=if aim~=nil then (aim :: Vector3)-root.Position else root.CFrame.LookVector*Shop.DefaultThrowDistance
	local flat=Vector3.new(wanted.X,0,wanted.Z)
	if flat.Magnitude>Shop.ThrowDistance then flat=flat.Unit*Shop.ThrowDistance end
	local params=RaycastParams.new()
	params.FilterType=Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances={player.Character :: Model,CatSpawnService.GetCatsFolder(),effectsFolder}
	params.RespectCanCollide=true
	params.CollisionGroup=CatSpawning.CollisionGroup
	local origin=root.Position+Vector3.new(0,Shop.ThrowOriginLift,0)
	if flat.Magnitude>Shop.DirectionEpsilon then
		local blocked=workspace:Raycast(origin,flat,params)
		if blocked then flat=blocked.Position-origin-flat.Unit*Shop.ThrowWallOffset end
	end
	local top=root.Position+flat+Vector3.new(0,Shop.GroundProbeUp,0)
	local ground=workspace:Raycast(top,Vector3.new(0,-Shop.GroundProbeDown,0),params)
	if ground==nil or math.abs(ground.Position.Y-root.Position.Y)>Shop.TargetVerticalTolerance then return nil end
	return ground.Position
end

-- Stage 17: the item mesh lands on the ground below `position` (thrown in an arc from `from` if given).
-- The invisible marker part stays the functional handle (label, lifetime, Bait Can `.Parent` check).
local function markerArt(part: BasePart,position: Vector3,text: string,from: Vector3?)
	local artName=ItemArtConfig.MarkerModels[text]
	local art=if artName then ItemArt.Clone(artName,true) else nil
	if art==nil then return end
	part.Transparency=1
	local ignored: {Instance}={CatSpawnService.GetCatsFolder(),effectsFolder}
	for _,other in Players:GetPlayers() do if other.Character then table.insert(ignored,other.Character) end end
	local params=RaycastParams.new()
	params.FilterType=Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances=ignored
	params.RespectCanCollide=true
	local hit=workspace:Raycast(position+Vector3.new(0,ItemArtConfig.MarkerProbeLift,0),Vector3.new(0,-ItemArtConfig.MarkerGroundProbe,0),params)
	local landing=if hit then hit.Position else position
	art:PivotTo(CFrame.new(from or landing))
	art.Parent=part
	if from==nil then return end
	task.spawn(function()
		local start=os.clock()
		while art.Parent do
			local t=math.min((os.clock()-start)/ItemArtConfig.ThrowSeconds,1)
			local arc=Vector3.new(0,4*ItemArtConfig.ThrowArcHeight*t*(1-t),0)
			art:PivotTo(CFrame.new(from:Lerp(landing,t)+arc)*CFrame.Angles(t*2*math.pi,0,0))
			if t>=1 then break end
			RunService.Heartbeat:Wait()
		end
	end)
end

local function throwOrigin(root: BasePart): Vector3
	return root.Position+root.CFrame.LookVector+Vector3.new(0,Shop.ThrowOriginLift,0)
end

local function marker(position: Vector3,color: Color3,text: string,duration: number,from: Vector3?): BasePart
	local part=Instance.new("Part")
	part.Name=text
	part.Shape=Enum.PartType.Ball
	part.Size=Shop.MarkerSize
	part.Color=color
	part.Material=Enum.Material.Neon
	part.Anchored=true
	part.CanCollide=false part.CanTouch=false part.CanQuery=false
	part.Position=position+Vector3.new(0,Shop.MarkerSize.Y/2+Shop.MarkerHeight,0)
	part.Parent=effectsFolder
	local gui=Instance.new("BillboardGui")
	gui.Size=UDim2.fromOffset(Shop.MarkerLabelSize.X,Shop.MarkerLabelSize.Y)
	gui.StudsOffset=Shop.MarkerLabelOffset
	gui.MaxDistance=Shop.MarkerLabelDistance
	gui.Parent=part
	local label=Instance.new("TextLabel")
	label.Size=UDim2.fromScale(1,1) label.BackgroundTransparency=1
	label.Text=text label.Font=Enum.Font.GothamBold label.TextSize=Shop.MarkerTextSize
	label.TextColor3=color label.TextStrokeTransparency=0
	label.Parent=gui
	markerArt(part,position,text,from)
	Debris:AddItem(part,duration)
	return part
end

local function nearestWild(position: Vector3,radius: number): Model?
	local nearest: Model?=nil
	local best=radius
	for _,model in CatSpawnService.GetWildCats() do
		local root=model:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and not CatSpawnService.IsLocked(model) then
			local distance=(root.Position-position).Magnitude
			if distance<=best then nearest=model best=distance end
		end
	end
	return nearest
end

local function nearestOwnedCat(player: Player,position: Vector3,purpose: "Bell" | "BribeFood"): Model?
	local plot=PlotService.GetPlot(player)
	local data=DataService.GetData(player)
	if plot==nil or data==nil then return nil end
	local best=if purpose=="Bell" then Defense.BellEquipDistance else Defense.BribeRange
	local closest: Model?=nil
	for _,model in PillowService.GetPlacedCats(plot) do
		local id=model:GetAttribute(ATTR.UniqueId)
		local record=if type(id)=="string" then data.cats[id] else nil
		local catRoot=model:FindFirstChild("HumanoidRootPart")
		if record==nil or model:GetAttribute(ATTR.OwnerUserId)~=player.UserId
			or model:GetAttribute(ATTR.State)~=CatSchema.States.OnPillow
			or not CollectionService:HasTag(model,Tags.Cat) or catRoot==nil or not catRoot:IsA("BasePart") then continue end
		if purpose=="Bell" and record.bell==true then continue end
		if purpose=="BribeFood" and (record.originalOwnerUserId==player.UserId or record.loyalty<=0) then continue end
		local distance=(catRoot.Position-position).Magnitude
		if distance<=best then best=distance closest=model end
	end
	return closest
end

function ItemService.Use(player: Player,itemId: unknown,aim: unknown): (boolean,string)
	local now=os.clock()
	if now-(lastUse[player] or -math.huge)<Shop.UseCooldown then return false,"Please wait." end
	lastUse[player]=now
	if type(itemId)~="string" or #itemId>Shop.MaxIdLength then return false,"Unknown item." end
	local item=Items.Get(itemId)
	if item==nil then return false,"Unknown item." end
	if aim~=nil and (typeof(aim)~="Vector3" or not finiteVector(aim :: Vector3)) then
		return false,"Invalid aim point."
	end
	local root=aliveRoot(player)
	if root==nil or DataService.GetData(player)==nil or player:GetAttribute(Shop.CatchingAttribute)==true then return false,"You cannot use an item right now." end
	if item.type=="permanent" and item.permanentScope~="cat" then return false,`{item.name} is always active once purchased.` end
	if not ItemService.HasItem(player,item.id) then return false,"You do not have this item." end
	if item.id=="SoftPaws" then
		if not ShopService.ArmSoftPaws(player) then return false,"Soft Paws is already ready for your next steal." end
		return true,"Soft Paws ready: your next successful steal sends no theft alert."
	elseif item.id=="Bell" then
		local model=nearestOwnedCat(player,root.Position,"Bell")
		if model==nil or not PillowService.EquipBell(player,model) then return false,"Stand near an owned cat on a pillow without a bell." end
		assert(ShopService.Consume(player,item.id),"Validated Bell attachment lost inventory")
		return true,"Bell attached permanently. You can track this cat if it is stolen!"
	elseif item.id=="BribeFood" then
		local model=nearestOwnedCat(player,root.Position,"BribeFood")
		local id=if model then model:GetAttribute(ATTR.UniqueId) else nil
		if model==nil or type(id)~="string" or not LoyaltyService.ReduceLoyalty(id,Defense.BribeLoyaltyReduction) then
			return false,"Stand near a stolen cat you own on a pillow with loyalty remaining."
		end
		assert(ShopService.Consume(player,item.id),"Validated bribe lost inventory")
		return true,`Loyalty reduced by {Defense.BribeLoyaltyReduction}.`
	elseif item.id=="BoxTrap" then
		local placed,message=DefenseService.UseBoxTrap(player,aim)
		if not placed then return false,message end
		assert(ShopService.Consume(player,item.id),"Validated trap lost inventory")
		return true,message
	elseif item.id=="Vacuum" then
		local used,message=DefenseService.UseVacuum(player)
		if not used then return false,message end
		assert(ShopService.Consume(player,item.id),"Validated vacuum lost inventory")
		return true,message
	elseif item.id=="Fish" then
		if not ShopService.ArmFish(player) then return false,"Fish is already ready for your next catch." end
		return true,"Fish ready: your next catch has a wider green zone!"
	elseif item.id=="LaserPointer" then
		local character=player.Character
		local started,reason=CatchDeliveryService.Begin(player,function(_success: boolean)
			if character then ItemArt.Release(character,"LaserPointer") end
		end)
		if not started then return false,reason or "Carry a freshly caught cat and leave a free pillow at home." end
		if character then ItemArt.Hold(character,"LaserPointer") end
		assert(ShopService.Consume(player,item.id),"[ItemService] Validated laser dispatch lost its inventory count")
		return true,"Follow the laser home!"
	elseif item.id=="YarnBall" then
		local point=groundTarget(player,root,aim)
		if point==nil then return false,"Aim at nearby ground." end
		local model=nearestWild(point,Items.Effects.YarnBall.TargetRadius)
		if model==nil or not CatSpawnService.FreezeWildCat(model,Items.Effects.YarnBall.Duration) then return false,"No available wild cat near the yarn." end
		assert(ShopService.Consume(player,item.id))
		AntiCheatService.Grace(player,Shop.GraceSeconds)
		marker(point,Shop.YarnColor,"Yarn Ball",Items.Effects.YarnBall.Duration,throwOrigin(root))
		return true,"That cat is distracted for 3 seconds!"
	elseif item.id=="BaitCan" then
		local point=groundTarget(player,root,aim)
		if point==nil then return false,"Aim at nearby ground." end
		assert(ShopService.Consume(player,item.id))
		AntiCheatService.Grace(player,Shop.GraceSeconds)
		local effect=Items.Effects.BaitCan
		CatSpawnService.AttractWildCats(point,effect.Radius,effect.Duration)
		local lure=marker(point,Shop.BaitColor,"Bait Can",effect.Duration,throwOrigin(root))
		local endsAt=os.clock()+effect.Duration
		task.spawn(function()
			while lure.Parent and os.clock()<endsAt do
				task.wait(Shop.BaitPulseInterval)
				local remaining=endsAt-os.clock()
				if remaining>0 and lure.Parent then CatSpawnService.AttractWildCats(point,effect.Radius,remaining) end
			end
		end)
		return true,"Bait is attracting nearby wild cats!"
	elseif item.id=="Catnip" then
		local effect=Items.Effects.Catnip
		local affected=CatSpawnService.SuppressFleeInRadius(root.Position,effect.Radius,effect.Duration)
		if affected<1 then return false,"No wild cats within catnip range." end
		assert(ShopService.Consume(player,item.id))
		AntiCheatService.Grace(player,Shop.GraceSeconds)
		marker(root.Position,Shop.CatnipColor,"Catnip",effect.Duration)
		return true,`{affected} wild cats stopped fleeing!`
	end
	return false,"This item is not available yet."
end

function ItemService:Init(): ()
	effectsFolder=Instance.new("Folder")
	effectsFolder.Name=Shop.EffectFolderName
	effectsFolder.Parent=workspace
	StealService.RegisterStealModifier("SoftPaws",function(thief: Player,_cat: Model): boolean
		return ShopService.ConsumeSoftPawsBoost(thief)
	end)
	ShopService.RegisterPurchaseListener("GuardDog",function(player: Player,id: string): ()
		if id==Defense.GuardDogItemId then DefenseService.Sync(player) end
	end)
end

function ItemService:Start(): ()
	Network.GetEvent("ItemUse").OnServerEvent:Connect(function(player: Player,id: unknown,aim: unknown)
		local success,message=ItemService.Use(player,id,aim)
		NotificationService.Notify(player,message,if success then "Success" else "Error")
	end)
	Players.PlayerRemoving:Connect(function(player: Player) lastUse[player]=nil end)
	-- Stage 17: Net owners hold the net while the catch minigame runs.
	local function watchNet(player: Player)
		player:GetAttributeChangedSignal(Shop.CatchingAttribute):Connect(function()
			local character=player.Character
			if character==nil then return end
			if player:GetAttribute(Shop.CatchingAttribute)==true and ItemService.HasItem(player,"Net") then
				ItemArt.Hold(character,"Net")
			else
				ItemArt.Release(character,"Net")
			end
		end)
	end
	Players.PlayerAdded:Connect(watchNet)
	for _,player in Players:GetPlayers() do watchNet(player) end
end
return ItemService

