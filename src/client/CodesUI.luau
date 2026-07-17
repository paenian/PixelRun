--!strict
--[[
    CodesUI.luau - Client-side UI for the Codes terminal

    Listens for the CodesProximityPrompt in the lobby's CodesTerminal.
    When triggered, opens a ScreenGui with:
    - TextBox for code entry
    - Submit button
    - Result message (success/error)

    Sends code to server via RemoteFunction "RedeemCode" and displays the result.

    Validates: Requirements from Epoch 2, Task 1.6 / 2.2
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

--============================================================================
-- Constants
--============================================================================

local BG_COLOR = Color3.fromRGB(15, 15, 25)
local PANEL_COLOR = Color3.fromRGB(25, 25, 40)
local ACCENT_COLOR = Color3.fromRGB(0, 255, 150) -- Green neon (matches the terminal screen)
local TEXT_COLOR = Color3.fromRGB(220, 220, 230)
local SUBMIT_COLOR = Color3.fromRGB(50, 200, 100)
local ERROR_COLOR = Color3.fromRGB(255, 80, 80)
local SUCCESS_COLOR = Color3.fromRGB(80, 255, 130)
local INPUT_BG_COLOR = Color3.fromRGB(10, 10, 20)

--============================================================================
-- State
--============================================================================

local CodesUI = {}

local screenGui: ScreenGui? = nil
local codesFrame: Frame? = nil
local inputBox: TextBox? = nil
local submitButton: TextButton? = nil
local resultLabel: TextLabel? = nil
local isOpen: boolean = false
local isInitialized: boolean = false
local isSubmitting: boolean = false

--============================================================================
-- UI Construction
--============================================================================

local function createCodesGui(): ScreenGui
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

    local gui = Instance.new("ScreenGui")
    gui.Name = "CodesPanel"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 10
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
    panel.Name = "CodesFrame"
    panel.Size = UDim2.new(0, 360, 0, 260)
    panel.Position = UDim2.new(0.5, -180, 0.5, -130)
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
    title.Text = "ENTER CODE"
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
        CodesUI.close()
    end)
end

local function createInputBox(parent: Frame): TextBox
    local box = Instance.new("TextBox")
    box.Name = "CodeInput"
    box.Size = UDim2.new(1, -40, 0, 42)
    box.Position = UDim2.new(0, 20, 0, 60)
    box.BackgroundColor3 = INPUT_BG_COLOR
    box.BorderSizePixel = 0
    box.TextColor3 = TEXT_COLOR
    box.PlaceholderText = "Type your code here..."
    box.PlaceholderColor3 = Color3.fromRGB(100, 100, 120)
    box.TextSize = 18
    box.Font = Enum.Font.GothamBold
    box.Text = ""
    box.ClearTextOnFocus = false
    box.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = box

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(60, 60, 80)
    stroke.Thickness = 1
    stroke.Parent = box

    return box
end

local function createSubmitButton(parent: Frame): TextButton
    local btn = Instance.new("TextButton")
    btn.Name = "SubmitBtn"
    btn.Size = UDim2.new(1, -40, 0, 40)
    btn.Position = UDim2.new(0, 20, 0, 115)
    btn.BackgroundColor3 = SUBMIT_COLOR
    btn.BorderSizePixel = 0
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 16
    btn.Font = Enum.Font.GothamBold
    btn.Text = "REDEEM"
    btn.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = btn

    return btn
end

local function createResultLabel(parent: Frame): TextLabel
    local label = Instance.new("TextLabel")
    label.Name = "ResultLabel"
    label.Size = UDim2.new(1, -40, 0, 50)
    label.Position = UDim2.new(0, 20, 0, 170)
    label.BackgroundTransparency = 1
    label.TextColor3 = TEXT_COLOR
    label.TextSize = 14
    label.Font = Enum.Font.GothamBold
    label.Text = ""
    label.TextWrapped = true
    label.Parent = parent

    return label
end

--============================================================================
-- Submission Logic
--============================================================================

local function submitCode()
    if isSubmitting then return end
    if not inputBox then return end

    local code = inputBox.Text
    if #code == 0 then
        if resultLabel then
            resultLabel.Text = "Please enter a code."
            resultLabel.TextColor3 = ERROR_COLOR
        end
        return
    end

    isSubmitting = true
    if submitButton then
        submitButton.Text = "..."
        submitButton.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    end

    -- Send to server via RemoteFunction
    local eventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
    if not eventsFolder then
        if resultLabel then
            resultLabel.Text = "Connection error. Try again."
            resultLabel.TextColor3 = ERROR_COLOR
        end
        isSubmitting = false
        if submitButton then
            submitButton.Text = "REDEEM"
            submitButton.BackgroundColor3 = SUBMIT_COLOR
        end
        return
    end

    local redeemFunc = eventsFolder:FindFirstChild("RedeemCode") :: RemoteFunction?
    if not redeemFunc then
        if resultLabel then
            resultLabel.Text = "Codes system unavailable."
            resultLabel.TextColor3 = ERROR_COLOR
        end
        isSubmitting = false
        if submitButton then
            submitButton.Text = "REDEEM"
            submitButton.BackgroundColor3 = SUBMIT_COLOR
        end
        return
    end

    -- Invoke server
    local success, result = pcall(function()
        return redeemFunc:InvokeServer(code)
    end)

    if success and type(result) == "table" then
        if result.success then
            if resultLabel then
                resultLabel.Text = result.message or "Code redeemed!"
                resultLabel.TextColor3 = SUCCESS_COLOR
            end
            -- Clear the input box on success
            if inputBox then
                inputBox.Text = ""
            end
        else
            if resultLabel then
                resultLabel.Text = result.message or "Failed to redeem code."
                resultLabel.TextColor3 = ERROR_COLOR
            end
        end
    else
        if resultLabel then
            resultLabel.Text = "Something went wrong. Try again."
            resultLabel.TextColor3 = ERROR_COLOR
        end
    end

    isSubmitting = false
    if submitButton then
        submitButton.Text = "REDEEM"
        submitButton.BackgroundColor3 = SUBMIT_COLOR
    end
end

--============================================================================
-- ProximityPrompt Wiring
--============================================================================

local function wireProximityPrompt()
    ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, _player: Player)
        if prompt.Name == "CodesProximityPrompt" then
            CodesUI.open()
        end
    end)
