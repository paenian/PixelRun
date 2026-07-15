--!strict
--[[
    LobbyUI.luau - Minimal lobby HUD overlay for Pixel Run Obby

    Now that the lobby is a physical 3D space (built by LobbyBuilder on the server),
    this module only provides a lightweight HUD overlay showing:
    - Player XP total (top-left, so they know what they can spend at the shop)
    - Hint text on first visit ("Walk through the gate to play!")

    The full portal grid, leaderboard panels, and Coming Soon UI have been replaced
    by physical 3D objects in the lobby world.

    Listens for RemoteEvents:
    - ShowLobby: shows the lobby HUD overlay
    - LevelStarted: hides the lobby HUD overlay
    - XPUpdate: updates the XP display while in lobby

    Validates: Requirements 2.2 (physical portals now handle this)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--============================================================================
-- Types
--============================================================================

export type LevelPackConfig = {
	name: string,
	displayOrder: number,
	themeId: string,
	obstacleTypes: { any },
	difficulty: { [number]: any },
	morassVisual: string,
	achievementName: string,
	musicTrack: string,
	prerequisitePack: string?,
}

export type LobbyUI = {
	init: () -> (),
	showPortals: (packs: { LevelPackConfig }) -> (),
	hide: () -> (),
}

--============================================================================
-- Module
--============================================================================

local LobbyUI = {}

--============================================================================
-- Constants
--============================================================================

local XP_COLOR = Color3.fromRGB(255, 255, 100)
local HINT_COLOR = Color3.fromRGB(200, 200, 220)
local BG_COLOR = Color3.fromRGB(0, 0, 0)
local HINT_FADE_DELAY = 8 -- seconds before hint fades out
local SETTINGS_BG = Color3.fromRGB(20, 20, 30)
local SETTINGS_ACCENT = Color3.fromRGB(80, 140, 255)
local SETTINGS_TEXT = Color3.fromRGB(220, 220, 230)

--============================================================================
-- State
--============================================================================

local screenGui: ScreenGui? = nil
local xpLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil
local settingsButton: TextButton? = nil
local settingsPanel: Frame? = nil
local isInitialized: boolean = false
local isVisible: boolean = false
local hasShownHint: boolean = false
local isSettingsOpen: boolean = false

-- Settings values (defaults)
local musicVolume: number = 50
local sfxVolume: number = 50
local screenShakeEnabled: boolean = true

--============================================================================
-- UI Construction
--============================================================================

local function createScreenGui(): ScreenGui
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local gui = Instance.new("ScreenGui")
	gui.Name = "PixelRunLobby"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	gui.Enabled = false
	gui.Parent = playerGui

	return gui
end

local function createXPDisplay(parent: ScreenGui): TextLabel
	local frame = Instance.new("Frame")
	frame.Name = "LobbyXP"
	frame.Size = UDim2.new(0, 180, 0, 40)
	frame.Position = UDim2.new(0, 10, 0, 10)
	frame.BackgroundColor3 = BG_COLOR
	frame.BackgroundTransparency = 0.5
	frame.BorderSizePixel = 0
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "XPText"
	label.Size = UDim2.new(1, -16, 1, 0)
	label.Position = UDim2.new(0, 8, 0, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = XP_COLOR
	label.TextSize = 18
	label.Font = Enum.Font.GothamBold
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "XP: 0"
	label.Parent = frame

	return label
end

local function createHintLabel(parent: ScreenGui): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "LobbyHint"
	label.Size = UDim2.new(0, 350, 0, 36)
	label.Position = UDim2.new(0.5, -175, 1, -60)
	label.BackgroundColor3 = BG_COLOR
	label.BackgroundTransparency = 0.4
	label.BorderSizePixel = 0
	label.TextColor3 = HINT_COLOR
	label.TextSize = 14
	label.Font = Enum.Font.Gotham
	label.Text = "Walk through the Tetris gate to start playing!"
	label.TextTransparency = 0
	label.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	return label
end

--============================================================================
-- Settings UI
--============================================================================

local function createSettingsButton(parent: ScreenGui): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = "SettingsButton"
	btn.Size = UDim2.new(0, 40, 0, 40)
	btn.Position = UDim2.new(1, -50, 0, 10)
	btn.BackgroundColor3 = BG_COLOR
	btn.BackgroundTransparency = 0.4
	btn.BorderSizePixel = 0
	btn.TextColor3 = SETTINGS_TEXT
	btn.TextSize = 24
	btn.Font = Enum.Font.GothamBold
	btn.Text = "\xE2\x9A\x99" -- gear icon (⚙)
	btn.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn

	return btn
end

local function createSlider(parent: Frame, name: string, labelText: string, yPos: number, initial: number, onChange: (number) -> ()): Frame
	local row = Instance.new("Frame")
	row.Name = name .. "Row"
	row.Size = UDim2.new(1, -20, 0, 50)
	row.Position = UDim2.new(0, 10, 0, yPos)
	row.BackgroundTransparency = 1
	row.Parent = parent

	-- Label
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Label"
	lbl.Size = UDim2.new(0.4, 0, 0, 20)
	lbl.Position = UDim2.new(0, 0, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = SETTINGS_TEXT
	lbl.TextSize = 14
	lbl.Font = Enum.Font.GothamBold
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = labelText
	lbl.Parent = row

	-- Value label
	local valLbl = Instance.new("TextLabel")
	valLbl.Name = "Value"
	valLbl.Size = UDim2.new(0, 40, 0, 20)
	valLbl.Position = UDim2.new(1, -40, 0, 0)
	valLbl.BackgroundTransparency = 1
	valLbl.TextColor3 = SETTINGS_ACCENT
	valLbl.TextSize = 14
	valLbl.Font = Enum.Font.GothamBold
	valLbl.Text = tostring(initial) .. "%"
	valLbl.Parent = row

	-- Slider track
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 8)
	track.Position = UDim2.new(0, 0, 0, 28)
	track.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
	track.BorderSizePixel = 0
	track.Parent = row

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 4)
	trackCorner.Parent = track

	-- Fill
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(initial / 100, 0, 1, 0)
	fill.BackgroundColor3 = SETTINGS_ACCENT
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	-- Click detection on track
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local relX = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
			local val = math.floor(relX * 100)
			fill.Size = UDim2.new(relX, 0, 1, 0)
			valLbl.Text = tostring(val) .. "%"
			onChange(val)
		end
	end)

	return row
end

local function createToggle(parent: Frame, name: string, labelText: string, yPos: number, initial: boolean, onChange: (boolean) -> ()): Frame
	local row = Instance.new("Frame")
	row.Name = name .. "Row"
	row.Size = UDim2.new(1, -20, 0, 36)
	row.Position = UDim2.new(0, 10, 0, yPos)
	row.BackgroundTransparency = 1
	row.Parent = parent

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Label"
	lbl.Size = UDim2.new(0.7, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = SETTINGS_TEXT
	lbl.TextSize = 14
	lbl.Font = Enum.Font.GothamBold
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = labelText
	lbl.Parent = row

	local toggle = Instance.new("TextButton")
	toggle.Name = "Toggle"
	toggle.Size = UDim2.new(0, 50, 0, 26)
	toggle.Position = UDim2.new(1, -50, 0.5, -13)
	toggle.BackgroundColor3 = if initial then SETTINGS_ACCENT else Color3.fromRGB(60, 60, 70)
	toggle.BorderSizePixel = 0
	toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
	toggle.TextSize = 12
	toggle.Font = Enum.Font.GothamBold
	toggle.Text = if initial then "ON" else "OFF"
	toggle.Parent = row

	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, 6)
	toggleCorner.Parent = toggle

	local state = initial
	toggle.MouseButton1Click:Connect(function()
		state = not state
		toggle.Text = if state then "ON" else "OFF"
		toggle.BackgroundColor3 = if state then SETTINGS_ACCENT else Color3.fromRGB(60, 60, 70)
		onChange(state)
	end)

	return row
end

local function createSettingsPanel(parent: ScreenGui): Frame
	local panel = Instance.new("Frame")
	panel.Name = "SettingsPanel"
	panel.Size = UDim2.new(0, 280, 0, 260)
	panel.Position = UDim2.new(1, -290, 0, 56)
	panel.BackgroundColor3 = SETTINGS_BG
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 36)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 18
	title.Font = Enum.Font.GothamBold
	title.Text = "Settings"
	title.Parent = panel

	-- Music volume slider
	createSlider(panel, "Music", "Music Volume", 40, musicVolume, function(val)
		musicVolume = val
		-- TODO: wire to SoundManager when settings persistence is added
	end)

	-- SFX volume slider
	createSlider(panel, "SFX", "SFX Volume", 100, sfxVolume, function(val)
		sfxVolume = val
	end)

	-- Screen shake toggle
	createToggle(panel, "Shake", "Screen Shake", 165, screenShakeEnabled, function(val)
		screenShakeEnabled = val
	end)

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 30, 0, 30)
	closeBtn.Position = UDim2.new(1, -36, 0, 4)
	closeBtn.BackgroundTransparency = 1
	closeBtn.TextColor3 = Color3.fromRGB(180, 180, 180)
	closeBtn.TextSize = 20
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Text = "X"
	closeBtn.Parent = panel

	closeBtn.MouseButton1Click:Connect(function()
		panel.Visible = false
		isSettingsOpen = false
	end)

	return panel
