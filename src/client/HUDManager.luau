--!strict
--[[
    HUDManager.luau - Client HUD/UI management for Pixel Run Obby

    Displays:
    - XP information (total, earned this run, cost of next power-up)
    - Level completion choice buttons (continue, next, lobby)
    - Error messages from server rejections
    - Achievement popup notification
    - Achievement list panel (toggle open/close) showing all achievements with earned/unearned status
    - Leaderboard panel (toggle open/close) with XP Rankings and Level Rankings tabs
      showing top 100 global entries and the current player's own rank

    Listens for RemoteEvents:
    - XPUpdate: updates the XP display labels
    - LevelCompleted: shows level choice UI
    - PlayerEliminated: hides level choice UI if visible
    - AchievementAwarded: updates achievement list and shows popup

    Fires RemoteFunctions:
    - RequestLeaderboard: fetches leaderboard data from server

    Fires RemoteEvents:
    - LevelChoice: when a level choice button is pressed

    Validates: Requirements 6.4, 8.7, 10.4, 10.5, 13.5
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

--============================================================================
-- Dependencies
--============================================================================

local EffectsManager = require(script.Parent.EffectsManager)

--============================================================================
-- Types
--============================================================================

export type LeaderboardEntry = {
	userId: number,
	displayName: string,
	value: number,
}

export type HUDManager = {
	updateXP: (current: number, earned: number, nextCost: number) -> (),
	showAchievement: (name: string, icon: string, duration: number) -> (),
	showLeaderboard: (entries: { LeaderboardEntry }, playerRank: number, playerValue: number?) -> (),
	showLevelChoice: () -> (),
	showError: (message: string) -> (),
}

--============================================================================
-- Module
--============================================================================

local HUDManager = {}

--============================================================================
-- Constants
--============================================================================

local ERROR_DISPLAY_DURATION = 3 -- seconds
local FADE_DURATION = 0.5 -- seconds for error fade in/out

--============================================================================
-- State
--============================================================================

local screenGui: ScreenGui? = nil
local xpFrame: Frame? = nil
local xpTotalLabel: TextLabel? = nil
local xpRunLabel: TextLabel? = nil
local xpNextLabel: TextLabel? = nil
local levelChoiceFrame: Frame? = nil
local errorLabel: TextLabel? = nil
local achievementLabel: TextLabel? = nil
local isInitialized: boolean = false
local errorTween: Tween? = nil

-- Achievement list state
local achievementToggleButton: TextButton? = nil
local achievementPanel: Frame? = nil
local achievementScrollFrame: ScrollingFrame? = nil
local isAchievementPanelOpen: boolean = false
local earnedAchievements: { [string]: boolean } = {}

-- Combo display state
local comboFrame: Frame? = nil
local comboStreakLabel: TextLabel? = nil
local comboTierLabel: TextLabel? = nil
local comboLastTierName: string? = nil

-- Leave button + confirm dialog state
local leaveButton: TextButton? = nil
local leaveConfirmFrame: Frame? = nil

-- Attempt/PB display state
local attemptPBLabel: TextLabel? = nil

-- Leaderboard state
local leaderboardToggleButton: TextButton? = nil
local leaderboardPanel: Frame? = nil
local leaderboardScrollFrame: ScrollingFrame? = nil
local leaderboardPlayerRankLabel: TextLabel? = nil
local leaderboardXPTabButton: TextButton? = nil
local leaderboardLevelTabButton: TextButton? = nil
local isLeaderboardPanelOpen: boolean = false
local currentLeaderboardTab: string = "xp" -- "xp" or "level"

-- Achievement definitions derived from known level packs
type AchievementDef = {
	name: string,
	icon: string,
}
local achievementDefinitions: { AchievementDef } = {}

-- Forward declarations for functions used in UI callbacks
local toggleAchievementPanel: () -> ()
local refreshAchievementList: () -> ()
local toggleLeaderboardPanel: () -> ()
local refreshLeaderboardData: () -> ()
local showLeaveConfirmDialog: () -> ()
local hideLeaveConfirmDialog: () -> ()

--============================================================================
-- UI Construction
--============================================================================

--- Create the root ScreenGui and parent it to PlayerGui.
local function createScreenGui(): ScreenGui
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local gui = Instance.new("ScreenGui")
	gui.Name = "PixelRunHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	return gui
end

--- Create the XP display frame (top-left corner).
local function createXPDisplay(parent: ScreenGui): (Frame, TextLabel, TextLabel, TextLabel)
	local frame = Instance.new("Frame")
	frame.Name = "XPDisplay"
	frame.Size = UDim2.new(0, 220, 0, 80)
	frame.Position = UDim2.new(0, 10, 0, 10)
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.5
	frame.BorderSizePixel = 0
	frame.Parent = parent

	-- Rounded corners
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	-- Padding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 6)
	padding.Parent = frame

	-- XP Total
	local totalLabel = Instance.new("TextLabel")
	totalLabel.Name = "XPTotal"
	totalLabel.Size = UDim2.new(1, -10, 0, 20)
	totalLabel.Position = UDim2.new(0, 0, 0, 0)
	totalLabel.BackgroundTransparency = 1
	totalLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
	totalLabel.TextSize = 16
	totalLabel.Font = Enum.Font.GothamBold
	totalLabel.TextXAlignment = Enum.TextXAlignment.Left
	totalLabel.Text = "XP: 0"
	totalLabel.Parent = frame

	-- XP Earned this run
	local runLabel = Instance.new("TextLabel")
	runLabel.Name = "XPRun"
	runLabel.Size = UDim2.new(1, -10, 0, 20)
	runLabel.Position = UDim2.new(0, 0, 0, 22)
	runLabel.BackgroundTransparency = 1
	runLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	runLabel.TextSize = 14
	runLabel.Font = Enum.Font.Gotham
	runLabel.TextXAlignment = Enum.TextXAlignment.Left
	runLabel.Text = "Run: +0"
	runLabel.Parent = frame

	-- XP needed for next power-up
	local nextLabel = Instance.new("TextLabel")
	nextLabel.Name = "XPNext"
	nextLabel.Size = UDim2.new(1, -10, 0, 20)
	nextLabel.Position = UDim2.new(0, 0, 0, 44)
	nextLabel.BackgroundTransparency = 1
	nextLabel.TextColor3 = Color3.fromRGB(200, 200, 255)
	nextLabel.TextSize = 14
	nextLabel.Font = Enum.Font.Gotham
	nextLabel.TextXAlignment = Enum.TextXAlignment.Left
	nextLabel.Text = "Next: 2000 XP"
	nextLabel.Parent = frame

	return frame, totalLabel, runLabel, nextLabel
end

--- Create the level choice overlay (centered, shown on level completion).
local function createLevelChoiceUI(parent: ScreenGui): Frame
	-- Semi-transparent overlay
	local frame = Instance.new("Frame")
	frame.Name = "LevelChoice"
	frame.Size = UDim2.new(0, 300, 0, 200)
	frame.Position = UDim2.new(0.5, -150, 0.5, -100)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = parent

	-- Rounded corners
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	-- Title label
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Position = UDim2.new(0, 0, 0, 10)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 20
	title.Font = Enum.Font.GothamBold
	title.Text = "Level Complete!"
	title.Parent = frame

	-- Button layout
	local buttonNames = { "Continue", "Next Level", "Return to Lobby" }
	local choiceValues = { "continue", "next", "lobby" }

	for i, buttonName in buttonNames do
		local button = Instance.new("TextButton")
		button.Name = "Choice_" .. choiceValues[i]
		button.Size = UDim2.new(0.8, 0, 0, 36)
		button.Position = UDim2.new(0.1, 0, 0, 50 + (i - 1) * 46)
		button.BackgroundColor3 = Color3.fromRGB(60, 60, 120)
		button.BorderSizePixel = 0
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.TextSize = 16
		button.Font = Enum.Font.GothamBold
		button.Text = buttonName
		button.Parent = frame

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = button

		-- Wire button click to fire LevelChoice RemoteEvent
		local choiceValue = choiceValues[i]
		button.MouseButton1Click:Connect(function()
			frame.Visible = false
			local eventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
			if eventsFolder then
				local levelChoiceEvent = eventsFolder:FindFirstChild("LevelChoice") :: RemoteEvent?
				if levelChoiceEvent then
					levelChoiceEvent:FireServer({ choice = choiceValue })
				end
			end
		end)
	end

	return frame
end

--- Create the error message display (top-center, fades in/out).
local function createErrorDisplay(parent: ScreenGui): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "ErrorDisplay"
	label.Size = UDim2.new(0, 400, 0, 36)
	label.Position = UDim2.new(0.5, -200, 0, 80)
	label.BackgroundColor3 = Color3.fromRGB(180, 30, 30)
	label.BackgroundTransparency = 0.3
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextSize = 16
	label.Font = Enum.Font.GothamBold
	label.TextTransparency = 1
	label.BackgroundTransparency = 1
	label.Text = ""
	label.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	return label
end

--- Create the achievement popup label (top-center, below error).
local function createAchievementDisplay(parent: ScreenGui): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "AchievementDisplay"
	label.Size = UDim2.new(0, 350, 0, 50)
	label.Position = UDim2.new(0.5, -175, 0, 130)
	label.BackgroundColor3 = Color3.fromRGB(50, 120, 50)
	label.BackgroundTransparency = 0.2
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.fromRGB(255, 255, 100)
	label.TextSize = 18
	label.Font = Enum.Font.GothamBold
	label.TextTransparency = 1
	label.BackgroundTransparency = 1
	label.Text = ""
	label.Visible = false
	label.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	return label
end

--- Create the achievement toggle button (top-right corner).
local function createAchievementToggleButton(parent: ScreenGui): TextButton
	local button = Instance.new("TextButton")
	button.Name = "AchievementToggle"
	button.Size = UDim2.new(0, 140, 0, 36)
	button.Position = UDim2.new(1, -196, 0, 10)
	button.BackgroundColor3 = Color3.fromRGB(50, 40, 80)
	button.BackgroundTransparency = 0.3
	button.BorderSizePixel = 0
	button.TextColor3 = Color3.fromRGB(255, 215, 0)
	button.TextSize = 14
	button.Font = Enum.Font.GothamBold
	button.Text = "🏆 Achievements"
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	button.MouseButton1Click:Connect(function()
		toggleAchievementPanel()
	end)

	return button
end

--- Create the achievement list panel (right side of screen, hidden by default).
local function createAchievementPanel(parent: ScreenGui): (Frame, ScrollingFrame)
	local panel = Instance.new("Frame")
	panel.Name = "AchievementPanel"
	panel.Size = UDim2.new(0, 250, 0, 300)
	panel.Position = UDim2.new(1, -260, 0, 52)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = parent

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = panel

	-- Title label
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 30)
	title.Position = UDim2.new(0, 0, 0, 6)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 16
	title.Font = Enum.Font.GothamBold
	title.Text = "Achievements"
	title.Parent = panel

	-- Separator line
	local separator = Instance.new("Frame")
	separator.Name = "Separator"
	separator.Size = UDim2.new(0.9, 0, 0, 1)
	separator.Position = UDim2.new(0.05, 0, 0, 36)
	separator.BackgroundColor3 = Color3.fromRGB(100, 100, 120)
	separator.BorderSizePixel = 0
	separator.Parent = panel

	-- Scrolling frame for achievement rows
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "AchievementList"
	scrollFrame.Size = UDim2.new(1, -10, 1, -46)
	scrollFrame.Position = UDim2.new(0, 5, 0, 42)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(150, 150, 150)
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.Parent = panel

	return panel, scrollFrame
