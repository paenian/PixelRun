--!strict
--[[
    SettingsUI.luau - Client settings panel for Pixel Run Obby

    Displays a gear icon button in the top-right corner of the screen (always visible).
    When clicked, opens a Settings panel with:
    - Music volume slider (0-100%)
    - SFX volume slider (0-100%)
    - Screen shake toggle (on/off)

    Settings are applied locally immediately and sent to the server for persistence.
    On init, loads saved settings from the player profile.

    Validates: Requirements 1.11
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

--============================================================================
-- Dependencies
--============================================================================

local SoundManager = require(script.Parent.SoundManager)

--============================================================================
-- Module
--============================================================================

local SettingsUI = {}

--============================================================================
-- State
--============================================================================

local screenGui: ScreenGui? = nil
local settingsPanel: Frame? = nil
local isOpen: boolean = false
local isInitialized: boolean = false

-- Current settings values
local musicVolume: number = 50
local sfxVolume: number = 80
local screenShake: boolean = true

-- Slider drag state
local activeDrag: { handle: Frame, track: Frame, onChange: (number) -> () }? = nil

-- Forward declaration for settings persistence
local saveSettings: () -> ()

--============================================================================
-- UI Construction
--============================================================================

--- Create the root ScreenGui with high DisplayOrder so it's always on top.
local function createScreenGui(): ScreenGui
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local gui = Instance.new("ScreenGui")
	gui.Name = "PixelRunSettings"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100 -- High priority to stay on top of other GUIs
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	return gui
end

--- Create the gear icon button in the top-right corner.
local function createGearButton(parent: ScreenGui): TextButton
	local button = Instance.new("TextButton")
	button.Name = "SettingsGearButton"
	button.Size = UDim2.new(0, 36, 0, 36)
	button.Position = UDim2.new(1, -46, 0, 10)
	button.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
	button.BackgroundTransparency = 0.3
	button.BorderSizePixel = 0
	button.TextColor3 = Color3.fromRGB(220, 220, 220)
	button.TextSize = 22
	button.Font = Enum.Font.GothamBold
	button.Text = "\xE2\x9A\x99" -- gear icon (⚙)
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	return button
end

--- Create a slider control (track + handle + label).
--- Returns: frame container, handle, and a function to set the value programmatically.
local function createSlider(
	parent: Frame,
	yPosition: number,
	labelText: string,
	initialValue: number,
	onChange: (number) -> ()
): (Frame, Frame, (number) -> ())
	-- Container
	local container = Instance.new("Frame")
	container.Name = "Slider_" .. labelText
	container.Size = UDim2.new(1, -20, 0, 50)
	container.Position = UDim2.new(0, 10, 0, yPosition)
	container.BackgroundTransparency = 1
	container.Parent = parent

	-- Label
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 0, 18)
	label.Position = UDim2.new(0, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(220, 220, 220)
	label.TextSize = 14
	label.Font = Enum.Font.GothamBold
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = labelText
	label.Parent = container

	-- Value label (right side)
	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "Value"
	valueLabel.Size = UDim2.new(0, 40, 0, 18)
	valueLabel.Position = UDim2.new(1, -40, 0, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.TextColor3 = Color3.fromRGB(180, 180, 255)
	valueLabel.TextSize = 14
	valueLabel.Font = Enum.Font.Gotham
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Text = tostring(math.floor(initialValue)) .. "%"
	valueLabel.Parent = container

	-- Track background
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 8)
	track.Position = UDim2.new(0, 0, 0, 28)
	track.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
	track.BorderSizePixel = 0
	track.Parent = container

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 4)
	trackCorner.Parent = track

	-- Fill bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(initialValue / 100, 0, 1, 0)
	fill.Position = UDim2.new(0, 0, 0, 0)
	fill.BackgroundColor3 = Color3.fromRGB(100, 150, 255)
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	-- Draggable handle
	local handle = Instance.new("Frame")
	handle.Name = "Handle"
	handle.Size = UDim2.new(0, 16, 0, 16)
	handle.Position = UDim2.new(initialValue / 100, -8, 0.5, -8)
	handle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	handle.BorderSizePixel = 0
	handle.Parent = track

	local handleCorner = Instance.new("UICorner")
	handleCorner.CornerRadius = UDim.new(0.5, 0)
	handleCorner.Parent = handle

	-- Clickable area over the track for easier interaction
	local clickArea = Instance.new("TextButton")
	clickArea.Name = "ClickArea"
	clickArea.Size = UDim2.new(1, 0, 0, 24)
	clickArea.Position = UDim2.new(0, 0, 0, 20)
	clickArea.BackgroundTransparency = 1
	clickArea.Text = ""
	clickArea.Parent = container

	-- Set value programmatically
	local function setValue(value: number)
		value = math.clamp(value, 0, 100)
		fill.Size = UDim2.new(value / 100, 0, 1, 0)
		handle.Position = UDim2.new(value / 100, -8, 0.5, -8)
		valueLabel.Text = tostring(math.floor(value)) .. "%"
	end

	-- Handle click on track to set value
	clickArea.MouseButton1Down:Connect(function()
		activeDrag = { handle = handle, track = track, onChange = function(val: number)
			setValue(val)
			onChange(val)
		end }
		-- Immediately apply the click position
		local mouse = Players.LocalPlayer:GetMouse()
		local trackAbsPos = track.AbsolutePosition.X
		local trackAbsSize = track.AbsoluteSize.X
		if trackAbsSize > 0 then
			local relativeX = math.clamp((mouse.X - trackAbsPos) / trackAbsSize, 0, 1)
			local newValue = math.floor(relativeX * 100 + 0.5)
			setValue(newValue)
			onChange(newValue)
		end
	end)

	return container, handle, setValue
end

--- Create a toggle control for screen shake.
local function createToggle(
	parent: Frame,
	yPosition: number,
	labelText: string,
	initialValue: boolean,
	onChange: (boolean) -> ()
): (Frame, (boolean) -> ())
	-- Container
	local container = Instance.new("Frame")
	container.Name = "Toggle_" .. labelText
	container.Size = UDim2.new(1, -20, 0, 36)
	container.Position = UDim2.new(0, 10, 0, yPosition)
	container.BackgroundTransparency = 1
	container.Parent = parent

	-- Label
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -60, 1, 0)
	label.Position = UDim2.new(0, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(220, 220, 220)
	label.TextSize = 14
	label.Font = Enum.Font.GothamBold
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = labelText
	label.Parent = container

	-- Toggle button
	local toggleBG = Instance.new("Frame")
	toggleBG.Name = "ToggleBG"
	toggleBG.Size = UDim2.new(0, 44, 0, 24)
	toggleBG.Position = UDim2.new(1, -44, 0.5, -12)
	toggleBG.BackgroundColor3 = if initialValue then Color3.fromRGB(80, 180, 80) else Color3.fromRGB(80, 80, 100)
	toggleBG.BorderSizePixel = 0
	toggleBG.Parent = container

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0.5, 0)
	bgCorner.Parent = toggleBG

	-- Toggle knob
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Size = UDim2.new(0, 20, 0, 20)
	knob.Position = if initialValue then UDim2.new(1, -22, 0.5, -10) else UDim2.new(0, 2, 0.5, -10)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.Parent = toggleBG

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(0.5, 0)
	knobCorner.Parent = knob

	-- Clickable overlay
	local clickButton = Instance.new("TextButton")
	clickButton.Name = "ClickArea"
	clickButton.Size = UDim2.new(1, 0, 1, 0)
	clickButton.BackgroundTransparency = 1
	clickButton.Text = ""
	clickButton.Parent = toggleBG

	local currentValue = initialValue

	-- Set value function
	local function setValue(value: boolean)
		currentValue = value
		toggleBG.BackgroundColor3 = if value then Color3.fromRGB(80, 180, 80) else Color3.fromRGB(80, 80, 100)
		knob.Position = if value then UDim2.new(1, -22, 0.5, -10) else UDim2.new(0, 2, 0.5, -10)
	end

	clickButton.MouseButton1Click:Connect(function()
		currentValue = not currentValue
		setValue(currentValue)
		onChange(currentValue)
	end)

	return container, setValue
