--!strict
--[[
    TutorialUI.luau - First-time tutorial overlay for new players

    Shows 3 sequential tip overlays on the first level start for new players
    (0 XP, no completions). Each tip can be dismissed by tap/click or auto-advances
    after 4 seconds. Once all tips are shown, the tutorialCompleted flag is persisted
    via a SaveTutorial RemoteEvent so the tutorial never shows again.

    Tips:
    1. "Jump over obstacles!" (jump hint)
    2. "Watch out! The Morass is chasing you!" (warning)
    3. "Earn XP by running far!" (XP hint)

    Validates: Requirements 8.1
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--============================================================================
-- Module
--============================================================================

local TutorialUI = {}

--============================================================================
-- State
--============================================================================

local tutorialCompleted: boolean = false
local isNewPlayer: boolean = false
local isShowingTutorial: boolean = false
local screenGui: ScreenGui? = nil

--============================================================================
-- Tip Definitions
--============================================================================

type TipDef = {
    text: string,
    icon: string,
    color: Color3,
}

local TIPS: {TipDef} = {
    {
        text = "Jump over obstacles!",
        icon = "\xE2\xAC\x86",  -- ⬆ arrow up
        color = Color3.fromRGB(60, 140, 220),
    },
    {
        text = "Watch out! The Morass is chasing you!",
        icon = "\xE2\x9A\xA0",  -- ⚠ warning
        color = Color3.fromRGB(220, 120, 40),
    },
    {
        text = "Earn XP by running far!",
        icon = "\xE2\xAD\x90",  -- ⭐ star
        color = Color3.fromRGB(80, 180, 80),
    },
}

local TIP_AUTO_ADVANCE_SECONDS = 4
local TIP_FADE_DURATION = 0.3

--============================================================================
-- UI Construction
--============================================================================

--- Create the tutorial ScreenGui (separate from HUD so it layers on top).
local function createScreenGui(): ScreenGui
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

    local gui = Instance.new("ScreenGui")
    gui.Name = "TutorialUI"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 10 -- Above other UIs
    gui.Parent = playerGui

    return gui
end

--- Create a tip overlay bar at the bottom of the screen.
--- Returns the frame and a function to dismiss it.
local function createTipOverlay(parent: ScreenGui, tip: TipDef): (Frame, TextButton)
    -- Full-width overlay bar at bottom
    local frame = Instance.new("Frame")
    frame.Name = "TipOverlay"
    frame.Size = UDim2.new(1, 0, 0, 70)
    frame.Position = UDim2.new(0, 0, 1, -70)
    frame.BackgroundColor3 = tip.color
    frame.BackgroundTransparency = 0.15
    frame.BorderSizePixel = 0
    frame.Parent = parent

    -- Rounded top corners
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame

    -- Icon label (left side)
    local iconLabel = Instance.new("TextLabel")
    iconLabel.Name = "Icon"
    iconLabel.Size = UDim2.new(0, 50, 1, 0)
    iconLabel.Position = UDim2.new(0, 16, 0, 0)
    iconLabel.BackgroundTransparency = 1
    iconLabel.TextSize = 28
    iconLabel.Font = Enum.Font.Gotham
    iconLabel.Text = tip.icon
    iconLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    iconLabel.Parent = frame

    -- Tip text label
    local textLabel = Instance.new("TextLabel")
    textLabel.Name = "TipText"
    textLabel.Size = UDim2.new(1, -130, 1, 0)
    textLabel.Position = UDim2.new(0, 66, 0, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.TextSize = 18
    textLabel.Font = Enum.Font.GothamBold
    textLabel.Text = tip.text
    textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    textLabel.TextXAlignment = Enum.TextXAlignment.Left
    textLabel.TextWrapped = true
    textLabel.Parent = frame

    -- "Tap to dismiss" hint (right side)
    local dismissHint = Instance.new("TextLabel")
    dismissHint.Name = "DismissHint"
    dismissHint.Size = UDim2.new(0, 60, 0, 20)
    dismissHint.Position = UDim2.new(1, -70, 0.5, -10)
    dismissHint.BackgroundTransparency = 1
    dismissHint.TextSize = 11
    dismissHint.Font = Enum.Font.Gotham
    dismissHint.Text = "Tap >"
    dismissHint.TextColor3 = Color3.fromRGB(255, 255, 255)
    dismissHint.TextTransparency = 0.4
    dismissHint.Parent = frame

    -- Invisible button covering the whole frame for tap/click dismiss
    local dismissButton = Instance.new("TextButton")
    dismissButton.Name = "DismissButton"
    dismissButton.Size = UDim2.new(1, 0, 1, 0)
    dismissButton.Position = UDim2.new(0, 0, 0, 0)
    dismissButton.BackgroundTransparency = 1
    dismissButton.Text = ""
    dismissButton.Parent = frame

    return frame, dismissButton
end

--============================================================================
-- Tutorial Sequence Logic
--============================================================================

--- Show all 3 tips sequentially, then persist the flag.
local function showTutorialSequence()
    if isShowingTutorial then
        return
    end
    isShowingTutorial = true

    -- Ensure the ScreenGui exists
    if not screenGui then
        screenGui = createScreenGui()
    end

    for _, tip in TIPS do
        -- Check if we should stop (e.g. player disconnected)
        if not screenGui or not screenGui.Parent then
            break
        end

        local frame, dismissButton = createTipOverlay(screenGui, tip)

        -- Wait for dismiss (tap) or auto-advance (4 seconds)
        local dismissed = false

        local dismissConnection: RBXScriptConnection? = nil
        dismissConnection = dismissButton.MouseButton1Click:Connect(function()
            dismissed = true
            if dismissConnection then
                dismissConnection:Disconnect()
                dismissConnection = nil
            end
        end)

        -- Wait up to TIP_AUTO_ADVANCE_SECONDS or until dismissed
        local elapsed = 0
        local step = 0.05
        while elapsed < TIP_AUTO_ADVANCE_SECONDS and not dismissed do
            task.wait(step)
            elapsed += step
        end

        -- Clean up the connection if still active
        if dismissConnection then
            dismissConnection:Disconnect()
            dismissConnection = nil
        end

        -- Fade out the tip
        local fadeElapsed = 0
        local fadeStep = 0.02
        while fadeElapsed < TIP_FADE_DURATION do
            fadeElapsed += fadeStep
            local alpha = fadeElapsed / TIP_FADE_DURATION
            frame.BackgroundTransparency = 0.15 + alpha * 0.85
            -- Fade children text
            for _, child in frame:GetChildren() do
                if child:IsA("TextLabel") then
                    child.TextTransparency = alpha
                end
            end
            task.wait(fadeStep)
        end

        -- Remove the tip overlay
        frame:Destroy()
    end

    -- All tips shown — persist the flag
    tutorialCompleted = true
    isShowingTutorial = false

    -- Fire SaveTutorial RemoteEvent to server
    local eventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
    if eventsFolder then
        local saveTutorialEvent = eventsFolder:FindFirstChild("SaveTutorial") :: RemoteEvent?
        if saveTutorialEvent then
            saveTutorialEvent:FireServer({})
        end
    end

    -- Cleanup ScreenGui
    if screenGui then
        screenGui:Destroy()
        screenGui = nil
    end
end

--============================================================================
-- Public API
--============================================================================

--- Called when ShowLobby data is received. Checks if the player is new.
--- @param data table - The ShowLobby payload containing packs, leaderboard, tutorialCompleted
function TutorialUI.onShowLobby(data: any)
    if tutorialCompleted then
        return
    end

    if type(data) ~= "table" then
        return
    end

    -- If server says tutorial is already completed, skip
    if data.tutorialCompleted == true then
        tutorialCompleted = true
        return
    end

    -- Determine if this is a new player: 0 XP and no completions
    local playerXP = 0
    if data.leaderboard and data.leaderboard.playerValueXP then
        playerXP = data.leaderboard.playerValueXP
    end

    local hasCompletions = false
    if data.packs and type(data.packs) == "table" then
        for _, pack in data.packs do
            if type(pack) == "table" and pack.completedLevels and pack.completedLevels > 0 then
                hasCompletions = true
                break
            end
        end
    end

    -- Only show tutorial for brand new players (0 XP, no completions)
    if playerXP == 0 and not hasCompletions then
        isNewPlayer = true
    end
end

--- Called when LevelStarted event fires. If player is new and tutorial not completed,
--- show the tutorial sequence.
function TutorialUI.onLevelStarted()
    if tutorialCompleted or not isNewPlayer or isShowingTutorial then
        return
    end

    -- Show tutorial asynchronously so it doesn't block other event handlers
    task.spawn(showTutorialSequence)
end

return TutorialUI