end

--- Create the combo display frame (bottom-center, shows streak counter and tier name).
local function createComboDisplay(parent: ScreenGui): (Frame, TextLabel, TextLabel)
	local frame = Instance.new("Frame")
	frame.Name = "ComboDisplay"
	frame.Size = UDim2.new(0, 200, 0, 60)
	frame.Position = UDim2.new(0.5, -100, 1, -100)
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.6
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	-- Combo streak counter (e.g., "5x COMBO")
	local streakLabel = Instance.new("TextLabel")
	streakLabel.Name = "ComboStreak"
	streakLabel.Size = UDim2.new(1, 0, 0, 30)
	streakLabel.Position = UDim2.new(0, 0, 0, 4)
	streakLabel.BackgroundTransparency = 1
	streakLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
	streakLabel.TextSize = 22
	streakLabel.Font = Enum.Font.GothamBold
	streakLabel.Text = ""
	streakLabel.Parent = frame

	-- Tier name (e.g., "Nice!", "Great!")
	local tierLabel = Instance.new("TextLabel")
	tierLabel.Name = "ComboTier"
	tierLabel.Size = UDim2.new(1, 0, 0, 22)
	tierLabel.Position = UDim2.new(0, 0, 0, 34)
	tierLabel.BackgroundTransparency = 1
	tierLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
	tierLabel.TextSize = 16
	tierLabel.Font = Enum.Font.GothamBold
	tierLabel.Text = ""
	tierLabel.Parent = frame

	return frame, streakLabel, tierLabel
