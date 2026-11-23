--!strict
-- Rebirth comparison and keep selection. Both purchase paths retain the same server safety checks.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Config=ReplicatedStorage.Shared.Config
local Cats=require(Config.Cats)
local Mutations=require(Config.Mutations)
local Economy=require(Config.Economy)
local Rebirth=require(Config.Rebirth)
local Shop=require(Config.Shop)
local UIAssets=require(Config.UIAssets)
local ExclusiveShop=require(Config.ExclusiveShop)
local Network=require(ReplicatedStorage.Shared.Network)
local L=require(ReplicatedStorage.Shared.Util.Localization)
local FeatureWindow=require(ReplicatedStorage.Shared.Util.FeatureWindow)
local CatPortrait=require(ReplicatedStorage.Shared.Util.CatPortrait)
local NumberFormat=require(ReplicatedStorage.Shared.Util.NumberFormat)
local UiSkin=require(ReplicatedStorage.Shared.Util.UiSkin)
local Notification=require(script.Parent.NotificationController)
local Controller={Priority=48}
local UI=Shop.Ui
local U=Rebirth.Ui
local player=Players.LocalPlayer
local window: any
local comparison: Frame
local nowCard: Frame
local nextCard: Frame
local arrow: ImageLabel
local nowIncome: TextLabel
local nextIncome: TextLabel
local nowCaption: TextLabel
local nextCaption: TextLabel
local nowUnlocks: TextLabel
local nextUnlocks: TextLabel
local unlockDetails: TextLabel
local warning: TextLabel
local resetRules: TextLabel
local costText: TextLabel
local costProgress: Frame
local progressFill: Frame
local keepTitle: TextLabel
local catBody: Frame
local catLayout: UIGridLayout
local styleBody: Frame
local styleLayout: UIGridLayout
local actions: Frame
local confirmButton: TextButton
local skipButton: TextButton
local latest: any=nil
local selected: {[string]: boolean}={}
local armed=false
local skipArmed=false
local busy=false
local catCards: {[string]: TextButton}={}
local styleButtons: {TextButton}={}
local function selectedCount(): number
	local count=0 for _,on in selected do if on then count+=1 end end return count
end
local function keepIds(): {string}
	local ids={} for id,on in selected do if on then table.insert(ids,id) end end table.sort(ids) return ids
end
local function translateUnlocks(keys: any): string
	local texts={}
	if type(keys)=="table" then for _,key in keys do table.insert(texts,L.T(key)) end end
	return if #texts>0 then table.concat(texts," · ") else L.T("Rebirth.NoUnlocks")
end
local function updateUnlocks()
	if latest==nil then return end
	local short=window.Body.AbsoluteSize.Y<U.CompactBodyHeight or window.Body.AbsoluteSize.X<U.CompareBreakpoint
	local function overview(keys: any): string
		if short and type(keys)=="table" and keys[1] then return L.T(keys[1]) end
		return translateUnlocks(keys)
	end
	nowUnlocks.Text=overview(latest.currentUnlocks) nextUnlocks.Text=overview(latest.nextUnlocks)
	unlockDetails.Visible=short
	L.Bind(unlockDetails,"Rebirth.UnlockDetails",{now=translateUnlocks(latest.currentUnlocks),next=translateUnlocks(latest.nextUnlocks)})
end
local function textLimit(label: TextLabel,maxSize: number,minSize: number?)
	local function apply(target: TextLabel)
		local limit=target:FindFirstChildOfClass("UITextSizeConstraint")
		if limit then limit.MaxTextSize=maxSize limit.MinTextSize=minSize or 12 end
	end
	apply(label)
	local lifted=UiSkin.GetText(label) if lifted then apply(lifted) end
