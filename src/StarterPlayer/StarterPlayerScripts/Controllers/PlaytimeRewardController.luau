--!strict
-- Free Gift is a session reward window. Counts, readiness and claimed state come from the server.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Config=ReplicatedStorage.Shared.Config
local Rewards=require(Config.PlaytimeRewards)
local Items=require(Config.Items)
local Shop=require(Config.Shop)
local UIAssets=require(Config.UIAssets)
local Network=require(ReplicatedStorage.Shared.Network)
local L=require(ReplicatedStorage.Shared.Util.Localization)
local NumberFormat=require(ReplicatedStorage.Shared.Util.NumberFormat)
local FeatureWindow=require(ReplicatedStorage.Shared.Util.FeatureWindow)
local CatPortrait=require(ReplicatedStorage.Shared.Util.CatPortrait)
local HudButtons=require(script.Parent.HudButtonsController)
local Notification=require(script.Parent.NotificationController)
local Controller={Priority=64.5}
local UI=Shop.Ui
local U=Rewards.Ui
local window: any
local grid: Frame
local gridLayout: UIGridLayout
local finalTile: Frame
local latest: any=nil
local tiles: {[string]: any}={}
local busy=false

local function text(parent: Instance,key: string,params: any,props: any): TextLabel
	return FeatureWindow.Text(parent,key,params,props)
