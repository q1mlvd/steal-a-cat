--!strict
-- Shared responsive modal shell. Content keeps the established UI pack and localization bindings.
local Players=game:GetService("Players")
local ContextActionService=game:GetService("ContextActionService")
local RS=game:GetService("ReplicatedStorage")
local C=require(RS.Shared.Config.FeatureWindows)
local Shop=require(RS.Shared.Config.Shop)
local L=require(RS.Shared.Util.Localization)
local Signal=require(RS.Shared.Util.Signal)
local UiSkin=require(RS.Shared.Util.UiSkin)
local Window={}
local windows={}
local function properties(object:any,props:any)
 if props then for key,value in props do object[key]=value end end
end
local function outline(object:Instance)
 local stroke=Instance.new("UIStroke") stroke.Name="FeatureTextOutline"
 local text=object::any
 local dark=text.TextColor3.R*.299+text.TextColor3.G*.587+text.TextColor3.B*.114<C.DarkTextThreshold
 stroke.Color=if dark then Shop.Ui.Background else UiSkin.Outline
 stroke.Thickness=if dark then C.DarkTextStroke else C.TextStroke stroke.Parent=object
end
function Window.Text(parent:Instance,key:string,params:any?,props:any?):TextLabel
 local text=Instance.new("TextLabel") text.BackgroundTransparency=1 text.Font=Enum.Font.FredokaOne
 text.TextScaled=true text.TextWrapped=true text.AutoLocalize=false text.TextColor3=Shop.Ui.Text
 text.Size=UDim2.new(1,0,0,C.TextHeight) text.Text="" properties(text,props) text.Parent=parent
 local limit=Instance.new("UITextSizeConstraint") limit.MaxTextSize=if props and props.TextSize then props.TextSize else C.BodyFontSize limit.MinTextSize=C.MinimumFontSize limit.Parent=text
 outline(text) if key~="" then L.Bind(text,key,params) end return text
end
function Window.Button(parent:Instance,key:string,params:any?,callback:(()->())?,props:any?):TextButton
 local button=Instance.new("TextButton") button.BackgroundColor3=Shop.Ui.Accent button.BorderSizePixel=0
 button.Font=Enum.Font.FredokaOne button.TextScaled=true button.TextWrapped=true button.AutoLocalize=false
 button.TextColor3=Shop.Ui.OnColor button.Text="" button.Size=UDim2.new(1,0,0,C.MinimumTouch)
 properties(button,props) button.Parent=parent
 local limit=Instance.new("UITextSizeConstraint") limit.MaxTextSize=if props and props.TextSize then props.TextSize else C.BodyFontSize limit.MinTextSize=C.MinimumFontSize limit.Parent=button
 outline(button) if key~="" then L.Bind(button,key,params) end
 if callback then button.Activated:Connect(function() if button.Active then callback() end end) end return button
end
function Window.Image(parent:Instance,imageId:string,props:any?):ImageLabel
 local image=Instance.new("ImageLabel") image.BackgroundTransparency=1 image.Image=imageId
 image.Size=UDim2.fromScale(1,1) image.ScaleType=Enum.ScaleType.Fit properties(image,props) image.Parent=parent return image
