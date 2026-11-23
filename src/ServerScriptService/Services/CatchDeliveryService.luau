--!strict
-- Laser Pointer delivery for newly caught cats. PillowService owns the reserved-pillow transaction;
-- this controller owns movement and rollback. Owned/stolen cats can never enter this path.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local CatSchema = require(Config.CatSchema)
local Cats = require(Config.Cats)
local Items = require(Config.Items)
local AntiCheatService = require(script.Parent.AntiCheatService)
local CarryService = require(script.Parent.CarryService)
local CatReturnNavigation = require(script.Parent.CatReturnNavigation)
local CatSpawnService = require(script.Parent.CatSpawnService)
local DataService = require(script.Parent.DataService)
local NotificationService = require(script.Parent.NotificationService)
local PillowService = require(script.Parent.PillowService)
local PlotService = require(script.Parent.PlotService)

local ATTR = CatSchema.Attributes
local LASER = Items.Effects.LaserPointer

export type OutcomeHandler = (success: boolean) -> ()

type Delivery = {
	ticket: PillowService.FreshDeliveryTicket,
	character: Model,
	uniqueId: string,
	catId: string,
	startCFrame: CFrame,
	cancelNavigation: (() -> ())?,
	connections: { RBXScriptConnection },
	onFinished: OutcomeHandler?,
}

local CatchDeliveryService = {
	Priority = 69,
}

local deliveries: { [Player]: Delivery } = {}

local function aliveCharacter(player: Player): (Model?, Humanoid?)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if player.Parent ~= Players or character == nil or humanoid == nil or humanoid.Health <= 0
		or root == nil or not root:IsA("BasePart") then
		return nil, nil
	end
	return character, humanoid
end

local function hasSavedRecord(uniqueId: string): boolean
	for _, player in Players:GetPlayers() do
		local data = DataService.GetData(player)
		if data and data.cats[uniqueId] then
			return true
		end
	end
	return false
end

local function rollback(player: Player, delivery: Delivery, lostModel: boolean): ()
	local ticket = delivery.ticket
	PillowService.CancelFreshDelivery(ticket)
	-- No record should ever have appeared in this path before arrival. If an external system
	-- legitimately seated it already, leave that single saved cat in place rather than cloning it.
	if hasSavedRecord(delivery.uniqueId) or PillowService.IsPlaced(ticket.model) then
		return
	end
	AntiCheatService.Grace(player, LASER.GraceSeconds)
	local model: Model? = ticket.model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not lostModel and model.Parent ~= nil and CatSpawnService.IsWild(model) then
		return
	end
	if lostModel or model.Parent == nil or humanoid == nil or humanoid.Health <= 0 then
		if not lostModel and model.Parent then
			model:Destroy()
		end
		model = CatSpawnService.CreateCatModel(delivery.catId, delivery.uniqueId)
		if model == nil then
			warn(`[CatchDeliveryService] Could not rebuild fresh cat {delivery.uniqueId}`)
			return
		end
		model:PivotTo(delivery.startCFrame)
		model.Parent = CatReturnNavigation.GetReturningFolder()
	end
	model:SetAttribute(ATTR.UniqueId, delivery.uniqueId)
	model:SetAttribute(ATTR.CatId, delivery.catId)
	model:SetAttribute(ATTR.OwnerUserId, CatSchema.WildOwnerUserId)
	model:SetAttribute(ATTR.OriginalOwnerUserId, ticket.originalOwnerUserId)
	model:SetAttribute(ATTR.CarrierUserId, nil)
	if not CatSpawnService.ReleaseToWild(model, delivery.character) then
		-- An invalid floor at the interrupted position must not erase a caught cat: retry from
		-- the validated dispatch position using a fresh rig, as for a model lost during transit.
		local replacement = CatSpawnService.CreateCatModel(delivery.catId, delivery.uniqueId)
		if replacement then
			replacement:PivotTo(delivery.startCFrame)
			replacement:SetAttribute(ATTR.OriginalOwnerUserId, ticket.originalOwnerUserId)
			replacement.Parent = CatReturnNavigation.GetReturningFolder()
			CatSpawnService.ReleaseToWild(replacement, delivery.character)
		end
	end
end

local function finish(player: Player, delivery: Delivery, arrived: boolean, lostModel: boolean): ()
	if deliveries[player] ~= delivery then
		return
	end
	deliveries[player] = nil
	for _, connection in delivery.connections do
		connection:Disconnect()
	end
	table.clear(delivery.connections)
	if delivery.cancelNavigation then
		delivery.cancelNavigation()
		delivery.cancelNavigation = nil
	end
	local success = false
	local character = aliveCharacter(player)
	if arrived and character == delivery.character then
		AntiCheatService.Grace(player, LASER.GraceSeconds)
		success = PillowService.CompleteFreshDelivery(delivery.ticket)
	end
	if not success then
		rollback(player, delivery, lostModel)
	end
	if player.Parent == Players then
		NotificationService.Notify(player,
			if success then "Your cat followed the laser home!" else "Laser delivery stopped; the cat is back in the city.",
			if success then "Success" else "Info")
	end
	if delivery.onFinished then
		local ok, err = pcall(delivery.onFinished, success)
		if not ok then
			warn(`[CatchDeliveryService] Outcome handler failed: {tostring(err)}`)
		end
	end