end

--============================================================================
-- Remote Event Connections
--============================================================================

local function connectRemoteEvents()
	local eventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if not eventsFolder then
		return
	end

	-- ShowLobby: show the lobby HUD when player is in lobby
	local showLobbyEvent = eventsFolder:WaitForChild("ShowLobby", 5) :: RemoteEvent?
	if showLobbyEvent then
		showLobbyEvent.OnClientEvent:Connect(function(data: any)
			if screenGui then
				screenGui.Enabled = true
				isVisible = true
			end

			-- Update XP if data includes it
			if type(data) == "table" and data.leaderboard then
				local lb = data.leaderboard
				if lb.playerValueXP and xpLabel then
					xpLabel.Text = "XP: " .. tostring(lb.playerValueXP)
				end
			end

			-- Show hint only on first lobby visit
			if not hasShownHint and hintLabel then
				hasShownHint = true
				hintLabel.TextTransparency = 0
				hintLabel.BackgroundTransparency = 0.4

				-- Fade out after delay
				task.delay(HINT_FADE_DELAY, function()
					if hintLabel then
						-- Simple fade (step-based since we don't want TweenService dependency for this)
						for i = 1, 10 do
							task.wait(0.1)
							if hintLabel then
								hintLabel.TextTransparency = i / 10
								hintLabel.BackgroundTransparency = 0.4 + (i / 10) * 0.6
							end
						end
						if hintLabel then
							hintLabel.Visible = false
						end
					end
				end)
			end
		end)
	end

	-- LevelStarted: hide lobby HUD when entering a level
	local levelStartedEvent = eventsFolder:WaitForChild("LevelStarted", 5) :: RemoteEvent?
	if levelStartedEvent then
		levelStartedEvent.OnClientEvent:Connect(function(_data: any)
			LobbyUI.hide()
		end)
	end

	-- XPUpdate: keep the lobby XP display current if visible
	local xpUpdateEvent = eventsFolder:WaitForChild("XPUpdate", 5) :: RemoteEvent?
	if xpUpdateEvent then
		xpUpdateEvent.OnClientEvent:Connect(function(data: any)
			if isVisible and xpLabel and type(data) == "table" then
				local xp = data.currentXP or 0
				xpLabel.Text = "XP: " .. tostring(math.floor(xp))
			end
		end)
	end
end

--============================================================================
-- Initialization
--============================================================================

local function initialize()
	if isInitialized then
		return
	end
	isInitialized = true

	screenGui = createScreenGui()
	xpLabel = createXPDisplay(screenGui)
	hintLabel = createHintLabel(screenGui)

	-- Settings button (always visible in lobby)
	settingsButton = createSettingsButton(screenGui)
	settingsPanel = createSettingsPanel(screenGui)

	settingsButton.MouseButton1Click:Connect(function()
		isSettingsOpen = not isSettingsOpen
		if settingsPanel then
			settingsPanel.Visible = isSettingsOpen
		end
	end)

	connectRemoteEvents()
end

--============================================================================
-- Public API
--============================================================================

--- Initialize the LobbyUI system.
function LobbyUI.init(): ()
	initialize()
end

--- Legacy compatibility: showPortals is now a no-op since portals are physical.
--- The ShowLobby RemoteEvent triggers the overlay display.
function LobbyUI.showPortals(_packs: { LevelPackConfig }): ()
	if not isInitialized then
		initialize()
	end
	if screenGui then
		screenGui.Enabled = true
		isVisible = true
	end
end

--- Hide the lobby HUD overlay.
function LobbyUI.hide(): ()
	if screenGui then
		screenGui.Enabled = false
		isVisible = false
	end
end

--============================================================================
-- Auto-initialize
--============================================================================

task.defer(initialize)

return LobbyUI
