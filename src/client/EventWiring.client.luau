--!strict
--[[
    EventWiring.client.luau - Client-side RemoteEvent wiring for effects and audio

    Connects remaining RemoteEvent listeners that are not handled by other client modules:
    - LevelStarted → SoundManager.playPackMusic (play pack theme music)
    - ShowLobby → SoundManager.playLobbyMusic (play lobby music)
    - PlayerEliminated → EffectsManager.playDeath (death particle burst)
    - LevelCompleted → EffectsManager.playLevelComplete (confetti effect)
    - XPUpdate → EffectsManager.playXPGain (floating XP text)

    Other modules already handle their own event wiring:
    - HUDManager: XPUpdate (display), LevelCompleted (choice UI), PlayerEliminated (hide UI), AchievementAwarded
    - LobbyUI: ShowLobby (show portals), LevelStarted (hide lobby)
    - InputController: PowerUpUpdate (apply power-up effects)

    Validates: Requirements 13.4, 13.5
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EffectsManager = require(script.Parent.EffectsManager)
local SoundManager = require(script.Parent.SoundManager)
local HUDManager = require(script.Parent.HUDManager)
local LobbyUI = require(script.Parent.LobbyUI)
local ShopUI = require(script.Parent.ShopUI)
local CodesUI = require(script.Parent.CodesUI)
local SpinUI = require(script.Parent.SpinUI)
local SettingsUI = require(script.Parent.SettingsUI)
local ModeSelectUI = require(script.Parent.ModeSelectUI)
local TutorialUI = require(script.Parent.TutorialUI)

--============================================================================
-- Helpers
--============================================================================

--- Get the local player's current HumanoidRootPart position.
--- Falls back to a default position if character or root part is unavailable.
local function getPlayerPosition(): Vector3
    local player = Players.LocalPlayer
    if player and player.Character then
        local rootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if rootPart then
            return rootPart.Position
        end
    end
    return Vector3.new(0, 5, 0)
end

--============================================================================
-- State for XP delta tracking
--============================================================================

local lastKnownRunXP: number = 0

--============================================================================
-- Event Wiring
--============================================================================

local function wireEvents()
    local eventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
    if not eventsFolder then
        warn("[EventWiring] RemoteEvents folder not found")
        return
    end

    -- LevelStarted → Play pack music based on the theme + trigger tutorial if new player
    local levelStartedEvent = eventsFolder:WaitForChild("LevelStarted", 5) :: RemoteEvent?
    if levelStartedEvent then
        levelStartedEvent.OnClientEvent:Connect(function(data: any)
            if type(data) == "table" then
                -- Use morassVisual as the theme identifier for music selection
                -- The server sends { packId, levelNum, conveyorSpeed, morassVisual }
                local theme = data.morassVisual or data.packId or "tetris"
                SoundManager.playPackMusic(theme)

                -- Start morass proximity warning with level-scaled intensity
                local levelNum = data.levelNum or 1
                EffectsManager.startMorassProximityWarning(levelNum)
            end
            -- Trigger tutorial overlay for new players on first level start
            TutorialUI.onLevelStarted()
        end)
    end

    -- ShowLobby → Play lobby music + notify TutorialUI + stop morass warning
    local showLobbyEvent = eventsFolder:WaitForChild("ShowLobby", 5) :: RemoteEvent?
    if showLobbyEvent then
        showLobbyEvent.OnClientEvent:Connect(function(data: any)
            SoundManager.playLobbyMusic()
            EffectsManager.stopMorassProximityWarning()
            TutorialUI.onShowLobby(data)
        end)
    end

    -- PlayerEliminated → Play death effect at player position + stop morass warning
    local eliminatedEvent = eventsFolder:WaitForChild("PlayerEliminated", 5) :: RemoteEvent?
    if eliminatedEvent then
        eliminatedEvent.OnClientEvent:Connect(function(_data: any)
            local position = getPlayerPosition()
            EffectsManager.playDeath(position)
            EffectsManager.stopMorassProximityWarning()
        end)
    end

    -- LevelCompleted → Play level complete effect at player position
    local levelCompletedEvent = eventsFolder:WaitForChild("LevelCompleted", 5) :: RemoteEvent?
    if levelCompletedEvent then
        levelCompletedEvent.OnClientEvent:Connect(function(_data: any)
            local position = getPlayerPosition()
            EffectsManager.playLevelComplete(position)
        end)
    end

    -- XPUpdate → Play XP gain effect when XP has increased
    local xpUpdateEvent = eventsFolder:WaitForChild("XPUpdate", 5) :: RemoteEvent?
    if xpUpdateEvent then
        xpUpdateEvent.OnClientEvent:Connect(function(data: any)
            if type(data) == "table" then
                local runXP = data.runXP or 0
                -- Calculate the delta since the last update to show earned amount
                local earnedSinceLastUpdate = runXP - lastKnownRunXP
                if earnedSinceLastUpdate > 0 then
                    local position = getPlayerPosition()
                    EffectsManager.playXPGain(earnedSinceLastUpdate, position)
                end
                lastKnownRunXP = runXP
            end
        end)
    end
end

--============================================================================
-- Initialize
--============================================================================

wireEvents()

-- Initialize SettingsUI (gear button always visible)
SettingsUI.init()

-- Initialize ModeSelectUI (mode selection popup for completed packs)
ModeSelectUI.init()