end
local function clock(seconds: number): string
	local n=math.max(0,math.ceil(seconds))
	return string.format("%d:%02d",n//60,n%60)
end
local function rewardText(reward: any): string
	if reward.kind=="Coins" then return L.T("Playtime.Coins",{amount=NumberFormat.Format(reward.amount)}) end
	if reward.kind=="Item" then return L.T("Playtime.Item",{count=reward.amount,item=L.T("Item."..reward.itemId..".Name")}) end
	return L.T("Playtime.Cat",{rarity=L.T("Rarity."..reward.rarity)})
		..(if (reward.bonusCoins or 0)>0 then "\n"..L.T("Playtime.BonusCoins",{amount=NumberFormat.Format(reward.bonusCoins)}) else "")
end
local function apply(state: any)
	if type(state)~="table" or type(state.rewards)~="table" then return end
	latest=state
	for _,reward in state.rewards do
		local tile=tiles[reward.id]
		if tile then
			tile.state=reward
			tile.reward.Text=rewardText(reward)
			tile.button.Active=reward.ready==true and not busy
			tile.button.AutoButtonColor=tile.button.Active
			tile.button.BackgroundColor3=if reward.ready then UI.Accent else UI.Surface
			tile.button.TextColor3=if reward.ready then UI.OnColor else UI.Text
			tile.glow.Enabled=reward.ready==true
			tile.frame:SetAttribute("UiSkin",if reward.ready then "Card:Legendary" else "Card")
			if reward.claimed then L.Bind(tile.button,"Playtime.Claimed")
			elseif reward.ready then L.Bind(tile.button,"Playtime.Claim")
			else tile.button.Text=clock((reward.unlockAt or 0)-workspace:GetServerTimeNow()) end
			tile.check.Visible=reward.claimed==true
			tile.lock.Visible=reward.ready~=true and reward.claimed~=true
		end
	end
end
local function claim(id: string)
	local tile=tiles[id]
	if busy or tile==nil or tile.state==nil or not tile.state.ready then return end
	busy=true apply(latest)
	task.spawn(function()
		local ok,success,key,state=pcall(function() return Network.GetFunction("PlaytimeRewardsClaim"):InvokeServer(id) end)
		busy=false
		if ok then
			apply(state)
			Notification.ShowLocal(L.T(key),if success then "Success" else "Error")
		else apply(latest) Notification.ShowLocal(L.T("Playtime.NetworkError"),"Error") end
	end)
end
local function makeTile(parent: Instance,reward: any,final: boolean): Frame
	local frame=Instance.new("Frame")
	frame.Name=reward.id frame.BackgroundColor3=UI.Surface frame:SetAttribute("UiSkin","Card") frame.Parent=parent
	local glowFrame=Instance.new("Frame") glowFrame.Name="ReadyGlow" glowFrame.BackgroundTransparency=1 glowFrame.Size=UDim2.fromScale(1,1) glowFrame:SetAttribute("UiSkin","None") glowFrame.Parent=frame
	local glow=Instance.new("UIStroke") glow.Thickness=U.GlowThickness glow.Color=U.GlowColor glow.Enabled=false glow.Parent=glowFrame
	local iconSize=if final then U.FinalIconSize else U.IconSize
	local icon: GuiObject
	if reward.kind=="Cat" then
		icon=CatPortrait.Create(frame,{rarity=reward.rarity,size=UDim2.fromOffset(iconSize,iconSize),position=UDim2.fromScale(0.5,0.12),anchor=Vector2.new(0.5,0),frameless=true})
	else
		local item=if reward.itemId then Items.Get(reward.itemId) else nil
		icon=FeatureWindow.Image(frame,if item then item.icon else UIAssets.Icons.CoinStack,{Size=UDim2.fromOffset(iconSize,iconSize),Position=UDim2.fromScale(0.5,0.12),AnchorPoint=Vector2.new(0.5,0)})
	end
	local duration=text(frame,if final then "Playtime.FinalTime" else "Playtime.UnlockTime",{minutes=reward.seconds//60},
		{Size=UDim2.new(1,-U.Gap,0,U.SmallTextSize+4),Position=UDim2.fromOffset(U.Gap/2,U.Gap/2),TextSize=U.SmallTextSize,TextColor3=UI.Muted})
	local label=text(frame,"Playtime.Coins",{amount=""},{Size=UDim2.new(1,-U.Gap*2,0,U.TextSize*2+4),
		Position=UDim2.new(0,U.Gap,1,-U.ClaimHeight-U.Gap*2-U.TextSize*2),TextSize=U.TextSize})
	local button=FeatureWindow.Button(frame,"Playtime.Locked",nil,function() claim(reward.id) end,
		{Size=UDim2.new(1,-U.Gap*2,0,U.ClaimHeight),Position=UDim2.new(0,U.Gap,1,-U.ClaimHeight-U.Gap),TextSize=U.SmallTextSize})
	local lock=FeatureWindow.Image(button,UIAssets.Icons.Lock,{Name="Locked",Size=UDim2.fromOffset(U.LockIconSize,U.LockIconSize),
		Position=UDim2.new(0,U.Gap/2,0.5,0),AnchorPoint=Vector2.new(0,0.5),ZIndex=8})
	local check=FeatureWindow.Image(frame,UIAssets.Controls.Check,{Size=UDim2.fromOffset(U.ClaimHeight,U.ClaimHeight),
		Position=UDim2.new(1,-U.Gap,0,U.Gap),AnchorPoint=Vector2.new(1,0),Visible=false,ZIndex=8})
	tiles[reward.id]={frame=frame,reward=label,button=button,glow=glow,check=check,lock=lock,icon=icon,duration=duration,state=nil,final=final}
	if final then
		icon.AnchorPoint=Vector2.new(0,0.5) icon.Position=UDim2.new(0,U.Gap,0.5,0)
		duration.Position=UDim2.fromOffset(iconSize+U.Gap*2,U.Gap)
		duration.Size=UDim2.new(1,-iconSize-U.Gap*3,0,U.TextSize+4)
		label.Position=UDim2.fromOffset(iconSize+U.Gap*2,U.Gap+U.TextSize+4)
		label.Size=UDim2.new(1,-iconSize-U.Gap*3,0,U.TextSize*2+8)
		button.Position=UDim2.new(0,iconSize+U.Gap*2,1,-U.ClaimHeight-U.Gap)
		button.Size=UDim2.new(1,-iconSize-U.Gap*3,0,U.ClaimHeight)
	end
	return frame
end
local function layout()
	local width=math.max(1,window.Body.AbsoluteSize.X-U.Gap)
	local columns=if width<U.Breakpoint then U.PortraitColumns else U.Columns
	gridLayout.FillDirectionMaxCells=columns
	gridLayout.CellPadding=UDim2.fromOffset(U.Gap,U.Gap)
	gridLayout.CellSize=UDim2.fromOffset(math.max(1,math.floor((width-U.Gap*(columns-1))/columns)),U.TileHeight)
	grid.Size=UDim2.new(1,0,0,math.ceil((#Rewards.Rewards-1)/columns)*(U.TileHeight+U.Gap)-U.Gap)
	finalTile.Size=UDim2.new(1,0,0,U.FinalHeight)
end
function Controller.Open(): ()
	window:Open()
	task.spawn(function()
		local ok,state=pcall(function() return Network.GetFunction("PlaytimeRewardsGet"):InvokeServer() end)
		if ok then apply(state) end
	end)
end
function Controller:Init(): ()
	window=FeatureWindow.Create("PlaytimeRewards","Playtime.Title",{width=U.Width,height=U.Height,scroll=true,displayOrder=50})
	grid=Instance.new("Frame") grid.Name="TimedTiles" grid.BackgroundTransparency=1 grid.LayoutOrder=1 grid.Parent=window.Body
	gridLayout=Instance.new("UIGridLayout") gridLayout.SortOrder=Enum.SortOrder.LayoutOrder gridLayout.Parent=grid
	for index,reward in Rewards.Rewards do
		local final=reward.id==Rewards.FinalRewardId
		local tile=makeTile(if final then window.Body else grid,reward,final)
		tile.LayoutOrder=if final then 2 else index
		if final then finalTile=tile end
	end
	local finalReward=Rewards.Get(Rewards.FinalRewardId)
	local note=text(window.Body,"Playtime.SessionNote",{minutes=if finalReward then finalReward.seconds//60 else 75},
		{Size=UDim2.new(1,0,0,U.FooterHeight),TextSize=U.SmallTextSize,TextColor3=UI.Muted,LayoutOrder=3})
	note.TextWrapped=true
	window.SizeChanged:Connect(layout)
	window.Body:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	HudButtons.Add("FreeGift",L.T("Hud.FreeGift"),30,nil,Controller.Open)
	layout()
end
function Controller:Start(): ()
	Network.GetEvent("PlaytimeRewardState").OnClientEvent:Connect(apply)
	L.Changed:Connect(function() if latest then apply(latest) end end)
	local elapsed=0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed+=dt if elapsed<U.DisplayTick or latest==nil then return end elapsed=0
		for _,tile in tiles do
			local state=tile.state
			if state and not state.ready and not state.claimed then tile.button.Text=clock((state.unlockAt or 0)-workspace:GetServerTimeNow()) end
		end
	end)
end
return Controller
