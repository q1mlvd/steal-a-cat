--!strict
-- Keyed translations use the game's LocalizationTable and the player's Roblox locale.
-- The source adapter covers server announcements and streamed world labels without changing gameplay data.
local Players = game:GetService("Players")
local LocalizationService = game:GetService("LocalizationService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Shared.Config.Localization)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local Localization = {}
Localization.Changed = Signal.new()
local translator: Translator? = nil
local localeTranslators: {[string]: Translator} = {}
local locale = string.lower(LocalizationService.RobloxLocaleId)
local sourceKeys: {[string]: string} = {}
local rows: {[string]: any} = {}
local bindings: {[Instance]: {key: string, params: any, property: string}} = setmetatable({}, {__mode = "k"}) :: any
local templates = {}
local atoms = {}
for _, row in Config.Rows do
	rows[row.Key] = row
	if sourceKeys[row.Source] == nil then sourceKeys[row.Source] = row.Key end
	for _, value in row.Values do
		if not string.find(value, "{", 1, true) and sourceKeys[value] == nil then sourceKeys[value] = row.Key end
	end
	if string.match(row.Key, "^Cat%.") or string.match(row.Key, "^Rarity%.") or string.match(row.Key, "^Mutation%.") or string.match(row.Key, "^Tier%.") then
		table.insert(atoms, row)
	end
	for _, source in {row.Source, row.Values.ru} do
	if type(source) == "string" and string.find(source, "{", 1, true) then
		local names = {}
		local pattern = "^"
		local cursor = 1
		for first, name, last in string.gmatch(source, "(){([%w_]+)}()") do
			pattern ..= string.gsub(string.sub(source, cursor, first - 1), "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") .. "(.-)"
			table.insert(names, name)
			cursor = last
		end
		pattern ..= string.gsub(string.sub(source, cursor), "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") .. "$"
		table.insert(templates, {key = row.Key, pattern = pattern, names = names, length = #source})
	end
	end
end
table.sort(templates, function(a, b) return a.length > b.length end)
table.sort(atoms, function(a, b) return #a.Source > #b.Source end)

local function interpolate(value: string, params: any): string
	return (string.gsub(value, "{([%w_]+)}", function(name)
		local replacement = if type(params) == "table" then params[name] else nil
		return if replacement ~= nil then tostring(replacement) else "{" .. name .. "}"
	end))
end

function Localization.Locale(): string
	local player = Players.LocalPlayer
	local debugLocale = if RunService:IsStudio() and player then player:GetAttribute("DebugLocale") else nil
	return if type(debugLocale) == "string" then string.lower(debugLocale) else locale
end

function Localization.T(key: string, params: any?): string
	local row = rows[key]
	if row == nil then return key end
	-- Untyped LocalizationTable numeric placeholders default to two decimal places.
	-- UI numbers are already formatted by the caller; raw integer counters must stay integer strings.
	local arguments = {}
	if type(params) == "table" then
		for name, value in params do
			arguments[name] = if type(value) == "number" then tostring(value) else value
		end
	end
	local player = Players.LocalPlayer
	local debugLocale = if RunService:IsStudio() and player then player:GetAttribute("DebugLocale") else nil
	local activeTranslator = translator
	if type(debugLocale) == "string" then
		local translationTable = LocalizationService:FindFirstChild(Config.TableName)
		if translationTable and translationTable:IsA("LocalizationTable") then
			if localeTranslators[debugLocale] == nil then
				local ok, result = pcall(function() return translationTable:GetTranslator(debugLocale) end)
				if ok then localeTranslators[debugLocale] = result end
			end
			activeTranslator = localeTranslators[debugLocale]
		end
	end
	if activeTranslator then
		local ok, result = pcall(function() return (activeTranslator :: Translator):FormatByKey(key, arguments) end)
		if ok and type(result) == "string" then return result end
	end
	local language = string.sub(Localization.Locale(), 1, 2)
	local value = row.Values[language] or row.Values.en or row.Source
	return interpolate(value, arguments)
end

local function translate(value: string, depth: number): string
	local key = sourceKeys[value]
	if key then return Localization.T(key) end
	if rows[value] then return Localization.T(value) end
	if depth >= 5 then return value end
	for _, template in templates do
		local captures = table.pack(string.match(value, template.pattern))
		if captures[1] ~= nil then
			local params = {}
			for index, name in template.names do
				local capture = captures[index]
				params[name] = if type(capture) == "string" and name ~= "player" then translate(capture, depth + 1) else capture
			end
			return Localization.T(template.key, params)
		end
	end
	-- Names rendered by the server combine canonical tier, mutation, rarity and cat catalog values.
	local remainder = value
	local parts = {}
	while remainder ~= "" do
		local found = false
		for _, atom in atoms do
			if remainder == atom.Source or string.sub(remainder, 1, #atom.Source + 1) == atom.Source .. " " then
				table.insert(parts, Localization.T(atom.Key))
				remainder = string.sub(remainder, #atom.Source + 2)
				found = true
				break
			end
		end
		if not found then break end
	end
	if remainder == "" and #parts > 0 then return table.concat(parts, " ") end
	return value
end

function Localization.Translate(value: string): string
	return translate(value, 0)
end

function Localization.Bind(object: Instance, key: string, params: any?, property: string?): ()
	local field = property or "Text"
	bindings[object] = {key = key, params = params, property = field}
	object:SetAttribute("LocalizationKey", key)
	local target = object :: any
	target[field] = Localization.T(key, params)
end

function Localization.Refresh(): ()
	for object, binding in bindings do
		if object.Parent then
			local target = object :: any
			target[binding.property] = Localization.T(binding.key, binding.params)
		end
	end
	Localization.Changed:Fire()
end

function Localization.LoadTranslator(): ()
	local player = Players.LocalPlayer
	if player == nil then return end
	local translationTable = LocalizationService:FindFirstChild(Config.TableName)
	local ok, result = pcall(function()
		if translationTable and translationTable:IsA("LocalizationTable") then
			return translationTable:GetTranslator(LocalizationService.RobloxLocaleId)
		end
		return LocalizationService:GetTranslatorForPlayerAsync(player)
	end)
	if ok then
		translator = result
		result:GetPropertyChangedSignal("LocaleId"):Connect(function()
			locale = string.lower(result.LocaleId)
			Localization.Refresh()
		end)
	end
	locale = string.lower(LocalizationService.RobloxLocaleId)
	Localization.Refresh()
end

return Localization