end

--- Create the settings panel (centered, hidden by default).
local function createSettingsPanel(parent: ScreenGui): Frame
	local panel = Instance.new("Frame")
	panel.Name = "SettingsPanel"
	panel.Size = UDim2.new(0, 280, 0, 260)
	panel.Position = UDim2.new(0.5, -140, 0.5, -130)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = parent

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 36)
	title.Position = UDim2.new(0, 0, 0, 8)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 18
	title.Font = Enum.Font.GothamBold
	title.Text = "\xE2\x9A\x99 Settings"
	title.Parent = panel

	-- Separator
	local separator = Instance.new("Frame")
	separator.Name = "Separator"
	separator.Size = UDim2.new(0.9, 0, 0, 1)
	separator.Position = UDim2.new(0.05, 0, 0, 44)
	separator.BackgroundColor3 = Color3.fromRGB(100, 100, 120)
	separator.BorderSizePixel = 0
	separator.Parent = panel

	-- Music Volume Slider
	createSlider(panel, 54, "Music Volume", musicVolume, function(value: number)
		musicVolume = value
		SoundManager.setMusicVolume(value)
		saveSettings()
	end)

	-- SFX Volume Slider
	createSlider(panel, 114, "SFX Volume", sfxVolume, function(value: number)
		sfxVolume = value
		SoundManager.setSFXVolume(value)
		saveSettings()
	end)

	-- Screen Shake Toggle
	createToggle(panel, 180, "Screen Shake", screenShake, function(value: boolean)
		screenShake = value
		saveSettings()
	end)

	-- Close button
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.new(0, 28, 0, 28)
	closeButton.Position = UDim2.new(1, -34, 0, 6)
	closeButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
	closeButton.BackgroundTransparency = 0.3
	closeButton.BorderSizePixel = 0
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.TextSize = 16
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Text = "X"
	closeButton.Parent = panel

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 6)
	closeCorner.Parent = closeButton

	closeButton.MouseButton1Click:Connect(function()
		SettingsUI.close()
	end)

	return panel
