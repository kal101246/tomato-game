local workspace = game:GetService("Workspace")

-- ── Container ─────────────────────────────────────────────────────────────────
local environment = Instance.new("Folder")
environment.Name   = "ClassroomEnvironment"
environment.Parent = workspace

-- ── Helper ────────────────────────────────────────────────────────────────────
type PropConfig = {
	name:       string,
	shape:      Enum.PartType,
	size:       Vector3,
	position:   Vector3,
	color:      Color3,
	material:   Enum.Material,
}

local function buildProp(cfg: PropConfig): BasePart
	local part             = Instance.new("Part")
	part.Name              = cfg.name
	part.Shape             = cfg.shape
	part.Size              = cfg.size
	part.Position          = cfg.position
	part.Color             = cfg.color
	part.Material          = cfg.material
	part.Anchored          = true
	part.CanCollide        = true
	part.TopSurface        = Enum.SurfaceType.Smooth
	part.BottomSurface     = Enum.SurfaceType.Smooth
	part.Parent            = environment
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

-- Apple sits on top of the desk surface
local deskTopY = DESK_POS.Y + desk.Size.Y / 2
local APPLE_RADIUS = 0.4

buildProp({
	name     = "Apple",
	shape    = Enum.PartType.Ball,
	size     = Vector3.new(APPLE_RADIUS * 2, APPLE_RADIUS * 2, APPLE_RADIUS * 2),
	position = Vector3.new(DESK_POS.X + 1.5, deskTopY + APPLE_RADIUS, DESK_POS.Z),
	color    = Color3.fromRGB(200, 35, 35),
	material = Enum.Material.SmoothPlastic,
})
