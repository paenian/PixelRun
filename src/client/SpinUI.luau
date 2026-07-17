--!strict
--[[
    SpinUI.luau - Client-side Daily Spin wheel UI

    Listens for the SpinProximityPrompt in the lobby's DailySpinWheel.
    When triggered, opens a ScreenGui with a spinning wheel animation,
    then displays the XP reward the player received.

    If the player has already spun today, the server returns an error
    and the UI shows "Come back tomorrow!" without spinning.

    Validates: Requirements from Epoch 2, Task 1.7 (Daily Spin Wheel)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")

--============================================================================
-- Constants
--============================================================================

local BG_COLOR = Color3.fromRGB(15, 15, 25)
local PANEL_COLOR = Color3.fromRGB(25, 25, 40)
local ACCENT_COLOR = Color3.fromRGB(255, 165, 0) -- Orange (matches wheel theme)
local TEXT_COLOR = Color3.fromRGB(220, 220, 230)
local REWARD_COLOR = Color3.fromRGB(255, 255, 100)
local ERROR_COLOR = Color3.fromRGB(255, 100, 100)

-- Wheel segment colors and reward labels (visual only - server determines actual reward)
local SEGMENTS = {
    { color = Color3.fromRGB(255, 50, 50), label = "100 XP" },
    { color = Color3.fromRGB(255, 165, 0), label = "200 XP" },
    { color = Color3.fromRGB(255, 255, 0), label = "500 XP" },
    { color = Color3.fromRGB(0, 255, 0), label = "1000 XP" },
    { color = Color3.fromRGB(0, 255, 255), label = "100 XP" },
    { color = Color3.fromRGB(128, 0, 128), label = "200 XP" },
    { color = Color3.fromRGB(255, 255, 0), label = "500 XP" },
    { color = Color3.fromRGB(0, 255, 0), label = "2000 XP" },
}

local NUM_SEGMENTS = #SEGMENTS
local SPIN_DURATION = 3.5 -- Seconds for the spin animation
local EXTRA_ROTATIONS = 4 -- Full extra rotations before landing

--============================================================================
-- State
--============================================================================

local SpinUI = {}

local screenGui: ScreenGui? = nil
local spinFrame: Frame? = nil
local wheelFrame: Frame? = nil
local resultLabel: TextLabel? = nil
local pointerFrame: Frame? = nil
local isOpen: boolean = false
local isSpinning: boolean = false
local isInitialized: boolean = false

--============================================================================
-- UI Construction
--============================================================================

local function createSpinGui(): ScreenGui
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

    local gui = Instance.new("ScreenGui")
    gui.Name = "SpinPanel"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 12
    gui.Enabled = false
    gui.Parent = playerGui

    return gui
end

local function createBackdrop(parent: ScreenGui): Frame
    local backdrop = Instance.new("Frame")
    backdrop.Name = "Backdrop"
    backdrop.Size = UDim2.new(1, 0, 1, 0)
    backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
    backdrop.BackgroundTransparency = 0.4
    backdrop.BorderSizePixel = 0
    backdrop.Parent = parent
    return backdrop
end

local function createMainPanel(parent: ScreenGui): Frame
    local panel = Instance.new("Frame")
    panel.Name = "SpinFrame"
    panel.Size = UDim2.new(0, 360, 0, 440)
    panel.Position = UDim2.new(0.5, -180, 0.5, -220)
    panel.BackgroundColor3 = BG_COLOR
    panel.BackgroundTransparency = 0.02
    panel.BorderSizePixel = 0
    panel.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 14)
    corner.Parent = panel

    local stroke = Instance.new("UIStroke")
    stroke.Color = ACCENT_COLOR
    stroke.Thickness = 2
    stroke.Transparency = 0.5
    stroke.Parent = panel

    return panel
end

local function createHeader(parent: Frame)
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 40)
    title.Position = UDim2.new(0, 0, 0, 8)
    title.BackgroundTransparency = 1
    title.TextColor3 = ACCENT_COLOR
    title.TextSize = 22
    title.Font = Enum.Font.GothamBold
    title.Text = "DAILY SPIN"
    title.Parent = parent
end

local function createCloseButton(parent: Frame)
    local btn = Instance.new("TextButton")
    btn.Name = "CloseBtn"
    btn.Size = UDim2.new(0, 36, 0, 36)
    btn.Position = UDim2.new(1, -42, 0, 6)
    btn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    btn.BackgroundTransparency = 0.3
    btn.BorderSizePixel = 0
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 18
    btn.Font = Enum.Font.GothamBold
    btn.Text = "X"
    btn.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = btn

    btn.MouseButton1Click:Connect(function()
        if not isSpinning then
            SpinUI.close()
        end
    end)
