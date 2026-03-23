local workspace = game:GetService("Workspace")

-- ── Wait for the Teacher model ────────────────────────────────────────────────
local teacher: Model = workspace:WaitForChild("Teacher") :: Model

local humanoid: Humanoid = teacher:WaitForChild("Humanoid") :: Humanoid
local rootPart: BasePart  = teacher:WaitForChild("HumanoidRootPart") :: BasePart

-- ── Unanchor all parts ────────────────────────────────────────────────────────
-- Rigs placed in Studio can have Anchored = true on their parts, which prevents
-- the Humanoid from applying any movement at all.
for _, part in teacher:GetDescendants() do
	if part:IsA("BasePart") then
		part.Anchored = false
	end
end

-- ── Initial placement ─────────────────────────────────────────────────────────
-- Y=6 gives enough clearance above the baseplate so the character drops cleanly
-- onto the floor without clipping through it.
local START_POS = Vector3.new(0, 6, -20)
rootPart.CFrame = CFrame.new(START_POS)

-- Give physics one frame to settle before issuing MoveTo commands
task.wait(0.5)

-- ── Pacing config ─────────────────────────────────────────────────────────────
local PACE_ORIGIN_X: number   =  0     -- centre of the patrol route
local PACE_HALF_WIDTH: number = 15     -- studs left/right of centre
local PACE_Y: number          =  0     -- Y stays constant (humanoid handles height)
local PACE_Z: number          = -20    -- Z stays constant
local MOVE_TIMEOUT: number    =  4     -- seconds before giving up on a MoveTo
local MIN_PAUSE: number       =  0.5   -- random pause range between legs (seconds)
local MAX_PAUSE: number       =  2.0

-- Waypoints: left end → right end, repeated forever
local waypoints: { Vector3 } = {
	Vector3.new(PACE_ORIGIN_X - PACE_HALF_WIDTH, PACE_Y, PACE_Z),
	Vector3.new(PACE_ORIGIN_X + PACE_HALF_WIDTH, PACE_Y, PACE_Z),
}

-- ── Helpers ───────────────────────────────────────────────────────────────────

-- Yields until MoveToFinished fires OR timeout elapses.
-- Returns true if the destination was reached, false if timed out.
local function moveToAndWait(target: Vector3): boolean
	humanoid:MoveTo(target)

	local reached  = false
	local finished = false

	local conn = humanoid.MoveToFinished:Connect(function(success: boolean)
		reached  = success
		finished = true
	end)

	local elapsed = 0
	local STEP    = 0.1
	while not finished and elapsed < MOVE_TIMEOUT do
		task.wait(STEP)
		elapsed += STEP
	end

	conn:Disconnect()
	return reached
end

-- ── Pacing loop ───────────────────────────────────────────────────────────────
local index: number = 1

while true do
	local target = waypoints[index]
	moveToAndWait(target)

	-- Random pause at each end before turning around
	task.wait(math.random() * (MAX_PAUSE - MIN_PAUSE) + MIN_PAUSE)

	index = (index % #waypoints) + 1
end
