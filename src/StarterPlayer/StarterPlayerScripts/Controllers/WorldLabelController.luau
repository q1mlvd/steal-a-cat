--!strict
-- One short house label replaces its SurfaceGui locally. Map signs share screen-space clearance.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local C=require(RS.Shared.Config.WorldLabels)
local Plots=require(RS.Shared.Config.Plots)
local L=require(RS.Shared.Util.Localization)
local Controller={Priority=19}
local player=Players.LocalPlayer
local labels:any={}
local folder:Folder
local function track(b:BillboardGui)
 if labels[b] then return end
 labels[b]={base=b.StudsOffsetWorldSpace, priority=b:GetAttribute("WorldLabelPriority") or 10, requested=true}
end
local function house(sign:BasePart)
 local plot=sign.Parent if not plot or not plot:IsA("Model") then return end
 local surface=sign:FindFirstChildOfClass("SurfaceGui") if surface then surface.Enabled=false end
 local b=Instance.new("BillboardGui") b.Name="HouseLabel" b.Adornee=sign b.Size=C.Size
 b.AlwaysOnTop=C.AlwaysOnTop b.StudsOffsetWorldSpace=C.Offset b.MaxDistance=C.MaxDistance b.LightInfluence=0 b:SetAttribute("WorldLabel",true)
 b:SetAttribute("WorldLabelPriority",50) b.Parent=folder
 local text=Instance.new("TextLabel") text.Size=UDim2.fromScale(1,1) text.BackgroundTransparency=1
 text.Font=Enum.Font.FredokaOne text.TextScaled=true text.TextColor3=C.TextColor
 text.TextStrokeTransparency=.15 text.Parent=b
 local limit=Instance.new("UITextSizeConstraint") limit.MaxTextSize=C.MaximumFontSize limit.MinTextSize=C.MinimumFontSize limit.Parent=text
 local function refresh()
  local owner=plot:GetAttribute(Plots.OwnerAttribute)
  if owner==player.UserId then L.Bind(text,"World.YourHome")
  elseif type(owner)=="number" then
   local p=Players:GetPlayerByUserId(owner) L.Bind(text,"World.OwnerHouse",{player=if p then p.DisplayName else tostring(owner)})
  else L.Bind(text,"World.EmptyHouse") end
 end
 plot:GetAttributeChangedSignal(Plots.OwnerAttribute):Connect(refresh) L.Changed:Connect(refresh) refresh() track(b)
end
local function inspect(instance:Instance)
 if instance:IsA("BillboardGui") and (instance:GetAttribute("WorldLabel")==true or (instance.Name=="Label" and instance:IsDescendantOf(workspace:FindFirstChild("Map") or workspace))) then track(instance)
 elseif instance:IsA("BasePart") and instance.Name=="Sign" and instance.Parent and instance.Parent:GetAttribute("PlotIndex")~=nil then house(instance) end
end
local function overlaps(a:any,b:any):boolean
 return a.x<b.x+b.w+C.Padding and a.x+a.w+C.Padding>b.x and a.y<b.y+b.h+C.Padding and a.y+a.h+C.Padding>b.y
end
local function update()
 local camera=workspace.CurrentCamera if not camera then return end
 local viewport=camera.ViewportSize local candidates={}
 for b,info in labels do
  if not b.Parent then labels[b]=nil continue end
  local ad=b.Adornee or b.Parent
  if not ad:IsA("BasePart") then continue end
  if b.Parent==folder or b.Name=="Label" then info.requested=true else info.requested=b.Enabled end
  local position=ad.Position+info.base local distance=(position-camera.CFrame.Position).Magnitude
  local point,onScreen=camera:WorldToViewportPoint(position)
  if info.requested and onScreen and (b.MaxDistance<=0 or distance<=b.MaxDistance) then
   table.insert(candidates,{b=b,info=info,point=point,distance=distance})
  elseif b.Parent==folder or b.Name=="Label" then b.Enabled=false end
 end
 table.sort(candidates,function(a,b) if a.info.priority~=b.info.priority then return a.info.priority>b.info.priority end return a.distance<b.distance end)
 local placed={}
 for _,candidate in candidates do
  local b=candidate.b local point=candidate.point local width=b.Size.X.Offset local height=b.Size.Y.Offset
  local found=false
  for step=0,math.floor(C.MaxShift/C.ShiftStep)*2 do
   local shift=if step==0 then 0 else math.ceil(step/2)*C.ShiftStep*(if step%2==1 then -1 else 1)
   local rect={x=point.X-width/2,y=point.Y-height/2+shift,w=width,h=height}
   if rect.y<C.TopMargin or rect.y+rect.h>viewport.Y-C.BottomMargin then continue end
   local collision=false for _,other in placed do if overlaps(rect,other) then collision=true break end end
   if not collision then
    local studs=2*math.tan(math.rad(camera.FieldOfView/2))*candidate.point.Z/viewport.Y
    b.StudsOffsetWorldSpace=candidate.info.base-camera.CFrame.UpVector*studs*shift
    b.Enabled=true table.insert(placed,rect) found=true break
   end
  end
  b.Enabled=found
 end
end
function Controller:Init()
 folder=Instance.new("Folder") folder.Name="WorldSignDisplays" folder.Parent=workspace
end
function Controller:Start()
 for _,instance in workspace:GetDescendants() do inspect(instance) end
 workspace.DescendantAdded:Connect(inspect)
 local elapsed=0 RunService.RenderStepped:Connect(function(dt) elapsed+=dt if elapsed>=C.RefreshInterval then elapsed=0 update() end end)
end
return Controller
