--!strict
--[[
    GameServer.server.luau - Central game orchestrator for Pixel Run Obby

    Manages the full game loop with lobby-first player flow:
    - On player join: spawn player in Lobby, send pack data to client via ShowLobby RemoteEvent
    - Sequential pack unlocking: pack N requires all 10 levels of pack N-1 completed
    - First pack (Tetris) always unlocked
    - On entering unlocked portal: teleport to level 1 of selected pack
    - Generates level layout, builds model, positions player
    - Uses MorassManager for morass tracking and collision detection each frame
    - Accumulates XP at 1 per block traveled × pack multiplier
    - Awards 500 XP completion bonus at 1000-block mark
    - On level completion: presents choice to continue, advance, or return to lobby
    - Retains all XP on elimination (no XP loss on death)
    - Tracks level completions per pack (levels 1-10)
    - On completing level 10: offers return to lobby or replay

    Validates: Requirements 2.1, 2.3, 2.6, 3.3, 3.5, 3.6, 4.4, 4.6, 6.1, 6.2, 6.3, 6.5
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LevelGenerator = require(ServerScriptService.LevelGenerator)
local MorassManager = require(ServerScriptService.MorassManager)
local AchievementService = require(ServerScriptService.AchievementService)
local LeaderboardService = require(ServerScriptService.LeaderboardService)
local DataStoreManager = require(ServerScriptService.DataStoreManager)
local PackRegistry = require(ServerScriptService.PackRegistry)
local ValidationService = require(ServerScriptService.ValidationService)
local RateLimiter = require(ServerScriptService.RateLimiter)
local TetrisPack = require(ReplicatedStorage.LevelPacks.TetrisPack)
local Types = require(ReplicatedStorage.Types)
local LevelUtils = require(ReplicatedStorage.LevelUtils)
local PowerUpManager = require(ReplicatedStorage.PowerUpManager)

--============================================================================
-- Types
--============================================================================

type PlayerState = {
    player: Player,
    packId: string,
    levelNum: number,
    levelModel: Model?,
    startTime: number,
    isActive: boolean,         -- Whether level is actively being played
    currentXP: number,         -- Player's total accumulated XP
    runXP: number,             -- XP earned this run (for display purposes)
    lastBlockZ: number,        -- Last recorded Z position for XP calculation
    completions: {[string]: {number}},  -- packId -> completed level numbers
    packMultiplier: number,    -- XP multiplier for the current pack
    powerUps: { higherJump: number, doubleJump: number, fasterSpeed: number }, -- Purchased power-up tiers
}

--============================================================================
-- State
--============================================================================

local playerStates: { [Player]: PlayerState } = {}
local remoteEvents: { [string]: RemoteEvent } = {}
local remoteFunctions: { [string]: RemoteFunction } = {}

--============================================================================
-- Constants
--============================================================================

local LEVEL_START_POSITION = Vector3.new(10, 5, 0)  -- Scaled: center of 20-stud-wide track, above ground
local LOBBY_SPAWN_POSITION = Vector3.new(0, 5, 0)
local LEVEL_LENGTH = Types.LEVEL_LENGTH  -- 1000 blocks
local BLOCK_SCALE = 2                    -- Must match LevelGenerator.BLOCK_SCALE
local LEVEL_LENGTH_STUDS = LEVEL_LENGTH * BLOCK_SCALE  -- 2000 studs
local XP_UPDATE_INTERVAL = 1  -- Send XP updates every 1 second
local LEVELS_PER_PACK = 10  -- Number of levels in each pack

--============================================================================
-- Remote Events Setup
--============================================================================

local function createRemoteEvents()
    local eventsFolder = Instance.new("Folder")
    eventsFolder.Name = "RemoteEvents"
    eventsFolder.Parent = ReplicatedStorage

    local eventNames = {
        "PlayerEliminated",
        "LevelStarted",
        "LevelCompleted",
        "LevelChoice",
        "XPUpdate",
        "PowerUpUpdate",
        "AchievementAwarded",
        "ShowLobby",
        "RequestStartLevel",
        "ServerError",
    }
    for _, name in eventNames do
        local event = Instance.new("RemoteEvent")
        event.Name = name
        event.Parent = eventsFolder
        remoteEvents[name] = event
    end

    -- Create RemoteFunctions (request-response pattern)
    local functionNames = {
        "PurchasePowerUp",
        "RequestLeaderboard",
    }
    for _, name in functionNames do
        local fn = Instance.new("RemoteFunction")
        fn.Name = name
        fn.Parent = eventsFolder
        remoteFunctions[name] = fn
    end
end

--============================================================================
-- XP Helpers
--============================================================================

--- Get the pack multiplier for a given packId.
--- The multiplier equals the pack's displayOrder.
--- Falls back to TetrisPack direct reference if registry lookup fails.
local function getPackMultiplier(packId: string): number
    local packConfig = PackRegistry.getPackConfig(packId)
    if packConfig then
        return packConfig.displayOrder
    end
    -- Fallback for legacy "TetrisPack" ID (before registry used themeId)
    if packId == "TetrisPack" then
        return TetrisPack.displayOrder
    end
    return 1
end

--- Check if a player has already completed a specific level in a pack.
local function hasCompletedLevel(state: PlayerState, packId: string, levelNum: number): boolean
    local packCompletions = state.completions[packId]
    if not packCompletions then
        return false
    end
    for _, completedLevel in packCompletions do
        if completedLevel == levelNum then
            return true
        end
    end
    return false
end

--- Record a level completion for a player.
local function recordLevelCompletion(state: PlayerState, packId: string, levelNum: number)
    if not state.completions[packId] then
        state.completions[packId] = {}
    end
    -- Only add if not already completed
    if not hasCompletedLevel(state, packId, levelNum) then
        table.insert(state.completions[packId], levelNum)
    end
end

--============================================================================
-- Pack Unlock Logic
--============================================================================

--- Determine the number of completed levels for a pack from a completions table.
local function getCompletedLevelCount(completions: {[string]: {number}}, packId: string): number
    local packCompletions = completions[packId]
    if not packCompletions then
        return 0
    end
    return #packCompletions
end

--- Check if a pack is unlocked for a player based on sequential unlock logic.
--- Pack 1 (no prerequisitePack, or first in orderedPacks) is always unlocked.
--- Pack N is unlocked if the player has completed all 10 levels of pack N-1.
local function isPackUnlocked(completions: {[string]: {number}}, packId: string, orderedPacks: {string}): boolean
    -- Find the index of this pack in the ordered list
    local packIndex = 0
    for i, id in orderedPacks do
        if id == packId then
            packIndex = i
            break
        end
    end

    -- If pack not found in the ordered list, check if it has no prerequisite
    if packIndex == 0 then
        local config = PackRegistry.getPackConfig(packId)
        if config and config.prerequisitePack == nil then
            return true
        end
        return false
    end

    -- First pack is always unlocked
    if packIndex == 1 then
        return true
    end

    -- Pack N is unlocked if player completed all 10 levels of pack N-1
    local previousPackId = orderedPacks[packIndex - 1]
    local completedCount = getCompletedLevelCount(completions, previousPackId)
    return completedCount >= LEVELS_PER_PACK
end

--============================================================================
-- Error Communication
--============================================================================

--- Fire a ServerError RemoteEvent to the client, triggering HUDManager.showError.
local function fireServerError(player: Player, message: string)
    if remoteEvents["ServerError"] then
        remoteEvents["ServerError"]:FireClient(player, { message = message })
    end
end

--============================================================================
-- Lobby Management
--============================================================================

--- Build lobby pack data and send ShowLobby RemoteEvent to the player.
--- Positions player at the neutral lobby spawn position.
local function sendToLobby(player: Player)
    -- Position the player character at lobby spawn
    local character = player.Character
    if character then
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if humanoidRootPart then
            humanoidRootPart.CFrame = CFrame.new(LOBBY_SPAWN_POSITION)
        end
    end

    -- Get player's completions from state or DataStore
    local completions: {[string]: {number}} = {}
    local state = playerStates[player]
    if state then
        completions = state.completions
    else
        -- Load from DataStore cache if no active state
        local profileData = DataStoreManager.getCachedData(player.UserId)
        if profileData then
            completions = profileData.completions
        end
    end

    -- Build pack display data from PackRegistry
    local orderedPacks = PackRegistry.getOrderedPacks()
    local packDisplayList = {}

    for _, packId in orderedPacks do
        local config = PackRegistry.getPackConfig(packId)
        if config then
            local completedLevels = getCompletedLevelCount(completions, packId)
            local unlocked = isPackUnlocked(completions, packId, orderedPacks)

            -- Determine prerequisite name for lock message
            local prerequisiteName: string? = nil
            if config.prerequisitePack then
                local prereqConfig = PackRegistry.getPackConfig(config.prerequisitePack)
                if prereqConfig then
                    prerequisiteName = prereqConfig.name
                end
            elseif not unlocked then
                -- Find the previous pack name from the ordered list
                for i, id in orderedPacks do
                    if id == packId and i > 1 then
                        local prevConfig = PackRegistry.getPackConfig(orderedPacks[i - 1])
                        if prevConfig then
                            prerequisiteName = prevConfig.name
                        end
                        break
                    end
                end
            end

            table.insert(packDisplayList, {
                packId = packId,
                name = config.name,
                displayOrder = config.displayOrder,
                themeId = config.themeId,
                completedLevels = completedLevels,
                isUnlocked = unlocked,
                prerequisiteName = prerequisiteName,
            })
        end
    end

    -- Fire ShowLobby RemoteEvent to client
    if remoteEvents["ShowLobby"] then
        remoteEvents["ShowLobby"]:FireClient(player, {
            packs = packDisplayList,
        })
    end
end

--============================================================================
-- Level Management
--============================================================================

--- Start a level for a player.
--- Generates layout, builds the model, positions the player, and starts morass.
local function startLevel(player: Player, packId: string, levelNum: number)
    -- Clean up any existing level for this player
    local existingState = playerStates[player]
    if existingState and existingState.levelModel then
        existingState.levelModel:Destroy()
    end

    -- Clean up any existing morass
    MorassManager.cleanup(player)

    -- Generate and build the level using PackRegistry lookup, fallback to TetrisPack
    local packConfig = PackRegistry.getPackConfig(packId)
    if not packConfig then
        -- Fallback: use TetrisPack directly for backward compatibility
        packConfig = TetrisPack
    end
    local layout = LevelGenerator.generateLevel(packConfig, levelNum)
    local levelModel = LevelGenerator.buildLevel(layout)
    levelModel.Name = "Level_" .. player.Name .. "_" .. packId .. "_" .. tostring(levelNum)

    -- Parent level model to workspace in a Levels folder
    local levelsFolder = workspace:FindFirstChild("Levels")
    if not levelsFolder then
        levelsFolder = Instance.new("Folder")
        levelsFolder.Name = "Levels"
        levelsFolder.Parent = workspace
    end
    levelModel.Parent = levelsFolder

    -- Position the player character at level start
    local character = player.Character
    if character then
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if humanoidRootPart then
            humanoidRootPart.CFrame = CFrame.new(LEVEL_START_POSITION)
        end
    end

    -- Initialize morass (spawns 50 blocks behind player start)
    MorassManager.init(player, layout, LEVEL_START_POSITION.Z)
    MorassManager.startMorass(player)

    -- Get pack multiplier
    local packMultiplier = getPackMultiplier(packId)

    -- Preserve existing XP state or initialize for new players
    local existingXP = 0
    local existingCompletions: {[string]: {number}} = {}
    local existingPowerUps = { higherJump = 0, doubleJump = 0, fasterSpeed = 0 }
    if existingState then
        existingXP = existingState.currentXP
        existingCompletions = existingState.completions
        existingPowerUps = existingState.powerUps
    end

    -- Track player state
    playerStates[player] = {
        player = player,
        packId = packId,
        levelNum = levelNum,
        levelModel = levelModel,
        startTime = tick(),
        isActive = true,
        currentXP = existingXP,
        runXP = 0,
        lastBlockZ = LEVEL_START_POSITION.Z,
        completions = existingCompletions,
        packMultiplier = packMultiplier,
        powerUps = existingPowerUps,
    }

    -- Notify client that level has started
    if remoteEvents["LevelStarted"] then
        remoteEvents["LevelStarted"]:FireClient(player, {
            packId = packId,
            levelNum = levelNum,
            conveyorSpeed = layout.conveyorSpeed,
            morassVisual = layout.morassVisual,
        })
    end
end

--============================================================================
-- Level Completion
--============================================================================

--- Handle level completion when player reaches the 1000-block mark.
local function completeLevel(player: Player)
    local state = playerStates[player]
    if not state or not state.isActive then
        return
    end

    -- Deactivate level (stop morass, stop XP tracking)
    state.isActive = false
    MorassManager.stopMorass(player)

    -- Award completion bonus
    local completionBonus = LevelUtils.calculateCompletionBonus()
    state.currentXP += completionBonus
    state.runXP += completionBonus

    -- Record level completion
    recordLevelCompletion(state, state.packId, state.levelNum)

    -- Pass current completions to AchievementService and check for pack achievement
    AchievementService.setPlayerCompletions(player, state.completions)
    AchievementService.checkPackCompletion(player, state.packId)

    -- Determine choices to present to the player
    local choices: {string} = {"continue", "next"}

    -- If player completed level 10, offer lobby instead of next
    if state.levelNum >= 10 then
        choices = {"continue", "lobby"}
    end

    -- Fire LevelCompleted event to client
    if remoteEvents["LevelCompleted"] then
        remoteEvents["LevelCompleted"]:FireClient(player, {
            bonus = completionBonus,
            totalXP = state.currentXP,
            runXP = state.runXP,
            levelNum = state.levelNum,
            packId = state.packId,
            choices = choices,
        })
    end
end

--- Handle the player's choice after level completion.
local function handleLevelChoice(player: Player, choice: string)
    local state = playerStates[player]
    if not state then
        return
    end

    if choice == "continue" then
        -- Restart the same level
        startLevel(player, state.packId, state.levelNum)
    elseif choice == "next" then
        -- Advance to next level (capped at 10)
        local nextLevel = math.min(state.levelNum + 1, 10)
        startLevel(player, state.packId, nextLevel)
    elseif choice == "lobby" then
        -- Clean up level model and morass, send player back to lobby
        if state.levelModel then
            state.levelModel:Destroy()
            state.levelModel = nil
        end
        MorassManager.cleanup(player)
        state.isActive = false
        sendToLobby(player)
    end
end

--============================================================================
-- Elimination
--============================================================================

--- Eliminate a player: stop morass, respawn at level start, reset morass, restart.
--- XP earned during the run is RETAINED (no deduction on death).
local function eliminatePlayer(player: Player, cause: string)
    local state = playerStates[player]
    if not state or not state.isActive then
        return
    end

    -- Temporarily deactivate
    state.isActive = false

    -- XP is retained — runXP was already added to currentXP incrementally
    -- Reset runXP counter for next run but keep currentXP intact
    state.runXP = 0
    state.lastBlockZ = LEVEL_START_POSITION.Z

    -- Respawn player at level start position
    local character = player.Character
    if character then
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if humanoidRootPart then
            humanoidRootPart.CFrame = CFrame.new(LEVEL_START_POSITION)
        end
    end

    -- Reset morass to spawn position (50 blocks behind) and restart
    MorassManager.resetMorass(player)
    MorassManager.startMorass(player)

    -- Re-activate level
    state.startTime = tick()
    state.isActive = true

    -- Fire PlayerEliminated RemoteEvent to client
    if remoteEvents["PlayerEliminated"] then
        remoteEvents["PlayerEliminated"]:FireClient(player, {
            cause = cause,
            xpRetained = state.currentXP,
        })
    end
end

--============================================================================
-- Player Connections
--============================================================================

--- Handle a player joining the game.
--- Spawns player in Lobby with pack data, loading persisted profile first.
local function onPlayerJoin(player: Player)
    -- Wait for the character to load
    local character = player.Character or player.CharacterAdded:Wait()
    -- Brief wait for physics to settle
    task.wait(0.5)

    -- Load player data from DataStore (or use defaults on failure)
    local profileData = DataStoreManager.loadPlayerData(player.UserId)
    if not profileData then
        profileData = Types.DEFAULT_PLAYER_PROFILE
    end

    -- Initialize player state with persisted data (not actively in a level yet)
    playerStates[player] = {
        player = player,
        packId = "",
        levelNum = 0,
        levelModel = nil,
        startTime = tick(),
        isActive = false,
        currentXP = profileData.xp,
        runXP = 0,
        lastBlockZ = 0,
        completions = profileData.completions,
        packMultiplier = 1,
        powerUps = profileData.powerUps,
    }

    -- Spawn player in lobby and send pack data to client
    sendToLobby(player)
end

--- Handle a player leaving the game.
--- Clean up player state and level model.
local function onPlayerLeave(player: Player)
    local state = playerStates[player]
    if state then
        state.isActive = false
        if state.levelModel then
            state.levelModel:Destroy()
        end
        playerStates[player] = nil
    end

    -- Clean up morass
    MorassManager.cleanup(player)

    -- Clean up rate limiter state
    RateLimiter.reset(player.UserId)
end

--============================================================================
-- Heartbeat: Morass Collision + XP Accumulation + Level Completion
--============================================================================

--- Each frame: check morass collision, accumulate XP, detect level completion.
local function onHeartbeat(_deltaTime: number)
    for player, state in playerStates do
        if not state.isActive then
            continue
        end

        -- Get player position
        local character = player.Character
        if not character then
            continue
        end

        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not humanoidRootPart then
            continue
        end

        local playerZ = humanoidRootPart.Position.Z

        -- Check morass collision
        if MorassManager.checkCollision(player) then
            eliminatePlayer(player, "morass")
            continue
        end

        -- XP Accumulation: award XP for each new block traveled (convert studs to blocks)
        if playerZ > state.lastBlockZ then
            local blocksAdvanced = math.floor(playerZ / BLOCK_SCALE) - math.floor(state.lastBlockZ / BLOCK_SCALE)
            if blocksAdvanced > 0 then
                local xpEarned = LevelUtils.calculateXP(blocksAdvanced, state.packMultiplier)
                state.currentXP += xpEarned
                state.runXP += xpEarned
                state.lastBlockZ = playerZ
            end
        end

        -- Level Completion Detection: player reached the end (scaled)
        if playerZ >= LEVEL_LENGTH_STUDS then
            completeLevel(player)
        end
    end
end

--============================================================================
-- XP Update Timer
--============================================================================

--- Periodically sends XP updates to clients (every 1 second).
local lastXPUpdateTime = 0

local function onXPUpdateHeartbeat(_deltaTime: number)
    local currentTime = tick()
    if currentTime - lastXPUpdateTime < XP_UPDATE_INTERVAL then
        return
    end
    lastXPUpdateTime = currentTime

    for player, state in playerStates do
        if remoteEvents["XPUpdate"] then
            remoteEvents["XPUpdate"]:FireClient(player, {
                currentXP = state.currentXP,
                runXP = state.runXP,
                packId = state.packId,
                levelNum = state.levelNum,
            })
        end
    end
end

--============================================================================
-- Initialization
--============================================================================

local function init()
    -- Initialize PackRegistry: auto-discover and register all level packs
    PackRegistry.init()

    -- Start DataStoreManager auto-save loop
    DataStoreManager.startAutoSave()

    -- Create RemoteEvents folder for client communication
    createRemoteEvents()

    -- Listen for player level choices
    if remoteEvents["LevelChoice"] then
        remoteEvents["LevelChoice"].OnServerEvent:Connect(function(player: Player, data: any)
            -- Rate limit check
            if not RateLimiter.check(player.UserId) then
                return
            end

            if type(data) == "table" and type(data.choice) == "string" then
                handleLevelChoice(player, data.choice)
            elseif type(data) == "string" then
                handleLevelChoice(player, data)
            end
        end)
    end

    -- Listen for RequestStartLevel from client (lobby portal click)
    if remoteEvents["RequestStartLevel"] then
        remoteEvents["RequestStartLevel"].OnServerEvent:Connect(function(player: Player, data: any)
            -- Rate limit check
            if not RateLimiter.check(player.UserId) then
                return
            end

            if type(data) ~= "table" then
                return
            end
            local packId = data.packId
            local levelNum = data.levelNum or 1
            if type(packId) ~= "string" then
                return
            end
            -- Validate pack exists in registry
            if not PackRegistry.hasPack(packId) then
                fireServerError(player, "Invalid pack: pack does not exist")
                return
            end
            -- Validate pack is unlocked using ValidationService
            local profile = DataStoreManager.getCachedData(player.UserId)
            if not profile then
                -- Fallback: try player state completions
                local state = playerStates[player]
                if state then
                    local orderedPacks = PackRegistry.getOrderedPacks()
                    if not isPackUnlocked(state.completions, packId, orderedPacks) then
                        fireServerError(player, "Pack is locked: complete the previous pack first")
                        return
                    end
                end
            else
                if not ValidationService.isPackUnlocked(profile, packId) then
                    fireServerError(player, "Pack is locked: complete the previous pack first")
                    return
                end
            end
            -- Start the level for the player (always level 1 when entering from portal)
            startLevel(player, packId, math.clamp(levelNum, 1, 10))
        end)
    end

    -- Set up PurchasePowerUp RemoteFunction handler
    if remoteFunctions["PurchasePowerUp"] then
        remoteFunctions["PurchasePowerUp"].OnServerInvoke = function(player: Player, data: any)
            -- Rate limit check
            if not RateLimiter.check(player.UserId) then
                return { success = false, message = "Rate limit exceeded, please slow down" }
            end

            -- Validate input data
            if type(data) ~= "table" then
                return { success = false, message = "Invalid request data" }
            end

            local powerUpId = data.powerUpId
            local tier = data.tier

            if type(powerUpId) ~= "string" or type(tier) ~= "number" then
                return { success = false, message = "Invalid power-up ID or tier" }
            end

            -- Use ValidationService for comprehensive purchase validation
            local isValid, validationError = ValidationService.validatePurchase(player, powerUpId, tier)
            if not isValid then
                return { success = false, message = validationError or "Purchase rejected" }
            end

            -- Get player state
            local state = playerStates[player]
            if not state then
                return { success = false, message = "No player state" }
            end

            -- Build a temporary PlayerProfile for applying the purchase
            local profile: Types.PlayerProfile = {
                version = Types.CURRENT_PROFILE_VERSION,
                xp = state.currentXP,
                powerUps = {
                    higherJump = state.powerUps.higherJump,
                    doubleJump = state.powerUps.doubleJump,
                    fasterSpeed = state.powerUps.fasterSpeed,
                },
                completions = state.completions,
                achievements = {},
                highestLevel = 0,
                totalBlocksRun = 0,
            }

            -- Apply with PowerUpManager.applyPurchase
            profile = PowerUpManager.applyPurchase(profile, powerUpId, tier)

            -- Update player state
            state.currentXP = profile.xp
            state.powerUps = profile.powerUps

            -- Fire PowerUpUpdate event to client so InputController can apply effects
            if remoteEvents["PowerUpUpdate"] then
                remoteEvents["PowerUpUpdate"]:FireClient(player, {
                    powerUps = state.powerUps,
                })
            end

            return { success = true, message = "Purchase successful", newData = state.powerUps }
        end
    end

    -- Set up RequestLeaderboard RemoteFunction handler
    if remoteFunctions["RequestLeaderboard"] then
        remoteFunctions["RequestLeaderboard"].OnServerInvoke = function(player: Player, data: any)
            -- Rate limit check
            if not RateLimiter.check(player.UserId) then
                return { entries = {}, playerRank = 0, playerValue = 0, board = "xp" }
            end

            -- Validate input
            local board = "xp"
            if type(data) == "table" and type(data.board) == "string" then
                if data.board == "xp" or data.board == "level" then
                    board = data.board
                end
            end

            -- Get top entries from LeaderboardService
            local entries
            if board == "xp" then
                entries = LeaderboardService.getTopXP(Types.LEADERBOARD_TOP_COUNT)
            else
                entries = LeaderboardService.getTopLevel(Types.LEADERBOARD_TOP_COUNT)
            end

            -- Get the requesting player's rank and score
            local playerRank, playerValue = LeaderboardService.getPlayerRank(player.UserId, board)

            return {
                entries = entries,
                playerRank = playerRank or 0,
                playerValue = playerValue or 0,
                board = board,
            }
        end
    end

    -- Connect player events
    Players.PlayerAdded:Connect(onPlayerJoin)
    Players.PlayerRemoving:Connect(onPlayerLeave)

    -- Handle players already in the game (in case script loads late)
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayerJoin, player)
    end

    -- Start morass collision detection + XP accumulation on Heartbeat
    RunService.Heartbeat:Connect(onHeartbeat)

    -- Start periodic XP update broadcasts
    RunService.Heartbeat:Connect(onXPUpdateHeartbeat)
end

-- Run initialization
init()
