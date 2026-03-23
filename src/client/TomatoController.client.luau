local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local mouse       = localPlayer:GetMouse()
local playerGui   = localPlayer:WaitForChild("PlayerGui")

local remotes     = ReplicatedStorage:WaitForChild("Remotes")
local throwTomato = remotes:WaitForChild("ThrowTomato") :: RemoteEvent

-- ── Config ────────────────────────────────────────────────────────────────────
local MAX_CHARGE_SECS: number = 2.0
local MIN_POWER: number       = 0.2
local MAX_POWER: number       = 2.0
local THROW_COOLDOWN: number  = 0.3
local MAX_THROWS: number      = 8    -- ammo per tool

-- ── State ─────────────────────────────────────────────────────────────────────
local chargeStart: number?  = nil
local lastThrowTime: number = 0
local throwsLeft: number    = MAX_THROWS
local connectedTools: { [Tool]: { RBXScriptConnection } } = {}

-- ── ScreenGui ─────────────────────────────────────────────────────────────────
local screenGui              = Instance.new("ScreenGui")
screenGui.Name               = "PowerBarGui"
screenGui.ResetOnSpawn       = false
screenGui.ZIndexBehavior     = Enum.ZIndexBehavior.Sibling
screenGui.Enabled            = false
screenGui.Parent             = playerGui

-- Ammo label (sits just above the power bar)
local ammoLabel                    = Instance.new("TextLabel")
ammoLabel.Name                     = "AmmoLabel"
ammoLabel.AnchorPoint              = Vector2.new(0.5, 1)
ammoLabel.Position                 = UDim2.new(0.5, 0, 1, -86)
ammoLabel.Size                     = UDim2.new(0, 320, 0, 22)
ammoLabel.BackgroundTransparency   = 1
ammoLabel.Font                     = Enum.Font.GothamBold
ammoLabel.TextSize                 = 14
ammoLabel.TextColor3               = Color3.fromRGB(200, 200, 200)
ammoLabel.Text                     = "AMMO: " .. MAX_THROWS
ammoLabel.Parent                   = screenGui

-- Power bar background
local bgFrame                      = Instance.new("Frame")
bgFrame.Name                       = "PowerBarBG"
bgFrame.AnchorPoint                = Vector2.new(0.5, 1)
bgFrame.Position                   = UDim2.new(0.5, 0, 1, -50)
bgFrame.Size                       = UDim2.new(0, 320, 0, 30)
bgFrame.BackgroundColor3           = Color3.fromRGB(25, 25, 25)
bgFrame.BorderSizePixel            = 0
bgFrame.ClipsDescendants           = true
bgFrame.Parent                     = screenGui

local bgCorner                     = Instance.new("UICorner")
bgCorner.CornerRadius              = UDim.new(0, 8)
bgCorner.Parent                    = bgFrame

local bgPadding                    = Instance.new("UIPadding")
bgPadding.PaddingLeft              = UDim.new(0, 4)
bgPadding.PaddingRight             = UDim.new(0, 4)
bgPadding.PaddingTop               = UDim.new(0, 4)
bgPadding.PaddingBottom            = UDim.new(0, 4)
bgPadding.Parent                   = bgFrame

local fillFrame                    = Instance.new("Frame")
fillFrame.Name                     = "PowerFill"
fillFrame.AnchorPoint              = Vector2.new(0, 0.5)
fillFrame.Position                 = UDim2.new(0, 0, 0.5, 0)
fillFrame.Size                     = UDim2.new(0, 0, 1, 0)
fillFrame.BackgroundColor3         = Color3.fromRGB(50, 205, 32)
fillFrame.BorderSizePixel          = 0
fillFrame.Parent                   = bgFrame

local fillCorner                   = Instance.new("UICorner")
fillCorner.CornerRadius            = UDim.new(0, 5)
fillCorner.Parent                  = fillFrame

local label                        = Instance.new("TextLabel")
label.Name                         = "Label"
label.Size                         = UDim2.new(1, 0, 1, 0)
label.Position                     = UDim2.new(0, 0, 0, 0)
label.BackgroundTransparency       = 1
label.Text                         = "POWER"
label.TextColor3                   = Color3.fromRGB(255, 255, 255)
label.TextStrokeTransparency       = 0.5
label.TextSize                     = 13
label.Font                         = Enum.Font.GothamBold
label.ZIndex                       = 3
label.Parent                       = bgFrame

-- ── UI helpers ────────────────────────────────────────────────────────────────
local function setFillLevel(level: number): ()
	fillFrame.Size = UDim2.new(level, 0, 1, 0)
	local r = math.round(50  + level * 170)
	local g = math.round(205 - level * 155)
	fillFrame.BackgroundColor3 = Color3.fromRGB(r, g, 32)
end

