--!strict
-- Name tags above characters: display name (gold for VIP), VIP badge and rebirth count.
-- Server-built so every client sees the same thing. Refresh(player) after pass/rebirth changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NameTags = require(ReplicatedStorage.Shared.Config.NameTags)
local Maid = require(ReplicatedStorage.Shared.Util.Maid)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)

local NameTagService = {
	Priority = 93,
}

local maids: { [Player]: Maid.Maid } = {}

local function label(parent: Instance, name: string, position: UDim2, size: UDim2): TextLabel
	local result = Instance.new("TextLabel")
	result.Name = name
	result.BackgroundTransparency = 1
	result.Position = position
	result.Size = size
	result.Font = Enum.Font.FredokaOne
	result.TextScaled = true
	result.TextStrokeTransparency = 0.3
	result.Parent = parent
	return result
end

function NameTagService.Refresh(player: Player)
	local character = player.Character
	local head = if character then character:FindFirstChild("Head") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if head == nil or not head:IsA("BasePart") or humanoid == nil then
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local gui = head:FindFirstChild(NameTags.GuiName)
	if gui == nil or not gui:IsA("BillboardGui") then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = NameTags.GuiName
		billboard.Size = NameTags.Size
		billboard.StudsOffset = NameTags.Offset
		billboard.MaxDistance = NameTags.MaxDistance
		billboard.LightInfluence = 0
		label(billboard, "Name", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.6))
		label(billboard, "Badges", UDim2.fromScale(0, 0.6), UDim2.fromScale(1, 0.4))
		billboard.Parent = head
		gui = billboard
	end
	local vip = MonetizationService.OwnsPass(player, "VIP")
	local data = DataService.GetData(player)
	local rebirths = if data and type(data.rebirths) == "number" then math.floor(data.rebirths) else 0
	local badges = {}
	if vip then
		table.insert(badges, NameTags.VipBadge)
	end
	if rebirths > 0 then
		table.insert(badges, string.format(NameTags.RebirthBadgeFormat, rebirths))
	end
	local nameLabel = (gui :: BillboardGui):FindFirstChild("Name") :: TextLabel
	local badgeLabel = (gui :: BillboardGui):FindFirstChild("Badges") :: TextLabel
	nameLabel.Text = player.DisplayName
	nameLabel.TextColor3 = if vip then NameTags.VipColor else NameTags.NameColor
	badgeLabel.Text = table.concat(badges, "  ")
	badgeLabel.TextColor3 = if vip then NameTags.VipColor else NameTags.BadgeColor
	badgeLabel.Visible = #badges > 0
end

local function onCharacterAdded(player: Player, character: Model)
	if character:WaitForChild("Head", NameTags.CharacterLoadTimeout) and player.Character == character then
		NameTagService.Refresh(player)
	end
end

local function onPlayerAdded(player: Player)
	if maids[player] then
		return
	end
	local maid = Maid.new()
	maids[player] = maid
	maid:Add(player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end))
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

function NameTagService:Start(): ()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		local maid = maids[player]
		if maid then
			maid:Clean()
			maids[player] = nil
		end
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	MonetizationService.PassChanged:Connect(function(player: Player, key: string)
		if key == "VIP" then
			NameTagService.Refresh(player)
		end
	end)
	DataService.DataLoaded:Connect(function(player: Player)
		NameTagService.Refresh(player)
	end)
end

return NameTagService

