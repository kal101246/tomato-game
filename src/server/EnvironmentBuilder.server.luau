local Players        = game:GetService("Players")
local TweenService   = game:GetService("TweenService")
local Debris         = game:GetService("Debris")
local ServerStorage  = game:GetService("ServerStorage")
local workspace      = game:GetService("Workspace")

-- ── Container ─────────────────────────────────────────────────────────────────
local environment = Instance.new("Folder")
environment.Name   = "ClassroomEnvironment"
environment.Parent = workspace

-- ── Helper ────────────────────────────────────────────────────────────────────
type PropConfig = {
	name:     string,
	shape:    Enum.PartType,
	size:     Vector3,
	position: Vector3,
	color:    Color3,
	material: Enum.Material,
}

local function buildProp(cfg: PropConfig): BasePart
	local part         = Instance.new("Part")
	part.Name          = cfg.name
	part.Shape         = cfg.shape
	part.Size          = cfg.size
	part.Position      = cfg.position
	part.Color         = cfg.color
	part.Material      = cfg.material
	part.Anchored      = true
	part.CanCollide    = true
	part.TopSurface    = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent        = environment
	return part
end

-- ── Props ─────────────────────────────────────────────────────────────────────
local WHITEBOARD_POS = Vector3.new(0, 5, -30)
local DESK_POS       = Vector3.new(0, 3, -25)

buildProp({
	name     = "Whiteboard",
	shape    = Enum.PartType.Block,
	size     = Vector3.new(18, 8, 0.4),
	position = WHITEBOARD_POS,
	color    = Color3.fromRGB(240, 240, 240),
	material = Enum.Material.SmoothPlastic,
})

local desk = buildProp({
	name     = "Desk",
	shape    = Enum.PartType.Block,
	size     = Vector3.new(6, 1.2, 3),
	position = DESK_POS,
	color    = Color3.fromRGB(106, 74, 40),
	material = Enum.Material.Wood,
})

local deskTopY    = DESK_POS.Y + desk.Size.Y / 2
local APPLE_RADIUS = 0.4

buildProp({
	name     = "Apple",
	shape    = Enum.PartType.Ball,
	size     = Vector3.new(APPLE_RADIUS * 2, APPLE_RADIUS * 2, APPLE_RADIUS * 2),
	position = Vector3.new(DESK_POS.X + 1.5, deskTopY + APPLE_RADIUS, DESK_POS.Z),
	color    = Color3.fromRGB(200, 35, 35),
	material = Enum.Material.SmoothPlastic,
})

-- ── CleanupClassroom ──────────────────────────────────────────────────────────
-- MatchManager invokes this between rounds to clear transient objects from
-- the previous round without touching the permanent classroom props.
-- SAFE: "AmmoCrate" is explicitly excluded because its name is neither
-- "Tomato" nor "FloatingTextAnchor", so it survives every cleanup call.
local cleanupFn        = Instance.new("BindableFunction")
cleanupFn.Name         = "CleanupClassroom"
cleanupFn.Parent       = ServerStorage

cleanupFn.OnInvoke = function(): ()
	local destroyed = 0
	for _, obj in workspace:GetDescendants() do
		-- Only destroy BasePart projectiles and anchor parts — never Tool instances,
		-- which would wipe the Tomato tool out of any equipped player's Character.
		-- "AmmoCrate" is intentionally NOT listed here and will never be deleted.
		if obj:IsA("BasePart") and (obj.Name == "Tomato" or obj.Name == "FloatingTextAnchor") then
			-- #region agent log
			destroyed += 1
			-- #endregion
			obj:Destroy()
		end
	end
	-- #region agent log
	print(string.format("[EnvironmentBuilder] CleanupClassroom removed %d transient parts", destroyed))
	-- #endregion
end

-- ── Ammo Crate ────────────────────────────────────────────────────────────────
-- Parented directly to workspace so it is NEVER inside ClassroomEnvironment
-- and therefore never touched by CleanupClassroom.
local CRATE_POS = Vector3.new(12, 1, -5)

local crate               = Instance.new("Part")
crate.Name                = "AmmoCrate"
crate.Size                = Vector3.new(3, 3, 3)
crate.Position            = CRATE_POS
crate.Color               = Color3.fromRGB(50, 180, 80)
crate.Material            = Enum.Material.SmoothPlastic
crate.Anchored            = true
crate.CanCollide          = true
crate.TopSurface          = Enum.SurfaceType.Smooth
crate.BottomSurface       = Enum.SurfaceType.Smooth
crate.Parent              = workspace   -- workspace root, NOT environment folder

local prompt              = Instance.new("ProximityPrompt")
prompt.ActionText         = "Refill Ammo"
prompt.ObjectText         = "Ammo Crate"
prompt.HoldDuration       = 0           -- instant, no hold required
prompt.MaxActivationDistance = 8
prompt.Parent             = crate