end

local function createWheel(parent: Frame): Frame
    -- Container for the spinning wheel
    local container = Instance.new("Frame")
    container.Name = "WheelContainer"
    container.Size = UDim2.new(0, 280, 0, 280)
    container.Position = UDim2.new(0.5, -140, 0, 55)
    container.BackgroundTransparency = 1
    container.ClipsDescendants = true
    container.Parent = parent

    -- The actual wheel that rotates
    local wheel = Instance.new("Frame")
    wheel.Name = "Wheel"
    wheel.Size = UDim2.new(1, 0, 1, 0)
    wheel.Position = UDim2.new(0, 0, 0, 0)
    wheel.BackgroundTransparency = 1
    wheel.AnchorPoint = Vector2.new(0.5, 0.5)
    wheel.Position = UDim2.new(0.5, 0, 0.5, 0)
    wheel.Parent = container

    -- Draw segments as colored frames arranged in a circle pattern
    local segmentAngle = 360 / NUM_SEGMENTS
    for i, seg in SEGMENTS do
        local angle = (i - 1) * segmentAngle
        local rad = math.rad(angle + segmentAngle / 2)
        local radius = 90

        -- Segment indicator (colored block positioned around the wheel edge)
        local segFrame = Instance.new("Frame")
        segFrame.Name = "Seg_" .. tostring(i)
        segFrame.Size = UDim2.new(0, 50, 0, 30)
        segFrame.AnchorPoint = Vector2.new(0.5, 0.5)
        segFrame.Position = UDim2.new(
            0.5, math.cos(rad) * radius,
            0.5, math.sin(rad) * radius
        )
        segFrame.Rotation = angle + segmentAngle / 2
        segFrame.BackgroundColor3 = seg.color
        segFrame.BorderSizePixel = 0
        segFrame.Parent = wheel

        local segCorner = Instance.new("UICorner")
        segCorner.CornerRadius = UDim.new(0, 4)
        segCorner.Parent = segFrame

        -- Label
        local lbl = Instance.new("TextLabel")
        lbl.Name = "Label"
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = Color3.new(1, 1, 1)
        lbl.TextSize = 10
        lbl.Font = Enum.Font.GothamBold
        lbl.Text = seg.label
        lbl.TextWrapped = true
        lbl.Parent = segFrame
    end

    -- Center dot
    local center = Instance.new("Frame")
    center.Name = "Center"
    center.Size = UDim2.new(0, 30, 0, 30)
    center.AnchorPoint = Vector2.new(0.5, 0.5)
    center.Position = UDim2.new(0.5, 0, 0.5, 0)
    center.BackgroundColor3 = ACCENT_COLOR
    center.BorderSizePixel = 0
    center.Parent = wheel

    local centerCorner = Instance.new("UICorner")
    centerCorner.CornerRadius = UDim.new(1, 0)
    centerCorner.Parent = center

    return wheel
end

local function createPointer(parent: Frame): Frame
    -- Triangle-shaped pointer at the top of the wheel area
    local pointer = Instance.new("Frame")
    pointer.Name = "Pointer"
    pointer.Size = UDim2.new(0, 20, 0, 24)
    pointer.AnchorPoint = Vector2.new(0.5, 0)
    pointer.Position = UDim2.new(0.5, 0, 0, 48)
    pointer.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    pointer.BorderSizePixel = 0
    pointer.Rotation = 180
    pointer.Parent = parent

    -- Make it triangular with a UICorner (approximate)
    local pCorner = Instance.new("UICorner")
    pCorner.CornerRadius = UDim.new(0, 3)
    pCorner.Parent = pointer

    return pointer
end

local function createResultLabel(parent: Frame): TextLabel
    local label = Instance.new("TextLabel")
    label.Name = "ResultLabel"
    label.Size = UDim2.new(1, -20, 0, 60)
    label.Position = UDim2.new(0, 10, 1, -75)
    label.BackgroundColor3 = PANEL_COLOR
    label.BackgroundTransparency = 0.3
    label.BorderSizePixel = 0
    label.TextColor3 = TEXT_COLOR
    label.TextSize = 18
    label.Font = Enum.Font.GothamBold
    label.Text = "Spin the wheel!"
    label.TextWrapped = true
    label.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = label

    return label
end

--============================================================================
-- Spin Animation
--============================================================================

