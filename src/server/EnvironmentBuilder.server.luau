local workspace      = game:GetService("Workspace")
local ServerStorage  = game:GetService("ServerStorage")

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