end

function CatchDeliveryService.IsDelivering(player: Player): boolean
	return deliveries[player] ~= nil
end

-- Consumed on a successfully validated dispatch by ItemService. A rejected dispatch changes nothing.
-- Navigation starts after this function returns so the caller can synchronously deduct inventory.
function CatchDeliveryService.Begin(player: Player, onFinished: OutcomeHandler?): (boolean, string?)
	if deliveries[player] then
		return false, "A cat is already following your laser."
	end
	local character, humanoid = aliveCharacter(player)
	if character == nil or humanoid == nil or DataService.GetData(player) == nil then
		return false, "You cannot use the laser right now."
	end
	local carried = CarryService.GetCarried(player)
	local model = carried[#carried]
	if model == nil or model:GetAttribute(ATTR.OwnerUserId) ~= CatSchema.WildOwnerUserId then
		return false, "Carry a newly caught cat to use the laser."
	end
	local catId = model:GetAttribute(ATTR.CatId)
	if type(catId) ~= "string" or Cats.Get(catId) == nil then
		return false, "That cat cannot follow the laser."
	end
	local catHumanoid = model:FindFirstChildOfClass("Humanoid")
	if catHumanoid == nil or catHumanoid.Health <= 0 then
		return false, "That cat cannot follow the laser."
	end
	local startCFrame = model:GetPivot()
	local ticket = PillowService.BeginFreshDelivery(player, model)
	if ticket == nil then
		return false, "You need a free pillow at home."
	end
	local delivery: Delivery = {
		ticket = ticket,
		character = character,
		uniqueId = tostring(model:GetAttribute(ATTR.UniqueId)),
		catId = tostring(model:GetAttribute(ATTR.CatId)),
		startCFrame = startCFrame,
		cancelNavigation = nil,
		connections = {},
		onFinished = onFinished,
	}
	deliveries[player] = delivery
	table.insert(delivery.connections, model.Destroying:Connect(function(): ()
		finish(player, delivery, false, true)
	end))
	table.insert(delivery.connections, humanoid.Died:Connect(function(): ()
		finish(player, delivery, false, false)
	end))
	AntiCheatService.Grace(player, LASER.GraceSeconds)
	task.defer(function(): ()
		if deliveries[player] ~= delivery then
			return
		end
		local function active(): boolean
			local currentCharacter = aliveCharacter(player)
			return deliveries[player] == delivery and currentCharacter == delivery.character
				and PillowService.IsFreshDelivering(model)
				and DataService.GetData(player) ~= nil and PlotService.GetPlot(player) == ticket.plot
				and model:GetAttribute(ATTR.UniqueId) == delivery.uniqueId
				and model:GetAttribute(ATTR.OwnerUserId) == CatSchema.WildOwnerUserId
				and model:GetAttribute(ATTR.OriginalOwnerUserId) == ticket.originalOwnerUserId
		end
		local navigationCancel: (() -> ())? = nil
		local ok, err = xpcall(function(): ()
			navigationCancel = CatReturnNavigation.Run(model, nil, ticket.plot, ticket.pillow.Position,
				active,
				function(): () finish(player, delivery, true, false) end,
				function(): () finish(player, delivery, false, false) end)
		end, debug.traceback)
		if not ok then
			warn(`[CatchDeliveryService] Navigation failed: {tostring(err)}`)
			finish(player, delivery, false, false)
		elseif deliveries[player] == delivery then
			delivery.cancelNavigation = navigationCancel
		elseif navigationCancel then
			-- A synchronous completion/abort already cleaned the ticket while Run was returning.
			navigationCancel()
		end
	end)
	return true, nil
end

function CatchDeliveryService.Cancel(player: Player): boolean
	local delivery = deliveries[player]
	if delivery == nil then
		return false
	end
	finish(player, delivery, false, false)
	return true
end

function CatchDeliveryService:Init(): ()
end

function CatchDeliveryService:Start(): ()
	Players.PlayerRemoving:Connect(function(player: Player): ()
		CatchDeliveryService.Cancel(player)
	end)
	PlotService.PlotReleased:Connect(function(player: Player, _plot: Model): ()
		CatchDeliveryService.Cancel(player)
	end)
	local function watchCharacter(player: Player): ()
		player.CharacterRemoving:Connect(function(_character: Model): ()
			CatchDeliveryService.Cancel(player)
		end)
	end
	Players.PlayerAdded:Connect(watchCharacter)
	for _, player in Players:GetPlayers() do
		watchCharacter(player)
	end
end

return CatchDeliveryService