-- Floating label so players can spot it from across the room
local billboard           = Instance.new("BillboardGui")
billboard.AlwaysOnTop     = false
billboard.Size            = UDim2.new(0, 160, 0, 44)
billboard.StudsOffset     = Vector3.new(0, 3, 0)
billboard.Parent          = crate

local billLabel           = Instance.new("TextLabel")
billLabel.Size            = UDim2.new(1, 0, 1, 0)
billLabel.BackgroundTransparency = 1
billLabel.Font            = Enum.Font.GothamBold
billLabel.TextScaled      = true
billLabel.TextColor3      = Color3.fromRGB(80, 220, 80)
billLabel.TextStrokeTransparency = 0.3
billLabel.Text            = "AMMO CRATE"
billLabel.Parent          = billboard

-- #region agent log
print("[EnvironmentBuilder] AmmoCrate spawned at: " .. tostring(crate.Position))
-- #endregion

-- ── StartPopQuiz ──────────────────────────────────────────────────────────────
-- MatchManager invokes this when a Pop Quiz event triggers.
-- Spawns "Flying Desks" that slide across the classroom for `duration` seconds.
-- Desks are Anchored (clean TweenService slide) but CanCollide=true so players
-- can jump on top to avoid them.  Touched callbacks manually fling any player
-- that gets hit because anchored parts don't exert physics forces.
local popQuizFn        = Instance.new("BindableFunction")
popQuizFn.Name         = "StartPopQuiz"
popQuizFn.Parent       = ServerStorage

-- Room X-bounds the desks slide between (well outside the whiteboard/desk area)
local DESK_SLIDE_START_X: number = -22
local DESK_SLIDE_END_X: number   =  22
-- Z range desks can spawn at (classroom depth, avoiding walls)
local DESK_SPAWN_Z_MIN: number   = -24
local DESK_SPAWN_Z_MAX: number   =   0
local DESK_FLOOR_Y: number       =  0.5   -- half of 1-stud height
local DESK_SLIDE_TIME: number    =  2.5   -- seconds to cross the room
local DESK_SPAWN_INTERVAL: number = 1.5   -- seconds between desk spawns
local FLING_SPEED: number        = 35

popQuizFn.OnInvoke = function(duration: number): ()
	local endTime = tick() + duration

	while tick() < endTime do
		local fromLeft  = math.random() < 0.5
		local startX    = fromLeft and DESK_SLIDE_START_X or DESK_SLIDE_END_X
		local endX      = fromLeft and DESK_SLIDE_END_X   or DESK_SLIDE_START_X
		local spawnZ    = DESK_SPAWN_Z_MIN + math.random() * (DESK_SPAWN_Z_MAX - DESK_SPAWN_Z_MIN)
		local slideDir  = fromLeft and Vector3.new(1, 0, 0) or Vector3.new(-1, 0, 0)

		local flyDesk               = Instance.new("Part")
		flyDesk.Name                = "FlyingDesk"
		flyDesk.Size                = Vector3.new(4, 1, 2.5)
		flyDesk.Color               = Color3.fromRGB(106, 74, 40)
		flyDesk.Material            = Enum.Material.Wood
		flyDesk.Anchored            = true   -- must be true for TweenService to work cleanly
		flyDesk.CanCollide          = true   -- players can jump on top to dodge
		flyDesk.TopSurface          = Enum.SurfaceType.Smooth
		flyDesk.BottomSurface       = Enum.SurfaceType.Smooth
		flyDesk.CastShadow          = false
		flyDesk.Position            = Vector3.new(startX, DESK_FLOOR_Y, spawnZ)
		flyDesk.Parent              = workspace

		-- Fling any player that gets touched (debounced per player)
		local hitPlayers: { [Player]: boolean } = {}
		flyDesk.Touched:Connect(function(hit: BasePart)
			local hitChar = hit:FindFirstAncestorOfClass("Model")
			if not hitChar then return end
			local hitPlayer = Players:GetPlayerFromCharacter(hitChar)
			if not hitPlayer or hitPlayers[hitPlayer] then return end
			hitPlayers[hitPlayer] = true

			local root = hitChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				-- Fling in the desk's travel direction with a slight upward kick
				root.AssemblyLinearVelocity =
					(slideDir + Vector3.new(0, 0.45, 0)).Unit * FLING_SPEED
			end

			-- Reset debounce so a player can be hit again if they stay in the path
			task.delay(1, function()
				hitPlayers[hitPlayer] = nil
			end)
		end)

		-- Tween the desk linearly across the room
		TweenService:Create(flyDesk,
			TweenInfo.new(DESK_SLIDE_TIME, Enum.EasingStyle.Linear),
			{ Position = Vector3.new(endX, DESK_FLOOR_Y, spawnZ) }
		):Play()

		-- Destroy slightly after tween finishes so it clears the far wall area
		Debris:AddItem(flyDesk, DESK_SLIDE_TIME + 0.5)

		task.wait(DESK_SPAWN_INTERVAL)
	end
end