local function updateAmmoUI(): ()
	if throwsLeft <= 0 then
		ammoLabel.TextColor3 = Color3.fromRGB(220, 50, 32)
		ammoLabel.Text = "OUT OF AMMO! REFILL AT CRATE!"
	else
		ammoLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		ammoLabel.Text = "AMMO: " .. throwsLeft
	end
end

RunService.RenderStepped:Connect(function(): ()
	if chargeStart then
		local elapsed = tick() - chargeStart
		setFillLevel(math.clamp(elapsed / MAX_CHARGE_SECS, 0, 1))
	end
end)

-- ── Charge logic ──────────────────────────────────────────────────────────────
local function onChargeStart(): ()
	if throwsLeft <= 0 then return end
	local now = tick()
	if now - lastThrowTime < THROW_COOLDOWN then return end
	if chargeStart then return end
	chargeStart = now
end

local function onChargeRelease(): ()
	if not chargeStart then return end

	local holdDuration = tick() - chargeStart
	chargeStart = nil
	setFillLevel(0)

	-- Safety: re-check ammo on release (could have depleted during the hold)
	if throwsLeft <= 0 then
		updateAmmoUI()
		return
	end

	local t: number          = math.clamp(holdDuration / MAX_CHARGE_SECS, 0, 1)
	local throwPower: number = MIN_POWER + (MAX_POWER - MIN_POWER) * t

	throwsLeft    -= 1
	lastThrowTime  = tick()
	updateAmmoUI()
	throwTomato:FireServer(mouse.Hit.Position, throwPower)
end

-- ── Tool wiring ───────────────────────────────────────────────────────────────
local function setupTool(instance: Instance): ()
	if not instance:IsA("Tool") then return end
	local tool = instance :: Tool
	if tool.Name ~= "Tomato" then return end
	if connectedTools[tool] then return end

	-- #region agent log
	print("[TomatoController] Setting up new Tomato tool instance: " .. tostring(tool))
	-- #endregion

	-- Reset ammo for the fresh tool given at round start
	throwsLeft = MAX_THROWS
	updateAmmoUI()

	local connections: { RBXScriptConnection } = {
		tool.Equipped:Connect(function()
			screenGui.Enabled = true
			-- #region agent log
			print("[TomatoController] Tomato equipped — throwsLeft: " .. throwsLeft)
			-- #endregion
		end),
		tool.Unequipped:Connect(function()
			screenGui.Enabled = false
			if chargeStart then
				chargeStart = nil
				setFillLevel(0)
			end
		end),
		tool.Activated:Connect(onChargeStart),
		tool.Deactivated:Connect(onChargeRelease),
	}

	table.insert(connections, tool.AncestryChanged:Connect(function()
		if not tool.Parent then
			if chargeStart then
				chargeStart = nil
				setFillLevel(0)
			end
			for _, conn in connectedTools[tool] or {} do
				conn:Disconnect()
			end
			connectedTools[tool] = nil
			screenGui.Enabled = false
			-- #region agent log
			print("[TomatoController] Tomato tool destroyed — connections cleaned up")
			-- #endregion
		end
	end))

	connectedTools[tool] = connections
end

-- ── Watch backpack and character ──────────────────────────────────────────────
local function watchContainer(container: Instance): ()
	for _, child in container:GetChildren() do
		setupTool(child)
	end
	container.ChildAdded:Connect(setupTool)
end

-- Backpack persists across respawns
watchContainer(localPlayer.Backpack)

if localPlayer.Character then
	watchContainer(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(function(character: Model)
	watchContainer(character)
end)

-- ── Ammo Crate ProximityPrompt ────────────────────────────────────────────────
-- The crate is created by EnvironmentBuilder at server start. We wait for it
-- to replicate, then hook into the ProximityPrompt.Triggered client-side event
-- (fires only for the local player — no RemoteEvent needed).
local function setupAmmoCrate(crate: Instance): ()
	local prompt = crate:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		-- #region agent log
		print("[TomatoController] AmmoCrate found but no ProximityPrompt child — cannot wire refill")
		-- #endregion
		return
	end

	-- #region agent log
	print("[TomatoController] Checking for refill — ProximityPrompt found on AmmoCrate")
	-- #endregion

	prompt.Triggered:Connect(function()
		-- #region agent log
		print("[TomatoController] Ammo refilled via ProximityPrompt!")
		-- #endregion
		throwsLeft = MAX_THROWS
		updateAmmoUI()
	end)
end

task.spawn(function()
	-- 30-second timeout in case Studio is slow to replicate
	local crate = workspace:WaitForChild("AmmoCrate", 30)
	if crate then
		setupAmmoCrate(crate)
	else
		-- #region agent log
		print("[TomatoController] WARNING — AmmoCrate not found in workspace after 30s")
		-- #endregion
	end
end)
