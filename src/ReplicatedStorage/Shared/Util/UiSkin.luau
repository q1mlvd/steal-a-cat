--!strict
-- UI skin helpers (Stage 18 UI pack): 9-slice frames behind any GuiObject, text lifted above the image,
-- bars, icons and badges. Client-side only. Asset ids: Config/UIAssets.
--
-- How a skin is added: a child ImageLabel "Skin" (ZIndex below the other children, padding ignored) carries the
-- sliced image and the object's own background is hidden. A Text* object's own text would render under that
-- child, so its text is mirrored into a child TextLabel "SkinText" that follows every text property change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIAssets = require(ReplicatedStorage.Shared.Config.UIAssets)

local SKIN_NAME = "Skin"
local TEXT_NAME = "SkinText"
local SKIN_Z = 0 -- below default children (ZIndex 1)
local OUTLINE = Color3.fromRGB(58, 26, 70) -- the pack's dark-purple outline
local PRESS_TINT = Color3.fromRGB(215, 215, 215)
local HOVER_TINT = Color3.fromRGB(240, 240, 240)
local MIRRORED = { "Text", "TextColor3", "FontFace", "TextSize", "TextScaled", "TextWrapped", "TextXAlignment",
	"TextYAlignment", "TextTruncate", "RichText", "LineHeight", "TextStrokeColor3", "TextStrokeTransparency" }

export type Slice = UIAssets.Slice

local UiSkin = {}

local mirrors: { [Instance]: { RBXScriptConnection } } = setmetatable({}, { __mode = "k" }) :: any
local sizeWatch: { [Instance]: RBXScriptConnection } = setmetatable({}, { __mode = "k" }) :: any

-- Corners never take more than half of the element: shrink SliceScale for small/short elements.
local function fitSlice(image: ImageLabel)
	local base = image:GetAttribute("BaseSliceScale")
	local corner = image:GetAttribute("CornerPixels")
	if type(base) ~= "number" or type(corner) ~= "number" or corner <= 0 then return end
	local size = image.AbsoluteSize
	local smallest = math.min(size.X, size.Y)
	if smallest <= 0 then
		image.SliceScale = base
		return
	end
	image.SliceScale = math.min(base, smallest / (2 * corner))
end
local pressWatch: { [Instance]: RBXScriptConnection } = setmetatable({}, { __mode = "k" }) :: any

local function paddingOf(object: GuiObject): (UDim, UDim, UDim, UDim)
	local padding = object:FindFirstChildOfClass("UIPadding")
	if padding then
		return padding.PaddingLeft, padding.PaddingRight, padding.PaddingTop, padding.PaddingBottom
	end
	return UDim.new(), UDim.new(), UDim.new(), UDim.new()
end

local function hasLayout(object: Instance): boolean
	return object:FindFirstChildWhichIsA("UIGridStyleLayout") ~= nil
end

-- Hides the outline strokes and the plain background so only the image shows. (Text objects keep a
-- Contextual stroke: that one outlines their text, not the box.)
local function hideBase(object: GuiObject)
	object.BackgroundTransparency = 1
	local isText = object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox")
	for _, child in object:GetChildren() do
		if child:IsA("UIStroke") and (not isText or child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border) then
			child.Enabled = false
		end
	end
end

-- Puts `slice` behind `object` (creates or updates its Skin child). Returns the image, or nil when the object
-- lays out its children with a UIListLayout/UIGridLayout (a Skin child would take a layout slot).
function UiSkin.Apply(object: GuiObject, slice: Slice): ImageLabel?
	if hasLayout(object) then
		return nil
	end
	local skin = object:FindFirstChild(SKIN_NAME)
	if skin == nil or not skin:IsA("ImageLabel") then
		skin = Instance.new("ImageLabel")
		skin.Name = SKIN_NAME
		skin.BackgroundTransparency = 1
		skin.ScaleType = Enum.ScaleType.Slice
		skin.ZIndex = SKIN_Z
		skin.Active = false
		skin.Parent = object
	end
	local image = skin :: ImageLabel
	local left, right, top, bottom = paddingOf(object)
	image.Position = UDim2.new(-left.Scale, -left.Offset, -top.Scale, -top.Offset)
	image.Size = UDim2.new(1 + left.Scale + right.Scale, left.Offset + right.Offset,
		1 + top.Scale + bottom.Scale, top.Offset + bottom.Offset)
	image.Image = slice.image
	image.SliceCenter = slice.center
	image.ScaleType = Enum.ScaleType.Slice
	image:SetAttribute("BaseSliceScale", slice.scale)
	image:SetAttribute("CornerPixels", math.max(slice.center.Min.X, slice.center.Min.Y))
	fitSlice(image)
	if sizeWatch[image] == nil then
		sizeWatch[image] = image:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			fitSlice(image)
		end)
	end
	hideBase(object)
	return image
end

-- A plain (non-sliced) image behind/inside `object`, e.g. the round close button.
function UiSkin.ApplyImage(object: GuiObject, imageId: string): ImageLabel?
	if hasLayout(object) then
		return nil
	end
	local image = UiSkin.Apply(object, { image = imageId, center = Rect.new(0, 0, 0, 0), scale = 1 }) :: ImageLabel
	image.ScaleType = Enum.ScaleType.Fit
	image:SetAttribute("CornerPixels", nil)
	return image
