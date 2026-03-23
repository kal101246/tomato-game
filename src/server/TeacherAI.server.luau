local CollectionService = game:GetService("CollectionService")

local TEACHER_TAG: string    = "TeacherNPC"
local PACE_HALF_WIDTH: number = 12   -- studs each side of the patrol centre
local MOVE_TIMEOUT: number   =  4   -- seconds before giving up on a MoveTo
local MIN_PAUSE: number      =  0.5
local MAX_PAUSE: number      =  2.0

-- ── Per-teacher patrol ────────────────────────────────────────────────────────
-- Each tagged teacher gets its own task running this function independently.
local function patrol(teacher: Model): ()
	local humanoid: Humanoid = teacher:WaitForChild("Humanoid") :: Humanoid
	local rootPart: BasePart  = teacher:WaitForChild("HumanoidRootPart") :: BasePart

	-- Rigs placed or cloned from Studio templates can arrive anchored
	for _, part in teacher:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	-- Let physics settle after unanchoring before issuing movement commands
	task.wait(0.5)

	-- MatchManager stamps PatrolCenterX on the model before tagging it.
	-- Fall back to the current X if the attribute is absent (e.g. manual testing).
	local centerX: number = (teacher:GetAttribute("PatrolCenterX") :: number?)
		or rootPart.Position.X
	local patrolZ: number = rootPart.Position.Z

	local waypoints: { Vector3 } = {
		Vector3.new(centerX - PACE_HALF_WIDTH, 0, patrolZ),
		Vector3.new(centerX + PACE_HALF_WIDTH, 0, patrolZ),
	}

	local function moveToAndWait(target: Vector3): ()
		if not teacher.Parent then return end
		humanoid:MoveTo(target)

		local finished = false
		local conn = humanoid.MoveToFinished:Connect(function()
			finished = true
		end)

		local elapsed = 0
		while not finished and elapsed < MOVE_TIMEOUT and teacher.Parent do
			task.wait(0.1)
			elapsed += 0.1
		end
		conn:Disconnect()
	end

	local index = 1
	while teacher.Parent do
		moveToAndWait(waypoints[index])
		if not teacher.Parent then break end
		task.wait(math.random() * (MAX_PAUSE - MIN_PAUSE) + MIN_PAUSE)
		index = (index % #waypoints) + 1
	end
end

-- ── CollectionService listeners ───────────────────────────────────────────────
-- Handle any teachers already tagged when this script runs
for _, instance in CollectionService:GetTagged(TEACHER_TAG) do
	task.spawn(patrol, instance :: Model)
end

-- Handle teachers tagged later (each new round spawned by MatchManager)
CollectionService:GetInstanceAddedSignal(TEACHER_TAG):Connect(function(instance: Instance)
	task.spawn(patrol, instance :: Model)
end)
