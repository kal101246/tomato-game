local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

-- Wait for the server-side state values to exist before building the UI
local gameTimer     = ReplicatedStorage:WaitForChild("GameTimer")     :: StringValue
local statusMessage = ReplicatedStorage:WaitForChild("StatusMessage") :: StringValue
local roundResult   = ReplicatedStorage:WaitForChild("RoundResult")   :: StringValue

-- ── Root ScreenGui ────────────────────────────────────────────────────────────
local screenGui              = Instance.new("ScreenGui")
screenGui.Name               = "MatchGui"
screenGui.ResetOnSpawn       = false
screenGui.ZIndexBehavior     = Enum.ZIndexBehavior.Sibling
screenGui.Parent             = playerGui

-- ── Top HUD Bar ───────────────────────────────────────────────────────────────
local topBar                 = Instance.new("Frame")
topBar.Name                  = "TopBar"
topBar.AnchorPoint           = Vector2.new(0.5, 0)
topBar.Position              = UDim2.new(0.5, 0, 0, 10)
topBar.Size                  = UDim2.new(0, 540, 0, 46)
topBar.BackgroundColor3      = Color3.fromRGB(12, 12, 12)
topBar.BackgroundTransparency = 0.25
topBar.BorderSizePixel       = 0
topBar.Parent                = screenGui

local topBarCorner           = Instance.new("UICorner")
topBarCorner.CornerRadius    = UDim.new(0, 10)
topBarCorner.Parent          = topBar

-- Status label (left side of bar)
local statusLabel                  = Instance.new("TextLabel")
statusLabel.Name                   = "StatusLabel"
statusLabel.AnchorPoint            = Vector2.new(0, 0.5)
statusLabel.Position               = UDim2.new(0, 14, 0.5, 0)
statusLabel.Size                   = UDim2.new(0, 352, 0.75, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Font                   = Enum.Font.GothamBold
statusLabel.TextColor3             = Color3.fromRGB(240, 240, 240)
statusLabel.TextScaled             = true
statusLabel.TextXAlignment         = Enum.TextXAlignment.Left
statusLabel.Text                   = "GET READY..."
statusLabel.Parent                 = topBar

-- Vertical divider
local divider                = Instance.new("Frame")
divider.AnchorPoint          = Vector2.new(1, 0.5)
divider.Position             = UDim2.new(1, -158, 0.5, 0)
divider.Size                 = UDim2.new(0, 2, 0.55, 0)
divider.BackgroundColor3     = Color3.fromRGB(80, 80, 80)
divider.BorderSizePixel      = 0
divider.Parent               = topBar

-- Timer label (right side of bar)
local timerLabel                   = Instance.new("TextLabel")
timerLabel.Name                    = "TimerLabel"
timerLabel.AnchorPoint             = Vector2.new(1, 0.5)
timerLabel.Position                = UDim2.new(1, -10, 0.5, 0)
timerLabel.Size                    = UDim2.new(0, 142, 0.75, 0)
timerLabel.BackgroundTransparency  = 1
timerLabel.Font                    = Enum.Font.GothamBold
timerLabel.TextColor3              = Color3.fromRGB(255, 215, 50)
timerLabel.TextScaled              = true
timerLabel.TextXAlignment          = Enum.TextXAlignment.Right
timerLabel.Text                    = "TIME: --"
timerLabel.Parent                  = topBar

-- ── Splash Frame (VICTORY / FAILED) ──────────────────────────────────────────
local splashFrame                  = Instance.new("Frame")
splashFrame.Name                   = "SplashFrame"
splashFrame.AnchorPoint            = Vector2.new(0.5, 0.5)
splashFrame.Position               = UDim2.new(0.5, 0, 0.45, 0)
splashFrame.Size                   = UDim2.new(0, 500, 0, 130)
splashFrame.BackgroundColor3       = Color3.fromRGB(10, 10, 10)
splashFrame.BackgroundTransparency = 1       -- starts invisible; tweened in
splashFrame.BorderSizePixel        = 0
splashFrame.Visible                = false
splashFrame.Parent                 = screenGui

local splashCorner                 = Instance.new("UICorner")
splashCorner.CornerRadius          = UDim.new(0, 18)
splashCorner.Parent                = splashFrame

local splashLabel                  = Instance.new("TextLabel")
splashLabel.Name                   = "SplashLabel"
splashLabel.Size                   = UDim2.new(1, 0, 1, 0)
splashLabel.BackgroundTransparency = 1
splashLabel.Font                   = Enum.Font.GothamBold
splashLabel.TextScaled             = true
splashLabel.TextTransparency       = 1       -- starts invisible; tweened in
splashLabel.Text                   = ""
splashLabel.Parent                 = splashFrame

-- ── Update functions ──────────────────────────────────────────────────────────
local function updateTimer(value: string): ()
	local n = tonumber(value)
	if n then
		timerLabel.Text = "TIME: " .. value .. "s"
		-- Flash red when 10 seconds or less remain
		timerLabel.TextColor3 = (n <= 10 and n > 0)
			and Color3.fromRGB(220, 50, 32)
			or  Color3.fromRGB(255, 215, 50)
	else
		timerLabel.Text      = "TIME: --"
		timerLabel.TextColor3 = Color3.fromRGB(255, 215, 50)
	end
end

local function updateStatus(value: string): ()
	statusLabel.Text = value
end

-- Prevents overlapping splash tweens if results fire rapidly
local splashActive = false

local function showSplash(result: string): ()
	if result == "" or splashActive then return end
	splashActive = true

	if result == "VICTORY" then
		splashLabel.Text      = "VICTORY!"
		splashLabel.TextColor3 = Color3.fromRGB(80, 220, 80)
	else
		splashLabel.Text      = "FAILED — RETRYING"
		splashLabel.TextColor3 = Color3.fromRGB(220, 70, 50)
	end

	splashFrame.BackgroundTransparency = 1
	splashLabel.TextTransparency       = 1
	splashFrame.Visible                = true

	-- Fade in
	local fadeIn = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(splashFrame, fadeIn, { BackgroundTransparency = 0.15 }):Play()
	TweenService:Create(splashLabel, fadeIn, { TextTransparency = 0 }):Play()

	-- Hold, then fade out
	task.delay(4, function()
		local fadeOut = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(splashFrame, fadeOut, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(splashLabel, fadeOut, { TextTransparency = 1 }):Play()
		task.wait(0.8)
		splashFrame.Visible = false
		splashActive        = false
	end)
end

-- ── Bind to server values ─────────────────────────────────────────────────────
gameTimer.Changed:Connect(updateTimer)
statusMessage.Changed:Connect(updateStatus)
roundResult.Changed:Connect(showSplash)

-- Seed UI with whatever the server already has when this client loads
updateTimer(gameTimer.Value)
updateStatus(statusMessage.Value)