end

--- Create the leaderboard toggle button (top-right, below achievement button).
local function createLeaderboardToggleButton(parent: ScreenGui): TextButton
	local button = Instance.new("TextButton")
	button.Name = "LeaderboardToggle"
	button.Size = UDim2.new(0, 140, 0, 36)
	button.Position = UDim2.new(1, -196, 0, 52)
	button.BackgroundColor3 = Color3.fromRGB(30, 50, 80)
	button.BackgroundTransparency = 0.3
	button.BorderSizePixel = 0
	button.TextColor3 = Color3.fromRGB(100, 200, 255)
	button.TextSize = 14
	button.Font = Enum.Font.GothamBold
	button.Text = "\xF0\x9F\x93\x8A Leaderboard"
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	button.MouseButton1Click:Connect(function()
		toggleLeaderboardPanel()
	end)

	return button
end

--- Create the leaderboard panel (right side of screen, hidden by default).
local function createLeaderboardPanel(parent: ScreenGui): (Frame, ScrollingFrame, TextLabel, TextButton, TextButton)
	local panel = Instance.new("Frame")
	panel.Name = "LeaderboardPanel"
	panel.Size = UDim2.new(0, 280, 0, 380)
	panel.Position = UDim2.new(1, -290, 0, 94)
	panel.BackgroundColor3 = Color3.fromRGB(15, 20, 40)
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = parent

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = panel

	-- Tab buttons container
	local tabFrame = Instance.new("Frame")
	tabFrame.Name = "TabFrame"
	tabFrame.Size = UDim2.new(1, -10, 0, 32)
	tabFrame.Position = UDim2.new(0, 5, 0, 6)
	tabFrame.BackgroundTransparency = 1
	tabFrame.BorderSizePixel = 0
	tabFrame.Parent = panel

	-- XP Rankings tab button
	local xpTab = Instance.new("TextButton")
	xpTab.Name = "XPTab"
	xpTab.Size = UDim2.new(0.48, 0, 1, 0)
	xpTab.Position = UDim2.new(0, 0, 0, 0)
	xpTab.BackgroundColor3 = Color3.fromRGB(60, 80, 140)
	xpTab.BorderSizePixel = 0
	xpTab.TextColor3 = Color3.fromRGB(255, 255, 255)
	xpTab.TextSize = 13
	xpTab.Font = Enum.Font.GothamBold
	xpTab.Text = "XP Rankings"
	xpTab.Parent = tabFrame

	local xpTabCorner = Instance.new("UICorner")
	xpTabCorner.CornerRadius = UDim.new(0, 6)
	xpTabCorner.Parent = xpTab

	-- Level Rankings tab button
	local levelTab = Instance.new("TextButton")
	levelTab.Name = "LevelTab"
	levelTab.Size = UDim2.new(0.48, 0, 1, 0)
	levelTab.Position = UDim2.new(0.52, 0, 0, 0)
	levelTab.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
	levelTab.BorderSizePixel = 0
	levelTab.TextColor3 = Color3.fromRGB(180, 180, 180)
	levelTab.TextSize = 13
	levelTab.Font = Enum.Font.GothamBold
	levelTab.Text = "Level Rankings"
	levelTab.Parent = tabFrame

	local levelTabCorner = Instance.new("UICorner")
	levelTabCorner.CornerRadius = UDim.new(0, 6)
	levelTabCorner.Parent = levelTab

	-- Separator below tabs
	local separator = Instance.new("Frame")
	separator.Name = "Separator"
	separator.Size = UDim2.new(0.9, 0, 0, 1)
	separator.Position = UDim2.new(0.05, 0, 0, 42)
	separator.BackgroundColor3 = Color3.fromRGB(80, 80, 120)
	separator.BorderSizePixel = 0
	separator.Parent = panel

	-- Scrolling frame for leaderboard entries
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "LeaderboardList"
	scrollFrame.Size = UDim2.new(1, -10, 1, -100)
	scrollFrame.Position = UDim2.new(0, 5, 0, 48)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(150, 150, 150)
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.Parent = panel

	-- Bottom separator above player rank
	local bottomSeparator = Instance.new("Frame")
	bottomSeparator.Name = "BottomSeparator"
	bottomSeparator.Size = UDim2.new(0.9, 0, 0, 1)
	bottomSeparator.Position = UDim2.new(0.05, 0, 1, -50)
	bottomSeparator.BackgroundColor3 = Color3.fromRGB(80, 80, 120)
	bottomSeparator.BorderSizePixel = 0
	bottomSeparator.Parent = panel

	-- Player's own rank label (always visible at bottom)
	local playerRankLabel = Instance.new("TextLabel")
	playerRankLabel.Name = "PlayerRank"
	playerRankLabel.Size = UDim2.new(1, -10, 0, 40)
	playerRankLabel.Position = UDim2.new(0, 5, 1, -45)
	playerRankLabel.BackgroundTransparency = 1
	playerRankLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	playerRankLabel.TextSize = 14
	playerRankLabel.Font = Enum.Font.GothamBold
	playerRankLabel.TextXAlignment = Enum.TextXAlignment.Center
	playerRankLabel.Text = "Your rank: -- (Score: 0)"
	playerRankLabel.Parent = panel

	-- Wire tab button clicks
	xpTab.MouseButton1Click:Connect(function()
		currentLeaderboardTab = "xp"
		xpTab.BackgroundColor3 = Color3.fromRGB(60, 80, 140)
		xpTab.TextColor3 = Color3.fromRGB(255, 255, 255)
		levelTab.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
		levelTab.TextColor3 = Color3.fromRGB(180, 180, 180)
		refreshLeaderboardData()
	end)

	levelTab.MouseButton1Click:Connect(function()
		currentLeaderboardTab = "level"
		levelTab.BackgroundColor3 = Color3.fromRGB(60, 80, 140)
		levelTab.TextColor3 = Color3.fromRGB(255, 255, 255)
		xpTab.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
		xpTab.TextColor3 = Color3.fromRGB(180, 180, 180)
		refreshLeaderboardData()
	end)

	return panel, scrollFrame, playerRankLabel, xpTab, levelTab
