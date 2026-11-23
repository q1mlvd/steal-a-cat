--!strict
-- LocalizationTable is the canonical catalog; world labels and server source text are adapted on this client.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalizationService = game:GetService("LocalizationService")
local Localization = require(ReplicatedStorage.Shared.Util.Localization)
local NameTags = require(ReplicatedStorage.Shared.Config.NameTags)
local Controller = {Priority = 0}
local observed: {[Instance]: boolean} = setmetatable({}, {__mode = "k"}) :: any
local refreshers: {[Instance]: {() -> ()}} = setmetatable({}, {__mode = "k"}) :: any

local function observe(object: Instance)
	if observed[object] then return end
	if object.Name == "Name" and object.Parent and object.Parent.Name == NameTags.GuiName then return end
	local ancestor: Instance? = object
	while ancestor do
		if ancestor:IsA("ScreenGui") and (ancestor.Name == "TouchGui" or ancestor.Name == "Chat"
			or ancestor.Name == "BubbleChat" or ancestor.Name == "BubbleChatUI") then return end
		ancestor = ancestor.Parent
	end
	local properties = {}
	if object:IsA("TextLabel") or object:IsA("TextButton") then properties = {"Text"}
	elseif object:IsA("TextBox") then properties = {"PlaceholderText"}
	elseif object:IsA("ProximityPrompt") then properties = {"ActionText", "ObjectText"}
	else return end
	observed[object] = true
	-- Translation is explicit through our table; prevent engine auto-fitting from shrinking numeric HUD text.
	if object:IsA("GuiBase2d") then object.AutoLocalize = false end
	refreshers[object] = {}
	local busy = false
	for _, property in properties do
		local source = (object :: any)[property]
		local lastApplied: string? = nil
		local function refresh(replaceSource: boolean?)
			if busy then return end
			if replaceSource then
				local current = (object :: any)[property]
				if current == lastApplied then return end
				source = current
			end
			local result = Localization.Translate(source)
			local target = object :: any
			if result ~= target[property] then
				busy = true
				lastApplied = result
				target[property] = result
				busy = false
			end
		end
		object:GetPropertyChangedSignal(property):Connect(function() refresh(true) end)
		table.insert(refreshers[object], function() refresh(false) end)
		refresh()
	end
end

function Controller:Start(): ()
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui.DescendantAdded:Connect(observe)
	workspace.DescendantAdded:Connect(observe)
	for _, object in gui:GetDescendants() do observe(object) end
	for _, object in workspace:GetDescendants() do observe(object) end
	Localization.Changed:Connect(function()
		for object, callbacks in refreshers do
			if object.Parent and object:GetAttribute("LocalizationKey") == nil then
				for _, callback in callbacks do callback() end
			end
		end
	end)
	Localization.LoadTranslator()
	LocalizationService:GetPropertyChangedSignal("RobloxLocaleId"):Connect(function() Localization.LoadTranslator() end)
	Players.LocalPlayer:GetAttributeChangedSignal("DebugLocale"):Connect(function() Localization.Refresh() end)
end

return Controller

