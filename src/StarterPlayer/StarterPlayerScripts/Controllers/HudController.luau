--!strict
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local SocialService=game:GetService("SocialService")
local Shared=RS.Shared
local Economy=require(Shared.Config.Economy)
local Shop=require(Shared.Config.Shop)
local Art=require(Shared.Config.UIAssets)
local C=require(Shared.Config.HudLayout)
local Layout=require(Shared.Util.HudLayout)
local Viewport=require(Shared.Util.Viewport)
local NumberFormat=require(Shared.Util.NumberFormat)
local L=require(Shared.Util.Localization)
local UiSkin=require(Shared.Util.UiSkin)
local Network=require(Shared.Network)
local InputMode=require(script.Parent.InputModeController)
local Notification=require(script.Parent.NotificationController)
local Controller={Priority=20}
local player=Players.LocalPlayer
local root:Frame local stats:Frame local invite:TextButton local pulse:UIScale
local labels:{TextLabel}={} local rows:{Frame}={}
local displayed,target=0,0
local function layout()
 local m=Layout.Get(root,InputMode.IsTouch())
 stats.Position=UDim2.fromOffset(m.statsX,m.statsY)
 stats.Size=UDim2.fromOffset(m.statsWidth,m.statHeight*4)
 for i,row in rows do
  row.Size=UDim2.new(1,0,0,m.statHeight) row.Position=UDim2.fromOffset(0,(i-1)*m.statHeight)
  local icon=row:FindFirstChild("Icon")::ImageLabel icon.Size=UDim2.fromOffset(m.statHeight,m.statHeight)
  labels[i].Position=UDim2.fromOffset(m.statHeight+5,0) labels[i].Size=UDim2.new(1,-m.statHeight-10-(if i==4 then C.MinimumTouch else 0),1,0)
 end
 invite.Size=UDim2.fromOffset(C.MinimumTouch,C.MinimumTouch) invite.AnchorPoint=Vector2.new(1,0.5) invite.Position=UDim2.new(1,0,0,m.statHeight*3.5)
 local hint=player.PlayerGui:FindFirstChild("ControlsHint") local panel=if hint then hint:FindFirstChild("Panel",true) else nil
 if panel and panel:IsA("Frame") then panel.AnchorPoint=Vector2.new(1,1) panel.Position=UDim2.new(1,-m.margin,1,-C.TimerHeight-C.Margin*3) end
end
function Controller.Pulse()
 pulse.Scale=C.CoinPulseScale TweenService:Create(pulse,TweenInfo.new(C.CoinPulseTime,Enum.EasingStyle.Back),{Scale=1}):Play()
end
function Controller:Init()
 local gui=Instance.new("ScreenGui") gui.Name="Hud" gui.ResetOnSpawn=false gui.DisplayOrder=5 gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets gui.ClipToDeviceSafeArea=true
 root=Instance.new("Frame") root.Name="StatsCanvas" root.Size=UDim2.fromScale(1,1) root.BackgroundTransparency=1 root:SetAttribute("UiNoScale",true) root.Parent=gui
 stats=Instance.new("Frame") stats.Name="Stats" stats.BackgroundTransparency=1 stats.Parent=root
 for i,id in {"Coin","IncomePerSec","Luck","Multiplier"} do
  local row=Instance.new("Frame") row.Name=id row.BackgroundTransparency=1 row.Parent=stats rows[i]=row
  local icon=UiSkin.Icon(row,(Art.Icons::any)[id],UDim2.fromOffset(32,32),UDim2.fromOffset(0,0)) icon.Name="Icon"
  local label=Instance.new("TextLabel") label.Name="Value" label.BackgroundTransparency=1 label.Font=Enum.Font.FredokaOne label.TextScaled=true label.TextXAlignment=Enum.TextXAlignment.Left
  label.AutoLocalize=false label.TextColor3=Shop.Ui.OnColor label.TextWrapped=true label.Parent=row labels[i]=label
  local stroke=Instance.new("UIStroke") stroke.Color=UiSkin.Outline stroke.Thickness=C.TextStroke stroke.Parent=label
 end
 pulse=Instance.new("UIScale") pulse.Parent=rows[1]
 invite=Instance.new("TextButton") invite.Name="InviteFriends" invite.BackgroundColor3=Shop.Ui.Accent invite.Text="" invite:SetAttribute("UiSkin","Button:Green") invite.Parent=stats
 UiSkin.Icon(invite,Art.Controls.Plus,UDim2.fromScale(0.6,0.6),UDim2.fromScale(0.5,0.5),Vector2.new(0.5,0.5))
 invite.Activated:Connect(function() task.spawn(function()
  local ok,can=pcall(function() return SocialService:CanSendGameInviteAsync(player) end)
  if ok and can then pcall(function() SocialService:PromptGameInvite(player) end) else Notification.ShowLocal(L.T("Hud.InviteUnavailable"),"Info") end
 end) end)
 gui.Parent=player:WaitForChild("PlayerGui")
 root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout) Viewport.Changed:Connect(layout) InputMode.Changed:Connect(layout)
 labels[1].Text=NumberFormat.Format(0) labels[2].Text=L.T("Hud.Income",{amount="0"}) labels[3].Text=L.T("Hud.Luck",{amount="1"}) labels[4].Text=L.T("Hud.Friends",{percent=0}) layout()
end
function Controller:Start()
 Network.GetEvent("HudState").OnClientEvent:Connect(function(s:any)
  if type(s)~="table" then return end labels[2].Text=L.T("Hud.Income",{amount=NumberFormat.Format(s.incomePerSecond or 0)})
  labels[3].Text=L.T("Hud.Luck",{amount=string.format("%.2f",s.luckMultiplier or 1)}) labels[4].Text=L.T("Hud.Friends",{percent=s.friendBonusPercent or 0})
 end)
 task.spawn(function()
  local leaderstats=player:WaitForChild("leaderstats",math.huge) local value=(leaderstats::Instance):WaitForChild(Economy.LeaderstatName,math.huge)::NumberValue
  displayed=value.Value target=value.Value labels[1].Text=NumberFormat.Format(displayed) value.Changed:Connect(function(v:number) target=v end)
 end)
 RunService.RenderStepped:Connect(function(dt:number)
  if displayed==target then return end displayed+=(target-displayed)*math.min(1,dt*Economy.CountUpSpeed)
  if math.abs(target-displayed)<C.CoinSnapEpsilon then displayed=target end labels[1].Text=NumberFormat.Format(displayed)
 end) task.defer(layout)
end
return Controller