end

--============================================================================
-- Attempt / Personal Best Display
--============================================================================

--- Create the attempt/PB text label (top-center, hidden by default).
--- Displays "Attempt #N | PB: X blocks" briefly on level start.
local function createAttemptPBDisplay(parent: ScreenGui): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "AttemptPBDisplay"
	label.Size = UDim2.new(0, 320, 0, 32)
	label.Position = UDim2.new(0.5, -160, 0, 44)
	label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	label.BackgroundTransparency = 0.6
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.fromRGB(220, 220, 255)
	label.TextSize = 15
	label.Font = Enum.Font.GothamBold
	label.Text = ""
	label.TextTransparency = 1
	label.BackgroundTransparency = 1
	label.Visible = false
	label.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	return label
end

--- Show the attempt count and personal best briefly, then fade out after 3 seconds.
--- @param attemptCount number - The current attempt number for this level
--- @param personalBest number - The player's best distance in blocks for this level
local function showAttemptPB(attemptCount: number, personalBest: number)
	if not attemptPBLabel then
		return
	end

	-- Build display text
	local text = "Attempt #" .. tostring(attemptCount)
	if personalBest > 0 then
		text = text .. "  |  PB: " .. tostring(personalBest) .. " blocks"
	end

	attemptPBLabel.Text = text
	attemptPBLabel.Visible = true
	attemptPBLabel.TextTransparency = 0
	attemptPBLabel.BackgroundTransparency = 0.6

	-- Fade out after 3 seconds
	task.delay(3, function()
		if attemptPBLabel then
			local fadeInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local fadeTween = TweenService:Create(attemptPBLabel, fadeInfo, {
				TextTransparency = 1,
				BackgroundTransparency = 1,
			})
			fadeTween:Play()
			fadeTween.Completed:Connect(function()
				if attemptPBLabel then
					attemptPBLabel.Visible = false
				end
			end)
		end
	end)
end

--============================================================================
-- Leave Button & Confirm Dialog
--============================================================================

--- Create a small "Leave" button (bottom-left, semi-transparent).
--- Visible during active gameplay. Pressing it opens the confirm dialog.
local function createLeaveButton(parent: ScreenGui): TextButton
	local button = Instance.new("TextButton")
	button.Name = "LeaveButton"
	button.Size = UDim2.new(0, 80, 0, 30)
	button.Position = UDim2.new(0, 10, 1, -44)
	button.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
	button.BackgroundTransparency = 0.5
	button.BorderSizePixel = 0
	button.TextColor3 = Color3.fromRGB(255, 200, 200)
	button.TextSize = 13
	button.Font = Enum.Font.GothamBold
	button.Text = "Leave"
	button.Visible = false -- shown when gameplay HUD is active
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	button.MouseButton1Click:Connect(function()
		showLeaveConfirmDialog()
	end)

	return button
end

--- Create a confirmation dialog for returning to lobby.
--- "Return to lobby? XP earned will be kept."
local function createLeaveConfirmDialog(parent: ScreenGui): Frame
	local frame = Instance.new("Frame")
	frame.Name = "LeaveConfirmDialog"
	frame.Size = UDim2.new(0, 300, 0, 140)
	frame.Position = UDim2.new(0.5, -150, 0.5, -70)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = 50
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	-- Message label
	local messageLabel = Instance.new("TextLabel")
	messageLabel.Name = "Message"
	messageLabel.Size = UDim2.new(1, -20, 0, 60)
	messageLabel.Position = UDim2.new(0, 10, 0, 14)
	messageLabel.BackgroundTransparency = 1
	messageLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	messageLabel.TextSize = 16
	messageLabel.Font = Enum.Font.GothamBold
	messageLabel.TextWrapped = true
	messageLabel.Text = "Return to lobby? XP earned will be kept."
	messageLabel.ZIndex = 51
	messageLabel.Parent = frame

	-- Confirm button
	local confirmButton = Instance.new("TextButton")
	confirmButton.Name = "ConfirmButton"
	confirmButton.Size = UDim2.new(0, 120, 0, 34)
	confirmButton.Position = UDim2.new(0.5, -130, 1, -48)
	confirmButton.BackgroundColor3 = Color3.fromRGB(50, 120, 50)
	confirmButton.BorderSizePixel = 0
	confirmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	confirmButton.TextSize = 14
	confirmButton.Font = Enum.Font.GothamBold
	confirmButton.Text = "Return to Lobby"
	confirmButton.ZIndex = 51
	confirmButton.Parent = frame

	local confirmCorner = Instance.new("UICorner")
	confirmCorner.CornerRadius = UDim.new(0, 6)
	confirmCorner.Parent = confirmButton

	-- Cancel button
	local cancelButton = Instance.new("TextButton")
	cancelButton.Name = "CancelButton"
	cancelButton.Size = UDim2.new(0, 90, 0, 34)
	cancelButton.Position = UDim2.new(0.5, 16, 1, -48)
	cancelButton.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
	cancelButton.BorderSizePixel = 0
	cancelButton.TextColor3 = Color3.fromRGB(255, 200, 200)
	cancelButton.TextSize = 14
	cancelButton.Font = Enum.Font.GothamBold
	cancelButton.Text = "Cancel"
	cancelButton.ZIndex = 51
	cancelButton.Parent = frame

	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 6)
	cancelCorner.Parent = cancelButton

	-- Wire confirm: fire LevelChoice("lobby") and hide dialog
	confirmButton.MouseButton1Click:Connect(function()
		frame.Visible = false
		local eventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
		if eventsFolder then
			local levelChoiceEvent = eventsFolder:FindFirstChild("LevelChoice") :: RemoteEvent?
			if levelChoiceEvent then
				levelChoiceEvent:FireServer({ choice = "lobby" })
			end
		end
	end)

	-- Wire cancel: just hide the dialog
	cancelButton.MouseButton1Click:Connect(function()
		frame.Visible = false
	end)

	return frame
