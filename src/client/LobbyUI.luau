--!strict
--[[
    LobbyUI.luau - Lobby UI management for Pixel Run Obby

    Displays level pack portals radiating from center of screen.
    Each portal shows:
    - Pack name/theme
    - Difficulty rating (displayOrder value, shown as "Difficulty: X/10")
    - Completion status ("X/10 levels complete")
    - Unlocked: full opacity, clickable (fires RequestStartLevel)
    - Locked: reduced opacity (0.5), lock icon overlay, shows unlock message on click

    Listens for RemoteEvents:
    - ShowLobby: receives pack info and completion data, shows lobby UI
    - LevelStarted: hides lobby UI when entering a level

    Fires RemoteEvents:
    - RequestStartLevel: when player clicks an unlocked portal (packId, levelNum: 1)

    Validates: Requirements 2.2, 2.3, 2.4, 2.5
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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

--- Data received from server about pack status for the current player.
type PackDisplayData = {
	packId: string,
	name: string,
	displayOrder: number,
	themeId: string,
	completedLevels: number, -- Number of levels completed (0-10)
	isUnlocked: boolean,
	prerequisiteName: string?, -- Name of prerequisite pack (for lock message)
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

local PORTAL_WIDTH = 200
local PORTAL_HEIGHT = 160
local PORTAL_PADDING = 20
local COLUMNS = 3 -- Max portals per row
local UNLOCK_MESSAGE_DURATION = 3 -- seconds
local FADE_DURATION = 0.3

-- Colors
local UNLOCKED_BG = Color3.fromRGB(30, 50, 80)
local LOCKED_BG = Color3.fromRGB(40, 40, 50)
local ENTER_BUTTON_COLOR = Color3.fromRGB(40, 120, 60)
local LOCKED_BUTTON_COLOR = Color3.fromRGB(80, 80, 80)
local TITLE_COLOR = Color3.fromRGB(255, 255, 255)
local DIFFICULTY_COLOR = Color3.fromRGB(200, 200, 255)
local COMPLETION_COLOR = Color3.fromRGB(100, 255, 100)
local LOCK_COLOR = Color3.fromRGB(255, 200, 50)
local MESSAGE_BG_COLOR = Color3.fromRGB(120, 60, 20)

--============================================================================
-- State
--============================================================================

local screenGui: ScreenGui? = nil
local portalContainer: Frame? = nil
local messageLabel: TextLabel? = nil
local messageTween: Tween? = nil
local isInitialized: boolean = false
local isVisible: boolean = false

-- Forward declarations
local showUnlockMessage: (message: string) -> ()
local showPortalsFromData: (packs: { PackDisplayData }) -> ()

--============================================================================
-- UI Construction
--============================================================================

--- Create the root ScreenGui for the lobby (separate from gameplay HUD).
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

--- Create the portal container frame (centered on screen).
local function createPortalContainer(parent: ScreenGui): Frame
	local frame = Instance.new("Frame")
	frame.Name = "PortalContainer"
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.Position = UDim2.new(0, 0, 0, 0)
	frame.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.Parent = parent

	-- Title at top
	local title = Instance.new("TextLabel")
	title.Name = "LobbyTitle"
	title.Size = UDim2.new(1, 0, 0, 50)
	title.Position = UDim2.new(0, 0, 0, 20)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 28
	title.Font = Enum.Font.GothamBold
	title.Text = "PIXEL RUN OBBY"
	title.Parent = frame

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, 0, 0, 30)
	subtitle.Position = UDim2.new(0, 0, 0, 60)
	subtitle.BackgroundTransparency = 1
	subtitle.TextColor3 = Color3.fromRGB(180, 180, 200)
	subtitle.TextSize = 16
	subtitle.Font = Enum.Font.Gotham
	subtitle.Text = "Choose a Level Pack"
	subtitle.Parent = frame

	return frame
end

--- Create the unlock message label (centered, shown temporarily).
local function createMessageLabel(parent: Frame): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "UnlockMessage"
	label.Size = UDim2.new(0, 400, 0, 44)
	label.Position = UDim2.new(0.5, -200, 1, -70)
	label.BackgroundColor3 = MESSAGE_BG_COLOR
	label.BackgroundTransparency = 0.2
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextSize = 16
	label.Font = Enum.Font.GothamBold
	label.Text = ""
	label.TextTransparency = 1
	label.BackgroundTransparency = 1
	label.Visible = false
	label.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	return label
end

--- Create a single portal frame for a level pack.
local function createPortalFrame(packData: PackDisplayData, index: number, totalPacks: number, parent: Frame): Frame
	-- Calculate grid position radiating from center
	local row = math.floor((index - 1) / COLUMNS)
	local col = (index - 1) % COLUMNS
	local totalRows = math.ceil(totalPacks / COLUMNS)
	local packsInRow = math.min(COLUMNS, totalPacks - row * COLUMNS)

	-- Center the portals horizontally and vertically
	local totalWidth = packsInRow * (PORTAL_WIDTH + PORTAL_PADDING) - PORTAL_PADDING
	local totalHeight = totalRows * (PORTAL_HEIGHT + PORTAL_PADDING) - PORTAL_PADDING

	-- Use UDim2 with offset from center for better centering
	local xOffset = col * (PORTAL_WIDTH + PORTAL_PADDING) - totalWidth / 2
	local yOffset = row * (PORTAL_HEIGHT + PORTAL_PADDING) - totalHeight / 2 + 40

	local portal = Instance.new("Frame")
	portal.Name = "Portal_" .. packData.packId
	portal.Size = UDim2.new(0, PORTAL_WIDTH, 0, PORTAL_HEIGHT)
	portal.Position = UDim2.new(0.5, xOffset, 0.5, yOffset)
	portal.BackgroundColor3 = if packData.isUnlocked then UNLOCKED_BG else LOCKED_BG
	portal.BackgroundTransparency = if packData.isUnlocked then 0.1 else 0.5
	portal.BorderSizePixel = 0
	portal.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = portal

	-- Pack name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PackName"
	nameLabel.Size = UDim2.new(1, -10, 0, 28)
	nameLabel.Position = UDim2.new(0, 5, 0, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = TITLE_COLOR
	nameLabel.TextSize = 16
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = packData.name
	nameLabel.TextTransparency = if packData.isUnlocked then 0 else 0.3
	nameLabel.Parent = portal

	-- Lock icon for locked packs
	if not packData.isUnlocked then
		local lockIcon = Instance.new("TextLabel")
		lockIcon.Name = "LockIcon"
		lockIcon.Size = UDim2.new(0, 30, 0, 30)
		lockIcon.Position = UDim2.new(1, -35, 0, 5)
		lockIcon.BackgroundTransparency = 1
		lockIcon.TextColor3 = LOCK_COLOR
		lockIcon.TextSize = 22
		lockIcon.Font = Enum.Font.GothamBold
		lockIcon.Text = "🔒"
		lockIcon.Parent = portal
	end

	-- Completion status
	local completionLabel = Instance.new("TextLabel")
	completionLabel.Name = "Completion"
	completionLabel.Size = UDim2.new(1, -10, 0, 22)
	completionLabel.Position = UDim2.new(0, 5, 0, 38)
	completionLabel.BackgroundTransparency = 1
	completionLabel.TextColor3 = COMPLETION_COLOR
	completionLabel.TextSize = 14
	completionLabel.Font = Enum.Font.Gotham
	completionLabel.TextXAlignment = Enum.TextXAlignment.Left
	completionLabel.Text = tostring(packData.completedLevels) .. "/10 levels complete"
	completionLabel.TextTransparency = if packData.isUnlocked then 0 else 0.3
	completionLabel.Parent = portal

	-- Difficulty rating
	local difficultyLabel = Instance.new("TextLabel")
	difficultyLabel.Name = "Difficulty"
	difficultyLabel.Size = UDim2.new(1, -10, 0, 22)
	difficultyLabel.Position = UDim2.new(0, 5, 0, 62)
	difficultyLabel.BackgroundTransparency = 1
	difficultyLabel.TextColor3 = DIFFICULTY_COLOR
	difficultyLabel.TextSize = 14
	difficultyLabel.Font = Enum.Font.Gotham
	difficultyLabel.TextXAlignment = Enum.TextXAlignment.Left
	difficultyLabel.Text = "Difficulty: " .. tostring(packData.displayOrder) .. "/10"
	difficultyLabel.TextTransparency = if packData.isUnlocked then 0 else 0.3
	difficultyLabel.Parent = portal

	-- Action button (Enter or Locked)
	local actionButton = Instance.new("TextButton")
	actionButton.Name = "ActionButton"
	actionButton.Size = UDim2.new(0.8, 0, 0, 34)
	actionButton.Position = UDim2.new(0.1, 0, 0, PORTAL_HEIGHT - 50)
	actionButton.BorderSizePixel = 0
	actionButton.TextSize = 14
	actionButton.Font = Enum.Font.GothamBold
	actionButton.Parent = portal

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = actionButton

	if packData.isUnlocked then
		actionButton.BackgroundColor3 = ENTER_BUTTON_COLOR
		actionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		actionButton.Text = "Enter"

		-- On click: fire RequestStartLevel RemoteEvent
		actionButton.MouseButton1Click:Connect(function()
			local eventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
			if eventsFolder then
				local requestEvent = eventsFolder:FindFirstChild("RequestStartLevel") :: RemoteEvent?
				if requestEvent then
					requestEvent:FireServer({ packId = packData.packId, levelNum = 1 })
				end
			end
		end)
	else
		actionButton.BackgroundColor3 = LOCKED_BUTTON_COLOR
		actionButton.TextColor3 = Color3.fromRGB(180, 180, 180)
		actionButton.Text = "🔒 Locked"

		-- On click: show unlock requirement message
		actionButton.MouseButton1Click:Connect(function()
			local prerequisiteName = packData.prerequisiteName or "the previous pack"
			showUnlockMessage("Complete " .. prerequisiteName .. " to unlock")
		end)
	end

	return portal
end

--============================================================================
-- Helper Functions
--============================================================================

--- Show a temporary unlock requirement message at the bottom of the screen.
showUnlockMessage = function(message: string)
	if not messageLabel then
		return
	end

	-- Cancel any existing fade tween
	if messageTween then
		messageTween:Cancel()
		messageTween = nil
	end

	messageLabel.Text = message
	messageLabel.Visible = true
	messageLabel.TextTransparency = 0
	messageLabel.BackgroundTransparency = 0.2

	-- Fade out after duration
	task.delay(UNLOCK_MESSAGE_DURATION, function()
		if messageLabel then
			local tweenInfo = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local tween = TweenService:Create(messageLabel, tweenInfo, {
				TextTransparency = 1,
				BackgroundTransparency = 1,
			})
			messageTween = tween
			tween:Play()
			tween.Completed:Connect(function()
				if messageLabel then
					messageLabel.Visible = false
				end
			end)
		end
	end)
end

--- Clear all portal frames from the container.
local function clearPortals()
	if not portalContainer then
		return
	end

	for _, child in portalContainer:GetChildren() do
		if child:IsA("Frame") and child.Name:find("Portal_") then
			child:Destroy()
		end
	end
end

--============================================================================
-- Remote Event Connections
--============================================================================

--- Connect to RemoteEvents for lobby data and level transitions.
local function connectRemoteEvents()
	local eventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if not eventsFolder then
		return
	end

	-- ShowLobby: server sends pack display data when player should see the lobby
	local showLobbyEvent = eventsFolder:WaitForChild("ShowLobby", 5) :: RemoteEvent?
	if showLobbyEvent then
		showLobbyEvent.OnClientEvent:Connect(function(data: any)
			if type(data) == "table" and type(data.packs) == "table" then
				-- Convert server data into PackDisplayData array
				local packDisplayList: { PackDisplayData } = {}
				for _, packInfo in data.packs do
					if type(packInfo) == "table" then
						table.insert(packDisplayList, {
							packId = packInfo.packId or "",
							name = packInfo.name or "Unknown",
							displayOrder = packInfo.displayOrder or 1,
							themeId = packInfo.themeId or "",
							completedLevels = packInfo.completedLevels or 0,
							isUnlocked = packInfo.isUnlocked ~= false,
							prerequisiteName = packInfo.prerequisiteName,
						})
					end
				end

				-- Sort by displayOrder
				table.sort(packDisplayList, function(a, b)
					return a.displayOrder < b.displayOrder
				end)

				-- Show portals
				showPortalsFromData(packDisplayList)
			end
		end)
	end

	-- LevelStarted: hide lobby when entering a level
	local levelStartedEvent = eventsFolder:WaitForChild("LevelStarted", 5) :: RemoteEvent?
	if levelStartedEvent then
		levelStartedEvent.OnClientEvent:Connect(function(_data: any)
			LobbyUI.hide()
		end)
	end
end

--============================================================================
-- Internal Portal Display
--============================================================================

--- Display portals from PackDisplayData (used by RemoteEvent handler).
showPortalsFromData = function(packs: { PackDisplayData })
	if not isInitialized then
		return
	end

	-- Clear existing portals
	clearPortals()

	-- Create portal for each pack
	local totalPacks = #packs
	for i, packData in packs do
		createPortalFrame(packData, i, totalPacks, portalContainer :: Frame)
	end

	-- Show the lobby GUI
	if screenGui then
		screenGui.Enabled = true
		isVisible = true
	end
end

--============================================================================
-- Initialization
--============================================================================

--- Initialize the lobby UI elements.
local function initialize()
	if isInitialized then
		return
	end
	isInitialized = true

	-- Create the root ScreenGui (separate from gameplay HUD)
	screenGui = createScreenGui()

	-- Create portal container
	portalContainer = createPortalContainer(screenGui)

	-- Create unlock message label
	messageLabel = createMessageLabel(portalContainer :: Frame)

	-- Connect to RemoteEvents
	connectRemoteEvents()
end

--============================================================================
-- Public API
--============================================================================

--- Initialize the LobbyUI system.
--- Creates the ScreenGui and connects RemoteEvent listeners.
function LobbyUI.init(): ()
	initialize()
end

--- Display level pack portals from LevelPackConfig data.
--- This is the interface-compatible entry point that builds PackDisplayData from configs.
--- In practice, the server sends pre-computed display data via ShowLobby RemoteEvent,
--- but this function supports direct calls with LevelPackConfig arrays for flexibility.
--- @param packs {LevelPackConfig} - Array of level pack configurations to display
function LobbyUI.showPortals(packs: { LevelPackConfig }): ()
	if not isInitialized then
		initialize()
	end

	-- Convert LevelPackConfig to PackDisplayData (without completion info, all unlocked by default)
	-- In normal gameplay, the server sends completion/unlock info via ShowLobby RemoteEvent
	local packDisplayList: { PackDisplayData } = {}
	for _, pack in packs do
		local isFirstPack = pack.prerequisitePack == nil
		table.insert(packDisplayList, {
			packId = pack.themeId or pack.name,
			name = pack.name,
			displayOrder = pack.displayOrder,
			themeId = pack.themeId,
			completedLevels = 0,
			isUnlocked = isFirstPack,
			prerequisiteName = pack.prerequisitePack,
		})
	end

	-- Sort by displayOrder
	table.sort(packDisplayList, function(a, b)
		return a.displayOrder < b.displayOrder
	end)

	showPortalsFromData(packDisplayList)
end

--- Hide the lobby ScreenGui (when entering a level).
function LobbyUI.hide(): ()
	if screenGui then
		screenGui.Enabled = false
		isVisible = false
	end
end

--============================================================================
-- Auto-initialize
--============================================================================

-- Defer initialization to ensure PlayerGui and RemoteEvents are available
task.defer(initialize)

return LobbyUI
