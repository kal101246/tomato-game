local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")
local TweenService      = game:GetService("TweenService")

-- ── Remotes setup ────────────────────────────────────────────────────────────
local remotes = Instance.new("Folder")
remotes.Name   = "Remotes"
remotes.Parent = ReplicatedStorage

local throwTomato = Instance.new("RemoteEvent")
throwTomato.Name   = "ThrowTomato"
throwTomato.Parent = remotes

-- Fires to the hitting player's client so the tween runs at full framerate
local showFloatingText = Instance.new("RemoteEvent")
showFloatingText.Name   = "ShowFloatingText"
showFloatingText.Parent = remotes

-- ── Config ───────────────────────────────────────────────────────────────────
local TOMATO_BASE_SPEED: number = 65    -- speed at throwPower = 1.0
local TOMATO_ARC: number        = 0.28  -- upward fraction added to throw direction
local TOMATO_SIZE: number       = 0.65
local TOMATO_LIFETIME: number   = 8     -- seconds before auto-destroy
local SPLAT_SOUND_ID: string    = "rbxassetid://876939830"
local SPLAT_DECAL_ID: string    = "rbxassetid://1319246532"

-- Server-side clamp for the power multiplier sent by the client
local MIN_THROW_POWER: number = 0.2
local MAX_THROW_POWER: number = 2.0

-- Distance thresholds for score tiers (studs)
local DIST_CLOSE: number = 20
local DIST_MID: number   = 50

-- ── Ownership map (part → { player, throw origin }) ──────────────────────────
type TomatoData = { player: Player, origin: Vector3 }
local tomatoOwners: { [BasePart]: TomatoData } = {}

-- ── Tomato factory ───────────────────────────────────────────────────────────
local function spawnTomato(origin: Vector3, direction: Vector3, owner: Player, throwPower: number): BasePart
	local tomato = Instance.new("Part")
	tomato.Name        = "Tomato"
	tomato.Shape       = Enum.PartType.Ball
	tomato.Size        = Vector3.new(TOMATO_SIZE, TOMATO_SIZE, TOMATO_SIZE)
	tomato.Color       = Color3.fromRGB(220, 50, 32)
	tomato.Material    = Enum.Material.SmoothPlastic
	tomato.CastShadow  = false
	tomato.Position    = origin
	tomato.Parent      = workspace

	local arcDir = (direction + Vector3.new(0, TOMATO_ARC, 0)).Unit
	tomato.AssemblyLinearVelocity = arcDir * (TOMATO_BASE_SPEED * throwPower)

	tomatoOwners[tomato] = { player = owner, origin = origin }

	task.delay(TOMATO_LIFETIME, function()
		if tomato.Parent then
			tomatoOwners[tomato] = nil
			tomato:Destroy()
		end
	end)

	return tomato
end

-- ── Splat sound effect ────────────────────────────────────────────────────────
local function playSplat(position: Vector3): ()
	local part = Instance.new("Part")
	part.Anchored     = true
	part.CanCollide   = false
	part.Transparency = 1
	part.Position     = position
	part.Parent       = workspace

	local sound = Instance.new("Sound")
	sound.SoundId            = SPLAT_SOUND_ID
	sound.Volume             = 3
	sound.RollOffMinDistance = 15
	sound.RollOffMaxDistance = 60
	sound.Parent             = part
	sound:Play()

	Debris:AddItem(part, 4)
end

