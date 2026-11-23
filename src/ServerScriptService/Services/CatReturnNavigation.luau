--!strict
-- Shared physical return route for dropped stolen cats and loyalty escapes.
-- This module never changes a save or seats a cat: its caller owns those transactions.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local CatSchema = require(Config.CatSchema)
local CatSpawning = require(Config.CatSpawning)
local Loyalty = require(Config.Loyalty)
local CatSpawnService = require(script.Parent.CatSpawnService)

local ATTR = CatSchema.Attributes
local RETURN = Loyalty.Return

type Segment = {
	position: Vector3,
	-- The door corridor is known to be open to the Cats collision group, even when locked.
	-- Moving across it directly avoids the navigation mesh treating the player barrier as a wall.
	doorCorridor: boolean,
}

local CatReturnNavigation = {
	Priority = 64,
}

local returningFolder: Folder? = nil

local function noop(): ()
end

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function insidePlot(position: Vector3, plot: Model): boolean
	local zone = plot:FindFirstChild("InteriorZone")
	if zone == nil or not zone:IsA("BasePart") then
		return false
	end
	local point = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(point.X) <= half.X and math.abs(point.Y) <= half.Y and math.abs(point.Z) <= half.Z
end

function CatReturnNavigation.GetReturningFolder(): Folder
	local existing = returningFolder
	if existing and existing.Parent then
		return existing
	end
	local catsFolder = CatSpawnService.GetCatsFolder()
	local found = catsFolder:FindFirstChild(RETURN.FolderName)
	if found and found:IsA("Folder") then
		returningFolder = found
		return found
	end
	local folder = Instance.new("Folder")
	folder.Name = RETURN.FolderName
	folder.Parent = catsFolder
	returningFolder = folder
	return folder
end