end
function Window.Create(name:string,titleKey:string,options:any?):any
 local opts=options or {} local player=Players.LocalPlayer assert(player,"FeatureWindow is client-only")
 local pg=player:FindFirstChildOfClass("PlayerGui") assert(pg,"PlayerGui must exist before controllers initialize")
 local gui=Instance.new("ScreenGui") gui.Name=name gui.ResetOnSpawn=false gui.Enabled=false
 gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets gui.ClipToDeviceSafeArea=true
 gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling gui.DisplayOrder=opts.displayOrder or C.DisplayOrder
 gui:SetAttribute("FeatureWindow",true)
 local canvas=Instance.new("Frame") canvas.Name="Canvas" canvas.BackgroundTransparency=1 canvas.Size=UDim2.fromScale(1,1)
 canvas:SetAttribute("UiNoScale",true) canvas.Parent=gui
 local shade=Instance.new("TextButton") shade.Name="Shade" shade.Text="" shade.AutoButtonColor=false shade.Modal=true
 shade.BackgroundColor3=Color3.new(0,0,0) shade.BackgroundTransparency=C.ShadeTransparency shade.Size=UDim2.fromScale(1,1) shade.Parent=canvas
 local panel=Instance.new("Frame") panel.Name="Panel" panel.BackgroundColor3=Shop.Ui.Background panel.BorderSizePixel=0
 panel:SetAttribute("UiSkin","Panel") panel:SetAttribute("UiSkinInset",true) panel:SetAttribute("UiNoScale",true) panel.ZIndex=2
 panel.AnchorPoint=Vector2.new(.5,.5) panel.Position=UDim2.fromScale(.5,.5) panel.Parent=canvas
 local header=Instance.new("Frame") header.Name="Header" header.BackgroundTransparency=1 header.Parent=panel
 local title=Window.Text(header,titleKey,nil,{Name="Title",TextSize=C.HeaderFontSize,TextXAlignment=Enum.TextXAlignment.Left})
 local close=Window.Button(header,"",nil,nil,{Name="Close",Text="×",BackgroundColor3=Shop.Ui.Danger})
 close:SetAttribute("UiSkin","Close")
 local body=Instance.new(if opts.scroll==false then "Frame" else "ScrollingFrame") body.Name="Body" body.BackgroundTransparency=1 body.BorderSizePixel=0 body.Parent=panel
 local layout:any=nil
 if body:IsA("ScrollingFrame") then
  body.ScrollingDirection=Enum.ScrollingDirection.Y body.AutomaticCanvasSize=Enum.AutomaticSize.Y
  body.CanvasSize=UDim2.fromOffset(0,0) body.ScrollBarThickness=C.Gap/2 body.ScrollBarImageColor3=Shop.Ui.Accent
  layout=Instance.new("UIListLayout") layout.SortOrder=Enum.SortOrder.LayoutOrder layout.Padding=UDim.new(0,C.Gap) layout.Parent=body
  local padding=Instance.new("UIPadding") padding.PaddingBottom=UDim.new(0,C.Gap) padding.PaddingRight=UDim.new(0,C.Gap) padding.Parent=body
 end
 local self:any={Gui=gui,Panel=panel,Header=header,Body=body,BodyLayout=layout,Title=title,CloseButton=close,SizeChanged=Signal.new()}
 local action="CloseFeatureWindow_"..name
 function self:Relayout()
  local available=canvas.AbsoluteSize if available.X<=0 or available.Y<=0 then local c=workspace.CurrentCamera available=if c then c.ViewportSize else Vector2.new(C.Width,C.Height) end
  local compact=available.Y<C.CompactHeight
  local padding=if compact then C.CompactPadding else C.Padding
  local headerHeight=if compact then C.CompactHeaderHeight else C.HeaderHeight
  local headerButton=if compact then C.MinimumTouch else C.HeaderButton
  local gap=if compact then C.CompactGap else C.Gap
  local width=math.max(headerButton+padding*2,math.min(opts.width or C.Width,available.X-C.Margin*2))
  local height=math.min(opts.height or C.Height,available.Y-C.Margin*2)
  panel.Size=UDim2.fromOffset(width,height)
  header.Position=UDim2.fromOffset(padding,padding) header.Size=UDim2.new(1,-padding*2,0,headerHeight)
  title.Size=UDim2.new(1,-(headerButton+gap+(opts.headerExtra or 0)),1,0)
  close.AnchorPoint=Vector2.new(1,.5) close.Position=UDim2.fromScale(1,.5) close.Size=UDim2.fromOffset(headerButton,headerButton)
  body.Position=UDim2.fromOffset(padding,padding+headerHeight+gap)
  body.Size=UDim2.new(1,-padding*2,1,-(padding*2+headerHeight+gap))
  self.SizeChanged:Fire(width,height)
 end
 function self:IsOpen():boolean return gui.Enabled end
 function self:Close()
  gui.Enabled=false ContextActionService:UnbindAction(action)
  local anyOpen=false for _,w in windows do if w.Gui.Enabled then anyOpen=true break end end
  if not anyOpen then player:SetAttribute(Shop.UiStateAttribute,false) end
 end
 function self:Open()
  for _,w in windows do if w~=self then w:Close() end end self:Relayout() gui.Enabled=true player:SetAttribute(Shop.UiStateAttribute,true)
  ContextActionService:BindActionAtPriority(action,function(_,state)
   if game:GetService("UserInputService"):GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
   if state==Enum.UserInputState.Begin then self:Close() end return Enum.ContextActionResult.Sink
  end,false,Enum.ContextActionPriority.High.Value,C.CloseKey,C.CloseGamepadKey)
 end
 close.Activated:Connect(function() self:Close() end) shade.Activated:Connect(function() self:Close() end)
 canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:Relayout() end)
 player.CharacterAdded:Connect(function() self:Close() end)
 table.insert(windows,self) gui.Parent=pg self:Relayout() return self
end
return Window