local function animateSpin(segmentIndex: number, callback: () -> ())
    if not wheelFrame then
        callback()
        return
    end

    -- Calculate target rotation: land on the given segment
    -- Segment 1 is at the top (0 degrees), each segment is 360/NUM_SEGMENTS apart
    local segmentAngle = 360 / NUM_SEGMENTS
    -- Target: we want the segmentIndex at the top (pointer position)
    -- Since pointer is at top (270 degrees in standard circle), align segment there
    local targetSegmentRotation = -(segmentIndex - 1) * segmentAngle
    -- Add extra full rotations for visual flair
    local totalRotation = targetSegmentRotation - (EXTRA_ROTATIONS * 360)

    -- Reset wheel rotation
    wheelFrame.Rotation = 0

    -- Animate using TweenService
    local tweenInfo = TweenInfo.new(
        SPIN_DURATION,
        Enum.EasingStyle.Quint,
        Enum.EasingDirection.Out
    )

    local tween = TweenService:Create(wheelFrame, tweenInfo, {
        Rotation = totalRotation,
    })

    tween.Completed:Once(function()
        callback()
    end)

    tween:Play()
end

--============================================================================
-- Server Communication
--============================================================================

local function requestSpin()
    if isSpinning then return end
    isSpinning = true

    if resultLabel then
        resultLabel.Text = "Spinning..."
        resultLabel.TextColor3 = TEXT_COLOR
    end

    -- Call server RemoteFunction
    local eventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
    if not eventsFolder then
        isSpinning = false
        return
    end

    local spinFunc = eventsFolder:FindFirstChild("ClaimDailySpin") :: RemoteFunction?
    if not spinFunc then
        warn("[SpinUI] ClaimDailySpin RemoteFunction not found")
        isSpinning = false
        if resultLabel then
            resultLabel.Text = "Error: Try again later"
            resultLabel.TextColor3 = ERROR_COLOR
        end
        return
    end

    local result = spinFunc:InvokeServer()

    if type(result) ~= "table" then
        isSpinning = false
        if resultLabel then
            resultLabel.Text = "Error: Try again later"
            resultLabel.TextColor3 = ERROR_COLOR
        end
        return
    end

    if not result.success then
        -- Already spun today or other error
        isSpinning = false
        if resultLabel then
            resultLabel.Text = result.message or "Come back tomorrow!"
            resultLabel.TextColor3 = ERROR_COLOR
        end
        return
    end

    -- Success! Animate the wheel to the segment, then show reward
    local segmentIndex = result.segmentIndex or 1
    local reward = result.reward or 0

    animateSpin(segmentIndex, function()
        isSpinning = false
        if resultLabel then
            resultLabel.Text = "+" .. tostring(reward) .. " XP!"
            resultLabel.TextColor3 = REWARD_COLOR
        end
    end)
end

--============================================================================
-- ProximityPrompt Wiring
--============================================================================

local function wireProximityPrompt()
    ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, _player: Player)
        if prompt.Name == "SpinProximityPrompt" then
            SpinUI.open()
        end
    end)
end

--============================================================================
-- Public API
--============================================================================

--- Initialize the SpinUI system.
function SpinUI.init()
    if isInitialized then return end
    isInitialized = true

    screenGui = createSpinGui()

    local backdrop = createBackdrop(screenGui)
    backdrop.InputBegan:Connect(function(input)
        if not isSpinning and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) then
            SpinUI.close()
        end
    end)

    spinFrame = createMainPanel(screenGui)
    createHeader(spinFrame)
    createCloseButton(spinFrame)
    wheelFrame = createWheel(spinFrame)
    pointerFrame = createPointer(spinFrame)
    resultLabel = createResultLabel(spinFrame)

    wireProximityPrompt()
end

--- Open the spin panel and immediately request a spin from the server.
function SpinUI.open()
    if not isInitialized then
        SpinUI.init()
    end
    if isOpen then return end

    if screenGui then
        screenGui.Enabled = true
        isOpen = true
    end

    -- Reset result text
    if resultLabel then
        resultLabel.Text = "Spin the wheel!"
        resultLabel.TextColor3 = TEXT_COLOR
    end

    -- Reset wheel rotation
    if wheelFrame then
        wheelFrame.Rotation = 0
    end

    -- Immediately send the spin request to the server
    task.defer(requestSpin)
end

--- Close the spin panel.
function SpinUI.close()
    if screenGui then
        screenGui.Enabled = false
        isOpen = false
    end
end

--- Check if the spin panel is currently open.
function SpinUI.isOpen(): boolean
    return isOpen
end

--============================================================================
-- Auto-initialize
--============================================================================

task.defer(SpinUI.init)

return SpinUI
