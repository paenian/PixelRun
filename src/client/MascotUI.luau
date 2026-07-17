--!strict
--[[
    MascotUI.luau - Client-side mascot selection panel

    Listens for the MascotProximityPrompt in the lobby's MascotDisplayCase.
    When triggered, opens a ScreenGui panel showing:
    - All 6 mascots in a grid
    - Each mascot: name, description, color swatch, lock/unlock/equip state
    - Locked mascots are grayed out with unlock condition
    - Unlocked mascots have an "Equip" button
    - Currently equipped mascot shows "Equipped" badge
    - Equip sends RemoteFunction to server for validation
    - On success: updates local state and calls MascotVisual.spawn()

    Follows the same pattern as ShopUI.luau and CodesUI.luau.

    Validates: Requirements 6.4
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local MascotManager = require(ReplicatedStorage:WaitForChild("MascotManager"))
local MascotVisual = require(script.Parent.MascotVisual)

--============================================================================
-- Constants
--============================================================================

local BG_COLOR = Color3.fromRGB(15, 15, 25)
local PANEL_COLOR = Color3.fromRGB(25, 25, 40)
local ACCENT_COLOR = Color3.fromRGB(255, 150, 255) -- Pink/magenta
local TEXT_COLOR = Color3.fromRGB(220, 220, 230)
local LOCKED_COLOR = Color3.fromRGB(80, 80, 90)
local LOCKED_TEXT_COLOR = Color3.fromRGB(120, 120, 130)
local EQUIP_COLOR = Color3.fromRGB(50, 180, 80)
local EQUIPPED_COLOR = Color3.fromRGB(80, 140, 255)

--============================================================================
-- State
--============================================================================

local MascotUI = {}

local screenGui: ScreenGui? = nil
local mascotFrame: Frame? = nil
local isOpen: boolean = false
local isInitialized: boolean = false

-- Player mascot state (updated from server events)
local unlockedMascots: {string} = { "pixel_pup" } -- Default free mascot
local equippedMascot: string = "pixel_pup"

-- References to UI elements for updating
local mascotCards: { [string]: Frame } = {}
local equipButtons: { [string]: TextButton } = {}
local stateLabels: { [string]: TextLabel } = {}

--============================================================================
-- UI Construction
--============================================================================

local function createMascotGui(): ScreenGui
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

    local gui = Instance.new("ScreenGui")
    gui.Name = "MascotPanel"
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
    panel.Name = "MascotFrame"
    panel.Size = UDim2.new(0, 480, 0, 520)
    panel.Position = UDim2.new(0.5, -240, 0.5, -260)
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
    title.Text = "MASCOT COLLECTION"
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
        MascotUI.close()
    end)
end

local function createMascotCard(parent: Frame, mascotDef: typeof(MascotManager.MASCOT_DEFINITIONS[1]), index: number)
    -- Layout: 2 columns, 3 rows
    local col = ((index - 1) % 2)
    local row = math.floor((index - 1) / 2)

    local cardWidth = 215
    local cardHeight = 140
    local margin = 10
    local startX = 15
    local startY = 55

    local xPos = startX + col * (cardWidth + margin)
    local yPos = startY + row * (cardHeight + margin)

    local card = Instance.new("Frame")
    card.Name = "Card_" .. mascotDef.id
    card.Size = UDim2.new(0, cardWidth, 0, cardHeight)
    card.Position = UDim2.new(0, xPos, 0, yPos)
    card.BackgroundColor3 = PANEL_COLOR
    card.BackgroundTransparency = 0.1
    card.BorderSizePixel = 0
    card.Parent = parent

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 10)
    cardCorner.Parent = card

    -- Color swatch (small circle showing the mascot's color)
    local swatch = Instance.new("Frame")
    swatch.Name = "ColorSwatch"
    swatch.Size = UDim2.new(0, 28, 0, 28)
    swatch.Position = UDim2.new(0, 8, 0, 8)
    swatch.BackgroundColor3 = mascotDef.color
    swatch.BorderSizePixel = 0
    swatch.Parent = card

    local swatchCorner = Instance.new("UICorner")
    swatchCorner.CornerRadius = UDim.new(1, 0) -- Circle
    swatchCorner.Parent = swatch

    -- Mascot name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "MascotName"
    nameLabel.Size = UDim2.new(1, -48, 0, 22)
    nameLabel.Position = UDim2.new(0, 42, 0, 8)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = TEXT_COLOR
    nameLabel.TextSize = 14
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.Text = mascotDef.name
    nameLabel.Parent = card

    -- Description
    local descLabel = Instance.new("TextLabel")
    descLabel.Name = "Description"
    descLabel.Size = UDim2.new(1, -16, 0, 36)
    descLabel.Position = UDim2.new(0, 8, 0, 38)
    descLabel.BackgroundTransparency = 1
    descLabel.TextColor3 = Color3.fromRGB(160, 160, 180)
    descLabel.TextSize = 11
    descLabel.Font = Enum.Font.Gotham
    descLabel.TextXAlignment = Enum.TextXAlignment.Left
    descLabel.TextYAlignment = Enum.TextYAlignment.Top
    descLabel.TextWrapped = true
    descLabel.Text = mascotDef.description
    descLabel.Parent = card

    -- State label (shows "Locked" condition or "Equipped")
    local stateLabel = Instance.new("TextLabel")
    stateLabel.Name = "StateLabel"
    stateLabel.Size = UDim2.new(0.5, -8, 0, 26)
    stateLabel.Position = UDim2.new(0, 8, 1, -34)
    stateLabel.BackgroundTransparency = 1
    stateLabel.TextColor3 = LOCKED_TEXT_COLOR
    stateLabel.TextSize = 11
    stateLabel.Font = Enum.Font.GothamBold
    stateLabel.TextXAlignment = Enum.TextXAlignment.Left
    stateLabel.Text = ""
    stateLabel.Parent = card

    -- Equip button
    local equipBtn = Instance.new("TextButton")
    equipBtn.Name = "EquipBtn"
    equipBtn.Size = UDim2.new(0, 80, 0, 28)
    equipBtn.Position = UDim2.new(1, -88, 1, -36)
    equipBtn.BackgroundColor3 = EQUIP_COLOR
    equipBtn.BorderSizePixel = 0
    equipBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    equipBtn.TextSize = 12
    equipBtn.Font = Enum.Font.GothamBold
    equipBtn.Text = "EQUIP"
    equipBtn.Visible = false
    equipBtn.Parent = card

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = equipBtn

    -- Wire equip button
    equipBtn.MouseButton1Click:Connect(function()
        MascotUI._requestEquip(mascotDef.id)
    end)

    -- Store references
    mascotCards[mascotDef.id] = card
    equipButtons[mascotDef.id] = equipBtn
    stateLabels[mascotDef.id] = stateLabel
end

--============================================================================
-- State Updates
--============================================================================

local function isMascotUnlocked(mascotId: string): boolean
    for _, id in unlockedMascots do
        if id == mascotId then
            return true
        end
    end
    return false
end

local function updateUI()
    local mascots = MascotManager.getMascotDefinitions()

    for _, mascotDef in mascots do
        local card = mascotCards[mascotDef.id]
        local equipBtn = equipButtons[mascotDef.id]
        local stateLabel = stateLabels[mascotDef.id]
        if not card or not equipBtn or not stateLabel then continue end

        local unlocked = isMascotUnlocked(mascotDef.id)
        local isEquipped = (equippedMascot == mascotDef.id)

        if isEquipped then
            -- Equipped state
            stateLabel.Text = "EQUIPPED"
            stateLabel.TextColor3 = EQUIPPED_COLOR
            equipBtn.Visible = true
            equipBtn.Text = "EQUIPPED"
            equipBtn.BackgroundColor3 = EQUIPPED_COLOR
            equipBtn.Active = false
            card.BackgroundTransparency = 0.05
        elseif unlocked then
            -- Unlocked, can equip
            stateLabel.Text = "Unlocked"
            stateLabel.TextColor3 = Color3.fromRGB(100, 255, 130)
            equipBtn.Visible = true
            equipBtn.Text = "EQUIP"
            equipBtn.BackgroundColor3 = EQUIP_COLOR
            equipBtn.Active = true
            card.BackgroundTransparency = 0.1
        else
            -- Locked
            stateLabel.Text = "Locked"
            stateLabel.TextColor3 = LOCKED_TEXT_COLOR
            equipBtn.Visible = false
            card.BackgroundTransparency = 0.4
        end

        -- Update swatch opacity for locked items
        local swatch = card:FindFirstChild("ColorSwatch") :: Frame?
        if swatch then
            swatch.BackgroundTransparency = if unlocked then 0 else 0.6
        end

        -- Update name color for locked items
        local nameLabel = card:FindFirstChild("MascotName") :: TextLabel?
        if nameLabel then
            nameLabel.TextColor3 = if unlocked then TEXT_COLOR else LOCKED_TEXT_COLOR
        end
    end
end

--============================================================================
-- Equip Logic
--============================================================================

function MascotUI._requestEquip(mascotId: string)
    local eventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
    if not eventsFolder then return end

    local equipFunc = eventsFolder:FindFirstChild("EquipMascot") :: RemoteFunction?
    if not equipFunc then
        warn("[MascotUI] EquipMascot RemoteFunction not found")
        return
    end

    -- Send equip request to server
    local success, result = pcall(function()
        return equipFunc:InvokeServer(mascotId)
    end)

    if success and type(result) == "table" then
        if result.success then
            -- Update local state
            equippedMascot = mascotId
            updateUI()

            -- Spawn the mascot visual
            MascotVisual.spawn(mascotId)
        else
            -- Flash error on the card's equip button
            local btn = equipButtons[mascotId]
            if btn then
                local originalColor = btn.BackgroundColor3
                local originalText = btn.Text
                btn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
                btn.Text = result.message or "Failed"
                task.delay(1.5, function()
                    if btn then
                        btn.BackgroundColor3 = originalColor
                        btn.Text = originalText
                        updateUI()
                    end
                end)
            end
        end
    end
end

--============================================================================
-- ProximityPrompt Wiring
--============================================================================

local function wireProximityPrompt()
    ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, _player: Player)
        if prompt.Name == "MascotProximityPrompt" then
            MascotUI.open()
        end
    end)
