--!strict
-- Keeps the city stocked with wild cats and runs their AI.
-- One loop drives every wild cat (no per-cat scripts). Wild cats are server-owned (network owner = server),
-- so clients can't teleport or fling them.
--
-- Other services work with wild cats through:
--   LockWildCat / UnlockWildCat - freeze a cat for a while (catch mini-game) without leaving the wild
--   ClaimWildCat                - take a cat out of the wild for good; the caller now owns the Model
--   ReleaseToWild               - hand a Model back (e.g. dropped when its carrier dies)

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Config = ReplicatedStorage.Shared.Config
local Cats = require(Config.Cats)
local CatSchema = require(Config.CatSchema)
local CatSpawning = require(Config.CatSpawning)
local Districts = require(Config.Districts)
local Events = require(Config.Events)
local Mutations = require(Config.Mutations)
local Rarities = require(Config.Rarities)
local Shop = require(Config.Shop)
local Tags = require(Config.Tags)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local NotificationService = require(script.Parent.NotificationService)
local LuckService = require(script.Parent.LuckService)

local ATTR = CatSchema.Attributes
local SECRET = CatSpawning.Secret
local ITEM_EFFECTS = Shop.WildEffects
local TEMPLATE_NAME = "CatTemplate"
local MODELS_FOLDER_NAME = "CatModels" -- per-cat art (Config/Cats modelName); same root + Humanoid as the template
local CATS_FOLDER_NAME = "Cats"
local WILD_FOLDER_NAME = "Wild"
local RARITY_TINT_ATTRIBUTE = "RarityTint"
local MIN_DIRECTION_LENGTH = 1e-3

-- Humanoid states a walking cat never needs; disabling them saves physics work and avoids odd falls.
local DISABLED_STATES: { Enum.HumanoidStateType } = {
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.Swimming,
	Enum.HumanoidStateType.Seated,
	Enum.HumanoidStateType.PlatformStanding,
	Enum.HumanoidStateType.Flying,
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.Dead,
}

export type RemoveReason = "Despawned" | "Stuck" | "Claimed" | "Destroyed"

type Mode = "Idle" | "Wander" | "Flee" | "Rest" | "Attract"

type Area = {
	name: string,
	rarities: { Rarities.Rarity },
	rarityWeightTotal: number,
	zones: { BasePart },
	zoneWeightTotal: number,
	quota: number,
	count: number,
}

type WildCat = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	rarity: Rarities.Rarity,
	area: Area,
	bonus: boolean, -- Secret cats: outside the normal population count
	locked: boolean,
	frozenUntil: number,
	calmUntil: number,
	baitUntil: number,
	baitTarget: Vector3?,
	expiresAt: number,
	mode: Mode,
	modeUntil: number,
	target: Vector3?,
	nextMoveAt: number,
	lastCheckPos: Vector3,
	nextStuckCheckAt: number,
	stuckStrikes: number,
	destroyingConnection: RBXScriptConnection?,
}

local CatSpawnService = {
	Priority = 30,

	-- (model) whenever a cat becomes wild: freshly spawned or released back.
	WildCatAdded = Signal.new() :: Signal.Signal<Model>,
	-- (model, reason) after a cat stops being tracked as wild.
	WildCatRemoved = Signal.new() :: Signal.Signal<Model, RemoveReason>,
}