end
local function layout()
	local width=math.max(1,window.Body.AbsoluteSize.X-U.Gap)
	local wide=width>=U.CompareBreakpoint
	local compact=window.Body.AbsoluteSize.Y<U.CompactBodyHeight
	local phone=not wide
	local sideBySide=window.Body.AbsoluteSize.X>=U.SideBySideMinWidth
	local gap=if compact then U.CompactGap elseif phone then U.PhoneGap else U.Gap
	local cardHeight=if compact then U.CompactOverviewHeight elseif phone then U.PhoneOverviewHeight else U.OverviewHeight
	local arrowSize=if compact then U.CompactArrowSize elseif phone then U.PhoneArrowSize else U.ArrowSize
	local buttonHeight=if compact then U.CompactButtonHeight elseif phone then U.PhoneButtonHeight else U.ButtonHeight
	window.BodyLayout.Padding=UDim.new(0,gap)
	comparison.Size=UDim2.new(1,0,0,if sideBySide then cardHeight else cardHeight*2+arrowSize+gap*2)
	arrow.Size=UDim2.fromOffset(arrowSize,arrowSize)
	if sideBySide then
		local cardWidth=math.floor((width-arrowSize-gap*2)/2)
		nowCard.Position=UDim2.new() nowCard.Size=UDim2.fromOffset(cardWidth,cardHeight)
		nextCard.Position=UDim2.new(1,0,0,0) nextCard.AnchorPoint=Vector2.new(1,0) nextCard.Size=nowCard.Size
		arrow.Position=UDim2.fromScale(0.5,0.5) arrow.Rotation=0
	else
		nowCard.Position=UDim2.new() nowCard.Size=UDim2.new(1,0,0,cardHeight)
		nextCard.AnchorPoint=Vector2.zero nextCard.Position=UDim2.fromOffset(0,cardHeight+arrowSize+gap*2) nextCard.Size=nowCard.Size
		arrow.Position=UDim2.new(0.5,0,0,cardHeight+gap+arrowSize/2) arrow.Rotation=90
	end
	local padding=if compact then U.CompactCardPadding elseif phone then U.PhoneCardPadding else U.Gap
	local titleSize=if compact then U.CompactTitleSize elseif phone then U.PhoneTitleSize else U.HeaderTextSize
	local incomeSize=if compact then U.CompactIncomeSize elseif phone then U.PhoneIncomeSize else U.HeaderTextSize+6
	local unlockSize=if compact then U.CompactUnlockSize elseif phone then U.PhoneUnlockSize else U.BodyTextSize
	for _,labels in {{nowCaption,nowIncome,nowUnlocks},{nextCaption,nextIncome,nextUnlocks}} do
		local caption,income,unlocks=labels[1],labels[2],labels[3]
		local captionHeight=titleSize+2
		local incomeHeight=incomeSize+6
		local incomeTop=padding+captionHeight
		local unlockTop=incomeTop+incomeHeight
		caption.Position=UDim2.fromOffset(padding,padding) caption.Size=UDim2.new(1,-padding*2,0,captionHeight)
		income.Position=UDim2.fromOffset(padding,incomeTop) income.Size=UDim2.new(1,-padding*2,0,incomeHeight)
		unlocks.Position=UDim2.fromOffset(padding,unlockTop) unlocks.Size=UDim2.new(1,-padding*2,1,-unlockTop-padding)
		unlocks.TextWrapped=not compact unlocks.TextTruncate=if compact then Enum.TextTruncate.AtEnd else Enum.TextTruncate.None
		textLimit(caption,titleSize) textLimit(income,incomeSize,if phone or compact then 16 else 12) textLimit(unlocks,unlockSize)
	end
	warning.Size=UDim2.new(1,0,0,if compact then U.CompactWarningHeight elseif phone then U.PhoneWarningHeight else U.WarningHeight)
	costText.Size=UDim2.new(1,0,0,if compact then U.CompactCostHeight elseif phone then U.PhoneCostHeight else U.ProgressHeight)
	costProgress.Size=UDim2.new(1,0,0,if compact then U.CompactProgressHeight elseif phone then U.PhoneProgressHeight else U.ProgressHeight)
	updateUnlocks()
	local columns=if wide then 2 else 1
	catLayout.FillDirectionMaxCells=columns catLayout.CellPadding=UDim2.fromOffset(U.Gap,U.Gap)
	catLayout.CellSize=UDim2.fromOffset(math.max(1,math.floor((width-U.Gap*(columns-1))/columns)),U.CatHeight)
	local catCount=0 for _ in catCards do catCount+=1 end
	catBody.Size=UDim2.new(1,0,0,if catCount>0 then math.ceil(catCount/columns)*(U.CatHeight+U.Gap)-U.Gap else U.CatHeight)
	local styleColumns=math.max(1,if wide then #styleButtons else 2)
	styleLayout.FillDirectionMaxCells=styleColumns styleLayout.CellPadding=UDim2.fromOffset(U.Gap,U.Gap)
	styleLayout.CellSize=UDim2.fromOffset(math.max(1,math.floor((width-U.Gap*(styleColumns-1))/styleColumns)),U.StylesHeight)
	styleBody.Size=UDim2.new(1,0,0,math.max(0,math.ceil(#styleButtons/styleColumns)*(U.StylesHeight+U.Gap)-U.Gap))
	local showSkip=skipButton.Visible
	actions.Size=UDim2.new(1,0,0,if not showSkip or sideBySide then buttonHeight else buttonHeight*2+gap)
	confirmButton.Position=UDim2.new() confirmButton.Size=if showSkip and sideBySide then UDim2.new(0.5,-gap/2,0,buttonHeight) else UDim2.new(1,0,0,buttonHeight)
	skipButton.Position=if sideBySide then UDim2.new(0.5,gap/2,0,0) else UDim2.fromOffset(0,buttonHeight+gap)
	skipButton.Size=if sideBySide then UDim2.new(0.5,-gap/2,0,buttonHeight) else UDim2.new(1,0,0,buttonHeight)
end
local function renderState()
	local info=latest if info==nil then return end
	L.Bind(nowIncome,"Rebirth.IncomeCard",{amount=info.currentMultiplier})
	L.Bind(nextIncome,"Rebirth.IncomeCard",{amount=info.nextMultiplier})
	updateUnlocks()
	L.Bind(warning,"Rebirth.ResetWarning",{keep=info.keepCount})
	L.Bind(resetRules,"Rebirth.ResetRules",{keep=info.keepCount})
	L.Bind(costText,"Rebirth.CostProgress",{coins=NumberFormat.Format(info.coins),cost=NumberFormat.Format(info.cost)})
	progressFill.Size=UDim2.fromScale(math.clamp(info.coins/math.max(1,info.cost),0,1),1)
	local afford=info.coins>=info.cost
	progressFill.BackgroundColor3=if afford then UI.Accent else UI.Danger
	L.Bind(keepTitle,"Rebirth.ChooseKeep",{count=selectedCount(),max=info.keepCount})
	for id,button in catCards do
		button.BackgroundColor3=if selected[id] then UI.Accent else UI.Surface
		button:SetAttribute("UiSkin",if selected[id] then "Button:Green" else "Card")
		local check=button:FindFirstChild("Selected") if check and check:IsA("ImageLabel") then check.Visible=selected[id]==true end
	end
	local ready=afford and not info.blocked and not info.skipPending and not busy
	confirmButton.Active=ready confirmButton.AutoButtonColor=ready
	confirmButton.BackgroundColor3=if ready then UI.Accent else UI.Danger confirmButton.TextColor3=UI.OnColor
	L.Bind(confirmButton,if info.blocked then "Rebirth.Wait" elseif not afford then "Rebirth.NeedCoins" elseif armed then "Rebirth.ConfirmButton" else "Rebirth.RebirthButton",
		{amount=NumberFormat.Format(math.max(0,info.cost-info.coins)),count=selectedCount()})
	skipButton.Visible=info.skipAvailable==true or info.skipPending==true
	skipButton.Active=info.skipAvailable==true and not info.skipPending and not info.blocked and not busy skipButton.AutoButtonColor=skipButton.Active
	skipButton.BackgroundColor3=U.SkipColor skipButton.TextColor3=UI.OnColor
	local skipSkin=UiSkin.GetSkin(skipButton) if skipSkin then skipSkin.ImageColor3=U.SkipColor end
	L.Bind(skipButton,if info.skipPending then "Rebirth.SkipPendingCaption" elseif not info.skipAvailable then "Rebirth.SkipUnavailable" elseif skipArmed then "Rebirth.SkipConfirm" else "Rebirth.SkipButton",{price=info.skipRobux})
	layout()
end
local function rebuildCats()
	for _,button in catCards do button:Destroy() end table.clear(catCards)
	for index,cat in latest.cats do
		local def=Cats.Get(cat.catId) local tier=Mutations.GetTier(cat.tier) local mutation=Mutations.Get(cat.mutation)
		local parts={}
		if tier.displayName~="" then table.insert(parts,L.T("Tier."..tier.id)) end
		if mutation then table.insert(parts,L.T("Mutation."..mutation.id)) end
		table.insert(parts,if def then L.T("Cat."..def.id..".Name") else cat.catId)
		local id=cat.uniqueId
		local button=FeatureWindow.Button(catBody,"",nil,function()
			if busy then return end
			if selected[id] then selected[id]=nil elseif selectedCount()<latest.keepCount then selected[id]=true end
			armed=false skipArmed=false renderState()
		end,{Text="",LayoutOrder=index,BackgroundColor3=UI.Surface})
		button.Name=id button:SetAttribute("UiSkin","Card")
		CatPortrait.Create(button,{catId=cat.catId,tier=cat.tier,mutation=cat.mutation,frameless=true,
			size=UDim2.fromOffset(U.CatHeight-U.Gap,U.CatHeight-U.Gap),position=UDim2.new(0,U.Gap/2,0.5,0),anchor=Vector2.new(0,0.5)})
		local name=FeatureWindow.Text(button,"",nil,{Text=table.concat(parts," "),
			Size=UDim2.new(1,-U.CatHeight-U.Gap*3,1,-U.Gap),Position=UDim2.fromOffset(U.CatHeight,U.Gap/2),TextSize=U.BodyTextSize})
		name:SetAttribute("LocalizationKey",nil)
		local check=FeatureWindow.Image(button,UIAssets.Controls.Check,{Size=UDim2.fromOffset(U.BodyTextSize,U.BodyTextSize),
			Position=UDim2.new(1,-U.Gap,0.5,0),AnchorPoint=Vector2.new(1,0.5),Visible=selected[id]==true}) check.Name="Selected"
		catCards[id]=button
	end
end
local function rebuildStyles()
	for _,button in styleButtons do button:Destroy() end table.clear(styleButtons)
	for index,style in latest.styles do
		local id=style.id
		local button=FeatureWindow.Button(styleBody,"House."..id,nil,function()
			if style.unlocked and not busy then Network.GetEvent("SetHouseStyle"):FireServer(id) end
		end,{LayoutOrder=index,Active=style.unlocked,AutoButtonColor=style.unlocked,
			BackgroundColor3=if id==latest.style then UI.Accent else UI.Surface,TextSize=U.BodyTextSize})
		if not style.unlocked then L.Bind(button,"Rebirth.StyleLocked",{style=L.T("House."..id),required=style.requiredRebirths}) end
		table.insert(styleButtons,button)
	end
end
local function show(info: any)
	if type(info)~="table" then return end latest=info
	local valid={} for _,cat in info.cats do valid[cat.uniqueId]=true end
	for id in selected do if not valid[id] then selected[id]=nil end end
	armed=false skipArmed=false rebuildCats() rebuildStyles() renderState() window:Open() layout()
end
function Controller.Open(): () Network.GetEvent("RebirthOpenRequest"):FireServer() end
function Controller:Init(): ()
	window=FeatureWindow.Create("Rebirth","Rebirth.Title",{width=U.Width,height=U.Height,scroll=true,displayOrder=50})
	comparison=Instance.new("Frame") comparison.Name="Comparison" comparison.BackgroundTransparency=1 comparison.LayoutOrder=1 comparison.Parent=window.Body
	local function card(key: string): (Frame,TextLabel,TextLabel,TextLabel)
		local frame=Instance.new("Frame") frame.Name=key frame.BackgroundColor3=UI.Surface frame:SetAttribute("UiSkin","Card") frame.Parent=comparison
		local caption=FeatureWindow.Text(frame,key,nil,{Size=UDim2.new(1,-U.Gap*2,0,U.HeaderTextSize+6),Position=UDim2.fromOffset(U.Gap,U.Gap),TextSize=U.HeaderTextSize})
		local income=FeatureWindow.Text(frame,"Rebirth.IncomeCard",{amount=1},{Size=UDim2.new(1,-U.Gap*2,0,U.HeaderTextSize+14),Position=UDim2.fromOffset(U.Gap,U.Gap+U.HeaderTextSize+8),TextSize=U.HeaderTextSize+6,TextColor3=UI.Coin})
		local unlocks=FeatureWindow.Text(frame,"Rebirth.NoUnlocks",nil,{Size=UDim2.new(1,-U.Gap*2,1,-U.HeaderTextSize*2-U.Gap*3-14),Position=UDim2.fromOffset(U.Gap,U.HeaderTextSize*2+U.Gap*2+14),TextSize=U.BodyTextSize,TextColor3=UI.Muted})
		return frame,income,unlocks,caption
	end
	nowCard,nowIncome,nowUnlocks,nowCaption=card("Rebirth.Now") nextCard,nextIncome,nextUnlocks,nextCaption=card("Rebirth.Next") nextCard:SetAttribute("UiSkin","Card:Legendary")
	arrow=FeatureWindow.Image(comparison,UIAssets.Controls.ArrowRight,{Size=UDim2.fromOffset(U.ArrowSize,U.ArrowSize),AnchorPoint=Vector2.new(0.5,0.5)})
	warning=FeatureWindow.Text(window.Body,"Rebirth.ResetWarning",{keep=1},{Size=UDim2.new(1,0,0,U.WarningHeight),TextSize=U.BodyTextSize,TextColor3=U.ResetColor,LayoutOrder=2})
	costText=FeatureWindow.Text(window.Body,"Rebirth.CostProgress",{coins=0,cost=0},{Size=UDim2.new(1,0,0,U.ProgressHeight),TextSize=U.BodyTextSize,LayoutOrder=3})
	costProgress=Instance.new("Frame") costProgress.Name="CostProgress" costProgress.Size=UDim2.new(1,0,0,U.ProgressHeight) costProgress.BackgroundColor3=UI.Surface costProgress:SetAttribute("UiSkin","None") costProgress.LayoutOrder=4 costProgress.Parent=window.Body
	progressFill=Instance.new("Frame") progressFill.Name="Fill" progressFill.Size=UDim2.fromScale(0,1) progressFill.BackgroundColor3=UI.Accent progressFill:SetAttribute("UiSkin","None") progressFill.Parent=costProgress
	resetRules=FeatureWindow.Text(window.Body,"Rebirth.ResetRules",{keep=1},{Size=UDim2.new(1,0,0,U.RulesHeight),TextSize=U.SmallTextSize,TextColor3=UI.Muted,LayoutOrder=6})
	unlockDetails=FeatureWindow.Text(window.Body,"Rebirth.UnlockDetails",{now="",next=""},{Size=UDim2.new(1,0,0,U.UnlockDetailsHeight),TextSize=U.SmallTextSize,TextColor3=UI.Muted,LayoutOrder=7,Visible=false})
	keepTitle=FeatureWindow.Text(window.Body,"Rebirth.ChooseKeep",{count=0,max=1},{Size=UDim2.new(1,0,0,U.HeaderTextSize+8),TextSize=U.HeaderTextSize,LayoutOrder=8})
	catBody=Instance.new("Frame") catBody.Name="KeepCats" catBody.BackgroundTransparency=1 catBody.LayoutOrder=9 catBody.Parent=window.Body
	catLayout=Instance.new("UIGridLayout") catLayout.SortOrder=Enum.SortOrder.LayoutOrder catLayout.Parent=catBody
	FeatureWindow.Text(window.Body,"Rebirth.HouseStyles",nil,{Size=UDim2.new(1,0,0,U.HeaderTextSize+8),TextSize=U.HeaderTextSize,LayoutOrder=10})
	styleBody=Instance.new("Frame") styleBody.Name="HouseStyles" styleBody.BackgroundTransparency=1 styleBody.LayoutOrder=11 styleBody.Parent=window.Body
	styleLayout=Instance.new("UIGridLayout") styleLayout.SortOrder=Enum.SortOrder.LayoutOrder styleLayout.Parent=styleBody
	actions=Instance.new("Frame") actions.Name="Actions" actions.BackgroundTransparency=1 actions.LayoutOrder=5 actions.Parent=window.Body
	confirmButton=FeatureWindow.Button(actions,"Rebirth.RebirthButton",nil,function()
		if busy or latest==nil or not confirmButton.Active then return end
		if not armed then armed=true skipArmed=false renderState() return end
		Network.GetEvent("RebirthRequest"):FireServer(keepIds()) armed=false
	end,{TextSize=U.BodyTextSize,BackgroundColor3=UI.Accent})
	skipButton=FeatureWindow.Button(actions,"Rebirth.SkipUnavailable",nil,function()
		if busy or latest==nil or not skipButton.Active then return end
		if not skipArmed then skipArmed=true armed=false renderState() return end
		busy=true renderState()
		task.spawn(function()
			local ok,success,key,info=pcall(function() return Network.GetFunction("RebirthSkipRequest"):InvokeServer(keepIds()) end)
			busy=false skipArmed=false
			if ok then
				if type(info)=="table" then latest=info end
				if type(key)=="string" and key~="" then Notification.ShowLocal(L.T(key),if success then "Info" else "Error") end
			else Notification.ShowLocal(L.T("Playtime.NetworkError"),"Error") end
			renderState()
		end)
	end,{TextSize=U.BodyTextSize,BackgroundColor3=U.SkipColor})
	skipButton:SetAttribute("UiSkin","None")
	local skipSkin=UiSkin.Apply(skipButton,UIAssets.Buttons.Gray)
	if skipSkin then skipSkin.ImageColor3=U.SkipColor end
	UiSkin.LiftText(skipButton,true,UI.OnColor)
	FeatureWindow.Image(skipButton,ExclusiveShop.RobuxIcon,{Size=UDim2.fromOffset(U.RobuxIconSize,U.RobuxIconSize),Position=UDim2.new(0,U.Gap,0.5,0),AnchorPoint=Vector2.new(0,0.5),ZIndex=4})
	window.SizeChanged:Connect(layout)
	window.Body:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	window.Gui:GetPropertyChangedSignal("Enabled"):Connect(function() if not window.Gui.Enabled then armed=false skipArmed=false end end)
	layout()
end
function Controller:Start(): ()
	Network.GetEvent("RebirthOpen").OnClientEvent:Connect(show)
	L.Changed:Connect(function() if latest then rebuildCats() rebuildStyles() renderState() layout() end end)
	task.spawn(function()
		local stats=player:WaitForChild("leaderstats") local coins=stats:WaitForChild(Economy.LeaderstatName) :: NumberValue
		coins.Changed:Connect(function(value: number) if latest then latest.coins=value renderState() end end)
	end)
end
return Controller