end

function UiSkin.GetSkin(object: Instance): ImageLabel?
	local skin = object:FindFirstChild(SKIN_NAME)
	return if skin and skin:IsA("ImageLabel") then skin else nil
end

function UiSkin.Remove(object: GuiObject)
	local skin = object:FindFirstChild(SKIN_NAME)
	if skin then
		skin:Destroy()
	end
end

-- Lifts a TextLabel/TextButton's text above its Skin child (mirrored child label). `outline` adds the pack's
-- dark outline (for text on coloured buttons/tabs); `color` overrides the text colour.
function UiSkin.LiftText(object: TextLabel | TextButton, outline: boolean?, color: Color3?)
	local source = object :: any
	local label = object:FindFirstChild(TEXT_NAME) :: TextLabel?
	if label == nil then
		local created = Instance.new("TextLabel")
		created.Name = TEXT_NAME
		created.BackgroundTransparency = 1
		created.Size = UDim2.fromScale(1, 1)
		created.ZIndex = 1
		created.Active = false
		for _, child in object:GetChildren() do
			if child:IsA("UITextSizeConstraint") then
				child:Clone().Parent = created
			end
		end
		created.Parent = object
		label = created
		local connections: { RBXScriptConnection } = {}
		for _, property in MIRRORED do
			table.insert(connections, object:GetPropertyChangedSignal(property):Connect(function()
				local target = object:FindFirstChild(TEXT_NAME) :: any
				if target == nil then return end
				if property == "TextColor3" and target:GetAttribute("ColorOverride") then return end
				target[property] = source[property]
			end))
		end
		-- Keep the parent's own glyphs invisible even if a controller fades/sets them later.
		table.insert(connections, object:GetPropertyChangedSignal("TextTransparency"):Connect(function()
			local target = object:FindFirstChild(TEXT_NAME) :: TextLabel?
			if target and source.TextTransparency ~= 1 then
				target.TextTransparency = source.TextTransparency
				source.TextTransparency = 1
			end
		end))
		mirrors[object] = connections
	end
	local target = label :: any
	for _, property in MIRRORED do
		target[property] = source[property]
	end
	target.TextTransparency = if source.TextTransparency == 1 then 0 else source.TextTransparency
	source.TextTransparency = 1
	local stroke = (label :: TextLabel):FindFirstChild("Outline")
	if outline then
		if stroke == nil then
			local created = Instance.new("UIStroke")
			created.Name = "Outline"
			created.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			created.Color = OUTLINE
			created.Thickness = 1.5
			created.Parent = label
		end
	elseif stroke then
		stroke:Destroy()
	end
	if color then
		target:SetAttribute("ColorOverride", true)
		target.TextColor3 = color
	else
		target:SetAttribute("ColorOverride", nil)
		target.TextColor3 = source.TextColor3
	end
end

function UiSkin.GetText(object: Instance): TextLabel?
	local label = object:FindFirstChild(TEXT_NAME)
	return if label and label:IsA("TextLabel") then label else nil
end

-- Darkens the skin while a button is hovered / pressed (AutoButtonColor has no visible background any more).
function UiSkin.WatchPress(button: GuiButton)
	if pressWatch[button] then
		return
	end
	pressWatch[button] = button:GetPropertyChangedSignal("GuiState"):Connect(function()
		local skin = UiSkin.GetSkin(button)
		if skin == nil then return end
		local state = button.GuiState
		local configured = button:GetAttribute("UiSkinTintColor")
		local tint = if typeof(configured) == "Color3" then configured else Color3.new(1, 1, 1)
		local shade = if not button.Active then Color3.new(1, 1, 1)
			elseif state == Enum.GuiState.Press then PRESS_TINT
			elseif state == Enum.GuiState.Hover then HOVER_TINT else Color3.new(1, 1, 1)
		skin.ImageColor3 = Color3.new(tint.R * shade.R, tint.G * shade.G, tint.B * shade.B)
	end)
end

-- Progress bar look: sliced track on `back`, sliced fill on `fill` (fill keeps its Size/X scale = progress).
function UiSkin.Bar(back: GuiObject, fill: GuiObject, fillName: "Green" | "Pink" | "Gold")
	back.ClipsDescendants = false
	UiSkin.Apply(back, UIAssets.Bars.Background)
	UiSkin.Apply(fill, (UIAssets.Bars :: any)[fillName])
	for _, child in fill:GetChildren() do
		if child:IsA("UICorner") then child:Destroy() end
	end
	for _, child in back:GetChildren() do
		if child:IsA("UICorner") then child:Destroy() end
	end
end

-- A square icon image.
function UiSkin.Icon(parent: Instance, imageId: string, size: UDim2, position: UDim2?, anchor: Vector2?): ImageLabel
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = imageId
	icon.Size = size
	icon.Position = position or UDim2.new()
	icon.AnchorPoint = anchor or Vector2.zero
	icon.Parent = parent
	return icon
end

UiSkin.Outline = OUTLINE

return UiSkin