local random = Random.new()
local rayParams = RaycastParams.new()
local areas: { Area } = {}
local areaByName: { [string]: Area } = {}
local secretArea: Area? = nil
local wildCats: { [Model]: WildCat } = {}
local wildCount = 0 -- normal wild cats (excludes Secret bonus cats)
local secretCount = 0
local summonedCount = 0 -- other bonus cats (summoned by products/events), outside the population count
local template: Model
local catModels: Folder? = nil
local rootHeight = 0 -- HumanoidRootPart centre height above the ground
local catsFolder: Folder
local wildFolder: Folder
local avgTickMs = 0
local season: string? = nil -- enables seasonal mutations (EventService)
local hiding = false -- Rain event: wild cats hide (can't be caught) and no new cats spawn

-- Helpers --------------------------------------------------------------------

local function pickWeighted<T>(items: { T }, weightOf: (T) -> number, total: number): T
	local roll = random:NextNumber(0, total)
	for _, item in items do
		roll -= weightOf(item)
		if roll <= 0 then
			return item
		end
	end
	return items[#items]
end

local function zoneArea(zone: BasePart): number
	return zone.Size.X * zone.Size.Z
end

local function rarityWeight(rarity: Rarities.Rarity): number
	return rarity.spawnWeight
end

-- Rarity roll with luck (Config/Luck): every rarity above the most common one gets weight x luck.
local function rollRarity(rarities: { Rarities.Rarity }, luck: number): Rarities.Rarity
	local function weight(rarity: Rarities.Rarity): number
		return rarity.spawnWeight * (if rarity.order > 1 then luck else 1)
	end
	local total = 0
	for _, rarity in rarities do
		total += weight(rarity)
	end
	return pickWeighted(rarities, weight, total)
end

local function isPointInPart(point: Vector3, part: BasePart): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

local function isInsideArea(area: Area, point: Vector3): boolean
	for _, zone in area.zones do
		if isPointInPart(point, zone) then
			return true
		end
	end
	return false
end

local function probeGround(x: number, z: number, fromY: number, depth: number, params: RaycastParams?): Vector3?
	local result = workspace:Raycast(Vector3.new(x, fromY, z), Vector3.new(0, -depth, 0), params or rayParams)
	return if result then result.Position else nil
end

-- A random walkable point on the floor of a zone (rejects tops of props, gaps between roofs, etc.).
local function randomPointInZone(zone: BasePart): Vector3?
	local half = zone.Size / 2
	local top = zone.CFrame * Vector3.new(random:NextNumber(-half.X, half.X), half.Y, random:NextNumber(-half.Z, half.Z))
	local hit = probeGround(top.X, top.Z, top.Y, zone.Size.Y + CatSpawning.GroundTolerance)
	local bottom = zone.Position.Y - half.Y
	if hit and math.abs(hit.Y - bottom) <= CatSpawning.GroundTolerance then
		return hit
	end
	return nil
end

-- True when a cat can walk in a straight line from `from` to `to` (both ground points):
-- nothing blocks the way at body height and the floor never drops or rises more than MaxStepHeight.
local function isLineWalkable(from: Vector3, to: Vector3): boolean
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local distance = flat.Magnitude
	if distance < MIN_DIRECTION_LENGTH then
		return true
	end

	local lift = Vector3.new(0, CatSpawning.ObstacleProbeHeight, 0)
	if workspace:Raycast(from + lift, (to + lift) - (from + lift), rayParams) then
		return false
	end

	local steps = math.max(1, math.ceil(distance / CatSpawning.LineSampleStep))
	local lastY = from.Y
	for i = 1, steps do
		local sample = from + flat * (i / steps)
		local hit = probeGround(sample.X, sample.Z, lastY + CatSpawning.GroundProbeUp, CatSpawning.GroundProbeUp + CatSpawning.GroundProbeDown)
		if hit == nil or math.abs(hit.Y - lastY) > CatSpawning.MaxStepHeight then
			return false
		end
		lastY = hit.Y
	end
	return true
end

local function groundBelow(cat: WildCat): Vector3
	return cat.root.Position - Vector3.new(0, rootHeight, 0)
end

local function isNearAnyPlayer(point: Vector3, radius: number, playerPositions: { Vector3 }): boolean
	for _, position in playerPositions do
		if (position - point).Magnitude < radius then
			return true
		end
	end
	return false
end

local function getPlayerPositions(): { Vector3 }
	local positions = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character == nil then
			continue
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			table.insert(positions, root.Position)
		end
	end
	return positions
end

local function idleDuration(): number
	return random:NextNumber(CatSpawning.IdleTimeMin, CatSpawning.IdleTimeMax)
end

local function setMode(cat: WildCat, mode: Mode, untilTime: number)
	cat.mode = mode
	cat.modeUntil = untilTime
	cat.target = nil
	cat.nextMoveAt = 0
	cat.stuckStrikes = 0
	cat.humanoid.WalkSpeed = if mode == "Flee" then cat.rarity.fleeSpeed else CatSpawning.WanderSpeed
	if mode == "Idle" or mode == "Rest" then
		cat.humanoid:MoveTo(cat.root.Position)
	end
end

-- Wild tracking ----------------------------------------------------------------

local function updateCountAttribute()
	wildFolder:SetAttribute("WildCount", wildCount)
	wildFolder:SetAttribute("SecretCount", secretCount)
end

local untrack: (model: Model, reason: RemoveReason) -> WildCat?

local function register(model: Model, rarity: Rarities.Rarity, area: Area, bonus: boolean): WildCat
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	root.Anchored = false
	root:SetNetworkOwner(nil)
	for _, state in DISABLED_STATES do
		humanoid:SetStateEnabled(state, false)
	end

	local now = os.clock()
	local lifetimeMin = if bonus then SECRET.LifetimeMin else CatSpawning.WildLifetimeMin
	local lifetimeMax = if bonus then SECRET.LifetimeMax else CatSpawning.WildLifetimeMax
	local cat: WildCat = {
		model = model,
		root = root,
		humanoid = humanoid,
		rarity = rarity,
		area = area,
		bonus = bonus,
		locked = false,
		frozenUntil = 0,
		calmUntil = 0,
		baitUntil = 0,
		baitTarget = nil,
		expiresAt = now + random:NextNumber(lifetimeMin, lifetimeMax),
		mode = "Idle",
		modeUntil = now + idleDuration(),
		target = nil,
		nextMoveAt = 0,
		lastCheckPos = root.Position,
		nextStuckCheckAt = now + CatSpawning.StuckCheckInterval,
		stuckStrikes = 0,
		destroyingConnection = nil,
	}
	humanoid.WalkSpeed = CatSpawning.WanderSpeed
	model:SetAttribute(Shop.CatchLockedAttribute, nil)
	model:SetAttribute(Events.Rain.HidingAttribute, if hiding then true else nil)
	for _, attribute in { ITEM_EFFECTS.FrozenUntilAttribute, ITEM_EFFECTS.CalmUntilAttribute, ITEM_EFFECTS.BaitUntilAttribute } do
		model:SetAttribute(attribute, nil)
	end

	wildCats[model] = cat
	if bonus and rarity.id == SECRET.RarityId then
		secretCount += 1
	elseif bonus then
		summonedCount += 1
	else
		wildCount += 1
		area.count += 1
	end
	updateCountAttribute()

	-- If something else destroys the model (fell out of the world, admin cleanup), stop tracking it.
	cat.destroyingConnection = model.Destroying:Connect(function()
		untrack(model, "Destroyed")
	end)

	CatSpawnService.WildCatAdded:Fire(model)
	return cat
end

function untrack(model: Model, reason: RemoveReason): WildCat?
	local cat = wildCats[model]
	if cat == nil then
		return nil
	end
	wildCats[model] = nil
	model:SetAttribute(Shop.CatchLockedAttribute, nil)
	model:SetAttribute(Events.Rain.HidingAttribute, nil)
	-- Temporary city effects cannot follow a successfully caught cat into carrying or ownership.
	for _, attribute in { ITEM_EFFECTS.FrozenUntilAttribute, ITEM_EFFECTS.CalmUntilAttribute, ITEM_EFFECTS.BaitUntilAttribute } do
		model:SetAttribute(attribute, nil)
	end
	if cat.frozenUntil > 0 and not cat.locked then
		cat.root.Anchored = false
		if cat.root:IsDescendantOf(workspace) then
			cat.root:SetNetworkOwner(nil)
		end
	end
	if cat.bonus and cat.rarity.id == SECRET.RarityId then
		secretCount -= 1
	elseif cat.bonus then
		summonedCount -= 1
	else
		wildCount -= 1
		cat.area.count -= 1
	end
	if cat.destroyingConnection then
		cat.destroyingConnection:Disconnect()
	end
	updateCountAttribute()
	CatSpawnService.WildCatRemoved:Fire(model, reason)
	return cat
end

local function fadeAndDestroy(model: Model)
	local tweenInfo = TweenInfo.new(CatSpawning.DespawnFadeTime)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			TweenService:Create(descendant, tweenInfo, { Transparency = 1 }):Play()
		elseif descendant:IsA("BillboardGui") then
			descendant.Enabled = false
		end
	end
	task.delay(CatSpawning.DespawnFadeTime, function()
		model:Destroy()
	end)
end

-- Spawning -----------------------------------------------------------------------

local function chooseArea(): Area?
	local best: Area? = nil
	local bestFill = math.huge
	for _, area in areas do
		local fill = area.count / area.quota
		if fill < bestFill then
			best = area
			bestFill = fill
		end
	end
	return best
end

-- Name plate: "[Tier] [Mutation] Name", coloured by the mutation.
local function refreshNameplate(model: Model)
	local catDef = Cats.Get(tostring(model:GetAttribute(ATTR.CatId)))
	local nameplate = model:FindFirstChild("Nameplate", true)
	local nameLabel = if nameplate then nameplate:FindFirstChild("NameLabel") else nil
	if catDef == nil or nameLabel == nil or not nameLabel:IsA("TextLabel") then
		return
	end
	local parts = {}
	local tier = Mutations.GetTier(model:GetAttribute(ATTR.Tier))
	if tier.displayName ~= "" then
		table.insert(parts, tier.displayName)
	end
	local mutation = Mutations.Get(tostring(model:GetAttribute(ATTR.Mutation)))
	if mutation then
		table.insert(parts, mutation.displayName)
	end
	table.insert(parts, catDef.name)
	nameLabel.Text = table.concat(parts, " ")
	nameLabel.TextColor3 = if mutation then mutation.color else Color3.new(1, 1, 1)
end

local function setupModel(model: Model, catDef: Cats.Cat, rarity: Rarities.Rarity, areaName: string)
	model.Name = catDef.id
	model:SetAttribute(ATTR.CatId, catDef.id)
	model:SetAttribute(ATTR.Rarity, rarity.id)
	model:SetAttribute(ATTR.State, CatSchema.States.Wild)
	model:SetAttribute(ATTR.OwnerUserId, CatSchema.WildOwnerUserId)
	model:SetAttribute(ATTR.UniqueId, HttpService:GenerateGUID(false))
	model:SetAttribute(ATTR.SpawnArea, areaName)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = CatSpawning.CollisionGroup
			if descendant:GetAttribute(RARITY_TINT_ATTRIBUTE) then
				descendant.Color = rarity.color
			end
		end
	end

	local nameplate = model:FindFirstChild("Nameplate", true)
	if nameplate then
		local nameLabel = nameplate:FindFirstChild("NameLabel")
		local rarityLabel = nameplate:FindFirstChild("RarityLabel")
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = catDef.name
		end
		if rarityLabel and rarityLabel:IsA("TextLabel") then
			rarityLabel.Text = rarity.displayName
			rarityLabel.TextColor3 = rarity.color
		end
	end

	CollectionService:AddTag(model, Tags.Cat)
	if model:GetAttribute("NameplateWatch") == nil then
		model:SetAttribute("NameplateWatch", true)
		model:GetAttributeChangedSignal(ATTR.Mutation):Connect(function()
			refreshNameplate(model)
		end)
		model:GetAttributeChangedSignal(ATTR.Tier):Connect(function()
			refreshNameplate(model)
		end)
	end
	refreshNameplate(model)
end

-- The cat's own art model when it has one, else the generic template (e.g. seasonal cats).
local function cloneCatModel(catDef: Cats.Cat): Model
	local source = if catDef.modelName and catModels then catModels:FindFirstChild(catDef.modelName) else nil
	if source and source:IsA("Model") then
		return source:Clone()
	end
	return template:Clone()
end

-- Builds an owned cat Model from the template (not wild, not parented). Used to restore saved cats.
function CatSpawnService.CreateCatModel(catId: string, uniqueId: string): Model?
	local catDef = Cats.Get(catId)
	local rarity = if catDef then Rarities.Get(catDef.rarity) else nil
	if catDef == nil or rarity == nil then
		return nil
	end
	local model = cloneCatModel(catDef)
	setupModel(model, catDef, rarity, "")
	model:SetAttribute(ATTR.UniqueId, uniqueId)
	model:SetAttribute(ATTR.SpawnArea, nil)
	return model
end

-- forcedRarity spawns a bonus cat of that rarity (Secret) instead of rolling the area's pool.
-- `quiet` skips the rare-spawn announcement (callers that announce themselves).
local function spawnCat(area: Area, playerPositions: { Vector3 }, forcedRarity: Rarities.Rarity?, quiet: boolean?): Model?
	for _ = 1, CatSpawning.SpawnPointAttempts do
		local zone = pickWeighted(area.zones, zoneArea, area.zoneWeightTotal)
		local ground = randomPointInZone(zone)
		if ground == nil or isNearAnyPlayer(ground, CatSpawning.SpawnMinPlayerDistance, playerPositions) then
			continue
		end

		local luck = LuckService.GetLuckNear(ground)
		local rarity = forcedRarity or rollRarity(area.rarities, luck)
		local pool = Cats.ByRarity[rarity.id]
		local seasonalPool = Cats.GetSeasonal(season, rarity.id)
		if #seasonalPool > 0 and random:NextNumber() < Events.SeasonalCatChance then
			pool = seasonalPool
		end
		local catDef = pool[random:NextInteger(1, #pool)]

		local model = cloneCatModel(catDef)
		local mutationId = Mutations.Roll(random, luck, season)
		model:SetAttribute(ATTR.Mutation, mutationId)
		setupModel(model, catDef, rarity, area.name)
		local mutation = Mutations.Get(mutationId)
		if not quiet and rarity.id ~= SECRET.RarityId
			and (rarity.order >= Mutations.AnnounceRarityOrder or (mutation ~= nil and mutation.announce)) then
			local prefix = if mutation then mutation.displayName .. " " else ""
			NotificationService.Announce(`A {prefix}{rarity.displayName} {catDef.name} appeared in {area.name}!`, catDef.id, mutationId)
		end
		model:PivotTo(CFrame.new(ground + Vector3.new(0, rootHeight, 0)) * CFrame.Angles(0, random:NextNumber(0, 2 * math.pi), 0))
		model.Parent = wildFolder
		register(model, rarity, area, forcedRarity ~= nil)
		return model
	end
	return nil
end

local function topUp(maxToSpawn: number)
	if hiding then
		return
	end
	local playerPositions = getPlayerPositions()
	local spawned = 0
	-- Bounded tries so an area with no valid ground can't stall the pass.
	local tries = 0
	while wildCount < CatSpawning.TargetWildCats and spawned < maxToSpawn and tries < maxToSpawn + #areas do
		tries += 1
		local area = chooseArea()
		if area == nil then
			return
		end
		if spawnCat(area, playerPositions) then
			spawned += 1
		end
	end
end

local function maybeSpawnSecret()
	local area = secretArea
	if area == nil or secretCount >= SECRET.MaxWild then
		return
	end

	local forced = RunService:IsStudio() and wildFolder:GetAttribute(SECRET.DebugForceAttribute) == true
	if forced then
		wildFolder:SetAttribute(SECRET.DebugForceAttribute, nil)
	elseif random:NextNumber() >= SECRET.SpawnChancePerTick then
		return
	end

	local rarity = Rarities.Get(SECRET.RarityId) :: Rarities.Rarity
	if spawnCat(area, getPlayerPositions(), rarity, true) then
		NotificationService.Announce(SECRET.Announcement)
	end
end

-- AI -----------------------------------------------------------------------------

local function chooseWanderTarget(cat: WildCat): Vector3?
	local ground = groundBelow(cat)
	if not isInsideArea(cat.area, cat.root.Position) then
		-- Strayed (e.g. after fleeing or being dropped): head back to any point in the home area.
		for _ = 1, CatSpawning.WanderAttempts do
			local zone = pickWeighted(cat.area.zones, zoneArea, cat.area.zoneWeightTotal)
			local point = randomPointInZone(zone)
			if point then
				return point
			end
		end
		return nil
	end

	for _ = 1, CatSpawning.WanderAttempts do
		local angle = random:NextNumber(0, 2 * math.pi)
		local distance = random:NextNumber(CatSpawning.WanderMinDistance, CatSpawning.WanderMaxDistance)
		local x = ground.X + math.cos(angle) * distance
		local z = ground.Z + math.sin(angle) * distance
		local hit = probeGround(x, z, ground.Y + CatSpawning.GroundProbeUp, CatSpawning.GroundProbeUp + CatSpawning.GroundProbeDown)
		if hit and isInsideArea(cat.area, hit + Vector3.new(0, rootHeight, 0)) and isLineWalkable(ground, hit) then
			return hit
		end
	end
	return nil
end

local function chooseFleeTarget(cat: WildCat, away: Vector3): Vector3?
	local ground = groundBelow(cat)
	local baseAngle = math.atan2(away.Z, away.X)
	for _, offset in CatSpawning.FleeAngles do
		local angle = baseAngle + math.rad(offset)
		local x = ground.X + math.cos(angle) * CatSpawning.FleeStepDistance
		local z = ground.Z + math.sin(angle) * CatSpawning.FleeStepDistance
		local hit = probeGround(x, z, ground.Y + CatSpawning.GroundProbeUp, CatSpawning.GroundProbeUp + CatSpawning.GroundProbeDown)
		if hit and isLineWalkable(ground, hit) then
			return hit
		end
	end
	return nil -- cornered: the cat stays put
end

local function resetItemStuckTracking(cat: WildCat, now: number)
	cat.lastCheckPos = cat.root.Position
	cat.nextStuckCheckAt = now + CatSpawning.StuckCheckInterval
	cat.stuckStrikes = 0
end

-- Effects use their own deadlines, never the catch-session lock. Expiring while locked must not
-- unanchor the cat or end the catch session; UnlockWildCat restores its remaining item effect.
local function expireItemEffects(cat: WildCat, now: number)
	if cat.frozenUntil > 0 and now >= cat.frozenUntil then
		cat.frozenUntil = 0
		cat.model:SetAttribute(ITEM_EFFECTS.FrozenUntilAttribute, nil)
		if not cat.locked then
			cat.root.Anchored = false
			cat.root:SetNetworkOwner(nil)
			setMode(cat, "Idle", now + idleDuration())
			resetItemStuckTracking(cat, now)
		end
	end
	if cat.calmUntil > 0 and now >= cat.calmUntil then
		cat.calmUntil = 0
		cat.model:SetAttribute(ITEM_EFFECTS.CalmUntilAttribute, nil)
	end
	if cat.baitUntil > 0 and now >= cat.baitUntil then
		cat.baitUntil = 0
		cat.baitTarget = nil
		cat.model:SetAttribute(ITEM_EFFECTS.BaitUntilAttribute, nil)
		if not cat.locked and cat.mode == "Attract" then
			setMode(cat, "Idle", now + idleDuration())
			resetItemStuckTracking(cat, now)
		end
	end
end

-- Reuses the city's ground and wall probes. Short angled steps can go around nearby props, while
-- an unreachable lure makes the cat wait safely rather than walk through a wall or off a roof.
local function chooseBaitTarget(cat: WildCat): Vector3?
	local lure = cat.baitTarget
	if lure == nil then
		return nil
	end
	local ground = groundBelow(cat)
	local flat = Vector3.new(lure.X - ground.X, 0, lure.Z - ground.Z)
	local distance = flat.Magnitude
	if distance <= ITEM_EFFECTS.BaitStopDistance then
		return nil
	end
	local advance = math.min(distance - ITEM_EFFECTS.BaitStopDistance, ITEM_EFFECTS.BaitStepDistance)
	local baseAngle = math.atan2(flat.Z, flat.X)
	for _, offset in ITEM_EFFECTS.BaitAngles do
		local angle = baseAngle + math.rad(offset)
		local x = ground.X + math.cos(angle) * advance
		local z = ground.Z + math.sin(angle) * advance
		local hit = probeGround(x, z, ground.Y + CatSpawning.GroundProbeUp, CatSpawning.GroundProbeUp + CatSpawning.GroundProbeDown)
		if hit and isLineWalkable(ground, hit) then
			return hit
		end
	end
	return nil
end

-- Returns a reason when the cat should be removed this tick.
local function stepCat(cat: WildCat, now: number, playerPositions: { Vector3 }): RemoveReason?
	expireItemEffects(cat, now)
	if cat.locked then
		return nil
	end

	local position = cat.root.Position
	local frozen = now < cat.frozenUntil
	local baited = now < cat.baitUntil and cat.baitTarget ~= nil
	local calm = now < cat.calmUntil or baited
	local hasItemEffect = frozen or calm
	if hasItemEffect then
		resetItemStuckTracking(cat, now)
	end
	if frozen then
		cat.root.Anchored = true
		cat.humanoid.WalkSpeed = 0
		cat.humanoid:MoveTo(position)
		return nil
	end
	if baited then
		if cat.mode ~= "Attract" then
			setMode(cat, "Attract", cat.baitUntil)
		end
		if now >= cat.nextMoveAt then
			cat.nextMoveAt = now + ITEM_EFFECTS.BaitRetargetInterval
			cat.target = chooseBaitTarget(cat)
			cat.humanoid:MoveTo(cat.target or position)
		end
		return nil
	end
	if calm and cat.mode == "Flee" then
		setMode(cat, "Idle", now + idleDuration())
	end

	local nearest = math.huge
	local away = Vector3.zero
	for _, playerPosition in playerPositions do
		local offset = Vector3.new(position.X - playerPosition.X, 0, position.Z - playerPosition.Z)
		local distance = offset.Magnitude
		nearest = math.min(nearest, distance)
		if distance < CatSpawning.FleeRadius and distance > MIN_DIRECTION_LENGTH then
			away += offset.Unit / distance -- closer players push harder
		end
	end

	if not hasItemEffect and now >= cat.expiresAt and cat.mode ~= "Flee" and nearest > CatSpawning.DespawnSafeDistance then
		return "Despawned"
	end

	-- Mode transitions
	if cat.mode == "Flee" then
		if nearest > CatSpawning.FleeSafeRadius then
			setMode(cat, "Idle", now + idleDuration())
		elseif now >= cat.modeUntil then
			setMode(cat, "Rest", now + CatSpawning.FleeRestTime)
		end
	elseif cat.mode == "Rest" then
		if now >= cat.modeUntil then
			setMode(cat, "Idle", now)
		end
	elseif not calm and nearest <= CatSpawning.FleeRadius then
		setMode(cat, "Flee", now + CatSpawning.FleeMaxDuration)
	end

	-- Mode behaviour
	if cat.mode == "Flee" then
		if now >= cat.nextMoveAt and away.Magnitude > MIN_DIRECTION_LENGTH then
			cat.nextMoveAt = now + CatSpawning.FleeRetargetInterval
			local target = chooseFleeTarget(cat, away)
			cat.target = target
			cat.humanoid:MoveTo(target or position)
		end
	elseif cat.mode == "Idle" then
		if now >= cat.modeUntil then
			local target = chooseWanderTarget(cat)
			if target then
				setMode(cat, "Wander", math.huge)
				cat.target = target
			else
				cat.modeUntil = now + idleDuration()
			end
		end
	elseif cat.mode == "Wander" then
		local target = cat.target
		if target == nil or (Vector3.new(target.X - position.X, 0, target.Z - position.Z)).Magnitude <= CatSpawning.ArriveDistance then
			setMode(cat, "Idle", now + idleDuration())
		elseif now >= cat.nextMoveAt then
			cat.nextMoveAt = now + CatSpawning.MoveToRefreshInterval
			cat.humanoid:MoveTo(target)
		end
	end

	-- Stuck detection (only while trying to move somewhere)
	if not hasItemEffect and now >= cat.nextStuckCheckAt then
		cat.nextStuckCheckAt = now + CatSpawning.StuckCheckInterval
		local moving = (cat.mode == "Wander" or cat.mode == "Flee") and cat.target ~= nil
		if moving and (position - cat.lastCheckPos).Magnitude < CatSpawning.StuckMinMove then
			cat.stuckStrikes += 1
			if cat.stuckStrikes >= CatSpawning.StuckMaxStrikes then
				return "Stuck"
			end
			if cat.mode == "Wander" then
				local strikes = cat.stuckStrikes
				setMode(cat, "Idle", now) -- pick a different target next tick
				cat.stuckStrikes = strikes -- keep the count across retargets
			end
		elseif moving then
			cat.stuckStrikes = 0
		end
		cat.lastCheckPos = position
	end

	return nil
end

local function aiTick()
	local started = os.clock()
	local playerPositions = getPlayerPositions()
	local toRemove: { [Model]: RemoveReason } = {}

	for model, cat in wildCats do
		local reason = stepCat(cat, started, playerPositions)
		if reason then
			toRemove[model] = reason
		end
	end

	for model, reason in toRemove do
		if untrack(model, reason) then
			fadeAndDestroy(model)
		end
	end

	local elapsedMs = (os.clock() - started) * 1000
	avgTickMs += (elapsedMs - avgTickMs) * CatSpawning.StatsSmoothing
	wildFolder:SetAttribute("AvgTickMs", math.round(avgTickMs * 1000) / 1000)
end

-- Public API -----------------------------------------------------------------------

-- Spawns one extra wild cat of `rarityId` (products, events, admin) in an area that can hold that rarity
-- (any area if none lists it), with the normal spawn-point safety checks. Bonus cats are outside the
-- population target and limited to `maxBonus` at once. Does not yield. Returns the Model or nil.
function CatSpawnService.SpawnBonusCat(rarityId: string, maxBonus: number, catId: string?): Model?
	local rarity = Rarities.Get(rarityId)
	if rarity == nil or rarity.id == SECRET.RarityId or summonedCount >= maxBonus or #areas == 0 then
		return nil
	end
	local candidates: { Area } = {}
	for _, area in areas do
		if table.find(area.rarities, rarity) then
			table.insert(candidates, area)
		end
	end
	if #candidates == 0 then
		candidates = areas
	end
	local positions = getPlayerPositions()
	for _ = 1, #candidates do
		local model = spawnCat(candidates[random:NextInteger(1, #candidates)], positions, rarity, true)
		if model then
			local catDef = if catId then Cats.Get(catId) else nil
			if catDef and catDef.rarity == rarity.id then
				-- Requested a specific cat of this rarity (admin): rename the spawned one.
				setupModel(model, catDef, rarity, tostring(model:GetAttribute(ATTR.SpawnArea)))
			end
			return model
		end
	end
	return nil
end

-- Rain: wild cats hide (Hiding attribute; CatchService refuses them) and no new cats spawn.
function CatSpawnService.SetHiding(on: boolean)
	hiding = on
	for model in wildCats do
		model:SetAttribute(Events.Rain.HidingAttribute, if on then true else nil)
	end
end

function CatSpawnService.IsHiding(): boolean
	return hiding
end

-- Admin "secret rain": spawns up to `count` Secret cats now (announced once by the caller).
function CatSpawnService.ForceSecret(count: number): number
	local area = secretArea
	local rarity = Rarities.Get(SECRET.RarityId)
	if area == nil or rarity == nil then
		return 0
	end
	local spawned = 0
	local positions = getPlayerPositions()
	for _ = 1, count do
		if spawnCat(area, positions, rarity, true) then
			spawned += 1
		end
	end
	return spawned
end

-- Enables a season's mutations in the spawn roll (nil = none). Used by EventService.
function CatSpawnService.SetSeason(name: string?)
	season = name
end

-- Studio only: the spawn mutation roll `count` times with `luck` (rate check).
function CatSpawnService.DebugRollMutations(count: number, luck: number): { [string]: number }
	local result: { [string]: number } = {}
	if not RunService:IsStudio() then
		return result
	end
	local rng = Random.new()
	for _ = 1, count do
		local id = Mutations.Roll(rng, luck, season)
		local key = if id == "" then "None" else id
		result[key] = (result[key] or 0) + 1
	end
	return result
end

function CatSpawnService.GetBonusCount(): number
	return summonedCount
end

function CatSpawnService.GetCatsFolder(): Folder
	return catsFolder
end

function CatSpawnService.IsWild(model: Model): boolean
	return wildCats[model] ~= nil
end

function CatSpawnService.IsLocked(model: Model): boolean
	local cat = wildCats[model]
	return cat ~= nil and cat.locked
end

function CatSpawnService.GetWildCats(): { Model }
	local models = {}
	for model in wildCats do
		table.insert(models, model)
	end
	return models
end

local function isFinite(value: number): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function validEffectDuration(duration: number): boolean
	return isFinite(duration) and duration > 0 and duration <= ITEM_EFFECTS.MaxDuration
end

local function validEffectArea(center: Vector3, radius: number, duration: number): boolean
	return typeof(center) == "Vector3" and isFinite(center.X) and isFinite(center.Y) and isFinite(center.Z)
		and isFinite(radius) and radius > 0 and radius <= ITEM_EFFECTS.MaxRadius and validEffectDuration(duration)
end

local function getEffectCat(model: Model): WildCat?
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil
	end
	local cat = wildCats[model]
	if cat == nil or not model:IsDescendantOf(workspace) or not cat.root:IsDescendantOf(model)
		or cat.humanoid.Health <= 0 or model:GetAttribute(ATTR.State) ~= CatSchema.States.Wild
		or model:GetAttribute(ATTR.OwnerUserId) ~= CatSchema.WildOwnerUserId then
		return nil
	end
	return cat
end

local function setEffectDeadline(cat: WildCat, attribute: string, deadline: number, now: number)
	-- Client-facing deadlines share Roblox's synchronized clock rather than this server's os.clock.
	cat.model:SetAttribute(attribute, workspace:GetServerTimeNow() + math.max(0, deadline - now))
end

-- Yarn freezes movement, not catching. The ordinary catch lock can still be acquired while frozen.
function CatSpawnService.FreezeWildCat(model: Model, duration: number): boolean
	if not validEffectDuration(duration) then
		return false
	end
	local cat = getEffectCat(model)
	if cat == nil or cat.locked then
		return false
	end
	local now = os.clock()
	cat.frozenUntil = math.max(cat.frozenUntil, now + duration)
	setEffectDeadline(cat, ITEM_EFFECTS.FrozenUntilAttribute, cat.frozenUntil, now)
	setMode(cat, "Idle", cat.frozenUntil)
	cat.humanoid.WalkSpeed = 0
	cat.root.AssemblyLinearVelocity = Vector3.zero
	cat.root.AssemblyAngularVelocity = Vector3.zero
	cat.root.Anchored = true
	resetItemStuckTracking(cat, now)
	return true
end

-- Catnip leaves idle/wandering behaviour intact; it only suppresses fleeing from nearby players.
function CatSpawnService.SuppressFleeInRadius(center: Vector3, radius: number, duration: number): number
	if not validEffectArea(center, radius, duration) then
		return 0
	end
	local now = os.clock()
	local affected = 0
	for model in wildCats do
		local cat = getEffectCat(model)
		if cat == nil or (cat.root.Position - center).Magnitude > radius then
			continue
		end
		cat.calmUntil = math.max(cat.calmUntil, now + duration)
		setEffectDeadline(cat, ITEM_EFFECTS.CalmUntilAttribute, cat.calmUntil, now)
		if not cat.locked and now >= cat.frozenUntil and cat.mode == "Flee" then
			setMode(cat, "Idle", now + idleDuration())
		end
		resetItemStuckTracking(cat, now)
		affected += 1
	end
	return affected
end

-- Lures are ground-probed once here, then each AI tick checks safe floor/body-height movement.
-- Only models tracked as Wild are eligible; owned, carried and returning cats are never affected.
function CatSpawnService.AttractWildCats(center: Vector3, radius: number, duration: number): number
	if not validEffectArea(center, radius, duration) then
		return 0
	end
	local ground = probeGround(center.X, center.Z, center.Y + CatSpawning.GroundProbeUp, CatSpawning.GroundProbeUp + CatSpawning.GroundProbeDown)
	if ground == nil then
		return 0
	end
	local now = os.clock()
	local affected = 0
	for model in wildCats do
		local cat = getEffectCat(model)
		if cat == nil or (cat.root.Position - center).Magnitude > radius then
			continue
		end
		cat.baitTarget = ground
		cat.baitUntil = math.max(cat.baitUntil, now + duration)
		setEffectDeadline(cat, ITEM_EFFECTS.BaitUntilAttribute, cat.baitUntil, now)
		if not cat.locked and now >= cat.frozenUntil then
			setMode(cat, "Attract", cat.baitUntil)
			cat.target = chooseBaitTarget(cat)
			cat.humanoid:MoveTo(cat.target or cat.root.Position)
			cat.nextMoveAt = now + ITEM_EFFECTS.BaitRetargetInterval
		end
		resetItemStuckTracking(cat, now)
		affected += 1
	end
	return affected
end

-- Freezes a wild cat in place (anchored, AI paused). Returns false if it isn't wild or is already locked,
-- which is what stops two players from catching the same cat at once.
function CatSpawnService.LockWildCat(model: Model): boolean
	local cat = wildCats[model]
	if cat == nil or cat.locked then
		return false
	end
	cat.locked = true
	model:SetAttribute(Shop.CatchLockedAttribute, true)
	setMode(cat, "Idle", math.huge)
	cat.root.Anchored = true
	return true
end

-- Resumes AI on a locked cat. `flee` makes it bolt immediately (failed catch).
function CatSpawnService.UnlockWildCat(model: Model, flee: boolean)
	local cat = wildCats[model]
	if cat == nil or not cat.locked then
		return
	end
	cat.locked = false
	model:SetAttribute(Shop.CatchLockedAttribute, nil)
	local now = os.clock()
	expireItemEffects(cat, now)
	local frozen = now < cat.frozenUntil
	local calm = now < cat.calmUntil or now < cat.baitUntil
	cat.root.Anchored = frozen
	if not frozen then
		cat.root:SetNetworkOwner(nil) -- unanchoring would otherwise let a nearby client take physics ownership
	end
	if frozen then
		setMode(cat, "Idle", cat.frozenUntil)
		cat.humanoid.WalkSpeed = 0
	elseif flee and not calm then
		setMode(cat, "Flee", now + CatSpawning.FleeMaxDuration)
	else
		setMode(cat, "Idle", now + idleDuration())
	end
	cat.lastCheckPos = cat.root.Position
	cat.nextStuckCheckAt = now + CatSpawning.StuckCheckInterval
end

-- Takes a cat out of the wild for good (AI stops, no longer counted). The caller now owns the Model.
-- Returns false if the cat wasn't wild.
function CatSpawnService.ClaimWildCat(model: Model): boolean
	local cat = untrack(model, "Claimed")
	if cat == nil then
		return false
	end
	cat.humanoid:MoveTo(cat.root.Position)
	return true
end

-- Puts a non-wild cat Model back into the wild where it is (snapped to the ground below).
-- `ignore` is excluded from the ground probe (e.g. the dead carrier's character).
-- Destroys the cat and returns false if there is no ground below it.
function CatSpawnService.ReleaseToWild(model: Model, ignore: Instance?): boolean
	if wildCats[model] then
		return false
	end

	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local rarity = Rarities.Get(tostring(model:GetAttribute(ATTR.Rarity)))
	if root == nil or not root:IsA("BasePart") or humanoid == nil or rarity == nil then
		model:Destroy()
		return false
	end

	local params = rayParams
	if ignore then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { catsFolder, ignore }
		params.CollisionGroup = CatSpawning.CollisionGroup
		params.RespectCanCollide = true
	end

	local position = root.Position
	local ground = probeGround(position.X, position.Z, position.Y + CatSpawning.GroundProbeUp, CatSpawning.GroundProbeUp + CatSpawning.ReleaseProbeDepth, params)
	if ground == nil then
		model:Destroy()
		return false
	end

	local look = root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	model:PivotTo(CFrame.new(ground + Vector3.new(0, rootHeight, 0)) * CFrame.Angles(0, yaw, 0))
	model:SetAttribute(ATTR.State, CatSchema.States.Wild)
	model:SetAttribute(ATTR.OwnerUserId, CatSchema.WildOwnerUserId)
	model:SetAttribute(ATTR.CarrierUserId, nil)
	for _, attribute in { ATTR.PillowIndex, ATTR.Tamed, ATTR.TameDuration, ATTR.TameEndsAt, ATTR.TameRemaining } do
		model:SetAttribute(attribute, nil)
	end
	model.Parent = wildFolder
	humanoid.EvaluateStateMachine = true

	local bonus = rarity.id == SECRET.RarityId
	local area: Area? = nil
	for _, candidate in areas do
		if isInsideArea(candidate, ground + Vector3.new(0, rootHeight, 0)) then
			area = candidate
			break
		end
	end
	area = area or areaByName[tostring(model:GetAttribute(ATTR.SpawnArea))] or (if bonus then secretArea else nil) or areas[1]
	assert(area, "[CatSpawnService] No spawn areas")

	register(model, rarity, area, bonus)
	return true
end

-- Lifecycle --------------------------------------------------------------------------

local function newArea(name: string, rarityIds: { string }, zones: { BasePart }, quota: number): Area
	local rarities: { Rarities.Rarity } = {}
	local rarityTotal = 0
	for _, rarityId in rarityIds do
		local rarity = Rarities.Get(rarityId)
		assert(rarity, `[CatSpawnService] Area "{name}" lists unknown rarity "{rarityId}"`)
		assert(#Cats.ByRarity[rarityId] > 0, `[CatSpawnService] No cats of rarity "{rarityId}"`)
		table.insert(rarities, rarity)
		rarityTotal += rarity.spawnWeight
	end

	local zoneTotal = 0
	for _, zone in zones do
		zoneTotal += zoneArea(zone)
	end

	return {
		name = name,
		rarities = rarities,
		rarityWeightTotal = rarityTotal,
		zones = zones,
		zoneWeightTotal = zoneTotal,
		quota = quota,
		count = 0,
	}
end

local function buildAreas()
	local zonesByName: { [string]: { BasePart } } = {}
	for _, instance in CollectionService:GetTagged(Tags.District) do
		if not instance:IsA("BasePart") or not instance:IsDescendantOf(workspace) then
			continue
		end
		local name = instance:GetAttribute(Districts.NameAttribute)
		if type(name) ~= "string" or not Districts.IsValid(name) then
			warn(`[CatSpawnService] {instance:GetFullName()} has invalid {Districts.NameAttribute} "{tostring(name)}"`)
			continue
		end
		zonesByName[name] = zonesByName[name] or {}
		table.insert(zonesByName[name], instance)
	end

	local totalWeight = 0
	for name, rule in CatSpawning.Areas do
		assert(Districts.IsValid(name), `[CatSpawnService] CatSpawning.Areas has unknown district "{name}"`)
		assert(not table.find(rule.rarities, SECRET.RarityId), `[CatSpawnService] Area "{name}" must not list {SECRET.RarityId}; it uses its own roll`)
		local zones = zonesByName[name]
		if zones == nil then
			warn(`[CatSpawnService] No zones tagged for area "{name}"; it will not spawn cats`)
			continue
		end
		local area = newArea(name, rule.rarities, zones, rule.weight) -- quota normalised below
		table.insert(areas, area)
		areaByName[name] = area
		totalWeight += rule.weight
	end

	for _, area in areas do
		area.quota = CatSpawning.TargetWildCats * area.quota / totalWeight
	end
	table.sort(areas, function(a: Area, b: Area): boolean
		return a.name < b.name
	end)

	local secretZones = zonesByName[SECRET.Area]
	if secretZones then
		secretArea = newArea(SECRET.Area, { SECRET.RarityId }, secretZones, 0)
	else
		warn(`[CatSpawnService] No zones for Secret area "{SECRET.Area}"; Secret cats disabled`)
	end
end

function CatSpawnService:Init(): ()
	local found = ServerStorage:FindFirstChild(TEMPLATE_NAME)
	assert(found and found:IsA("Model"), `[CatSpawnService] ServerStorage.{TEMPLATE_NAME} Model is missing`)
	template = found
	local templateRoot = template:FindFirstChild("HumanoidRootPart")
	local templateHumanoid = template:FindFirstChildOfClass("Humanoid")
	assert(templateRoot and templateRoot:IsA("BasePart"), "[CatSpawnService] CatTemplate needs a HumanoidRootPart")
	assert(templateHumanoid, "[CatSpawnService] CatTemplate needs a Humanoid")
	rootHeight = templateHumanoid.HipHeight + templateRoot.Size.Y / 2
	local modelsFolder = ServerStorage:FindFirstChild(MODELS_FOLDER_NAME)
	catModels = if modelsFolder and modelsFolder:IsA("Folder") then modelsFolder else nil
	if catModels == nil then
		warn(`[CatSpawnService] ServerStorage.{MODELS_FOLDER_NAME} is missing; every cat uses the template`)
	end

	local group = CatSpawning.CollisionGroup
	if not PhysicsService:IsCollisionGroupRegistered(group) then
		PhysicsService:RegisterCollisionGroup(group)
	end
	PhysicsService:CollisionGroupSetCollidable(group, group, false)

	catsFolder = Instance.new("Folder")
	catsFolder.Name = CATS_FOLDER_NAME
	catsFolder.Parent = workspace
	wildFolder = Instance.new("Folder")
	wildFolder.Name = WILD_FOLDER_NAME
	wildFolder.Parent = catsFolder

	-- Rays use the Cats group so they pass through cats, and ignore non-collidable zone parts.
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { catsFolder }
	rayParams.CollisionGroup = group
	rayParams.RespectCanCollide = true

	buildAreas()
	print(`[CatSpawnService] {#areas} spawn areas, target {CatSpawning.TargetWildCats} wild cats`)
end

function CatSpawnService:Start(): ()
	topUp(CatSpawning.TargetWildCats)

	task.spawn(function()
		while true do
			task.wait(CatSpawning.SpawnInterval)
			topUp(CatSpawning.SpawnBatchSize)
			maybeSpawnSecret()
		end
	end)

	while true do
		task.wait(CatSpawning.AITickInterval)
		aiTick()
	end
end

return CatSpawnService

