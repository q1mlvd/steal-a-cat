--!strict
-- Plot defenses only affect live characters. Cat records remain owned by PillowService;
-- forced drops always use CarryService's existing drop/return-home handler.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Config = ReplicatedStorage.Shared.Config
local Defense = require(Config.Defense)
local CatSchema = require(Config.CatSchema)
local CatSpawning = require(Config.CatSpawning)
local Plots = require(Config.Plots)
local Events = require(Config.Events)
local ItemArtConfig = require(Config.ItemArt)
local ItemArt = require(ReplicatedStorage.Shared.Util.ItemArt)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local CarryService = require(script.Parent.CarryService)
local CatSpawnService = require(script.Parent.CatSpawnService)
local AntiCheatService = require(script.Parent.AntiCheatService)
local NotificationService = require(script.Parent.NotificationService)
local EconomyService = require(script.Parent.EconomyService)
local SlapService = require(script.Parent.SlapService)

local ATTR = CatSchema.Attributes
local DOG = Defense.Dog
local TRAP = Defense.Trap
local MOVE = Defense.Movement
local VACUUM = Defense.Vacuum
local RAID = Events.DogRaid

type TrapState = {owner: Player, plot: Model, model: Model, root: BasePart, expiresAt: number}
type StunState = {character: Model, root: BasePart, humanoid: Humanoid, anchored: boolean,
	endsAt: number, diedConnection: RBXScriptConnection?}
type DogState = {owner: Player, plot: Model, model: Model, root: BasePart, label: TextLabel,
	target: Player?, patrolIndex: number, nextPatrolAt: number, nextBarkAt: number,
	path: {Vector3}, pathIndex: number, pathGoal: Vector3?, nextPathAt: number,
	pathPending: boolean, generation: number}

local DefenseService = {Priority = 87}
local dogs: {[Player]: DogState} = {}
local traps: {TrapState} = {}
local stuns: {[Player]: StunState} = {}
local raidDogs: {DogState} = {} -- Dog Raid event (EventService); they only take bowl coins, never cats
local random = Random.new()
local effectsFolder: Folder

