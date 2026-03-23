local Players = game:GetService("Players")

local function onPlayerAdded(player: Player): ()
	-- #region agent log
	print("[Leaderstats] PlayerAdded fired for: " .. player.Name)
	-- #endregion

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"   -- lowercase is required for the leaderboard to recognise it
	leaderstats.Parent = player

	local score = Instance.new("IntValue")
	score.Name = "Score"
	score.Value = 0
	score.Parent = leaderstats

	-- #region agent log
	print("[Leaderstats] leaderstats + Score created for: " .. player.Name)
	-- #endregion
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- Handle players who joined before this script loaded
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
