--!strict
--[[
    ModeSelectUI.luau - Mode selection popup for completed packs

    When a player walks through a portal for a pack they've fully completed,
    this UI appears showing available game modes (Classic, Time Attack, Sprint).
    The player picks a mode, and RequestStartLevel is fired with the chosen mode.

    If the player doesn't pick within a timeout, defaults to Classic.

    Listens for:
    - ShowModeSelection (RemoteEvent): { packId, levelNum, modes: {{id, name, description}} }

    Fires:
    - RequestStartLevel (RemoteEvent): { packId, levelNum, modeId }

    Validates: Requirements 7.3
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModeSelectUI = {}

--============================================================================
-- Constants
--============================================================================

local BG_COLOR = Color3.fromRGB(10, 10, 20)
local BUTTON_COLOR = Color3.fromRGB(40, 50, 80)
local BUTTON_HOVER_COLOR = Color3.fromRGB(60, 80, 140)
local BUTTON_TEXT_COLOR = Color3.fromRGB(240, 240, 255)
local TITLE_COLOR = Color3.fromRGB(0, 255, 255)
local DESC_COLOR = Color3.fromRGB(160, 170, 200)
local TIMEOUT_SECONDS = 8 -- Auto-select Classic if no choice made

--============================================================================
-- State
--============================================================================

local screenGui: ScreenGui? = nil
local panelFrame: Frame? = nil
local isInitialized: boolean = false
local isVisible: boolean = false
local pendingPackId: string? = nil
local pendingLevelNum: number? = nil
local timeoutThread: thread? = nil

--============================================================================
-- UI Construction
--============================================================================

local function createScreenGui(): ScreenGui
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local gui = Instance.new("ScreenGui")
	gui.Name = "PixelRunModeSelect"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 20 -- Above lobby UI
	gui.Enabled = false
	gui.Parent = playerGui

	return gui
end

local function createPanel(parent: ScreenGui): Frame
	-- Semi-transparent background overlay
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.Parent = parent

	-- Center panel
	local panel = Instance.new("Frame")
	panel.Name = "ModePanel"
	panel.Size = UDim2.new(0, 340, 0, 320)
	panel.Position = UDim2.new(0.5, -170, 0.5, -160)
	panel.BackgroundColor3 = BG_COLOR
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Parent = overlay

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Position = UDim2.new(0, 0, 0, 10)
	title.BackgroundTransparency = 1
	title.TextColor3 = TITLE_COLOR
	title.TextSize = 22
	title.Font = Enum.Font.GothamBold
	title.Text = "Choose Mode"
	title.Parent = panel

	-- Subtitle hint
	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, -20, 0, 20)
	subtitle.Position = UDim2.new(0, 10, 0, 48)
	subtitle.BackgroundTransparency = 1
	subtitle.TextColor3 = DESC_COLOR
	subtitle.TextSize = 12
	subtitle.Font = Enum.Font.Gotham
	subtitle.Text = "Pack completed! Pick a mode to play."
	subtitle.Parent = panel

	return panel
end

--============================================================================
-- Mode Button Creation
--============================================================================

local function createModeButton(parent: Frame, mode: { id: string, name: string, description: string }, yOffset: number, onSelect: (string) -> ())
	local btn = Instance.new("TextButton")
	btn.Name = "ModeBtn_" .. mode.id
	btn.Size = UDim2.new(1, -30, 0, 60)
	btn.Position = UDim2.new(0, 15, 0, yOffset)
	btn.BackgroundColor3 = BUTTON_COLOR
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.Parent = parent

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = btn

	-- Mode name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "ModeName"
	nameLabel.Size = UDim2.new(1, -16, 0, 24)
	nameLabel.Position = UDim2.new(0, 8, 0, 6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = BUTTON_TEXT_COLOR
	nameLabel.TextSize = 16
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = mode.name
	nameLabel.Parent = btn

	-- Mode description
	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "ModeDesc"
	descLabel.Size = UDim2.new(1, -16, 0, 20)
	descLabel.Position = UDim2.new(0, 8, 0, 32)
	descLabel.BackgroundTransparency = 1
	descLabel.TextColor3 = DESC_COLOR
	descLabel.TextSize = 12
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.Text = mode.description
	descLabel.Parent = btn

	-- Hover effect
	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = BUTTON_HOVER_COLOR
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = BUTTON_COLOR
	end)

	-- Click handler
	btn.MouseButton1Click:Connect(function()
		onSelect(mode.id)
	end)
end

--============================================================================
-- Show / Hide
--============================================================================

local function selectMode(modeId: string)
	-- Hide the UI
	ModeSelectUI.hide()

	-- Cancel timeout
	if timeoutThread then
		task.cancel(timeoutThread)
		timeoutThread = nil
	end

	-- Fire RequestStartLevel to server
	local eventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if eventsFolder then
		local requestEvent = eventsFolder:FindFirstChild("RequestStartLevel") :: RemoteEvent?
		if requestEvent then
			requestEvent:FireServer({
				packId = pendingPackId,
				levelNum = pendingLevelNum or 1,
				modeId = modeId,
			})
		end
	end

	pendingPackId = nil
	pendingLevelNum = nil
end

--- Show the mode selection UI with the given modes.
function ModeSelectUI.show(data: { packId: string, levelNum: number, modes: {{ id: string, name: string, description: string }} })
	if not isInitialized then
		ModeSelectUI.init()
	end

	pendingPackId = data.packId
	pendingLevelNum = data.levelNum

	-- Clear any existing mode buttons
	if panelFrame then
		for _, child in panelFrame:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
	end

	-- Create mode buttons
	local startY = 76
	local buttonHeight = 68

	if panelFrame then
		for i, mode in data.modes do
			createModeButton(panelFrame, mode, startY + (i - 1) * buttonHeight, selectMode)
		end

		-- Resize panel to fit buttons
		local totalHeight = startY + #data.modes * buttonHeight + 15
		panelFrame.Size = UDim2.new(0, 340, 0, totalHeight)
		panelFrame.Position = UDim2.new(0.5, -170, 0.5, -totalHeight / 2)
	end

	-- Show
	if screenGui then
		screenGui.Enabled = true
		isVisible = true
	end

	-- Start timeout: auto-select Classic if no choice made
	if timeoutThread then
		task.cancel(timeoutThread)
	end
	timeoutThread = task.delay(TIMEOUT_SECONDS, function()
		if isVisible then
			selectMode("classic")
		end
	end)
end

--- Hide the mode selection UI.
function ModeSelectUI.hide()
	if screenGui then
		screenGui.Enabled = false
		isVisible = false
	end
	if timeoutThread then
		task.cancel(timeoutThread)
		timeoutThread = nil
	end
end

--============================================================================
-- Initialization
--============================================================================

function ModeSelectUI.init()
	if isInitialized then
		return
	end
	isInitialized = true

	screenGui = createScreenGui()
	panelFrame = createPanel(screenGui)

	-- Connect to ShowModeSelection RemoteEvent
	local eventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if eventsFolder then
		local showEvent = eventsFolder:WaitForChild("ShowModeSelection", 5) :: RemoteEvent?
		if showEvent then
			showEvent.OnClientEvent:Connect(function(data: any)
				if type(data) == "table" and data.packId and data.modes then
					ModeSelectUI.show(data)
				end
			end)
		end
	end

	-- Hide mode select when a level starts (in case server starts level directly)
	if eventsFolder then
		local levelStartedEvent = eventsFolder:FindFirstChild("LevelStarted") :: RemoteEvent?
		if levelStartedEvent then
			levelStartedEvent.OnClientEvent:Connect(function(_data: any)
				ModeSelectUI.hide()
			end)
		end
	end
end

return ModeSelectUI
