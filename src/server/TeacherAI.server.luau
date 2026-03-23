local Players           = game:GetService("Players")
local Debris            = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local TEACHER_TAG: string     = "TeacherNPC"

-- ── Patrol config ─────────────────────────────────────────────────────────────
local PACE_HALF_WIDTH: number = 12
local MOVE_TIMEOUT: number   =  4
local MIN_PAUSE: number      =  0.5
local MAX_PAUSE: number      =  2.0

-- ── Chalk attack config ───────────────────────────────────────────────────────
local CHALK_SPEED: number        = 45
local CHALK_COOLDOWN_MIN: number =  5   -- seconds between attacks
local CHALK_COOLDOWN_MAX: number =  8
local STUN_DURATION: number      =  2
local BONK_SOUND_ID: string      = "rbxassetid://12222216"

-- ── Shared helpers ────────────────────────────────────────────────────────────
local function findNearestPlayer(fromPos: Vector3): Player?
	local nearest: Player? = nil
	local nearestDist      = math.huge

	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local dist = (root.Position - fromPos).Magnitude
				if dist < nearestDist then
					nearest     = player
					nearestDist = dist
				end
			end
		end
	end

	return nearest
end

local function playBonkAt(position: Vector3): ()
	local anchor            = Instance.new("Part")
	anchor.Anchored         = true
	anchor.CanCollide       = false
	anchor.Transparency     = 1
	anchor.Size             = Vector3.new(1, 1, 1)
	anchor.Position         = position
	anchor.Parent           = workspace

	local sound             = Instance.new("Sound")
	sound.SoundId           = BONK_SOUND_ID
	sound.Volume            = 2
	sound.RollOffMaxDistance = 50
	sound.Parent            = anchor
	sound:Play()

	Debris:AddItem(anchor, 3)
end

local function applyStun(character: Model): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local head     = character:FindFirstChild("Head")             :: BasePart?
	if not humanoid then return end

	humanoid.WalkSpeed = 0

	-- "STUNNED!" floating billboard over the player's head
	local billboard           = Instance.new("BillboardGui")
	billboard.AlwaysOnTop     = true
	billboard.Size            = UDim2.new(0, 130, 0, 44)
	billboard.StudsOffset     = Vector3.new(0, 3, 0)
	billboard.Parent          = head or character:FindFirstChild("HumanoidRootPart") or character

	local stunnedLabel                      = Instance.new("TextLabel")
	stunnedLabel.Size                       = UDim2.new(1, 0, 1, 0)
	stunnedLabel.BackgroundTransparency     = 1
	stunnedLabel.Font                       = Enum.Font.GothamBold
	stunnedLabel.TextScaled                 = true
	stunnedLabel.TextColor3                 = Color3.fromRGB(255, 215, 0)
	stunnedLabel.TextStrokeTransparency     = 0.3
	stunnedLabel.Text                       = "STUNNED!"
	stunnedLabel.Parent                     = billboard

	Debris:AddItem(billboard, STUN_DURATION + 0.2)

	task.delay(STUN_DURATION, function()
		if humanoid and humanoid.Parent then
			humanoid.WalkSpeed = 16
		end
	end)
end