end

--- Show the leave confirmation dialog.
showLeaveConfirmDialog = function()
	if leaveConfirmFrame then
		leaveConfirmFrame.Visible = true
	end
end

--- Hide the leave confirmation dialog.
hideLeaveConfirmDialog = function()
	if leaveConfirmFrame then
		leaveConfirmFrame.Visible = false
	end
end

--============================================================================
-- Helper Functions
--============================================================================

--- Load achievement definitions from level pack configs in ReplicatedStorage.
local function loadAchievementDefinitions()
	achievementDefinitions = {}

	local levelPacks = ReplicatedStorage:FindFirstChild("LevelPacks")
	if levelPacks then
		for _, child in levelPacks:GetChildren() do
			if child:IsA("ModuleScript") then
				local success, config = pcall(function()
					return require(child)
				end)
				if success and type(config) == "table" and config.achievementName then
					-- Use a themed icon based on pack display order
					local icon = "🏆"
					if config.themeId == "tetris" then
						icon = "🟦"
					end
					table.insert(achievementDefinitions, {
						name = config.achievementName,
						icon = icon,
					})
				end
			end
		end
	end

	-- Fallback: ensure at least the known Tetris pack achievement is present
	if #achievementDefinitions == 0 then
		table.insert(achievementDefinitions, {
			name = "Tetris Master",
			icon = "🟦",
		})
	end

	-- Sort by name for consistent display
	table.sort(achievementDefinitions, function(a, b)
		return a.name < b.name
	end)
end