end

--============================================================================
-- Public API
--============================================================================

--- Initialize the CodesUI system.
function CodesUI.init()
    if isInitialized then return end
    isInitialized = true

    screenGui = createCodesGui()

    local backdrop = createBackdrop(screenGui)
    backdrop.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            CodesUI.close()
        end
    end)

    codesFrame = createMainPanel(screenGui)
    createHeader(codesFrame)
    createCloseButton(codesFrame)
    inputBox = createInputBox(codesFrame)
    submitButton = createSubmitButton(codesFrame)
    resultLabel = createResultLabel(codesFrame)

    -- Wire submit button
    submitButton.MouseButton1Click:Connect(submitCode)

    -- Wire Enter key on TextBox
    inputBox.FocusLost:Connect(function(enterPressed: boolean)
        if enterPressed then
            submitCode()
        end
    end)

    wireProximityPrompt()
end

--- Open the codes panel.
function CodesUI.open()
    if not isInitialized then
        CodesUI.init()
    end
    if screenGui then
        screenGui.Enabled = true
        isOpen = true
        -- Clear previous result and input
        if resultLabel then
            resultLabel.Text = ""
        end
        if inputBox then
            inputBox.Text = ""
            -- Focus the text box for immediate typing
            task.defer(function()
                if inputBox then
                    inputBox:CaptureFocus()
                end
            end)
        end
    end
end

--- Close the codes panel.
function CodesUI.close()
    if screenGui then
        screenGui.Enabled = false
        isOpen = false
    end
end

--- Check if the codes panel is currently open.
function CodesUI.isOpen(): boolean
    return isOpen
end

--============================================================================
-- Auto-initialize
--============================================================================

task.defer(CodesUI.init)

return CodesUI