function CatReturnNavigation.Run(
	model: Model,
	sourcePlot: Model?,
	targetPlot: Model,
	target: Vector3,
	isActive: () -> boolean,
	complete: () -> (),
	abort: () -> ()
): () -> ()
	local root = rootOf(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if root == nil or humanoid == nil or not model:IsDescendantOf(workspace)
		or not targetPlot:IsDescendantOf(workspace) or not isActive() then
		abort()
		return noop
	end
	-- These references stay fixed for this run. A replacement model starts a separate run.
	local catRoot: BasePart = root
	local catHumanoid: Humanoid = humanoid
	local rootHeight = catHumanoid.HipHeight + catRoot.Size.Y / 2
	local originalJumpPower = catHumanoid.JumpPower
	local originalUseJumpPower = catHumanoid.UseJumpPower
	local originalJumpEnabled = catHumanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
	local deadline = os.clock() + RETURN.MaxTime
	local ended = false
	local effects: { Instance } = {}
	local destroyingConnection: RBXScriptConnection? = nil

	local function valid(): boolean
		return not ended and model:IsDescendantOf(workspace)
			and catRoot:IsDescendantOf(model) and catHumanoid:IsDescendantOf(model)
			and catHumanoid.Health > 0 and targetPlot:IsDescendantOf(workspace)
			and model:GetAttribute(ATTR.State) == CatSchema.States.Returning and isActive()
	end

	local function cleanup(): ()
		if destroyingConnection then
			destroyingConnection:Disconnect()
			destroyingConnection = nil
		end
		for _, effect in effects do
			effect:Destroy()
		end
		table.clear(effects)
		if catRoot:IsDescendantOf(workspace) and catHumanoid:IsDescendantOf(model) then
			catHumanoid:Move(Vector3.zero)
			catHumanoid:MoveTo(catRoot.Position)
			catHumanoid.Jump = false
			catHumanoid.JumpPower = originalJumpPower
			catHumanoid.UseJumpPower = originalUseJumpPower
			catHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, originalJumpEnabled)
			catRoot.AssemblyLinearVelocity = Vector3.zero
		end
	end

	local function finish(success: boolean): ()
		if ended then
			return
		end
		-- Revalidate immediately before either the arrival transaction or timeout fallback.
		local canComplete = success and valid()
		ended = true
		cleanup()
		if canComplete then
			complete()
		else
			abort()
		end
	end

	-- A caller cancelling the route owns its rollback. Cancellation does not call either callback.
	local function cancel(): ()
		if ended then
			return
		end
		ended = true
		cleanup()
	end

	model:SetAttribute(ATTR.State, CatSchema.States.Returning)
	model:SetAttribute(ATTR.CarrierUserId, nil)
	model.Parent = CatReturnNavigation.GetReturningFolder()
	catRoot.Anchored = false
	catRoot.CanCollide = true
	catRoot.Massless = false
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = CatSpawning.CollisionGroup
		end
	end
	catHumanoid.EvaluateStateMachine = true
	catHumanoid.WalkSpeed = RETURN.Speed
	-- Wild cats disable jumping. Returns need to cross raised house floors and navigation jumps.
	catHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	local ownershipSet = pcall(function(): ()
		catRoot:SetNetworkOwner(nil)
	end)
	if not ownershipSet then
		finish(false)
		return noop
	end
	catRoot.AssemblyLinearVelocity = RETURN.HopVelocity

	local attachment0 = Instance.new("Attachment")
	attachment0.Name = RETURN.TrailName .. "Start"
	attachment0.Position = Vector3.new(-RETURN.TrailAttachmentOffset, 0, 0)
	attachment0.Parent = catRoot
	table.insert(effects, attachment0)
	local attachment1 = Instance.new("Attachment")
	attachment1.Name = RETURN.TrailName .. "End"
	attachment1.Position = Vector3.new(RETURN.TrailAttachmentOffset, 0, 0)
	attachment1.Parent = catRoot
	table.insert(effects, attachment1)
	local trail = Instance.new("Trail")
	trail.Name = RETURN.TrailName
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.Lifetime = RETURN.TrailLifetime
	trail.WidthScale = NumberSequence.new(RETURN.TrailWidth)
	trail.Color = ColorSequence.new(RETURN.TrailColor)
	trail.FaceCamera = true
	trail.Parent = catRoot
	table.insert(effects, trail)
	destroyingConnection = model.Destroying:Connect(function(): ()
		finish(false)
	end)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local ignored: { Instance } = { CatSpawnService.GetCatsFolder() }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignored, player.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignored
	rayParams.CollisionGroup = CatSpawning.CollisionGroup
	rayParams.RespectCanCollide = true

	local function atGround(position: Vector3, floorY: number): Vector3
		local origin = Vector3.new(position.X, floorY + CatSpawning.GroundProbeUp, position.Z)
		local hit = workspace:Raycast(
			origin,
			Vector3.new(0, -(CatSpawning.GroundProbeUp + CatSpawning.ReleaseProbeDepth), 0),
			rayParams
		)
		local groundY = if hit then hit.Position.Y else floorY
		return Vector3.new(position.X, groundY + rootHeight, position.Z)
	end

	local function doorPoints(plot: Model): (Vector3?, Vector3?)
		local door = plot:FindFirstChild("Door")
		if door == nil or not door:IsA("BasePart") then
			return nil, nil
		end
		local facing = door.CFrame.LookVector
		local horizontal = Vector3.new(facing.X, 0, facing.Z)
		if horizontal.Magnitude == 0 then
			return nil, nil
		end
		local outward = horizontal.Unit
		-- Door centers are at head height. Probe from the bottom, so waypoints lie on the floor.
		local floorY = door.Position.Y - door.Size.Y / 2
		local inside = atGround(door.Position - outward * RETURN.DoorOffset, floorY)
		local outside = atGround(door.Position + outward * RETURN.DoorOffset, floorY)
		return inside, outside
	end

	local route: { Segment } = {}
	local sameInterior = sourcePlot == targetPlot and insidePlot(catRoot.Position, targetPlot)
	if sourcePlot and not sameInterior and insidePlot(catRoot.Position, sourcePlot) then
		local inside, outside = doorPoints(sourcePlot)
		if inside and outside then
			table.insert(route, { position = inside, doorCorridor = false })
			table.insert(route, { position = outside, doorCorridor = true })
		end
	end
	if not sameInterior then
		local inside, outside = doorPoints(targetPlot)
		if inside and outside then
			table.insert(route, { position = outside, doorCorridor = false })
			table.insert(route, { position = inside, doorCorridor = true })
		end
	end
	table.insert(route, { position = atGround(target, target.Y), doorCorridor = false })

	local function reached(position: Vector3, radius: number?): boolean
		local offset = position - catRoot.Position
		return Vector3.new(offset.X, 0, offset.Z).Magnitude <= (radius or RETURN.ArriveDistance)
	end

	local function goalReached(position: Vector3, radius: number?): boolean
		-- A wider final approach only seats cats already inside the destination house, on the pillow's
		-- floor: standing below a second-floor pillow is not arrival (the path continues up the stairs).
		return reached(position, radius) and (radius == nil or (insidePlot(catRoot.Position, targetPlot)
			and math.abs(position.Y - catRoot.Position.Y) <= RETURN.GoalVerticalTolerance))
	end

	local function jump(power: number?): ()
		catHumanoid.UseJumpPower = if power then true else originalUseJumpPower
		catHumanoid.JumpPower = power or originalJumpPower
		catHumanoid.Jump = true
		catHumanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end

	local function jumpStep(position: Vector3): ()
		if position.Y - catRoot.Position.Y <= RETURN.DoorStepHeight
			or catHumanoid.FloorMaterial == Enum.Material.Air then
			return
		end
		local offset = position - catRoot.Position
		local horizontal = Vector3.new(offset.X, 0, offset.Z)
		if horizontal.Magnitude == 0 then
			return
		end
		-- Probe just above the feet. House floor lips and pillow edges can block this small rig.
		-- Jump at the step rather than several studs away from it.
		local origin = catRoot.Position + Vector3.new(0, -rootHeight + RETURN.DoorStepHeight, 0)
		local probeLength = catRoot.Size.Z / 2 + RETURN.AgentRadius
		if workspace:Raycast(origin, horizontal.Unit * probeLength, rayParams) then
			jump(RETURN.DoorJumpPower)
		end
	end

	local function walkTo(position: Vector3, goal: Vector3?, goalRadius: number?): boolean
		if not valid() or os.clock() >= deadline then
			return false
		end
		catHumanoid:MoveTo(position)
		local waypointDeadline = math.min(deadline, os.clock() + RETURN.WaypointTimeout)
		while valid() and os.clock() < waypointDeadline do
			if reached(position) or (goal ~= nil and goalRadius ~= nil and goalReached(goal, goalRadius)) then
				return true
			end
			jumpStep(position)
			task.wait(RETURN.StepInterval)
		end
		return valid() and (reached(position) or (goal ~= nil and goalRadius ~= nil and goalReached(goal, goalRadius)))
	end

	local function followPath(destination: Vector3, finishRadius: number?): boolean
		catHumanoid.UseJumpPower = originalUseJumpPower
		catHumanoid.JumpPower = originalJumpPower
		for _ = 0, RETURN.RepathAttempts do
			if not valid() or os.clock() >= deadline then
				return false
			end
			if goalReached(destination, finishRadius) then
				return true
			end
			-- A step jump at the top of the stairs can throw the cat several studs up; a path computed from
			-- mid-air fails, and burning every attempt there left cats idle until the timeout.
			local landBy = os.clock() + RETURN.LandTimeout
			while valid() and catHumanoid.FloorMaterial == Enum.Material.Air and os.clock() < landBy do
				task.wait(RETURN.StepInterval)
			end
			if not valid() then
				return false
			end
			local pathDestination = destination
			if finishRadius and finishRadius > RETURN.ArriveDistance then
				-- Aim for floor beside the pillow; its small raised top need not be navigable.
				-- Leave the normal waypoint tolerance inside the final seating radius.
				local offset = destination - catRoot.Position
				local horizontal = Vector3.new(offset.X, 0, offset.Z)
				if horizontal.Magnitude > 0 then
					local approach = destination - horizontal.Unit * (finishRadius - RETURN.ArriveDistance)
					pathDestination = atGround(approach, destination.Y - rootHeight)
				end
			end
			local path = PathfindingService:CreatePath({
				AgentRadius = RETURN.AgentRadius,
				AgentHeight = RETURN.AgentHeight,
				AgentCanJump = RETURN.AgentCanJump,
				WaypointSpacing = RETURN.WaypointSpacing,
			})
			local ok = pcall(function(): ()
				path:ComputeAsync(catRoot.Position, pathDestination)
			end)
			-- ComputeAsync yields. Never issue a move on a cancelled or transferred cat afterward.
			if not valid() or os.clock() >= deadline then
				path:Destroy()
				return false
			end
			local arrived = ok and path.Status == Enum.PathStatus.Success
			if arrived then
				for _, waypoint in path:GetWaypoints() do
					if valid() and goalReached(destination, finishRadius) then
						break
					end
					if valid() and waypoint.Action == Enum.PathWaypointAction.Jump then
						jump(nil)
					end
					-- Navigation waypoints lie at floor height; step detection compares root heights.
					local rootPosition = waypoint.Position + Vector3.new(0, rootHeight, 0)
					if not walkTo(rootPosition, destination, finishRadius) then
						arrived = false
						break
					end
				end
			end
			path:Destroy()
			if arrived and valid() and goalReached(destination, finishRadius) then
				return true
			end
			task.wait(RETURN.StepInterval)
		end
		return false
	end

	-- Independent watchdog covers a delayed ComputeAsync as well as a blocked movement route.
	task.spawn(function(): ()
		while not ended do
			if not valid() then
				finish(false)
				return
			end
			if os.clock() >= deadline then
				finish(true) -- The caller seats at the destination after revalidating its transaction.
				return
			end
			task.wait(RETURN.StepInterval)
		end
	end)

	task.spawn(function(): ()
		local ok, err = xpcall(function(): ()
			for index, segment in route do
				if not valid() then
					finish(false)
					return
				end
				local finishRadius = if index == #route then RETURN.PillowApproachDistance else nil
				local arrived = if segment.doorCorridor then walkTo(segment.position) else followPath(segment.position, finishRadius)
				-- Keep walking (re-path) rather than standing still until the timeout.
				while not arrived and not segment.doorCorridor and valid() and os.clock() < deadline do
					task.wait(RETURN.SegmentRetryDelay)
					arrived = followPath(segment.position, finishRadius)
				end
				if not arrived then
					-- Stay in transit until the timeout. Do not teleport through walls on the first blockage.
					return
				end
			end
			finish(true)
		end, debug.traceback)
		if not ok then
			warn(`[CatReturnNavigation] {tostring(err)}`)
			finish(false)
		end
	end)
	return cancel
end

function CatReturnNavigation:Init(): ()
	CatReturnNavigation.GetReturningFolder()
end

function CatReturnNavigation:Start(): ()
end

return CatReturnNavigation