local function aliveParts(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil, nil
end

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function finiteVector(value: Vector3): boolean
	return value.X == value.X and value.Y == value.Y and value.Z == value.Z
		and math.abs(value.X) <= Defense.MaxAimCoordinate
		and math.abs(value.Y) <= Defense.MaxAimCoordinate
		and math.abs(value.Z) <= Defense.MaxAimCoordinate
end

local function interior(plot: Model): BasePart?
	local zone = plot:FindFirstChild("InteriorZone")
	return if zone and zone:IsA("BasePart") then zone else nil
end

local function pointInside(point: Vector3, plot: Model, inset: number?): boolean
	local zone = interior(plot)
	if zone == nil then return false end
	local localPoint = zone.CFrame:PointToObjectSpace(point)
	local half = zone.Size / 2
	local margin = inset or 0
	return math.abs(localPoint.X) <= half.X - margin
		and math.abs(localPoint.Z) <= half.Z - margin
end

-- True when `y` is on one of the house's floors (ground or second floor), not the stairs.
local function onHouseFloor(plot: Model, y: number): boolean
	local zone = interior(plot)
	if zone == nil then return false end
	local bottom = zone.CFrame:PointToWorldSpace(Vector3.new(0, -zone.Size.Y / 2, 0)).Y
	for _, height in Plots.FloorHeights do
		if math.abs(y - (bottom + height)) <= math.min(TRAP.FloorHeightTolerance, Plots.FloorHeightTolerance) then
			return true
		end
	end
	return false
end

local function rayParams(): RaycastParams
	local ignored: {Instance} = {CatSpawnService.GetCatsFolder(), effectsFolder}
	for _, player in Players:GetPlayers() do
		if player.Character then table.insert(ignored, player.Character) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignored
	params.RespectCanCollide = true
	params.CollisionGroup = CatSpawning.CollisionGroup
	return params
end

local function groundAt(point: Vector3): Vector3?
	local origin = point + Vector3.new(0, MOVE.GroundProbeUp, 0)
	local hit = workspace:Raycast(origin, Vector3.new(0, -MOVE.GroundProbeDown, 0), rayParams())
	if hit == nil or hit.Normal.Y < MOVE.MinimumGroundNormalY then return nil end
	return hit.Position
end

local function clearSight(from: Vector3, to: Vector3): boolean
	local delta = to - from
	return delta.Magnitude <= Defense.DirectionEpsilon
		or workspace:Raycast(from, delta, rayParams()) == nil
end

local function hasStolenCat(player: Player, ownerUserId: number?): boolean
	for _, model in CarryService.GetCarried(player) do
		local owner = model:GetAttribute(ATTR.OwnerUserId)
		if model:IsDescendantOf(workspace) and model:GetAttribute(ATTR.State) == CatSchema.States.Carried
			and model:GetAttribute(ATTR.CarrierUserId) == player.UserId
			and type(owner) == "number" and owner ~= CatSchema.WildOwnerUserId and owner ~= player.UserId
			and (ownerUserId == nil or owner == ownerUserId) then
			return true
		end
	end
	return false
end

local function releaseStun(player: Player, state: StunState)
	if stuns[player] ~= state then return end
	stuns[player] = nil
	if state.diedConnection then state.diedConnection:Disconnect() end
	-- WalkSpeed and jump settings were never changed, so carry speed updates and upgrades survive.
	if state.root.Parent and state.root:IsDescendantOf(state.character) then
		state.root.Anchored = state.anchored
	end
	player:SetAttribute(MOVE.TrapUntilAttribute, nil)
	if player.Parent == Players then AntiCheatService.Grace(player, MOVE.GraceSeconds) end
end

local function stun(player: Player): boolean
	local root, humanoid = aliveParts(player)
	local character = player.Character
	if root == nil or humanoid == nil or character == nil then return false end
	local existing = stuns[player]
	if existing and existing.root == root then
		existing.endsAt = math.max(existing.endsAt, os.clock() + TRAP.Duration)
	else
		if existing then releaseStun(player, existing) end
		local state: StunState = {character = character, root = root, humanoid = humanoid,
			anchored = root.Anchored, endsAt = os.clock() + TRAP.Duration, diedConnection = nil}
		stuns[player] = state
		state.diedConnection = humanoid.Died:Connect(function() releaseStun(player, state) end)
	end
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	player:SetAttribute(MOVE.TrapUntilAttribute, workspace:GetServerTimeNow() + TRAP.Duration)
	AntiCheatService.Grace(player, TRAP.Duration + MOVE.GraceSeconds)
	return true
end

local function makePart(model: Model, name: string, size: Vector3, color: Color3, cf: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CollisionGroup = CatSpawning.CollisionGroup
	part.CFrame = cf
	part.Parent = model
	return part
end

-- Stage 17 art: welds an item mesh under `root` (bottom at `root` minus `lift`). Returns nil when the art is
-- missing so callers keep their old part visuals. The functional root keeps its name, size and attributes.
local function attachArt(model: Model, root: BasePart, artName: string, lift: number): Model?
	local art = ItemArt.Clone(artName, false)
	local primary = if art then art.PrimaryPart else nil
	if art == nil or primary == nil then return nil end
	art:PivotTo(root.CFrame * CFrame.new(0, -lift, 0))
	for _, part in art:GetDescendants() do
		if part:IsA("BasePart") and part ~= primary then
			local constraint = Instance.new("WeldConstraint")
			constraint.Part0 = primary
			constraint.Part1 = part
			constraint.Parent = part
		end
	end
	local weld = Instance.new("Weld")
	weld.Name = ItemArtConfig.ArtWeldName
	weld.Part0 = root
	weld.Part1 = primary
	weld.C0 = root.CFrame:ToObjectSpace(primary.CFrame)
	weld.Parent = primary
	root.Transparency = 1
	art.Parent = model
	return art
end

local function removeDog(owner: Player)
	local state = dogs[owner]
	if state then
		dogs[owner] = nil
		state.generation += 1
		state.model:Destroy()
	end
end

local function createDog(player: Player, plot: Model, runtime: Folder): DogState?
	local zone = interior(plot)
	if zone == nil then return nil end
	local spawn = PlotService.GetSpawnCFrame(plot).Position
	local ground = groundAt(spawn)
	if ground == nil then return nil end
	local cf = CFrame.new(ground + Vector3.new(0, DOG.RootHeight, 0))
	local model = Instance.new("Model")
	model.Name = DOG.ModelName
	model:SetAttribute(DOG.OwnerAttribute, player.UserId)
	model:SetAttribute(DOG.StatusAttribute, "Patrolling")
	local root = makePart(model, "Body", DOG.BodySize, DOG.BodyColor, cf)
	model.PrimaryPart = root
	if attachArt(model, root, ItemArtConfig.DogModel, DOG.RootHeight) then
		CollectionService:AddTag(model, ItemArtConfig.DogTag)
	else
		makePart(model, "Head", DOG.HeadSize, DOG.BodyColor, cf * DOG.HeadOffset)
		makePart(model, "Snout", DOG.SnoutSize, DOG.DarkColor, cf * DOG.SnoutOffset)
		makePart(model, "Tail", DOG.TailSize, DOG.BodyColor, cf * DOG.TailOffset)
		makePart(model, "Collar", DOG.CollarSize, DOG.CollarColor, cf * DOG.CollarOffset)
		for index, offset in DOG.LegOffsets do
			makePart(model, `Leg{index}`, DOG.LegSize, DOG.DarkColor, cf * offset)
		end
		for index, offset in DOG.EarOffsets do
			makePart(model, `Ear{index}`, DOG.EarSize, DOG.DarkColor, cf * offset)
		end
		for index, offset in DOG.EyeOffsets do
			makePart(model, `Eye{index}`, DOG.EyeSize, DOG.DarkColor, cf * offset)
		end
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "GuardDogLabel"
	gui.Size = UDim2.fromOffset(DOG.LabelSize.X, DOG.LabelSize.Y)
	gui.StudsOffset = DOG.LabelOffset
	gui.MaxDistance = DOG.LabelDistance
	gui.Parent = root
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = DOG.CollarColor
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.TextSize = DOG.LabelTextSize
	label.Text = "Guard Dog"
	label.Parent = gui
	model.Parent = runtime
	return {owner = player, plot = plot, model = model, root = root, label = label,
		target = nil, patrolIndex = random:NextInteger(1, #DOG.PatrolRoute), nextPatrolAt = 0, nextBarkAt = 0,
		path = {}, pathIndex = 1, pathGoal = nil, nextPathAt = 0, pathPending = false, generation = 0}
end

function DefenseService.Sync(player: Player): ()
	local data = DataService.GetData(player)
	local plot = PlotService.GetPlot(player)
	local count = if data then data.inventory[Defense.GuardDogItemId] else nil
	if player.Parent ~= Players or data == nil or type(count) ~= "number" or count < 1
		or plot == nil or PlotService.GetOwner(plot) ~= player then
		removeDog(player)
		return
	end
	local previous = dogs[player]
	if previous and previous.plot == plot and previous.model:IsDescendantOf(workspace) then return end
	removeDog(player)
	local runtime = PlotService.GetRuntimeFolder(plot)
	if runtime then dogs[player] = createDog(player, plot, runtime) end
end

-- ItemService owns inventory consumption and its general remote rate limit. These APIs do not yield:
-- placement/drop success and inventory consumption can happen together in the same server frame.
function DefenseService.CanUseBoxTrap(player: Player, aim: unknown): (boolean, string, Vector3?)
	local root = aliveParts(player)
	local plot = PlotService.GetPlot(player)
	if root == nil or DataService.GetData(player) == nil or plot == nil
		or PlotService.GetOwner(plot) ~= player or not PlotService.IsInsidePlot(player, plot) then
		return false, "Place traps inside your own house.", nil
	end
	if aim ~= nil and (typeof(aim) ~= "Vector3" or not finiteVector(aim :: Vector3)) then
		return false, "Invalid trap placement.", nil
	end
	local desired = if aim ~= nil then aim :: Vector3
		else root.Position + root.CFrame.LookVector * TRAP.DefaultPlaceDistance
	if not finiteVector(root.Position) or (desired - root.Position).Magnitude > TRAP.PlaceRange then
		return false, "Place the trap closer to you.", nil
	end
	local point = groundAt(desired)
	if point == nil or math.abs(point.Y - root.Position.Y) > TRAP.GroundVerticalTolerance
		or not onHouseFloor(plot, point.Y)
		or not pointInside(point, plot, math.max(TRAP.Size.X, TRAP.Size.Z) / 2)
		or not clearSight(root.Position, point + Vector3.new(0, TRAP.TriggerHeight / 2, 0)) then
		return false, "Aim at a clear floor inside your house.", nil
	end
	local count = 0
	for _, state in traps do
		if state.owner == player and state.model.Parent and state.expiresAt > os.clock() then
			count += 1
			if flat(state.root.Position - point).Magnitude < TRAP.MinimumSpacing then
				return false, "Leave space between your traps.", nil
			end
		end
	end
	if count >= TRAP.MaxPlaced then return false, "Your house already has the maximum traps.", nil end
	if PlotService.GetRuntimeFolder(plot) == nil then return false, "Your house is not ready.", nil end
	return true, "Trap ready.", point
end

function DefenseService.UseBoxTrap(player: Player, aim: unknown): (boolean, string)
	local ok, message, point = DefenseService.CanUseBoxTrap(player, aim)
	if not ok or point == nil then return false, message end
	local plot = PlotService.GetPlot(player)
	local runtime = if plot then PlotService.GetRuntimeFolder(plot) else nil
	if plot == nil or runtime == nil then return false, "Your house is not ready." end
	local model = Instance.new("Model")
	model.Name = TRAP.ModelName
	model:SetAttribute(ATTR.OwnerUserId, player.UserId)
	local cf = CFrame.new(point + Vector3.new(0, TRAP.Size.Y / 2 + TRAP.GroundClearance, 0))
	local root = makePart(model, "Box", TRAP.Size, TRAP.Color, cf)
	model.PrimaryPart = root
	if attachArt(model, root, ItemArtConfig.TrapModel, TRAP.Size.Y / 2) == nil then
		for _, direction in {-1, 1} do
			makePart(model, "Tape", TRAP.StripeSize, TRAP.StripeColor,
				cf * CFrame.new(direction * TRAP.StripeOffset, TRAP.Size.Y / 2, 0))
		end
	end
	model.Parent = runtime
	table.insert(traps, {owner = player, plot = plot, model = model, root = root,
		expiresAt = os.clock() + TRAP.Lifetime})
	return true, `Box trap placed: the next cat thief gets stuck for {TRAP.Duration} seconds!`
end

function DefenseService.UseVacuum(player: Player): (boolean, string)
	local root = aliveParts(player)
	if root == nil or DataService.GetData(player) == nil then return false, "You cannot use a vacuum right now." end
	local target: Player? = nil
	local targetRoot: BasePart? = nil
	local best = VACUUM.Range
	for _, other in Players:GetPlayers() do
		local otherRoot = if other ~= player and hasStolenCat(other, nil) then aliveParts(other) else nil
		if otherRoot then
			local distance = (otherRoot.Position - root.Position).Magnitude
			if distance <= best and clearSight(root.Position, otherRoot.Position) then
				target = other targetRoot = otherRoot best = distance
			end
		end
	end
	if target == nil or targetRoot == nil then return false, "No cat thief in sight within vacuum range." end
	-- No teleport or record mutation: the existing stolen-cat drop handler starts its safe return.
	AntiCheatService.Grace(target, MOVE.GraceSeconds)
	CarryService.DropAll(target, nil, false)
	local effect = Instance.new("Model")
	effect.Name = VACUUM.ModelName
	local held = if player.Character then ItemArt.Hold(player.Character, "Vacuum") else nil
	if held then
		Debris:AddItem(held, ItemArtConfig.VacuumHoldSeconds)
	else
		makePart(effect, "Vacuum", VACUUM.Size, VACUUM.Color, root.CFrame * VACUUM.Offset)
	end
	local ring = makePart(effect, "ScareRing", VACUUM.RingSize, VACUUM.RingColor,
		CFrame.new(targetRoot.Position + Vector3.new(0, VACUUM.RingLift, 0)))
	ring.Shape = Enum.PartType.Ball
	ring.Material = Enum.Material.Neon
	ring.Transparency = VACUUM.RingTransparency
	effect.Parent = effectsFolder
	TweenService:Create(ring, TweenInfo.new(VACUUM.EffectDuration),
		{Size = VACUUM.RingSize * VACUUM.RingFinalScale, Transparency = 1}):Play()
	Debris:AddItem(effect, VACUUM.EffectDuration)
	NotificationService.Notify(target, "The vacuum scared you! The stolen cat is running home.", "Error")
	return true, "Vacuum! The thief dropped their cats."
end

local function patrolPoint(state: DogState): Vector3?
	local zone = interior(state.plot)
	if zone == nil then return nil end
	local half = zone.Size / 2
	local x = math.max(0, half.X - DOG.PatrolInset)
	local z = math.max(0, half.Z - DOG.PatrolInset)
	local stop = DOG.PatrolRoute[state.patrolIndex]
	local height = Plots.FloorHeights[stop.floor] or 0
	local point = zone.CFrame:PointToWorldSpace(Vector3.new(stop.point.X * x, -half.Y + height, stop.point.Y * z))
	local ground = groundAt(point)
	return if ground then ground + Vector3.new(0, DOG.RootHeight, 0) else nil
end

local function targetFor(state: DogState): Player?
	local zone = interior(state.plot)
	if zone == nil then return nil end
	local best = DOG.DetectRange
	local selected: Player? = nil
	for _, player in CarryService.GetCarriers() do
		local root = if player ~= state.owner and hasStolenCat(player, state.owner.UserId) then aliveParts(player) else nil
		if root then
			local distance = flat(root.Position - zone.Position).Magnitude
			if distance <= best then selected = player best = distance end
		end
	end
	return selected
end

local function doorGoal(state: DogState, target: Vector3): Vector3
	local dogInside = pointInside(state.root.Position, state.plot)
	local targetInside = pointInside(target, state.plot)
	if dogInside == targetInside then return target end
	local door = state.plot:FindFirstChild("Door")
	if door == nil or not door:IsA("BasePart") then return target end
	local direction = flat(door.CFrame.LookVector)
	if direction.Magnitude < Defense.DirectionEpsilon then return target end
	local outward = direction.Unit
	-- Probe from the door's sill, not its centre: from head height the probe would hit the second floor.
	local sill = door.Position - Vector3.new(0, door.Size.Y / 2, 0)
	local near = sill + outward * (if dogInside then -DOG.DoorOffset else DOG.DoorOffset)
	local far = sill + outward * (if dogInside then DOG.DoorOffset else -DOG.DoorOffset)
	local nearGround = groundAt(near)
	local farGround = groundAt(far)
	if nearGround == nil or farGround == nil then return target end
	near = nearGround + Vector3.new(0, DOG.RootHeight, 0)
	far = farGround + Vector3.new(0, DOG.RootHeight, 0)
	-- Keep crossing once near the door; testing distance to the inside waypoint would
	-- send the dog back to it every time it stepped more than one tolerance away.
	local progress = flat(state.root.Position - door.Position):Dot(outward)
	local approaching = if dogInside then progress < -DOG.DoorOffset - DOG.WaypointDistance
		else progress > DOG.DoorOffset + DOG.WaypointDistance
	return if approaching then near else far
end

local function requestPath(state: DogState, goal: Vector3)
	if state.pathPending or os.clock() < state.nextPathAt then return end
	state.pathPending = true
	state.nextPathAt = os.clock() + DOG.RepathInterval
	state.generation += 1
	local generation = state.generation
	local start = state.root.Position
	task.spawn(function()
		local path = PathfindingService:CreatePath({AgentRadius = DOG.PathAgentRadius,
			AgentHeight = DOG.PathAgentHeight, AgentCanJump = false, WaypointSpacing = DOG.WaypointSpacing})
		local success = pcall(function() path:ComputeAsync(start, goal) end)
		if dogs[state.owner] ~= state or state.generation ~= generation then path:Destroy() return end
		state.pathPending = false
		if success and path.Status == Enum.PathStatus.Success then
			local positions: {Vector3} = {}
			for _, waypoint in path:GetWaypoints() do
				table.insert(positions, waypoint.Position + Vector3.new(0, DOG.RootHeight, 0))
			end
			state.path = positions
			state.pathIndex = 1
			state.pathGoal = goal
		else
			table.clear(state.path)
			state.pathGoal = nil
		end
		path:Destroy()
	end)
end

local function moveDog(state: DogState, goal: Vector3, speed: number, dt: number)
	local position = state.root.Position
	local point = goal
	if not clearSight(position + Vector3.new(0, DOG.SightHeight, 0), goal + Vector3.new(0, DOG.SightHeight, 0)) then
		requestPath(state, goal)
		while state.pathIndex <= #state.path
			and flat(state.path[state.pathIndex] - position).Magnitude <= DOG.WaypointDistance do
			state.pathIndex += 1
		end
		point = state.path[state.pathIndex] or position
	end
	local direction = flat(point - position)
	if direction.Magnitude <= Defense.DirectionEpsilon then return end
	local step = direction.Unit * math.min(direction.Magnitude, speed * dt)
	local obstruction = workspace:Raycast(position + Vector3.new(0, DOG.SightHeight, 0),
		step + direction.Unit * MOVE.WallClearance, rayParams())
	if obstruction then requestPath(state, goal) return end
	local ground = groundAt(position + step)
	if ground == nil then return end
	local nextPosition = ground + Vector3.new(0, DOG.RootHeight, 0)
	if math.abs(nextPosition.Y - position.Y) > MOVE.MaximumStepHeight then return end
	state.model:PivotTo(CFrame.lookAt(nextPosition, nextPosition + direction.Unit))
end

local function updateDog(state: DogState, dt: number)
	local data = DataService.GetData(state.owner)
	if data == nil or PlotService.GetPlot(state.owner) ~= state.plot
		or PlotService.GetOwner(state.plot) ~= state.owner then removeDog(state.owner) return end
	local count = data.inventory[Defense.GuardDogItemId]
	if type(count) ~= "number" or count < 1 then removeDog(state.owner) return end
	if not state.model:IsDescendantOf(workspace) then DefenseService.Sync(state.owner) return end
	local target = targetFor(state)
	if target ~= state.target then
		state.target = target
		state.generation += 1
		state.pathPending = false
		state.nextPathAt = 0
		table.clear(state.path)
		state.model:SetAttribute(DOG.TargetAttribute, if target then target.UserId else nil)
		state.model:SetAttribute(DOG.StatusAttribute, if target then "Chasing" else "Patrolling")
		state.label.Text = if target then "Guard Dog — chasing!" else "Guard Dog"
	end
	if target then
		local root = aliveParts(target)
		if root == nil then return end
		local offset = root.Position - state.root.Position
		if flat(offset).Magnitude <= DOG.CatchDistance and math.abs(offset.Y) <= DOG.CatchVerticalTolerance
			and clearSight(state.root.Position + Vector3.new(0, DOG.SightHeight, 0), root.Position)
			and hasStolenCat(target, state.owner.UserId) then
			AntiCheatService.Grace(target, MOVE.GraceSeconds)
			CarryService.DropAll(target, nil, false)
			if os.clock() >= state.nextBarkAt then
				state.nextBarkAt = os.clock() + DOG.BarkCooldown
				NotificationService.Notify(target, "The guard dog caught you! The stolen cat is running home.", "Error")
				NotificationService.Notify(state.owner, "Your guard dog caught a cat thief!", "Success")
			end
			return
		end
		local ground = groundAt(root.Position)
		if ground then moveDog(state, doorGoal(state, ground + Vector3.new(0, DOG.RootHeight, 0)), DOG.ChaseSpeed, dt) end
	else
		if os.clock() < state.nextPatrolAt then return end
		local goal = patrolPoint(state)
		if goal == nil then return end
		-- Same x/z on the other floor is not arrival: the dog must take the stairs.
		if flat(goal - state.root.Position).Magnitude <= DOG.WaypointDistance
			and math.abs(goal.Y - state.root.Position.Y) <= MOVE.MaximumStepHeight then
			state.patrolIndex = state.patrolIndex % #DOG.PatrolRoute + 1
			state.nextPatrolAt = os.clock() + DOG.PatrolPause
			table.clear(state.path)
		else
			moveDog(state, doorGoal(state, goal), DOG.PatrolSpeed, dt)
		end
	end
end

-- Dog Raid ---------------------------------------------------------------------------

local function removeRaidDog(index: number)
	local state = table.remove(raidDogs, index)
	if state then
		state.generation += 1
		state.model:Destroy()
	end
end

-- Spawns raid dogs outside every occupied house. Returns how many spawned.
function DefenseService.StartRaid(): number
	local count = 0
	for _, plot in PlotService.GetPlots() do
		local owner = PlotService.GetOwner(plot)
		local runtime = PlotService.GetRuntimeFolder(plot)
		local door = plot:FindFirstChild("Door")
		if owner == nil or runtime == nil or door == nil or not door:IsA("BasePart") then continue end
		for index = 1, RAID.DogsPerHouse do
			local state = createDog(owner, plot, runtime)
			if state == nil then continue end
			local outward = flat(door.CFrame.LookVector).Unit
			local sideways = Vector3.new(-outward.Z, 0, outward.X) * (index - 1) * 3
			local ground = groundAt(door.Position + outward * RAID.SpawnDistance + sideways)
			if ground then
				state.model:PivotTo(CFrame.lookAt(ground + Vector3.new(0, DOG.RootHeight, 0), door.Position))
			end
			state.model.Name = "RaidDog"
			state.model:SetAttribute(DOG.StatusAttribute, "Raiding")
			state.model:SetAttribute("RaidDog", true)
			state.label.Text = RAID.Label
			for _, part in state.model:GetChildren() do
				if part:IsA("BasePart") and part.Color == DOG.BodyColor then part.Color = RAID.Color end
			end
			if state.model:FindFirstChild(ItemArtConfig.ArtName) then
				local glow = Instance.new("PointLight")
				glow.Color = ItemArtConfig.RaidGlowColor
				glow.Range = ItemArtConfig.RaidGlowRange
				glow.Parent = state.root
			end
			table.insert(raidDogs, state)
			count += 1
		end
	end
	return count
end

function DefenseService.StopRaid()
	for index = #raidDogs, 1, -1 do removeRaidDog(index) end
end

function DefenseService.GetRaidDogCount(): number
	return #raidDogs
end

local function updateRaidDog(index: number, dt: number)
	local state = raidDogs[index]
	local bowl = state.plot:FindFirstChild("Bowl")
	local zone = interior(state.plot)
	if not state.model:IsDescendantOf(workspace) or bowl == nil or not bowl:IsA("BasePart") or zone == nil
		or PlotService.GetOwner(state.plot) == nil then
		removeRaidDog(index)
		return
	end
	if flat(bowl.Position - state.root.Position).Magnitude <= RAID.StealDistance
		and math.abs(bowl.Position.Y - state.root.Position.Y) <= DOG.CatchVerticalTolerance then
		local owner = PlotService.GetOwner(state.plot)
		local amount = EconomyService.StealFromBowl(state.plot, RAID.StealFraction)
		if owner then
			NotificationService.Notify(owner, `A raid dog ate {amount} coins from your bowl!`, "Error")
		end
		removeRaidDog(index)
		return
	end
	local toward = flat(zone.Position - bowl.Position)
	local approach = bowl.Position + (if toward.Magnitude > Defense.DirectionEpsilon then toward.Unit * (RAID.StealDistance / 2) else Vector3.zero)
	local ground = groundAt(approach)
	if ground then
		moveDog(state, doorGoal(state, ground + Vector3.new(0, DOG.RootHeight, 0)), RAID.Speed, dt)
	end
end

-- Slap target: the nearest raid dog in front of the slapper is chased away for a coin reward.
local function slapRaidDog(player: Player, origin: Vector3, look: Vector3, range: number, facingDot: number): boolean
	local bestIndex: number? = nil
	local best = range
	for index, state in raidDogs do
		local offset = flat(state.root.Position - origin)
		local distance = offset.Magnitude
		if distance <= best and distance > 0 and look:Dot(offset.Unit) >= facingDot then
			best = distance
			bestIndex = index
		end
	end
	if bestIndex == nil then return false end
	local position = raidDogs[bestIndex].root.Position
	removeRaidDog(bestIndex)
	SlapService.PlayEffect(position)
	local reward = math.floor(math.max(RAID.RewardBase, EconomyService.GetIncomePerSecond(player) * RAID.RewardIncomeSeconds))
	EconomyService.AddCoins(player, reward)
	NotificationService.Notify(player, `You chased a raid dog away! +{reward} coins`, "Success")
	return true
end

local function updateTraps()
	for index = #traps, 1, -1 do
		local state = traps[index]
		if not state.model:IsDescendantOf(workspace) or os.clock() >= state.expiresAt
			or PlotService.GetPlot(state.owner) ~= state.plot or DataService.GetData(state.owner) == nil then
			state.model:Destroy()
			table.remove(traps, index)
			continue
		end
		for _, thief in CarryService.GetCarriers() do
			local root = if thief ~= state.owner and hasStolenCat(thief, state.owner.UserId)
				and PlotService.IsInsidePlot(thief, state.plot) then aliveParts(thief) else nil
			if root then
				local localPoint = state.root.CFrame:PointToObjectSpace(root.Position)
				if math.abs(localPoint.X) <= TRAP.Size.X / 2 + TRAP.TriggerInset
					and math.abs(localPoint.Z) <= TRAP.Size.Z / 2 + TRAP.TriggerInset
					and localPoint.Y >= -TRAP.Size.Y and localPoint.Y <= TRAP.TriggerHeight
					and stun(thief) then
					NotificationService.Notify(thief, `Box trap! You are stuck for {TRAP.Duration} seconds.`, "Error")
					NotificationService.Notify(state.owner, "Your box trap caught a cat thief!", "Success")
					state.model:Destroy()
					table.remove(traps, index)
					break
				end
			end
		end
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterRemoving:Connect(function(character: Model)
		local state = stuns[player]
		if state and state.character == character then releaseStun(player, state) end
	end)
	DefenseService.Sync(player)
end

function DefenseService:Init(): ()
	effectsFolder = Instance.new("Folder")
	effectsFolder.Name = Defense.EffectFolderName
	effectsFolder.Parent = workspace
	SlapService.RegisterSlapTarget("RaidDogs", slapRaidDog)
end

function DefenseService:Start(): ()
	DataService.DataLoaded:Connect(function(player: Player) DefenseService.Sync(player) end)
	PlotService.PlotAssigned:Connect(function(player: Player) DefenseService.Sync(player) end)
	PlotService.PlotReleased:Connect(function(player: Player)
		removeDog(player)
		for index = #traps, 1, -1 do
			if traps[index].owner == player then traps[index].model:Destroy() table.remove(traps, index) end
		end
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		local state = stuns[player]
		if state then releaseStun(player, state) end
		removeDog(player)
	end)
	for _, player in Players:GetPlayers() do onPlayerAdded(player) end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < Defense.PollInterval then return end
		local step = math.min(elapsed, Defense.MaxStepDelta)
		elapsed = 0
		for player, state in stuns do
			if player.Parent ~= Players or player.Character ~= state.character
				or state.humanoid.Health <= 0 or state.root.Parent == nil or os.clock() >= state.endsAt then
				releaseStun(player, state)
			elseif not state.root.Anchored then
				state.root.Anchored = true
			end
		end
		updateTraps()
		for _, state in dogs do updateDog(state, step) end
		for index = #raidDogs, 1, -1 do updateRaidDog(index, step) end
	end)
end

return DefenseService

