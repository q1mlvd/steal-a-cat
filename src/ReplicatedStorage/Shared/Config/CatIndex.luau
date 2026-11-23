--!strict
-- Mutation collection rules, repeat-safe milestones and base discovery odds.
local Cats=require(script.Parent.Cats)
local Rarities=require(script.Parent.Rarities)
local Mutations=require(script.Parent.Mutations)
local CatSpawning=require(script.Parent.CatSpawning)
local Events=require(script.Parent.Events)
local CatIndex={
	Tabs=table.freeze({"Normal","Shiny","Rainbow","Diamond","Starry"}),
	DistrictOrder=table.freeze({"Square","Paths","Residential","Park","Industrial","Rooftops","Sewers"}),
	DistrictsByRarity=table.freeze({Common="Residential",Uncommon="Park",Rare="Industrial",Epic="Industrial",Legendary="Rooftops",Mythic="Sewers",Secret="Sewers"}),
	Milestones=table.freeze({
		table.freeze({count=5,coins=1000,luck=0,speed=0}),
		table.freeze({count=10,coins=5000,luck=0.02,speed=0}),
		table.freeze({count=15,coins=15000,luck=0,speed=0.2}),
		table.freeze({count=20,coins=50000,luck=0.03,speed=0}),
		table.freeze({count=25,coins=150000,luck=0.05,speed=0.3}),
	}),
	RewardCoinMultipliers=table.freeze({Normal=1,Shiny=2,Rainbow=3,Diamond=5,Starry=3}),
	SweepInterval=1,RequestCooldown=0.25,ClaimCooldown=0.3,MaxTabIdLength=16,
	RewardsReadyAttribute="IndexRewardsReady",LuckBonusAttribute="IndexLuckBonus",SpeedBonusAttribute="IndexSpeedBonus",
	Ui=table.freeze({Width=940,Height=680,Gap=8,TouchMinimum=44,TabHeight=64,ProgressHeight=20,
		MilestoneHeight=54,DetailWidth=248,DetailHeight=200,CellWidth=112,CellHeight=132,DistrictHeight=30,
		DetailBreakpoint=440,WideDetailBreakpoint=650,CompactDetailWidth=180,CompactHeight=280,CompactTabHeight=44,CompactProgressHeight=16,CompactMilestoneHeight=44,CompactGap=4,
		PhoneCellWidth=90,PhoneCellHeight=116,CompactCellHeight=96,ScrollBar=5,
		TabColumnWidth=120,PhoneTabColumnWidth=80,PhoneBreakpoint=520,CompactTabColumnWidth=96,TabTextSize=20,PhoneTabTextSize=16,
		DetailPortrait=140,DetailLargeHeight=420,CompactPortrait=72,MilestoneWidth=138,CounterHeight=28}),
}

function CatIndex.Includes(cat:any):boolean
	return cat.season==nil and cat.indexExcluded~=true and cat.spawnEnabled~=false
end
function CatIndex.GetCatalog():{any}
	local result={}
	for _,cat in Cats.List do if CatIndex.Includes(cat) then table.insert(result,cat) end end
	return result
end
function CatIndex.TabForMutation(mutation:unknown):string?
	if mutation==nil or mutation=="" or mutation=="Normal" then return "Normal" end
	return if type(mutation)=="string" and table.find(CatIndex.Tabs,mutation) then mutation else nil
end
function CatIndex.District(cat:any):string
	return if type(cat.district)=="string" then cat.district else (CatIndex.DistrictsByRarity::any)[cat.rarity] or "Residential"
end
function CatIndex.MilestoneKey(tab:string,count:number):string return tab..":"..tostring(count) end
function CatIndex.MutationProbability(tab:string):number
	local remaining=1
	for _,mutation in Mutations.List do
		if mutation.chance>0 and mutation.season==nil then
			local chance=math.min(Mutations.MaxChance,mutation.chance)
			if tab==mutation.id then return remaining*chance end
			remaining*=1-chance
		end
	end
	return if tab=="Normal" then remaining else 0
end
-- N is a base roll in the preferred district (or a Secret tick / Starfall roll).
function CatIndex.OneIn(cat:any,tab:string):(number?,string)
	local sameRarity=0
	for _,definition in CatIndex.GetCatalog() do if definition.rarity==cat.rarity then sameRarity+=1 end end
	if sameRarity==0 then return nil,"Unavailable" end
	local chance=0 local context="District"
	if tab=="Starry" then
		context="Starfall"
		local weight=(Events.Starfall.RarityWeights::any)[cat.rarity] or 0
		local total=0 for _,n in Events.Starfall.RarityWeights do total+=n end
		chance=if total>0 then weight/total/sameRarity else 0
	elseif cat.rarity==CatSpawning.Secret.RarityId then
		context="SecretTick" chance=CatSpawning.Secret.SpawnChancePerTick/sameRarity*CatIndex.MutationProbability(tab)
	else
		local area=(CatSpawning.Areas::any)[CatIndex.District(cat)]
		local rarity=Rarities.Get(cat.rarity)
		if area and rarity and table.find(area.rarities,cat.rarity) then
			local total=0
			for _,id in area.rarities do local r=Rarities.Get(id) if r then total+=r.spawnWeight end end
			chance=rarity.spawnWeight/total/sameRarity*CatIndex.MutationProbability(tab)
		end
	end
	return if chance>0 then math.max(1,math.floor(1/chance+0.5)) else nil,context
end
return table.freeze(CatIndex)