-- ── Floating points text ──────────────────────────────────────────────────────
-- Runs on the client (via RemoteEvent) so the tween animates at full framerate.
-- This function builds the BillboardGui and drives it with TweenService locally.
local function createFloatingText(position: Vector3, points: number, isLongShot: boolean): ()
	local anchor = Instance.new("Part")
	anchor.Name         = "FloatingTextAnchor"
	anchor.Anchored     = true
	anchor.CanCollide   = false
	anchor.Transparency = 1
	anchor.Size         = Vector3.new(1, 1, 1)
	anchor.Position     = position + Vector3.new(0, 2, 0)
	anchor.Parent       = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.AlwaysOnTop = true
	billboard.Size        = UDim2.new(0, 150, 0, 50)
	billboard.Parent      = anchor

	local label = Instance.new("TextLabel")
	label.Size                 = UDim2.new(1, 0, 1, 0)
	label.Position             = UDim2.new(0, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.TextScaled           = true
	label.Font                 = Enum.Font.GothamBold
	label.TextTransparency     = 0
	label.TextStrokeTransparency = 0.4
	label.Text = isLongShot
		and ("+" .. tostring(points) .. " LONG SHOT!")
		or  ("+" .. tostring(points))
	label.TextColor3 = isLongShot
		and Color3.fromRGB(255, 215, 0)   -- gold for long shots
		or  Color3.fromRGB(50, 205, 50)   -- green for normal hits
	label.Parent = billboard

	local tweenInfo = TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- Float the anchor upward in world space
	TweenService:Create(anchor, tweenInfo, {
		Position = anchor.Position + Vector3.new(0, 5, 0),
	}):Play()

	-- Fade the label out
	TweenService:Create(label, tweenInfo, {
		TextTransparency = 1,
	}):Play()

	-- Clean up after the tween has fully completed
	Debris:AddItem(anchor, 2)
end

-- ── Hit detection ────────────────────────────────────────────────────────────
local function onTomatoTouched(tomato: BasePart, hit: BasePart): ()
	if not tomato.Parent then return end
	local data = tomatoOwners[tomato]
	if not data then return end

	local teacher = workspace:FindFirstChild("Teacher")
	if not teacher then return end

	local hitModel = hit:FindFirstAncestorOfClass("Model")
	if hitModel ~= teacher then return end

	-- Claim before any async work to block duplicate touch callbacks
	tomatoOwners[tomato] = nil

	local owner: Player        = data.player
	local throwOrigin: Vector3 = data.origin
	local hitPosition: Vector3 = tomato.Position
	tomato:Destroy()

	playSplat(hitPosition)

	-- Visual splat decal on Torso or Head (R6 and R15)
	if hit.Name == "Torso" or hit.Name == "Head" or hit.Name == "UpperTorso" then
		local decal = Instance.new("Decal")
		decal.Texture = SPLAT_DECAL_ID
		decal.Parent  = hit
		Debris:AddItem(decal, 4)
	end

	-- Distance-based scoring
	local distance: number = (hitPosition - throwOrigin).Magnitude
	local points: number

	if distance < DIST_CLOSE then
		points = 1
	elseif distance <= DIST_MID then
		points = 3
	else
		points = 5
	end

	local isLongShot = distance > DIST_MID

	print(string.format(
		"[TomatoHandler] %s hit the Teacher! Distance: %.1f studs → +%d point%s%s",
		owner.Name,
		distance,
		points,
		points == 1 and "" or "s",
		isLongShot and " (LONG SHOT!)" or ""
	))

	local leaderstats = owner:FindFirstChild("leaderstats")
	if leaderstats then
		local score = leaderstats:FindFirstChild("Score") :: IntValue
		if score then
			score.Value += points
		end
	end

	createFloatingText(hitPosition, points, isLongShot)
end

-- ── Remote handler ───────────────────────────────────────────────────────────
throwTomato.OnServerEvent:Connect(function(player: Player, targetPosition: Vector3, throwPower: number): ()
	if typeof(targetPosition) ~= "Vector3" then return end
	if typeof(throwPower) ~= "number" then return end

	throwPower = math.clamp(throwPower, MIN_THROW_POWER, MAX_THROW_POWER)

	local character = player.Character
	if not character then return end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root then return end

	local origin    = root.Position + Vector3.new(0, 1.5, 0)
	local direction = (targetPosition - origin).Unit

	local tomato = spawnTomato(origin, direction, player, throwPower)
	tomato.Touched:Connect(function(hit: BasePart)
		onTomatoTouched(tomato, hit)
	end)
end)
