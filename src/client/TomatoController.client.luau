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
local THROW_COOLDOWN: number  = 0.3   -- minimum gap between throws (seconds)

-- ── Power Bar UI (built entirely in code) ─────────────────────────────────────
local screenGui         = Instance.new("ScreenGui")
screenGui.Name          = "PowerBarGui"
screenGui.ResetOnSpawn  = false   -- survives respawns; we manage it ourselves
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Enabled       = false   -- hidden until the Tomato tool is equipped
screenGui.Parent        = playerGui

-- Dark background bar anchored to bottom-center
local bgFrame                   = Instance.new("Frame")
bgFrame.Name                    = "PowerBarBG"
bgFrame.AnchorPoint             = Vector2.new(0.5, 1)
bgFrame.Position                = UDim2.new(0.5, 0, 1, -50)
bgFrame.Size                    = UDim2.new(0, 320, 0, 30)
bgFrame.BackgroundColor3        = Color3.fromRGB(25, 25, 25)
bgFrame.BorderSizePixel         = 0
bgFrame.ClipsDescendants        = true
bgFrame.Parent                  = screenGui

local bgCorner                  = Instance.new("UICorner")
bgCorner.CornerRadius           = UDim.new(0, 8)
bgCorner.Parent                 = bgFrame

-- 4 px inner padding so the fill never touches the edges of the bg
local bgPadding                 = Instance.new("UIPadding")
bgPadding.PaddingLeft           = UDim.new(0, 4)
bgPadding.PaddingRight          = UDim.new(0, 4)
bgPadding.PaddingTop            = UDim.new(0, 4)
bgPadding.PaddingBottom         = UDim.new(0, 4)
bgPadding.Parent                = bgFrame

-- Fill frame – Size.X.Scale goes from 0 → 1; color shifts green → red
local fillFrame                 = Instance.new("Frame")
fillFrame.Name                  = "PowerFill"
fillFrame.AnchorPoint           = Vector2.new(0, 0.5)
fillFrame.Position              = UDim2.new(0, 0, 0.5, 0)
fillFrame.Size                  = UDim2.new(0, 0, 1, 0)  -- width updated each frame
fillFrame.BackgroundColor3      = Color3.fromRGB(50, 205, 32)
fillFrame.BorderSizePixel       = 0
fillFrame.Parent                = bgFrame

local fillCorner                = Instance.new("UICorner")
fillCorner.CornerRadius         = UDim.new(0, 5)
fillCorner.Parent               = fillFrame

-- "POWER" label centred over the bar
local label                     = Instance.new("TextLabel")
label.Name                      = "Label"
label.Size                      = UDim2.new(1, 0, 1, 0)
label.Position                  = UDim2.new(0, 0, 0, 0)
label.BackgroundTransparency    = 1
label.Text                      = "POWER"
label.TextColor3                = Color3.fromRGB(255, 255, 255)
label.TextStrokeTransparency    = 0.5
label.TextSize                  = 13
label.Font                      = Enum.Font.GothamBold
label.ZIndex                    = 3
label.Parent                    = bgFrame

-- ── Charge state ──────────────────────────────────────────────────────────────
local chargeStart: number?  = nil   -- tick() when hold began, nil when not charging
local lastThrowTime: number = 0

-- connectedTools: tool → array of connections, so we can disconnect on cleanup
local connectedTools: { [Tool]: { RBXScriptConnection } } = {}

-- ── UI helpers ────────────────────────────────────────────────────────────────
local function setFillLevel(level: number): ()
	-- level: 0.0 (empty) → 1.0 (full)
	fillFrame.Size = UDim2.new(level, 0, 1, 0)

	-- Color: green (low) → orange → red (full)
	local r = math.round(50  + level * 170)  -- 50  → 220
	local g = math.round(205 - level * 155)  -- 205 → 50
	fillFrame.BackgroundColor3 = Color3.fromRGB(r, g, 32)
end

-- Drive the fill bar every render frame while charging
RunService.RenderStepped:Connect(function(): ()
	if chargeStart then
		local elapsed = tick() - chargeStart
		setFillLevel(math.clamp(elapsed / MAX_CHARGE_SECS, 0, 1))
	end
end)

-- ── Charge input ──────────────────────────────────────────────────────────────
local function onChargeStart(): ()
	local now = tick()
	if now - lastThrowTime < THROW_COOLDOWN then return end
	if chargeStart then return end  -- already charging (shouldn't happen, but guard it)
	chargeStart = now
end

local function onChargeRelease(): ()
	if not chargeStart then return end

	local holdDuration = tick() - chargeStart
	chargeStart = nil
	setFillLevel(0)

	-- Map hold time → power in [MIN_POWER, MAX_POWER]
	local t: number          = math.clamp(holdDuration / MAX_CHARGE_SECS, 0, 1)
	local throwPower: number = MIN_POWER + (MAX_POWER - MIN_POWER) * t

	lastThrowTime = tick()
	throwTomato:FireServer(mouse.Hit.Position, throwPower)
end

-- ── Tool wiring ───────────────────────────────────────────────────────────────
local function setupTool(instance: Instance): ()
	if not instance:IsA("Tool") then return end
	local tool = instance :: Tool
	if tool.Name ~= "Tomato" then return end
	if connectedTools[tool] then return end

	-- Show power bar when equipped; hide when unequipped/destroyed
	local connections: { RBXScriptConnection } = {
		tool.Equipped:Connect(function()
			screenGui.Enabled = true
		end),
		tool.Unequipped:Connect(function()
			screenGui.Enabled = false
			-- Cancel any in-progress charge
			if chargeStart then
				chargeStart = nil
				setFillLevel(0)
			end
		end),
		tool.Activated:Connect(onChargeStart),
		tool.Deactivated:Connect(onChargeRelease),
	}

	-- Cleanup when tool instance is destroyed (e.g. removed from game)
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

-- Backpack persists across respawns; character is re-scanned on each spawn
watchContainer(localPlayer.Backpack)

if localPlayer.Character then
	watchContainer(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(function(character: Model)
	watchContainer(character)
end)
