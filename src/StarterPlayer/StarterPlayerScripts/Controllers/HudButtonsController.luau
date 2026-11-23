--!strict
-- Existing Add API; entries are positioned into simulator HUD regions using our asset pack.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Shared=RS.Shared
local Shop=require(Shared.Config.Shop)
local Monetization=require(Shared.Config.Monetization)
local Art=require(Shared.Config.UIAssets)
local C=require(Shared.Config.HudLayout)
local Layout=require(Shared.Util.HudLayout)
local Viewport=require(Shared.Util.Viewport)
local L=require(Shared.Util.Localization)
local UiSkin=require(Shared.Util.UiSkin)
local Network=require(Shared.Network)
local InputMode=require(script.Parent.InputModeController)
local ShopController=require(script.Parent.ShopController)
local RebirthController=require(script.Parent.RebirthController)
local MergeController=require(script.Parent.MergeController)
local Notification=require(script.Parent.NotificationController)
local UI=Shop.Ui
local Controller={Priority=62}
local player=Players.LocalPlayer
local root:Frame
local buttons:{[string]:TextButton}={}
local labels:{[string]:TextLabel}={}
local icons:{[string]:ImageLabel}={}
local badges:{[string]:TextLabel}={}
local ribbons:{[string]:TextLabel}={}
local positions:{[string]:UDim2}={}
local snapshot:any={}
local auto:TextButton
local busy=false
local iconKeys={Home="Pillow",FreeGift="Daily",Merge="Merge"}
local topOrder={Collection=1,Home=2,Robux=3}
local leftOrder={Shop=1,Rebirth=2,Quests=3,Daily=4}
local rightOrder={FreeGift=1,Inventory=2,Merge=3}
local function text(parent:Instance,name:string):TextLabel
 local label=Instance.new("TextLabel")
 label.Name=name label.BackgroundTransparency=1 label.Font=Enum.Font.FredokaOne
 label.TextScaled=true label.TextColor3=UI.OnColor label.ZIndex=3
 local stroke=Instance.new("UIStroke") stroke.Color=UiSkin.Outline stroke.Thickness=C.TextStroke stroke.Parent=label
 label.Parent=parent return label
end
local function layout()
 if not root then return end
 local m=Layout.Get(root,InputMode.IsTouch())
 for id,button in buttons do
  local wide=topOrder[id]~=nil local round=id=="Settings" or id=="Admin"
  local right=rightOrder[id]~=nil
  local w=if wide then m.wide elseif round then C.MinimumTouch elseif right then m.rightTile else m.tile
  local h=if wide then m.topHeight elseif round then C.MinimumTouch elseif right then m.rightTile else m.tile
  local x,y
  if wide then x=m.topX+(topOrder[id]-1)*(m.wide+m.gap) y=m.margin
  elseif leftOrder[id] then local i=leftOrder[id]-1 x=m.margin+(i%2)*(m.tile+m.gap) y=m.gridTop+math.floor(i/2)*(m.tile+m.gap)
  elseif rightOrder[id] then x=m.rightX y=m.rightTop+(rightOrder[id]-1)*(m.rightTile+m.gap)
  elseif round then x=m.width-m.margin-C.MinimumTouch-(if id=="Admin" then C.MinimumTouch+m.gap else 0) y=m.cornerY
  else x=m.width-m.tile-m.margin y=m.rightTop+3*(m.tile+m.gap) end
  button.Size=UDim2.fromOffset(w,h) button.Position=UDim2.fromOffset(x,y) positions[id]=button.Position
  local icon=icons[id]
  if icon then icon.Size=UDim2.fromOffset(h*0.59,h*0.59)
   icon.Position=if wide then UDim2.fromOffset(h*0.36,h*0.5) else UDim2.fromScale(0.5,if round then 0.5 else 0.34) end
  local label=labels[id] label.Visible=not round
  label.Size=if wide then UDim2.new(1,-h*0.8-8,1,-10) else UDim2.new(1,-6,0.32,0)
  label.Position=if wide then UDim2.fromOffset(h*0.75,5) else UDim2.new(0,3,0.65,0)
  label.TextWrapped=true
  local limit=label:FindFirstChildOfClass("UITextSizeConstraint") if limit then limit.MaxTextSize=if m.compact then 16 else 23 end
 end
 auto.Size=UDim2.fromOffset(m.tile*2+m.gap,C.MinimumTouch)
 auto.Position=UDim2.fromOffset(m.margin,m.gridTop+m.tile*2+m.gap*2)
