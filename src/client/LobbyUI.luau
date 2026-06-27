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

--============================================================================
-- State
--============================================================================

local screenGui: ScreenGui? = nil
local xpLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil
local isInitialized: boolean = false
local isVisible: boolean = false
local hasShownHint: boolean = false

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
