local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local TEACHER_TAG = "TeacherNPC"

-- ── Round definitions ─────────────────────────────────────────────────────────
type RoundConfig = {
	duration:         number,
	pointsNeeded:     number,
	teacherPositions: { Vector3 },
}

local ROUNDS: { RoundConfig } = {
	{
		duration         = 30,
		pointsNeeded     = 10,
		teacherPositions = {
			Vector3.new(0, 6, -20),
		},
	},
	{
		duration         = 30,
		pointsNeeded     = 25,
		teacherPositions = {
			Vector3.new(-8, 6, -20),
			Vector3.new(8, 6, -20),
		},
	},
	{
		duration         = 30,
		pointsNeeded     = 50,
		teacherPositions = {
			Vector3.new(-16, 6, -20),
			Vector3.new(0, 6, -20),
			Vector3.new(16, 6, -20),
		},
	},
}

-- ── Pull Teacher rig out of workspace into ServerStorage as a reusable template
-- (this also removes it from the live world so it isn't targetable while idle)
local teacherTemplate: Model = workspace:WaitForChild("Teacher") :: Model
teacherTemplate.Parent = ServerStorage

-- ── Shared state values (auto-replicated to all clients) ──────────────────────
local gameTimer = Instance.new("StringValue")
gameTimer.Name   = "GameTimer"
gameTimer.Value  = "--"
gameTimer.Parent = ReplicatedStorage

local statusMessage = Instance.new("StringValue")
statusMessage.Name   = "StatusMessage"
statusMessage.Value  = "GET READY..."
statusMessage.Parent = ReplicatedStorage

local roundResult = Instance.new("StringValue")
roundResult.Name   = "RoundResult"
roundResult.Value  = ""
roundResult.Parent = ReplicatedStorage

-- ── Wait for EnvironmentBuilder callables ─────────────────────────────────────
local cleanupFn: BindableFunction =
	ServerStorage:WaitForChild("CleanupClassroom") :: BindableFunction

local popQuizFn: BindableFunction =
	ServerStorage:WaitForChild("StartPopQuiz") :: BindableFunction

-- Pop Quiz config
local POP_QUIZ_CHECK_INTERVAL: number = 10   -- seconds between each 30% roll
local POP_QUIZ_CHANCE: number         = 0.30
local POP_QUIZ_DURATION: number       = 10   -- seconds the desk barrage lasts

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function getTopScore(): number
	local top = 0
	for _, player in Players:GetPlayers() do
		local ls = player:FindFirstChild("leaderstats")
		if ls then
			local score = ls:FindFirstChild("Score") :: IntValue
			if score and score.Value > top then
				top = score.Value
			end
		end
	end
	return top
end

local function resetAllScores(): ()
	for _, player in Players:GetPlayers() do
		local ls = player:FindFirstChild("leaderstats")
		if ls then
			local score = ls:FindFirstChild("Score") :: IntValue
			if score then score.Value = 0 end
		end
	end
end

local function spawnTeachers(config: RoundConfig): ()
	for i, pos in ipairs(config.teacherPositions) do
		local teacher: Model = teacherTemplate:Clone() :: Model
		teacher.Name = "Teacher_" .. i
		teacher.Parent = workspace
		-- PivotTo moves the whole model so HumanoidRootPart lands at pos
		teacher:PivotTo(CFrame.new(pos))
		-- Stamp patrol centre so TeacherAI builds relative waypoints
		teacher:SetAttribute("PatrolCenterX", pos.X)
		-- Tag triggers TeacherAI.GetInstanceAddedSignal → spawns patrol task
		CollectionService:AddTag(teacher, TEACHER_TAG)
	end
end

local function cleanupRound(): ()
	-- Untag and destroy all active teachers
	for _, teacher in CollectionService:GetTagged(TEACHER_TAG) do
		CollectionService:RemoveTag(teacher, TEACHER_TAG)
		teacher:Destroy()
	end
	-- Remove tomatoes, floating text anchors, etc.
	cleanupFn:Invoke()
end

-- Ensures every connected player has a Tomato tool ready for the next round.
-- Skips players who already have one so duplicate tools aren't stacked.
local function giveTomatoToAll(): ()
	local starterPack   = game:GetService("StarterPack")
	local toolTemplate  = starterPack:FindFirstChild("Tomato")
	if not toolTemplate then
		-- #region agent log
		print("[MatchManager] WARNING — no 'Tomato' tool in StarterPack; cannot distribute")
		-- #endregion
		return
	end

	for _, player in Players:GetPlayers() do
		local backpack  = player:FindFirstChildOfClass("Backpack")
		local character = player.Character
		local hasTomato = (backpack  and backpack:FindFirstChild("Tomato")  ~= nil)
			or            (character and character:FindFirstChild("Tomato") ~= nil)

		if not hasTomato and backpack then
			toolTemplate:Clone().Parent = backpack
			-- #region agent log
			print("[MatchManager] Gave fresh Tomato tool to: " .. player.Name)
			-- #endregion
		else
			-- #region agent log
			print("[MatchManager] " .. player.Name .. " already has Tomato — skipping")
			-- #endregion
		end
	end
end

-- Counts down `duration` seconds, updating GameTimer each second.
local function runCountdown(duration: number): ()
	for t = duration, 0, -1 do
		gameTimer.Value = tostring(t)
		if t > 0 then task.wait(1) end
	end
end

-- ── Round loop ────────────────────────────────────────────────────────────────
local currentRound = 1

while true do
	local config = ROUNDS[currentRound]
	roundResult.Value = ""

	-- Brief "get ready" window so players can orient themselves
	statusMessage.Value = string.format("ROUND %d STARTING IN 3...", currentRound)
	gameTimer.Value = tostring(config.duration)
	task.wait(3)

	-- Announce goal and spawn teachers
	statusMessage.Value = string.format(
		"ROUND %d — GET %d POINTS!",
		currentRound,
		config.pointsNeeded
	)
	giveTomatoToAll()
	spawnTeachers(config)

	-- ── Pop Quiz checker (runs in parallel with the countdown) ────────────────
	-- Every POP_QUIZ_CHECK_INTERVAL seconds there is a POP_QUIZ_CHANCE chance of
	-- triggering a 10-second flying-desk barrage.  roundActive gates the loop so
	-- it exits cleanly when the countdown ends regardless of timing.
	local roundActive = true
	local roundStatusMsg = string.format(
		"ROUND %d — GET %d POINTS!",
		currentRound,
		config.pointsNeeded
	)

	task.spawn(function()
		while roundActive do
			task.wait(POP_QUIZ_CHECK_INTERVAL)
			if not roundActive then break end

			if math.random() < POP_QUIZ_CHANCE then
				statusMessage.Value = "POP QUIZ! DODGE THE DESKS!"
				-- Invoke blocks this coroutine for POP_QUIZ_DURATION seconds while
				-- EnvironmentBuilder runs the desk-spawning loop — that's intentional.
				popQuizFn:Invoke(POP_QUIZ_DURATION)
				if roundActive then
					statusMessage.Value = roundStatusMsg
				end
			end
		end
	end)

	-- Run the round timer
	runCountdown(config.duration)
	roundActive = false   -- signals the pop quiz checker to stop

	-- ── Evaluate result ───────────────────────────────────────────────────────
	local topScore = getTopScore()
	local passed   = topScore >= config.pointsNeeded

	if passed then
		roundResult.Value = "VICTORY"

		if currentRound < #ROUNDS then
			statusMessage.Value = string.format(
				"ROUND %d COMPLETE! NEXT ROUND UP...",
				currentRound
			)
			task.wait(5)
			cleanupRound()
			roundResult.Value  = ""
			currentRound      += 1
		else
			-- All rounds cleared
			statusMessage.Value = "ALL ROUNDS CLEARED — YOU WIN!"
			task.wait(5)
			cleanupRound()
			resetAllScores()
			roundResult.Value = ""
			currentRound      = 1
		end
	else
		-- ── Failure: intermission then restart ────────────────────────────────
		roundResult.Value   = "FAILED"
		statusMessage.Value = string.format(
			"ROUND %d FAILED! NEEDED %d POINTS.",
			currentRound,
			config.pointsNeeded
		)
		task.wait(5)
		roundResult.Value = ""

		for t = 10, 1, -1 do
			statusMessage.Value = string.format("RESTARTING IN %ds...", t)
			task.wait(1)
		end

		cleanupRound()
		resetAllScores()
		currentRound = 1
	end
end