--- Update the achievement list rows to reflect current earned status.
refreshAchievementList = function()
	if not achievementScrollFrame then
		return
	end

	-- Clear existing rows
	for _, child in achievementScrollFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local ROW_HEIGHT = 36
	local ROW_PADDING = 4

	for i, def in achievementDefinitions do
		local isEarned = earnedAchievements[def.name] == true

		local row = Instance.new("Frame")
		row.Name = "Achievement_" .. tostring(i)
		row.Size = UDim2.new(1, -10, 0, ROW_HEIGHT)
		row.Position = UDim2.new(0, 5, 0, (i - 1) * (ROW_HEIGHT + ROW_PADDING))
		row.BackgroundColor3 = if isEarned then Color3.fromRGB(40, 60, 40) else Color3.fromRGB(30, 30, 40)
		row.BackgroundTransparency = 0.3
		row.BorderSizePixel = 0
		row.Parent = achievementScrollFrame

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 4)
		rowCorner.Parent = row

		-- Icon
		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "Icon"
		iconLabel.Size = UDim2.new(0, 30, 1, 0)
		iconLabel.Position = UDim2.new(0, 4, 0, 0)
		iconLabel.BackgroundTransparency = 1
		iconLabel.TextSize = 18
		iconLabel.Font = Enum.Font.Gotham
		iconLabel.Text = if isEarned then def.icon else "⚪"
		iconLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		iconLabel.Parent = row

		-- Achievement name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "AchievementName"
		nameLabel.Size = UDim2.new(1, -80, 1, 0)
		nameLabel.Position = UDim2.new(0, 36, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextSize = 14
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Text = def.name
		nameLabel.TextColor3 = if isEarned then Color3.fromRGB(255, 215, 0) else Color3.fromRGB(150, 150, 150)
		nameLabel.Parent = row

		-- Status indicator
		local statusLabel = Instance.new("TextLabel")
		statusLabel.Name = "Status"
		statusLabel.Size = UDim2.new(0, 30, 1, 0)
		statusLabel.Position = UDim2.new(1, -34, 0, 0)
		statusLabel.BackgroundTransparency = 1
		statusLabel.TextSize = 18
		statusLabel.Font = Enum.Font.GothamBold
		statusLabel.Text = if isEarned then "✓" else "✗"
		statusLabel.TextColor3 = if isEarned then Color3.fromRGB(100, 255, 100) else Color3.fromRGB(100, 100, 100)
		statusLabel.Parent = row
	end

	-- Update canvas size for scrolling
	local totalHeight = #achievementDefinitions * (ROW_HEIGHT + ROW_PADDING)
	achievementScrollFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
end

--- Toggle the achievement panel open/closed.
toggleAchievementPanel = function()
	if not achievementPanel then
		return
	end

	isAchievementPanelOpen = not isAchievementPanelOpen
	achievementPanel.Visible = isAchievementPanelOpen

	if isAchievementPanelOpen then
		refreshAchievementList()
	end
end

--- Request leaderboard data from the server and render it.
refreshLeaderboardData = function()
	if not leaderboardScrollFrame or not leaderboardPlayerRankLabel then
		return
	end

	-- Request data from server via RemoteFunction
	local eventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not eventsFolder then
		if leaderboardPlayerRankLabel then
			leaderboardPlayerRankLabel.Text = "Leaderboard temporarily unavailable"
			leaderboardPlayerRankLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		end
		return
	end

	local requestFunc = eventsFolder:FindFirstChild("RequestLeaderboard") :: RemoteFunction?
	if not requestFunc then
		if leaderboardPlayerRankLabel then
			leaderboardPlayerRankLabel.Text = "Leaderboard temporarily unavailable"
			leaderboardPlayerRankLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		end
		return
	end

	-- Call server for leaderboard data
	local success, result = pcall(function()
		return requestFunc:InvokeServer({ board = currentLeaderboardTab })
	end)

	if not success or type(result) ~= "table" then
		if leaderboardPlayerRankLabel then
			leaderboardPlayerRankLabel.Text = "Leaderboard temporarily unavailable"
			leaderboardPlayerRankLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		end
		return
	end

	local entries = result.entries or {}
	local playerRank = result.playerRank or 0
	local playerValue = result.playerValue or 0

	-- Render entries
	HUDManager.showLeaderboard(entries, playerRank, playerValue)
end

--- Toggle the leaderboard panel open/closed.
toggleLeaderboardPanel = function()
	if not leaderboardPanel then
		return
	end

	isLeaderboardPanelOpen = not isLeaderboardPanelOpen
	leaderboardPanel.Visible = isLeaderboardPanelOpen

	-- Close achievement panel if leaderboard is opened (avoid overlap)
	if isLeaderboardPanelOpen and isAchievementPanelOpen then
		isAchievementPanelOpen = false
		if achievementPanel then
			achievementPanel.Visible = false
		end
	end

	if isLeaderboardPanelOpen then
		refreshLeaderboardData()
	end
end

--- Play a screen flash and floating text effect when the combo tier changes.
--- @param tierName string - The new tier name to display
local function playComboTierUpEffect(tierName: string)
	-- Get the ScreenGui for the flash overlay
	if not screenGui then
		return
	end

	-- Create a brief full-screen flash (white, fades out quickly)
	local flash = Instance.new("Frame")
	flash.Name = "ComboFlash"
	flash.Size = UDim2.new(1, 0, 1, 0)
	flash.Position = UDim2.new(0, 0, 0, 0)
	flash.BackgroundColor3 = Color3.fromRGB(255, 255, 200)
	flash.BackgroundTransparency = 0.6
	flash.BorderSizePixel = 0
	flash.ZIndex = 100
	flash.Parent = screenGui

	-- Fade out the flash quickly
	task.spawn(function()
		local elapsed = 0
		local flashDuration = 0.3
		local step = 0.02
		while elapsed < flashDuration do
			elapsed += step
			flash.BackgroundTransparency = 0.6 + (elapsed / flashDuration) * 0.4
			task.wait(step)
		end
		flash:Destroy()
	end)

	-- Show floating tier-up text in the center of the screen
	local tierUpLabel = Instance.new("TextLabel")
	tierUpLabel.Name = "TierUpText"
	tierUpLabel.Size = UDim2.new(0, 300, 0, 50)
	tierUpLabel.Position = UDim2.new(0.5, -150, 0.4, 0)
	tierUpLabel.BackgroundTransparency = 1
	tierUpLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	tierUpLabel.TextStrokeTransparency = 0.3
	tierUpLabel.TextStrokeColor3 = Color3.fromRGB(100, 50, 0)
	tierUpLabel.TextSize = 32
	tierUpLabel.Font = Enum.Font.GothamBold
	tierUpLabel.Text = tierName
	tierUpLabel.ZIndex = 101
	tierUpLabel.Parent = screenGui

	-- Float upward and fade out over 1.5 seconds
	task.spawn(function()
		local elapsed = 0
		local floatDuration = 1.5
		local step = 0.03
		while elapsed < floatDuration do
			elapsed += step
			local progress = elapsed / floatDuration
			tierUpLabel.Position = UDim2.new(0.5, -150, 0.4 - (progress * 0.1), 0)
			tierUpLabel.TextTransparency = progress
			tierUpLabel.TextStrokeTransparency = 0.3 + (progress * 0.7)
			task.wait(step)
		end
		tierUpLabel:Destroy()
	end)
end

--- Calculate the cost of the next cheapest available power-up based on current XP and owned tiers.
--- For the HUD, we show the minimum cost of any next tier the player can buy.
local function getNextPowerUpCost(_currentXP: number): number
	-- Attempt to get PowerUpManager from ReplicatedStorage
	local success, PowerUpManager = pcall(function()
		return require(ReplicatedStorage:FindFirstChild("PowerUpManager") :: ModuleScript)
	end)

	if not success or not PowerUpManager then
		return 2000 -- Default fallback: cheapest tier 1 cost
	end

	-- For now, return the cheapest available cost from definitions
	-- Full integration with player profile data will come in later epochs
	local definitions = PowerUpManager.getDefinitions()
	local minCost = math.huge

	for _, def in definitions do
		-- Show the tier 1 cost as default (full player data integration comes later)
		if def.costs and #def.costs > 0 then
			if def.costs[1] < minCost then
				minCost = def.costs[1]
			end
		end
	end

	if minCost == math.huge then
		return 2000 -- Fallback
	end

	return minCost
end

--============================================================================
-- Initialization
--============================================================================

--- Initialize all UI elements and connect RemoteEvent listeners.
local function initialize()
	if isInitialized then
		return
	end
	isInitialized = true

	-- Create the root ScreenGui
	screenGui = createScreenGui()

	-- Load achievement definitions from level packs
	loadAchievementDefinitions()

	-- Create UI components
	xpFrame, xpTotalLabel, xpRunLabel, xpNextLabel = createXPDisplay(screenGui)
	levelChoiceFrame = createLevelChoiceUI(screenGui)
	errorLabel = createErrorDisplay(screenGui)
	achievementLabel = createAchievementDisplay(screenGui)

	-- Create achievement list UI
	achievementToggleButton = createAchievementToggleButton(screenGui)
	achievementPanel, achievementScrollFrame = createAchievementPanel(screenGui)

	-- Create combo display
	comboFrame, comboStreakLabel, comboTierLabel = createComboDisplay(screenGui)

	-- Create leaderboard UI
	leaderboardToggleButton = createLeaderboardToggleButton(screenGui)
	leaderboardPanel, leaderboardScrollFrame, leaderboardPlayerRankLabel, leaderboardXPTabButton, leaderboardLevelTabButton = createLeaderboardPanel(screenGui)

	-- Create leave button and confirm dialog
	leaveButton = createLeaveButton(screenGui)
	leaveConfirmFrame = createLeaveConfirmDialog(screenGui)

	-- Create attempt/PB display
	attemptPBLabel = createAttemptPBDisplay(screenGui)

	-- Connect RemoteEvent listeners
	local eventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if eventsFolder then
		-- XPUpdate: server periodically sends XP state
		local xpUpdateEvent = eventsFolder:WaitForChild("XPUpdate", 5) :: RemoteEvent?
		if xpUpdateEvent then
			xpUpdateEvent.OnClientEvent:Connect(function(data: any)
				if type(data) == "table" then
					local current = data.currentXP or 0
					local earned = data.runXP or 0
					-- Calculate next cost from PowerUpManager
					local nextCost = getNextPowerUpCost(current)
					HUDManager.updateXP(current, earned, nextCost)
				end
			end)
		end

		-- LevelCompleted: server signals level completion
		local levelCompletedEvent = eventsFolder:WaitForChild("LevelCompleted", 5) :: RemoteEvent?
		if levelCompletedEvent then
			levelCompletedEvent.OnClientEvent:Connect(function(_data: any)
				HUDManager.showLevelChoice()
				-- Hide leave button during level complete screen
				if leaveButton then
					leaveButton.Visible = false
				end
				-- Hide leave confirm dialog if open
				hideLeaveConfirmDialog()
			end)
		end

		-- LevelStarted: show gameplay HUD elements including leave button and attempt/PB
		local levelStartedEvent = eventsFolder:WaitForChild("LevelStarted", 5) :: RemoteEvent?
		if levelStartedEvent then
			levelStartedEvent.OnClientEvent:Connect(function(data: any)
				if leaveButton then
					leaveButton.Visible = true
				end
				-- Show attempt count and personal best
				if type(data) == "table" then
					local attemptCount = data.attemptCount or 1
					local personalBest = data.personalBest or 0
					showAttemptPB(attemptCount, personalBest)
				end
			end)
		end

		-- PlayerEliminated: hide level choice if visible on death
		local eliminatedEvent = eventsFolder:WaitForChild("PlayerEliminated", 5) :: RemoteEvent?
		if eliminatedEvent then
			eliminatedEvent.OnClientEvent:Connect(function(_data: any)
				if levelChoiceFrame then
					levelChoiceFrame.Visible = false
				end
				-- Hide leave confirm dialog if open
				hideLeaveConfirmDialog()
			end)
		end

		-- AchievementAwarded: update achievement list and trigger effects + HUD display
		local achievementEvent = eventsFolder:WaitForChild("AchievementAwarded", 5) :: RemoteEvent?
		if achievementEvent then
			achievementEvent.OnClientEvent:Connect(function(data: any)
				if type(data) == "table" then
					local name = data.name or "Unknown"
					local icon = data.icon or "🏆"
					local duration = data.duration or 4

					-- Mark achievement as earned in local state
					earnedAchievements[name] = true

					-- Refresh the achievement list if panel is open
					if isAchievementPanelOpen then
						refreshAchievementList()
					end

					-- Trigger EffectsManager particle explosion + floating text
					EffectsManager.playAchievement(name, duration)

					-- Show HUD achievement popup
					HUDManager.showAchievement(name, icon, duration)
				end
			end)
		end

		-- ServerError: server sends validation/rate-limit error messages
		local serverErrorEvent = eventsFolder:WaitForChild("ServerError", 5) :: RemoteEvent?
		if serverErrorEvent then
			serverErrorEvent.OnClientEvent:Connect(function(data: any)
				if type(data) == "table" and type(data.message) == "string" then
					HUDManager.showError(data.message)
				end
			end)
		end

		-- ComboUpdate: server sends combo state changes
		local comboUpdateEvent = eventsFolder:WaitForChild("ComboUpdate", 5) :: RemoteEvent?
		if comboUpdateEvent then
			comboUpdateEvent.OnClientEvent:Connect(function(data: any)
				if type(data) == "table" then
					HUDManager.updateCombo(data.streak or 0, data.multiplier or 1.0, data.tierName, data.tierChanged)
				end
			end)
		end

		-- ShowLobby: hide gameplay HUD elements when returning to lobby
		local showLobbyEvent = eventsFolder:WaitForChild("ShowLobby", 5) :: RemoteEvent?
		if showLobbyEvent then
			showLobbyEvent.OnClientEvent:Connect(function(_data: any)
				if leaveButton then
					leaveButton.Visible = false
				end
				hideLeaveConfirmDialog()
			end)
		end
	end
end

--============================================================================
-- Public API
--============================================================================

--- Update the XP display with current values.
--- @param current number - Player's total accumulated XP
--- @param earned number - XP earned during this run
--- @param nextCost number - XP cost of the next cheapest available power-up
function HUDManager.updateXP(current: number, earned: number, nextCost: number): ()
	if not isInitialized then
		initialize()
	end

	if xpTotalLabel then
		xpTotalLabel.Text = "XP: " .. tostring(math.floor(current))
	end
	if xpRunLabel then
		xpRunLabel.Text = "Run: +" .. tostring(math.floor(earned))
	end
	if xpNextLabel then
		xpNextLabel.Text = "Next: " .. tostring(math.floor(nextCost)) .. " XP"
	end
end

--- Update the combo display with current combo state.
--- Shows/hides the combo counter and plays tier-up effects.
--- @param streak number - Current consecutive near-miss count
--- @param multiplier number - Current XP multiplier
--- @param tierName string? - Current tier display name (nil if below threshold)
--- @param tierChanged boolean? - Whether the tier just changed (triggers effects)
function HUDManager.updateCombo(streak: number, multiplier: number, tierName: string?, tierChanged: boolean?): ()
	if not isInitialized then
		initialize()
	end

	if not comboFrame or not comboStreakLabel or not comboTierLabel then
		return
	end

	if streak <= 0 then
		-- Hide combo display
		comboFrame.Visible = false
		comboStreakLabel.Text = ""
		comboTierLabel.Text = ""
		comboLastTierName = nil
		return
	end

	-- Show combo display
	comboFrame.Visible = true
	comboStreakLabel.Text = tostring(streak) .. "x COMBO"
	comboTierLabel.Text = tierName or ""

	-- Adjust combo streak label color based on multiplier
	if multiplier >= 5.0 then
		comboStreakLabel.TextColor3 = Color3.fromRGB(255, 50, 50) -- Red for Unstoppable
	elseif multiplier >= 3.0 then
		comboStreakLabel.TextColor3 = Color3.fromRGB(255, 100, 255) -- Purple for Amazing
	elseif multiplier >= 2.0 then
		comboStreakLabel.TextColor3 = Color3.fromRGB(100, 200, 255) -- Blue for Great
	elseif multiplier >= 1.5 then
		comboStreakLabel.TextColor3 = Color3.fromRGB(255, 200, 50) -- Gold for Nice
	else
		comboStreakLabel.TextColor3 = Color3.fromRGB(255, 255, 255) -- White below tier
	end

	-- Play tier-up effect if tier just changed
	if tierChanged and tierName then
		playComboTierUpEffect(tierName)
	end
end

--- Show an achievement notification (basic stub popup for Epoch 3).
--- @param name string - Achievement name to display
--- @param _icon string - Icon identifier (unused in stub)
--- @param duration number - How long to show the popup
function HUDManager.showAchievement(name: string, _icon: string, duration: number): ()
	if not isInitialized then
		initialize()
	end

	if not achievementLabel then
		return
	end

	achievementLabel.Text = "🏆 Achievement: " .. name
	achievementLabel.Visible = true
	achievementLabel.TextTransparency = 0
	achievementLabel.BackgroundTransparency = 0.2

	-- Fade out after duration
	task.delay(duration, function()
		if achievementLabel then
			local tweenInfo = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local tween = TweenService:Create(achievementLabel, tweenInfo, {
				TextTransparency = 1,
				BackgroundTransparency = 1,
			})
			tween:Play()
			tween.Completed:Connect(function()
				if achievementLabel then
					achievementLabel.Visible = false
				end
			end)
		end
	end)
end

--- Render leaderboard entries into the scrollable list and update player rank display.
--- @param entries {LeaderboardEntry} - Array of leaderboard entries to display
--- @param playerRank number - Current player's rank (0 if unavailable)
--- @param playerValue number? - Current player's score value
function HUDManager.showLeaderboard(entries: { LeaderboardEntry }, playerRank: number, playerValue: number?): ()
	if not isInitialized then
		initialize()
	end

	if not leaderboardScrollFrame or not leaderboardPlayerRankLabel then
		return
	end

	-- Clear existing rows
	for _, child in leaderboardScrollFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local ROW_HEIGHT = 30
	local ROW_PADDING = 2

	-- Determine score suffix based on current tab
	local scoreSuffix = if currentLeaderboardTab == "xp" then " XP" else " Lvl"

	for i, entry in entries do
		local row = Instance.new("Frame")
		row.Name = "Entry_" .. tostring(i)
		row.Size = UDim2.new(1, -6, 0, ROW_HEIGHT)
		row.Position = UDim2.new(0, 3, 0, (i - 1) * (ROW_HEIGHT + ROW_PADDING))
		row.BackgroundColor3 = if i <= 3
			then Color3.fromRGB(40, 50, 70)
			else Color3.fromRGB(25, 30, 45)
		row.BackgroundTransparency = 0.3
		row.BorderSizePixel = 0
		row.Parent = leaderboardScrollFrame

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 4)
		rowCorner.Parent = row

		-- Rank number
		local rankLabel = Instance.new("TextLabel")
		rankLabel.Name = "Rank"
		rankLabel.Size = UDim2.new(0, 30, 1, 0)
		rankLabel.Position = UDim2.new(0, 4, 0, 0)
		rankLabel.BackgroundTransparency = 1
		rankLabel.TextSize = 13
		rankLabel.Font = Enum.Font.GothamBold
		rankLabel.TextXAlignment = Enum.TextXAlignment.Center
		rankLabel.Text = "#" .. tostring(i)
		rankLabel.TextColor3 = if i == 1
			then Color3.fromRGB(255, 215, 0)
			elseif i == 2
			then Color3.fromRGB(200, 200, 200)
			elseif i == 3
			then Color3.fromRGB(205, 127, 50)
			else Color3.fromRGB(180, 180, 180)
		rankLabel.Parent = row

		-- Player name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "PlayerName"
		nameLabel.Size = UDim2.new(1, -130, 1, 0)
		nameLabel.Position = UDim2.new(0, 38, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextSize = 13
		nameLabel.Font = Enum.Font.Gotham
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Text = entry.displayName
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.Parent = row

		-- Score value
		local scoreLabel = Instance.new("TextLabel")
		scoreLabel.Name = "Score"
		scoreLabel.Size = UDim2.new(0, 85, 1, 0)
		scoreLabel.Position = UDim2.new(1, -90, 0, 0)
		scoreLabel.BackgroundTransparency = 1
		scoreLabel.TextSize = 12
		scoreLabel.Font = Enum.Font.GothamBold
		scoreLabel.TextXAlignment = Enum.TextXAlignment.Right
		scoreLabel.Text = tostring(entry.value) .. scoreSuffix
		scoreLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
		scoreLabel.Parent = row
	end

	-- Update canvas size for scrolling
	local totalHeight = #entries * (ROW_HEIGHT + ROW_PADDING)
	leaderboardScrollFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)

	-- Update player rank label at bottom
	local value = playerValue or 0
	if playerRank > 0 then
		leaderboardPlayerRankLabel.Text = "Your rank: #" .. tostring(playerRank) .. " (" .. tostring(value) .. scoreSuffix .. ")"
		leaderboardPlayerRankLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	else
		leaderboardPlayerRankLabel.Text = "Your rank: -- (Score: 0)"
		leaderboardPlayerRankLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	end
