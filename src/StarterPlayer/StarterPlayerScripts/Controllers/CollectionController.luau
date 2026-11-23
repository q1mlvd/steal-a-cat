--!strict
-- Mutation tabs and milestone claims extend the existing species collection using server snapshots.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Shared=ReplicatedStorage.Shared
local Cats=require(Shared.Config.Cats)
local Rarities=require(Shared.Config.Rarities)
local Mutations=require(Shared.Config.Mutations)
local Index=require(Shared.Config.CatIndex)
local Shop=require(Shared.Config.Shop)
local CatPortrait=require(Shared.Util.CatPortrait)
local NumberFormat=require(Shared.Util.NumberFormat)
local L=require(Shared.Util.Localization)
local Network=require(Shared.Network)
local Window=require(Shared.Util.FeatureWindow)
local UiSkin=require(Shared.Util.UiSkin)
local HudButtons=require(script.Parent.HudButtonsController)
local Notification=require(script.Parent.NotificationController)
local UI=Shop.Ui local C=Index.Ui
local CollectionController={Priority=67}
local player=Players.LocalPlayer
local window:any
local tabs:ScrollingFrame local progress:Frame local progressFill:Frame local progressText:TextLabel
local catalogScroll:ScrollingFrame local detail:Frame local rewards:ScrollingFrame
local tabButtons:{[string]:TextButton}={}
local tabBadges:{[string]:TextLabel}={}
local snapshot:any={loaded=false,total=#Index.GetCatalog(),counts={},discoveredByMutation={},milestones={}}
local selectedTab="Normal"
local selectedCat=Index.GetCatalog()[1].id
local requestBusy=false local claimBusy=false
local metrics:any={}
local render:()->()
local drawDetail:()->()
local drawCatalog:()->()
local function clear(parent:Instance)
	for _,object in parent:GetChildren() do if object:IsA("GuiObject") then object:Destroy() end end
end
local function known(id:string):boolean
	local set=snapshot.discoveredByMutation[selectedTab]
	return type(set)=="table" and set[id]==true
end
local function mutationName(tab:string):string return L.T("CatIndex.Tab."..tab) end
local function mutationId():string return if selectedTab=="Normal" then "" else selectedTab end
local function text(parent:Instance,key:string,params:any?,props:any?):TextLabel
	local label=Window.Text(parent,key,params,props)
	local limit=label:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
	limit.MaxTextSize=if props and props.TextSize then props.TextSize else UI.TextSize+2
	limit.MinTextSize=math.min(limit.MinTextSize,limit.MaxTextSize) limit.Parent=label
	return label
end
local function applySnapshot(value:any)
	if type(value)~="table" or type(value.counts)~="table" or type(value.discoveredByMutation)~="table" or type(value.milestones)~="table" then return end
	snapshot=value
	if window:IsOpen() then render() end
end
local function requestSnapshot()
	if requestBusy then return end requestBusy=true
	task.spawn(function()
		local ok,value=pcall(function() return Network.GetFunction("GetIndex"):InvokeServer() end)
		requestBusy=false
		if ok then applySnapshot(value) else Notification.ShowLocal(L.T("CatIndex.RequestFailed"),"Error") end
	end)
end
local function claim(threshold:number?)
	if claimBusy then return end claimBusy=true
	task.spawn(function()
		local ok,success,key,value=pcall(function() return Network.GetFunction("ClaimIndexRewards"):InvokeServer(selectedTab,threshold) end)
		claimBusy=false
		if ok then
			applySnapshot(value)
			Notification.ShowLocal(L.T(if type(key)=="string" then key else "CatIndex.RequestFailed"),if success then "Success" else "Info")
		else Notification.ShowLocal(L.T("CatIndex.RequestFailed"),"Error") end
	end)
end
local function drawRewards()
	clear(rewards)
	local height=metrics.milestoneHeight or C.MilestoneHeight
	local available=false
	local milestones=snapshot.milestones[selectedTab] or {}
	for _,reward in milestones do if reward.claimable then available=true end end
	local all=Window.Button(rewards,if available then "CatIndex.ClaimRewards" else "CatIndex.NothingToClaim",nil,function() claim(nil) end,
		{Name="ClaimRewards",Position=UDim2.fromOffset(0,0),Size=UDim2.fromOffset(C.MilestoneWidth,height),BackgroundColor3=if available then UI.Accent else UI.Surface,TextColor3=if available then UI.OnColor else UI.Muted})
	all:SetAttribute("UiSkin",if available then "Button:Green" else "Button:Gray") all.Active=available all.AutoButtonColor=available
	local x=C.MilestoneWidth+C.Gap
	for _,reward in milestones do
		local card=Window.Button(rewards,"",nil,function() if reward.claimable then claim(reward.count) end end,
			{Name="Reward"..tostring(reward.count),Position=UDim2.fromOffset(x,0),Size=UDim2.fromOffset(C.MilestoneWidth,height),BackgroundColor3=UI.Surface})
		card:SetAttribute("UiSkin",if reward.claimable then "Card:Uncommon" else "Card") card.Active=reward.claimable card.AutoButtonColor=reward.claimable
		text(card,"CatIndex.Milestone",{count=reward.count},{Position=UDim2.fromScale(0,0),Size=UDim2.new(1,0,0.29,0)})
		local amount=L.T("CatIndex.Coins",{coins=NumberFormat.Format(reward.coins)})
		if reward.luck>0 then amount..=" · "..L.T("CatIndex.LuckReward",{percent=math.floor(reward.luck*100+0.5)}) end
		if reward.speed>0 then amount..=" · "..L.T("CatIndex.SpeedReward",{amount=string.format("%.1f",reward.speed)}) end
		local award=text(card,"",nil,{Position=UDim2.fromScale(0.02,0.29),Size=UDim2.fromScale(0.96,0.37),TextColor3=UI.Coin}) award.Text=amount
		text(card,if reward.claimed then "CatIndex.Claimed" elseif reward.claimable then "CatIndex.Claim" else "CatIndex.Locked",nil,
			{Position=UDim2.fromScale(0,0.68),Size=UDim2.fromScale(1,0.28),TextColor3=if reward.claimable then UI.Accent else UI.Muted})
		x+=C.MilestoneWidth+C.Gap
	end
	rewards.CanvasSize=UDim2.fromOffset(x-C.Gap,height)
end
function CollectionController.SelectCat(id:string):boolean
	local cat=Cats.Get(id)
	if not cat or not Index.Includes(cat) then return false end
	selectedCat=id drawDetail() drawCatalog() return true
end
function CollectionController.SetTab(tab:string):boolean
	if not table.find(Index.Tabs,tab) then return false end
	selectedTab=tab render() return true
end
function CollectionController.GetState():any
	return {tab=selectedTab,catId=selectedCat,snapshot=snapshot,layout=metrics,open=window:IsOpen()}
end
function CollectionController.Open()
	window:Open() render() requestSnapshot()
end
function CollectionController.Close() window:Close() end

drawDetail=function()
	clear(detail)
	local cat=Cats.Get(selectedCat)
	if not cat then return end
	local size=detail.AbsoluteSize
	local compact=size.Y<C.DetailLargeHeight
	local tight=compact and size.Y<C.DetailHeight-C.CompactPortrait
	local portrait=if compact then math.min(C.DetailPortrait,math.max(C.TouchMinimum,math.min(size.Y-C.Gap*2,size.X*0.35))) else C.DetailPortrait
	local isKnown=known(cat.id)
	CatPortrait.Create(detail,{catId=cat.id,discovered=isKnown,mutation=mutationId(),frameless=true,
		size=UDim2.fromOffset(portrait,portrait),position=if compact then UDim2.fromOffset(C.Gap,C.Gap) else UDim2.new(0.5,0,0,C.Gap),anchor=if compact then Vector2.zero else Vector2.new(0.5,0)})
	local x=if compact then portrait+C.Gap*2 else C.Gap
	local y=if compact then C.Gap else portrait+C.Gap*2
	local width=if compact then math.max(C.TouchMinimum,size.X-x-C.Gap) else size.X-C.Gap*2
	local name=if isKnown then L.T("Cat."..cat.id..".Name") else L.T("CatIndex.Unknown")
	text(detail,"CatIndex.DetailName",{mutation=if selectedTab=="Normal" then "" else mutationName(selectedTab),cat=name},
		{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(width,if tight then 20 else 26),TextXAlignment=Enum.TextXAlignment.Left})
	text(detail,"CatIndex.Rarity",{rarity=L.T("Rarity."..cat.rarity)},
		{Position=UDim2.fromOffset(x,y+(if tight then 21 else 27)),Size=UDim2.fromOffset(width,if tight then 16 else 20),TextXAlignment=Enum.TextXAlignment.Left,TextColor3=(Rarities.Get(cat.rarity)::any).color})
	local oneIn,context=Index.OneIn(cat,selectedTab)
	local oddsX=if compact then C.Gap else x
	local oddsY=if compact then portrait+C.Gap*2 else y+49
	local oddsWidth=if compact then size.X-C.Gap*2 else width
	local oddsHeight=if compact then math.max(12,math.min(32,size.Y-oddsY-C.Gap)) else 44
	text(detail,if oneIn then "CatIndex.Probability"..context else "CatIndex.ProbabilityUnavailable",{chance=if oneIn then NumberFormat.Format(oneIn) else ""},
		{Position=UDim2.fromOffset(oddsX,oddsY),Size=UDim2.fromOffset(oddsWidth,oddsHeight),TextXAlignment=Enum.TextXAlignment.Left})
	local income=cat.coinsPerSecond*Mutations.Multiplier(mutationId())
	local incomeY=if compact then oddsY+oddsHeight+C.Gap else y+99
	if not compact or incomeY+24+C.Gap<=size.Y then
		text(detail,"CatIndex.Income",{amount=NumberFormat.Format(income)},
			{Position=UDim2.fromOffset(oddsX,incomeY),Size=UDim2.fromOffset(oddsWidth,24),TextXAlignment=Enum.TextXAlignment.Left,TextColor3=UI.Coin})
	end
	if not compact then
		text(detail,"CatIndex.OddsNote",nil,{Position=UDim2.fromOffset(x,y+129),Size=UDim2.fromOffset(width,60),TextXAlignment=Enum.TextXAlignment.Left,TextColor3=UI.Muted})
		text(detail,"CatIndex.Bonuses",{luck=math.floor((snapshot.luckBonus or 0)*100+0.5),speed=string.format("%.1f",snapshot.speedBonus or 0)},
			{Position=UDim2.fromOffset(x,y+196),Size=UDim2.fromOffset(width,56),TextXAlignment=Enum.TextXAlignment.Left,TextColor3=UI.Accent})
	end
end

drawCatalog=function()
	clear(catalogScroll)
	local width=catalogScroll.AbsoluteSize.X-C.ScrollBar-C.Gap
	if width<C.PhoneCellWidth then return end
	local targetCell=if metrics.stacked then C.PhoneCellWidth else C.CellWidth
	local columns=math.max(1,math.floor((width+C.Gap)/(targetCell+C.Gap)))
	local cellWidth=math.floor((width-C.Gap*(columns-1))/columns)
	local cellHeight=if metrics.compact then C.CompactCellHeight elseif cellWidth<C.CellWidth then C.PhoneCellHeight else C.CellHeight
	local byDistrict:any={}
	for _,cat in Index.GetCatalog() do local district=Index.District(cat) byDistrict[district]=byDistrict[district] or {} table.insert(byDistrict[district],cat) end
	local y=0
	for _,district in Index.DistrictOrder do
		local cats=byDistrict[district]
		if not cats or #cats==0 then continue end
		text(catalogScroll,"CatIndex.District",{district=L.T("World."..district)},
			{Name="District"..district,Position=UDim2.fromOffset(0,y),Size=UDim2.fromOffset(width,C.DistrictHeight),TextXAlignment=Enum.TextXAlignment.Left,TextSize=C.TabTextSize})
		y+=C.DistrictHeight+C.Gap/2
		local group=Instance.new("Frame") group.Name=district group.BackgroundTransparency=1 group.Position=UDim2.fromOffset(0,y)
		local rows=math.ceil(#cats/columns) local groupHeight=rows*cellHeight+(rows-1)*C.Gap
		group.Size=UDim2.fromOffset(width,groupHeight) group.Parent=catalogScroll
		local layout=Instance.new("UIGridLayout") layout.CellSize=UDim2.fromOffset(cellWidth,cellHeight) layout.CellPadding=UDim2.fromOffset(C.Gap,C.Gap)
		layout.FillDirectionMaxCells=columns layout.SortOrder=Enum.SortOrder.LayoutOrder layout.Parent=group
		for order,cat in cats do
			local isKnown=known(cat.id)
			local cell=Window.Button(group,"",nil,function() CollectionController.SelectCat(cat.id) end,
				{Name=cat.id,LayoutOrder=order,Size=UDim2.fromOffset(cellWidth,cellHeight),BackgroundColor3=UI.Surface})
			cell:SetAttribute("UiSkin",if selectedCat==cat.id then "Card:Uncommon" else "Card:"..cat.rarity)
			local icon=math.min(cellWidth-C.Gap*2,cellHeight-46)
			CatPortrait.Create(cell,{catId=cat.id,discovered=isKnown,mutation=mutationId(),frameless=true,size=UDim2.fromOffset(icon,icon),
				position=UDim2.new(0.5,0,0,C.Gap/2),anchor=Vector2.new(0.5,0)})
			text(cell,if isKnown then "Cat."..cat.id..".Name" else "CatIndex.Unknown",nil,
				{Position=UDim2.new(0,C.Gap/2,1,-40),Size=UDim2.new(1,-C.Gap,0,20),TextColor3=if isKnown then UI.Text else UI.Muted})
			text(cell,"Rarity."..cat.rarity,nil,
				{Position=UDim2.new(0,C.Gap/2,1,-20),Size=UDim2.new(1,-C.Gap,0,16),TextColor3=(Rarities.Get(cat.rarity)::any).color})
		end
		y+=groupHeight+C.Gap
	end
	catalogScroll.CanvasSize=UDim2.fromOffset(0,y)
end

local function relayout()
	if not window or not tabs then return end
	local size=window.Body.AbsoluteSize
	if size.X<=0 or size.Y<=0 then return end
	local compact=size.Y<C.CompactHeight
	local gap=if compact then C.CompactGap else C.Gap
	local tabHeight=if compact then C.CompactTabHeight else C.TabHeight
	local progressHeight=if compact then C.CompactProgressHeight else C.ProgressHeight
	local milestoneHeight=if compact then C.CompactMilestoneHeight else C.MilestoneHeight
	local columnWidth=if size.X<C.PhoneBreakpoint then C.PhoneTabColumnWidth elseif compact then C.CompactTabColumnWidth else C.TabColumnWidth
	local tabWidth=columnWidth-C.ScrollBar
	tabs.Position=UDim2.fromOffset(0,0) tabs.Size=UDim2.new(0,columnWidth,1,0)
	tabs.CanvasSize=UDim2.fromOffset(0,#Index.Tabs*(tabHeight+gap)-gap)
	for order,tab in Index.Tabs do
		local button=tabButtons[tab] button.Position=UDim2.fromOffset(0,(order-1)*(tabHeight+gap)) button.Size=UDim2.fromOffset(tabWidth,tabHeight)
		local limit=button:FindFirstChildOfClass("UITextSizeConstraint")
		if limit then limit.MaxTextSize=if columnWidth==C.PhoneTabColumnWidth then C.PhoneTabTextSize else C.TabTextSize end
	end
	local mainLeft=columnWidth+gap
	local mainWidth=math.max(C.TouchMinimum,size.X-mainLeft)
	progress.Position=UDim2.fromOffset(mainLeft,0) progress.Size=UDim2.fromOffset(mainWidth,progressHeight)
	local mainTop=progressHeight+gap
	local mainHeight=math.max(C.TouchMinimum,size.Y-mainTop-milestoneHeight-gap)
	local stacked=mainWidth<C.DetailBreakpoint
	if stacked then
		local detailHeight=math.min(C.DetailHeight,math.max(C.CompactPortrait+C.Gap*2,math.floor(mainHeight*0.43)))
		detail.Position=UDim2.fromOffset(mainLeft,mainTop) detail.Size=UDim2.fromOffset(mainWidth,detailHeight)
		catalogScroll.Position=UDim2.fromOffset(mainLeft,mainTop+detailHeight+gap) catalogScroll.Size=UDim2.fromOffset(mainWidth,math.max(C.TouchMinimum,mainHeight-detailHeight-gap))
	else
		local detailWidth=if mainWidth<C.WideDetailBreakpoint then C.CompactDetailWidth else C.DetailWidth
		detail.Position=UDim2.fromOffset(mainLeft+mainWidth-detailWidth,mainTop) detail.Size=UDim2.fromOffset(detailWidth,mainHeight)
		catalogScroll.Position=UDim2.fromOffset(mainLeft,mainTop) catalogScroll.Size=UDim2.fromOffset(mainWidth-detailWidth-gap,mainHeight)
	end
	rewards.Position=UDim2.new(0,mainLeft,1,-milestoneHeight) rewards.Size=UDim2.fromOffset(mainWidth,milestoneHeight)
	local cellWidth=if stacked then C.PhoneCellWidth else C.CellWidth
	metrics={width=size.X,height=size.Y,stacked=stacked,tabWidth=tabWidth,tabHeight=tabHeight,tabColumnWidth=columnWidth,
		mainLeft=mainLeft,mainWidth=mainWidth,compact=compact,milestoneHeight=milestoneHeight,
		catalogColumns=math.max(1,math.floor((catalogScroll.AbsoluteSize.X-C.ScrollBar)/(cellWidth+C.Gap)))}
	if window:IsOpen() then drawCatalog() drawDetail() end
end
render=function()
	relayout()
	local found=snapshot.counts[selectedTab] or 0 local total=snapshot.total or #Index.GetCatalog()
	for _,tab in Index.Tabs do
		local button=tabButtons[tab]
		button.Text=L.T("CatIndex.TabSummary",{mutation=mutationName(tab),found=snapshot.counts[tab] or 0,total=total})
		button.BackgroundColor3=if tab==selectedTab then UI.Accent else UI.Surface
		button.TextColor3=if tab==selectedTab then UI.OnColor else UI.Text
		button:SetAttribute("UiSkinSelected",tab==selectedTab)
		local ready=false for _,reward in snapshot.milestones[tab] or {} do if reward.claimable then ready=true end end
		tabBadges[tab].Visible=ready
	end
	progressText.Text=L.T("CatIndex.Progress",{found=found,total=total})
	progressFill.Size=UDim2.fromScale(if total>0 then math.clamp(found/total,0,1) else 0,1)
	drawCatalog() drawDetail() drawRewards()
end
function CollectionController:Init():()
	window=Window.Create("CatCollection","CatIndex.Title",{width=C.Width,height=C.Height,scroll=false})
	tabs=Instance.new("ScrollingFrame") tabs.Name="MutationTabs" tabs.BackgroundTransparency=1 tabs.BorderSizePixel=0
	tabs.ScrollingDirection=Enum.ScrollingDirection.Y tabs.ScrollBarThickness=C.ScrollBar tabs.ScrollBarImageColor3=UI.Accent tabs.CanvasSize=UDim2.new() tabs.Parent=window.Body
	for _,tab in Index.Tabs do
		local button=Window.Button(tabs,"",nil,function() CollectionController.SetTab(tab) end,{Name=tab,BackgroundColor3=UI.Surface})
		button:SetAttribute("UiSkin","Tab") tabButtons[tab]=button
		local badge=text(button,"Hud.Alert",nil,{Name="ClaimBadge",Size=UDim2.fromOffset(18,18),Position=UDim2.new(1,-20,0,2),TextColor3=UI.Danger,ZIndex=6})
		badge.Visible=false tabBadges[tab]=badge
	end
	progress=Instance.new("Frame") progress.Name="Progress" progress.BackgroundColor3=UI.Surface progress.Parent=window.Body
	progress:SetAttribute("UiSkin","None")
	progressFill=Instance.new("Frame") progressFill.Name="Fill" progressFill.BackgroundColor3=UI.Accent progressFill.BorderSizePixel=0 progressFill.Parent=progress
	progressFill:SetAttribute("UiSkin","None")
	local trackCorner=Instance.new("UICorner") trackCorner.CornerRadius=UDim.new(0,C.Gap) trackCorner.Parent=progress
	local fillCorner=trackCorner:Clone() fillCorner.Parent=progressFill
	UiSkin.Bar(progress,progressFill,"Green")
	progressText=text(progress,"CatIndex.Progress",{found=0,total=#Index.GetCatalog()},{Name="Counter",Size=UDim2.fromScale(1,1),ZIndex=3,TextColor3=UI.OnColor})
	catalogScroll=Instance.new("ScrollingFrame") catalogScroll.Name="DistrictCats" catalogScroll.BackgroundTransparency=1 catalogScroll.BorderSizePixel=0
	catalogScroll.ScrollingDirection=Enum.ScrollingDirection.Y catalogScroll.ScrollBarThickness=C.ScrollBar catalogScroll.ScrollBarImageColor3=UI.Accent catalogScroll.CanvasSize=UDim2.new() catalogScroll.Parent=window.Body
	detail=Instance.new("Frame") detail.Name="SelectedCat" detail.BackgroundColor3=UI.Surface detail:SetAttribute("UiSkin","Card") detail.Parent=window.Body
	rewards=Instance.new("ScrollingFrame") rewards.Name="Milestones" rewards.BackgroundTransparency=1 rewards.BorderSizePixel=0
	rewards.ScrollingDirection=Enum.ScrollingDirection.X rewards.ScrollBarThickness=C.ScrollBar rewards.ScrollBarImageColor3=UI.Accent rewards.CanvasSize=UDim2.new() rewards.Parent=window.Body
	window.SizeChanged:Connect(function() task.defer(relayout) end)
	window.Body:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	HudButtons.Add("Collection",L.T("Hud.Collection"),45,nil,CollectionController.Open)
	relayout()
end
function CollectionController:Start():()
	Network.GetEvent("IndexUpdated").OnClientEvent:Connect(applySnapshot)
	player:GetAttributeChangedSignal("DebugLocale"):Connect(function() if window:IsOpen() then render() end end)
	requestSnapshot()
end
return CollectionController