end
function Controller.Add(id:string,_text:string,order:number,color:Color3?,callback:()->()):TextButton
 if buttons[id] then buttons[id]:Destroy() end
 local button=Instance.new("TextButton")
 button.Name=id button.LayoutOrder=order button.BackgroundColor3=color or UI.Surface button.Text="" button.BorderSizePixel=0
 button:SetAttribute("UiSkin",if topOrder[id] then "Button:Gold" else "Slot") button:SetAttribute("UiNoScale",true) button.Parent=root
 if id=="Settings" or id=="Admin" then button:SetAttribute("UiSkin","None") local corner=Instance.new("UICorner") corner.CornerRadius=UDim.new(1,0) corner.Parent=button end
 local key=(iconKeys::any)[id] or (Art.HudIcons::any)[id]
 local iconId=if key then (Art.Icons::any)[key] else nil
 if iconId then icons[id]=UiSkin.Icon(button,iconId,UDim2.fromOffset(40,40),UDim2.fromScale(0.5,0.4),Vector2.new(0.5,0.5)) end
 local label=text(button,"Label") L.Bind(label,"Hud."..id) labels[id]=label
 local constraint=Instance.new("UITextSizeConstraint") constraint.MaxTextSize=23 constraint.Parent=label
 local badge=text(button,"ActionBadge") badge.Size=UDim2.fromOffset(22,22) badge.Position=UDim2.new(1,-15,0,-6)
 badge.BackgroundTransparency=0 badge.BackgroundColor3=UI.Danger badge.Text=L.T("Hud.Alert") badge.Visible=false badge.ZIndex=8
 local circle=Instance.new("UICorner") circle.CornerRadius=UDim.new(1,0) circle.Parent=badge badges[id]=badge
 if id=="Shop" or id=="Robux" then
  local ribbon=text(button,"NewRibbon") ribbon.BackgroundTransparency=0 ribbon.BackgroundColor3=UI.Danger
  ribbon.Size=UDim2.fromOffset(58,20) ribbon.Position=UDim2.fromOffset(-3,-6) ribbon.Rotation=-8 ribbon.Visible=false ribbon.ZIndex=9
  L.Bind(ribbon,"Hud.New") ribbons[id]=ribbon
 end
 button.Activated:Connect(callback) buttons[id]=button layout() return button
end
local function updateState(state:any)
 if type(state)~="table" then return end snapshot=state
 local active={Daily=state.dailyClaimable or state.pendingDailyClaimable,Quests=(state.questClaimableCount or 0)>0,
 FreeGift=state.freeGiftClaimable,Collection=state.indexRewardsReady,Rebirth=state.canRebirth,Merge=state.canMerge,Inventory=(state.usableItems or 0)>0}
 for id,badge in badges do badge.Visible=(active::any)[id]==true end
 for _,ribbon in ribbons do ribbon.Visible=state.shopHasNewItems==true end
 auto.Visible=state.autoCollectOwned==true auto.Text=L.T(if state.autoCollectEnabled then "Hud.AutoCollectOn" else "Hud.AutoCollectOff")
 auto:SetAttribute("UiSkin",if state.autoCollectEnabled then "Button:Green" else "Button:Gray")
end
local function invoke(name:string,arg:any?)
 if busy then return end busy=true
 task.spawn(function()
  local ok,success,key,state=pcall(function() return Network.GetFunction(name):InvokeServer(arg) end)
  if ok then updateState(state) if type(key)=="string" then Notification.ShowLocal(L.T(key),if success then "Success" else "Error") end end busy=false
 end)