end

--============================================================================
-- Settings Persistence
--============================================================================

--- Send current settings to the server for DataStore persistence.
saveSettings = function()
	local eventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not eventsFolder then
		return
	end
	local saveEvent = eventsFolder:FindFirstChild("SaveSettings") :: RemoteEvent?
	if saveEvent then
		saveEvent:FireServer({
			musicVolume = musicVolume,
			sfxVolume = sfxVolume,
			screenShake = screenShake,
		})
	end
end

--- Load settings from the player profile data sent by server.
local function loadSettings(data: { musicVolume: number?, sfxVolume: number?, screenShake: boolean? }?)
	if data then
		if data.musicVolume ~= nil then
			musicVolume = math.clamp(data.musicVolume :: number, 0, 100)
		end
		if data.sfxVolume ~= nil then
			sfxVolume = math.clamp(data.sfxVolume :: number, 0, 100)
		end
		if data.screenShake ~= nil then
			screenShake = data.screenShake :: boolean
		end
	end

	-- Apply loaded settings to SoundManager
	SoundManager.setMusicVolume(musicVolume)
	SoundManager.setSFXVolume(sfxVolume)
end

--============================================================================
-- Drag Handling
--============================================================================

--- Process mouse movement for slider dragging.
local function onInputChanged(input: InputObject)
	if not activeDrag then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local track = activeDrag.track
	local trackAbsPos = track.AbsolutePosition.X
	local trackAbsSize = track.AbsoluteSize.X

	if trackAbsSize > 0 then
		local relativeX = math.clamp((input.Position.X - trackAbsPos) / trackAbsSize, 0, 1)
		local newValue = math.floor(relativeX * 100 + 0.5)
		activeDrag.onChange(newValue)
	end
end

--- Stop dragging on mouse release.
local function onInputEnded(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		activeDrag = nil
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

	-- Create gear button
	local gearButton = createGearButton(screenGui)
	gearButton.MouseButton1Click:Connect(function()
		SettingsUI.toggle()
	end)

	-- Create settings panel
	settingsPanel = createSettingsPanel(screenGui)

	-- Wire input events for slider dragging
	UserInputService.InputChanged:Connect(onInputChanged)
	UserInputService.InputEnded:Connect(onInputEnded)

	-- Listen for settings data from server (sent on join via SettingsLoaded event)
	local eventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if eventsFolder then
		local settingsLoadedEvent = eventsFolder:WaitForChild("SettingsLoaded", 5) :: RemoteEvent?
		if settingsLoadedEvent then
			settingsLoadedEvent.OnClientEvent:Connect(function(data: any)
				if type(data) == "table" then
					loadSettings(data)
				end
			end)
		end
	end
end

--============================================================================
-- Public API
--============================================================================

--- Open the settings panel.
function SettingsUI.open(): ()
	if not isInitialized then
		initialize()
	end
	if settingsPanel then
		settingsPanel.Visible = true
		isOpen = true
	end
end

--- Close the settings panel.
function SettingsUI.close(): ()
	if settingsPanel then
		settingsPanel.Visible = false
		isOpen = false
	end
end

--- Toggle the settings panel open/closed.
function SettingsUI.toggle(): ()
	if not isInitialized then
		initialize()
	end
	if isOpen then
		SettingsUI.close()
	else
		SettingsUI.open()
	end
end

--- Check if screen shake is enabled (used by EffectsManager).
function SettingsUI.isScreenShakeEnabled(): boolean
	return screenShake
end

--- Get current music volume (0-100).
function SettingsUI.getMusicVolume(): number
	return musicVolume
end

--- Get current SFX volume (0-100).
function SettingsUI.getSFXVolume(): number
	return sfxVolume
end

--- Initialize the SettingsUI module. Should be called early in client startup.
function SettingsUI.init(): ()
	initialize()
end

return SettingsUI