end

--- Show the level completion choice UI with continue, next level, and lobby buttons.
function HUDManager.showLevelChoice(): ()
	if not isInitialized then
		initialize()
	end

	if levelChoiceFrame then
		levelChoiceFrame.Visible = true
	end
end

--- Show an error message that fades in, displays for 3 seconds, then fades out.
--- @param message string - Error message text to display
function HUDManager.showError(message: string): ()
	if not isInitialized then
		initialize()
	end

	if not errorLabel then
		return
	end

	-- Cancel any existing error tween
	if errorTween then
		errorTween:Cancel()
		errorTween = nil
	end

	-- Set the error text and fade in
	errorLabel.Text = message
	errorLabel.TextTransparency = 1
	errorLabel.BackgroundTransparency = 1

	-- Fade in
	local fadeInInfo = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeIn = TweenService:Create(errorLabel, fadeInInfo, {
		TextTransparency = 0,
		BackgroundTransparency = 0.3,
	})
	fadeIn:Play()

	-- After display duration, fade out
	task.delay(ERROR_DISPLAY_DURATION, function()
		if errorLabel then
			local fadeOutInfo = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			local fadeOut = TweenService:Create(errorLabel, fadeOutInfo, {
				TextTransparency = 1,
				BackgroundTransparency = 1,
			})
			errorTween = fadeOut
			fadeOut:Play()
		end
	end)
end

--============================================================================
-- Auto-initialize
--============================================================================

-- Defer initialization to ensure PlayerGui and RemoteEvents are available
task.defer(initialize)

return HUDManager