end
function Controller:Init()
 local gui=Instance.new("ScreenGui") gui.Name="HudButtons" gui.ResetOnSpawn=false gui.DisplayOrder=UI.HotbarDisplayOrder
 gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets gui.ClipToDeviceSafeArea=true
 root=Instance.new("Frame") root.Name="Navigation" root.BackgroundTransparency=1 root.Size=UDim2.fromScale(1,1) root:SetAttribute("UiNoScale",true) root.Parent=gui
 auto=Instance.new("TextButton") auto.Name="AutoCollect" auto.Text="" auto.BackgroundColor3=UI.Accent auto.Font=Enum.Font.FredokaOne auto.TextScaled=true
 auto.TextColor3=UI.OnColor auto.Visible=false auto:SetAttribute("UiSkin","Button:Green") auto.Parent=root
 auto.Activated:Connect(function() invoke("HudAutoCollect",not snapshot.autoCollectEnabled) end)
 gui.Parent=player:WaitForChild("PlayerGui")
 Controller.Add("Home","",2,UI.Coin,function() invoke("HudHome",nil) end)
 Controller.Add("Robux","",100,UI.Coin,function() ShopController.OpenTab(Monetization.StoreTabName) end)
 Controller.Add("Rebirth","",30,nil,RebirthController.Open)
 Controller.Add("FreeGift","",60,nil,function() Network.GetEvent("RetentionRequest"):FireServer(if (snapshot.questClaimableCount or 0)>0 and not snapshot.dailyClaimable and not snapshot.pendingDailyClaimable then "Quests" else "Daily") end)
 Controller.Add("Merge","",70,nil,MergeController.Open)
 root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout) Viewport.Changed:Connect(layout) InputMode.Changed:Connect(layout)
 local function watchControl(object:Instance)
  if object:IsA("GuiObject") and object.Name=="JumpButton" then
   object:GetPropertyChangedSignal("AbsolutePosition"):Connect(layout)
   object:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
   object:GetPropertyChangedSignal("Visible"):Connect(layout)
   task.defer(layout)
  end
 end
 for _,object in player.PlayerGui:GetDescendants() do watchControl(object) end
 player.PlayerGui.DescendantAdded:Connect(watchControl)
end
function Controller:Start()
 Network.GetEvent("HudState").OnClientEvent:Connect(updateState)
 task.spawn(function() local ok,state=pcall(function() return Network.GetFunction("HudSnapshot"):InvokeServer() end) if ok then updateState(state) end end)
 task.spawn(function()
  local shopGui=player.PlayerGui:WaitForChild(Shop.GuiName)
  local wasOpen=false
  shopGui:GetPropertyChangedSignal("Enabled"):Connect(function()
   if shopGui.Enabled then wasOpen=true elseif wasOpen then wasOpen=false
    task.spawn(function() local ok,state=pcall(function() return Network.GetFunction("HudShopSeen"):InvokeServer() end) if ok then updateState(state) end end)
   end
  end)
 end)
 RunService.RenderStepped:Connect(function()
  if labels.Home then local n=math.ceil(math.max(0,(snapshot.homeReadyAt or 0)-workspace:GetServerTimeNow()))
   labels.Home.Text=L.T(if n>0 then "Hud.HomeCooldown" else "Hud.Home",{seconds=n}) end
  if labels.Daily then
   if snapshot.loaded and not snapshot.dailyClaimable and not snapshot.pendingDailyClaimable then
    local n=math.ceil(math.max(0,(snapshot.dailyReadyAt or os.time())-os.time())) labels.Daily.Text=string.format("%02d:%02d:%02d",n//3600,(n%3600)//60,n%60)
   else labels.Daily.Text=L.T("Hud.Daily") end
  end
  if buttons.FreeGift and positions.FreeGift then local offset=if snapshot.freeGiftClaimable then math.abs(math.sin(os.clock()*C.GiftBounceSpeed))*C.GiftBounceHeight else 0
   buttons.FreeGift.Position=positions.FreeGift-UDim2.fromOffset(0,offset) end
 end)
 layout()
end
return Controller