end

--============================================================================
-- Remote Event Wiring
--============================================================================

local function wireRemoteEvents()
    local eventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
    if not eventsFolder then return end

    -- Listen for ShowLobby which includes player mascot data
    local showLobbyEvent = eventsFolder:WaitForChild("ShowLobby", 5) :: RemoteEvent?
    if showLobbyEvent then
        showLobbyEvent.OnClientEvent:Connect(function(data: any)
            if type(data) == "table" then
                if data.unlockedMascots and type(data.unlockedMascots) == "table" then
                    unlockedMascots = data.unlockedMascots
                end
                if data.equippedMascot and type(data.equippedMascot) == "string" then
                    equippedMascot = data.equippedMascot
                end
                if isOpen then
                    updateUI()
                end
            end
        end)
    end

    -- Listen for MascotUnlocked events
    local mascotUnlockedEvent = eventsFolder:WaitForChild("MascotUnlocked", 5) :: RemoteEvent?
    if mascotUnlockedEvent then
        mascotUnlockedEvent.OnClientEvent:Connect(function(data: any)
            if type(data) == "table" and data.mascotId then
                -- Add to unlocked list if not already there
                if not isMascotUnlocked(data.mascotId) then
                    table.insert(unlockedMascots, data.mascotId)
                end
                if isOpen then
                    updateUI()
                end
            end
        end)
    end
end

--============================================================================
-- Public API
--============================================================================

--- Initialize the MascotUI system.
function MascotUI.init()
    if isInitialized then return end
    isInitialized = true

    screenGui = createMascotGui()

    local backdrop = createBackdrop(screenGui)
    backdrop.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            MascotUI.close()
        end
    end)

    mascotFrame = createMainPanel(screenGui)
    createHeader(mascotFrame)
    createCloseButton(mascotFrame)

    -- Build mascot cards
    local mascots = MascotManager.getMascotDefinitions()
    for i, mascotDef in mascots do
        createMascotCard(mascotFrame, mascotDef, i)
    end

    wireProximityPrompt()
    wireRemoteEvents()
end

--- Open the mascot panel.
function MascotUI.open()
    if not isInitialized then
        MascotUI.init()
    end
    if screenGui then
        screenGui.Enabled = true
        isOpen = true
        updateUI()
    end
end

--- Close the mascot panel.
function MascotUI.close()
    if screenGui then
        screenGui.Enabled = false
        isOpen = false
    end
end

--- Check if the mascot panel is currently open.
function MascotUI.isOpen(): boolean
    return isOpen
end

--============================================================================
-- Auto-initialize
--============================================================================

task.defer(MascotUI.init)

return MascotUI