-- ── Per-teacher patrol + chalk attack ─────────────────────────────────────────
-- Each teacher tagged "TeacherNPC" gets its own isolated call of this function
-- via task.spawn, so all state is local and teachers never share variables.
local function patrol(teacher: Model): ()
	local humanoid: Humanoid = teacher:WaitForChild("Humanoid")        :: Humanoid
	local rootPart: BasePart  = teacher:WaitForChild("HumanoidRootPart") :: BasePart

	for _, part in teacher:GetDescendants() do
		if part:IsA("BasePart") then part.Anchored = false end
	end

	task.wait(0.5)

	local centerX: number = (teacher:GetAttribute("PatrolCenterX") :: number?)
		or rootPart.Position.X
	local patrolZ: number = rootPart.Position.Z

	local waypoints: { Vector3 } = {
		Vector3.new(centerX - PACE_HALF_WIDTH, 0, patrolZ),
		Vector3.new(centerX + PACE_HALF_WIDTH, 0, patrolZ),
	}

	-- Shared via closure: chalk coroutine sets this true to pause the patrol
	local isAttacking = false

	-- ── Chalk attack coroutine (parallel to patrol) ───────────────────────────
	task.spawn(function()
		-- Stagger initial attacks so multiple teachers don't fire simultaneously
		task.wait(math.random() * 3 + 2)

		while teacher.Parent do
			local cooldown = math.random() * (CHALK_COOLDOWN_MAX - CHALK_COOLDOWN_MIN)
				+ CHALK_COOLDOWN_MIN
			task.wait(cooldown)
			if not teacher.Parent then break end

			local target = findNearestPlayer(rootPart.Position)
			if not target or not target.Character then continue end

			local targetRoot = target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not targetRoot then continue end

			local headPart = teacher:FindFirstChild("Head") :: BasePart?
			if not headPart then continue end

			-- Pause the patrol loop and face the player
			isAttacking            = true
			humanoid.WalkSpeed     = 0

			local lookTarget = Vector3.new(
				targetRoot.Position.X,
				rootPart.Position.Y,
				targetRoot.Position.Z
			)
			local lookDir = lookTarget - rootPart.Position
			if lookDir.Magnitude > 0.01 then
				rootPart.CFrame = CFrame.lookAt(
					rootPart.Position,
					rootPart.Position + lookDir.Unit
				)
			end

			task.wait(0.35)   -- brief "wind-up" pause before firing
			if not teacher.Parent then
				isAttacking = false
				break
			end

			-- Spawn chalk cylinder
			local chalk           = Instance.new("Part")
			chalk.Name            = "Chalk"
			chalk.Shape           = Enum.PartType.Cylinder
			chalk.Size            = Vector3.new(0.8, 0.2, 0.2)
			chalk.Color           = Color3.fromRGB(245, 245, 245)
			chalk.Material        = Enum.Material.SmoothPlastic
			chalk.CastShadow      = false
			chalk.CanCollide      = true
			chalk.Position        = headPart.Position
			chalk.Parent          = workspace

			local fireDir = (targetRoot.Position - headPart.Position).Unit
			-- Orient cylinder lengthwise along the fire direction
			chalk.CFrame = CFrame.lookAt(headPart.Position, headPart.Position + fireDir)
				* CFrame.Angles(0, math.pi / 2, 0)
			chalk.AssemblyLinearVelocity = fireDir * CHALK_SPEED

			-- Hit detection (debounced with a boolean so double-touches don't double-stun)
			local chalkHit = false
			chalk.Touched:Connect(function(hit: BasePart)
				if chalkHit then return end

				local hitModel = hit:FindFirstAncestorOfClass("Model")
				if not hitModel then return end
				-- Ignore the shooting teacher and any other TeacherNPC
				if hitModel == teacher then return end
				if CollectionService:HasTag(hitModel, TEACHER_TAG) then return end

				local hitPlayer = Players:GetPlayerFromCharacter(hitModel)
				if not hitPlayer then return end

				chalkHit = true
				if chalk.Parent then chalk:Destroy() end

				playBonkAt(hit.Position)
				applyStun(hitModel)
			end)

			Debris:AddItem(chalk, 3)

			task.wait(0.5)   -- total wind-up + fire pause ~0.85s

			-- Resume patrol
			isAttacking = false
			if humanoid and humanoid.Parent then
				humanoid.WalkSpeed = 16
			end
		end
	end)

	-- ── Patrol loop ───────────────────────────────────────────────────────────
	local function moveToAndWait(target: Vector3): ()
		if not teacher.Parent then return end
		humanoid:MoveTo(target)

		local finished = false
		local conn = humanoid.MoveToFinished:Connect(function()
			finished = true
		end)

		local elapsed = 0
		while not finished and elapsed < MOVE_TIMEOUT and teacher.Parent do
			if isAttacking then break end   -- yield control to chalk attack
			task.wait(0.1)
			elapsed += 0.1
		end
		conn:Disconnect()
	end

	local index = 1
	while teacher.Parent do
		if isAttacking then
			task.wait(0.1)
		else
			moveToAndWait(waypoints[index])
			if not teacher.Parent then break end
			if not isAttacking then
				-- Only advance waypoint when we completed the leg uninterrupted
				task.wait(math.random() * (MAX_PAUSE - MIN_PAUSE) + MIN_PAUSE)
				index = (index % #waypoints) + 1
			end
		end
	end
end

-- ── CollectionService listeners ───────────────────────────────────────────────
for _, instance in CollectionService:GetTagged(TEACHER_TAG) do
	task.spawn(patrol, instance :: Model)
end

CollectionService:GetInstanceAddedSignal(TEACHER_TAG):Connect(function(instance: Instance)
	task.spawn(patrol, instance :: Model)
end)
