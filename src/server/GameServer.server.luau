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
local CodesManager = require(ServerScriptService.CodesManager)
local LobbyBuilder = require(ServerScriptService.LobbyBuilder)
local TetrisPack = require(ReplicatedStorage.LevelPacks.TetrisPack)
local Types = require(ReplicatedStorage.Types)
local LevelUtils = require(ReplicatedStorage.LevelUtils)
local PowerUpManager = require(ReplicatedStorage.PowerUpManager)
local RewardsManager = require(ReplicatedStorage.RewardsManager)
local ComboManager = require(ReplicatedStorage.ComboManager)
local MascotManager = require(ReplicatedStorage.MascotManager)
local GameModeManager = require(ReplicatedStorage.GameModeManager)

--============================================================================
-- Types
--============================================================================

type PlayerState = {
    player: Player,
    packId: string,
    levelNum: number,
    levelModel: Model?,
    levelLayout: Types.LevelLayout?,  -- Stored layout for near-miss detection
    startTime: number,
    isActive: boolean,         -- Whether level is actively being played
    currentXP: number,         -- Player's total accumulated XP
    runXP: number,             -- XP earned this run (for display purposes)
    lastBlockZ: number,        -- Last recorded Z position for XP calculation
    completions: {[string]: {number}},  -- packId -> completed level numbers
    packMultiplier: number,    -- XP multiplier for the current pack
    powerUps: { higherJump: number, doubleJump: number, fasterSpeed: number }, -- Purchased power-up tiers
    comboState: Types.ComboState,   -- Combo system state (near-miss tracking)
    passedObstacleIndex: number,    -- Index of last obstacle the player has passed (for near-miss scan)
    modeId: string,                 -- Game mode ID ("classic", "time_attack", "sprint")
    modeConfig: Types.GameModeConfig?,  -- Mode config for current level
    timerStartTime: number?,        -- When the mode timer started (tick)
    timerElapsed: number?,          -- Accumulated timer seconds (for count-up)
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
local LOBBY_SPAWN_POSITION = Vector3.new(0, 5, 0)   -- Updated by LobbyBuilder.init()
local LEVEL_LENGTH = Types.LEVEL_LENGTH  -- 500 blocks
local BLOCK_SCALE = 2                    -- Must match LevelGenerator.BLOCK_SCALE
local LEVEL_LENGTH_STUDS = LEVEL_LENGTH * BLOCK_SCALE  -- 1000 studs
local XP_UPDATE_INTERVAL = 1  -- Send XP updates every 1 second
local LEVELS_PER_PACK = 10  -- Number of levels in each pack
local GATE_COOLDOWN = 2  -- Seconds between gate triggers per player
local gateCooldowns: { [Player]: number } = {}  -- Prevent repeated gate triggers
local NEAR_MISS_DISTANCE_STUDS = ComboManager.NEAR_MISS_DISTANCE * BLOCK_SCALE  -- 1 block in studs
local MASCOT_UNLOCK_THROTTLE = 2  -- Seconds between mascot unlock checks per player
local lastMascotCheckTime: { [Player]: number } = {}  -- Throttle unlock checks per player

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
        "SaveSettings",
        "SettingsLoaded",
        "ComboUpdate",
        "MascotUnlocked",
        "TimerUpdate",
        "ShowModeSelection",
        "SaveTutorial",
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
        "RedeemCode",
        "ClaimDailySpin",
        "EquipMascot",
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
-- Mascot Unlock Logic
--============================================================================

--- Calculate a player's login streak from their profile data.
--- Compares lastLoginDate to current time using day boundaries (86400 seconds per day).
--- Returns the updated streak count.
local function calculateLoginStreak(lastLoginDate: number?, currentLoginStreak: number?): number
    local now = os.time()
    local currentStreak = currentLoginStreak or 0

    if not lastLoginDate then
        -- First ever login
        return 1
    end

    -- Calculate day boundaries (using UTC days)
    local lastDay = math.floor(lastLoginDate / 86400)
    local todayDay = math.floor(now / 86400)
    local dayDifference = todayDay - lastDay

    if dayDifference == 0 then
        -- Same day, streak unchanged
        return currentStreak
    elseif dayDifference == 1 then
        -- Consecutive day, increment streak
        return currentStreak + 1
    else
        -- Streak broken (more than 1 day gap), reset to 1
        return 1
    end
end

--- Attempts to unlock all qualifying mascots for a player.
--- Evaluates each mascot definition against player data, unlocks any newly qualifying mascots,
--- fires MascotUnlocked RemoteEvent for each new unlock, and persists to DataStore cache.
--- @param player Player -- The player to check unlocks for
--- @param playerData { xp: number, completions: {[string]: {number}}, comboHighest: number?, loginStreak: number? }
local function tryUnlockMascots(player: Player, playerData: {
    xp: number,
    completions: {[string]: {number}},
    comboHighest: number?,
    loginStreak: number?,
})
    -- Get current unlocked list from DataStore cache
    local cachedProfile = DataStoreManager.getCachedData(player.UserId)
    if not cachedProfile then
        return
    end

    local unlockedList: {string} = cachedProfile.unlockedMascots or { "pixel_pup" }

    -- Evaluate all mascot definitions
    local mascotDefs = MascotManager.getMascotDefinitions()
    local newUnlocks: {string} = {}

    for _, mascotDef in mascotDefs do
        -- Skip if already unlocked
        if MascotManager.isUnlocked(unlockedList, mascotDef.id) then
            continue
        end

        -- Check if player now meets the unlock condition
        if MascotManager.checkUnlockConditions(mascotDef.id, playerData) then
            -- Unlock the mascot
            unlockedList = MascotManager.unlock(unlockedList, mascotDef.id)
            table.insert(newUnlocks, mascotDef.id)
        end
    end

    -- If any new unlocks occurred, persist and fire events
    if #newUnlocks > 0 then
        -- Update cached profile
        cachedProfile.unlockedMascots = unlockedList

        -- Fire MascotUnlocked event for each newly unlocked mascot
        for _, mascotId in newUnlocks do
            if remoteEvents["MascotUnlocked"] then
                remoteEvents["MascotUnlocked"]:FireClient(player, { mascotId = mascotId })
            end
        end
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

    -- Gather leaderboard snapshot for lobby display (top 5 each)
    local topXP = LeaderboardService.getTopXP(5)
    local topLevel = LeaderboardService.getTopLevel(5)
    local playerRankXP, playerValueXP = LeaderboardService.getPlayerRank(player.UserId, "xp")
    local playerRankLevel, playerValueLevel = LeaderboardService.getPlayerRank(player.UserId, "level")

    -- Fire ShowLobby RemoteEvent to client with packs + leaderboard data
    -- Get mascot data from cached profile
    local cachedProfile = DataStoreManager.getCachedData(player.UserId)
    local unlockedMascotsList: {string} = { "pixel_pup" }
    local equippedMascotId: string = "pixel_pup"
    if cachedProfile then
        if cachedProfile.unlockedMascots then
            unlockedMascotsList = cachedProfile.unlockedMascots
        end
        if cachedProfile.equippedMascot then
            equippedMascotId = cachedProfile.equippedMascot
        end
    end

    if remoteEvents["ShowLobby"] then
        remoteEvents["ShowLobby"]:FireClient(player, {
            packs = packDisplayList,
            leaderboard = {
                topXP = topXP,
                topLevel = topLevel,
                playerRankXP = playerRankXP,
                playerValueXP = playerValueXP,
                playerRankLevel = playerRankLevel,
                playerValueLevel = playerValueLevel,
            },
            unlockedMascots = unlockedMascotsList,
            equippedMascot = equippedMascotId,
            tutorialCompleted = cachedProfile and cachedProfile.tutorialCompleted or false,
        })
    end
end

--============================================================================
-- Level Management
--============================================================================

--- Start a level for a player.
--- Generates layout, builds the model, positions the player, and starts morass (if mode allows).
--- Accepts an optional modeId to select the game mode (defaults to "classic").
local function startLevel(player: Player, packId: string, levelNum: number, modeId: string?)
    -- Clean up any existing level for this player
    local existingState = playerStates[player]
    if existingState and existingState.levelModel then
        existingState.levelModel:Destroy()
    end

    -- Clean up any existing morass
    MorassManager.cleanup(player)

    -- Resolve mode config
    local resolvedModeId = modeId or "classic"
    local modeConfig = GameModeManager.getModeConfig(resolvedModeId)

    -- Generate and build the level using PackRegistry lookup, fallback to TetrisPack
    local packConfig = PackRegistry.getPackConfig(packId)
    if not packConfig then
        -- Fallback: use TetrisPack directly for backward compatibility
        packConfig = TetrisPack
    end
    local layout = LevelGenerator.generateLevel(packConfig, levelNum, modeConfig)
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

    -- Initialize morass only if the mode uses it
    if not modeConfig or modeConfig.hasMorass then
        MorassManager.init(player, layout, LEVEL_START_POSITION.Z, levelNum)
        MorassManager.startMorass(player)
    end

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

    -- Timer state: start timer if mode requires it
    local timerStartTime: number? = nil
    if modeConfig and modeConfig.hasTimer then
        timerStartTime = tick()
    end

    -- Track player state
    playerStates[player] = {
        player = player,
        packId = packId,
        levelNum = levelNum,
        levelModel = levelModel,
        levelLayout = layout,
        startTime = tick(),
        isActive = true,
        currentXP = existingXP,
        runXP = 0,
        lastBlockZ = LEVEL_START_POSITION.Z,
        completions = existingCompletions,
        packMultiplier = packMultiplier,
        powerUps = existingPowerUps,
        comboState = ComboManager.createDefaultState(),
        passedObstacleIndex = 0,
        modeId = resolvedModeId,
        modeConfig = modeConfig,
        timerStartTime = timerStartTime,
        timerElapsed = nil,
    }

    -- Notify client that level has started (include mode info + death/PB stats)
    local levelKey = packId .. "_" .. tostring(levelNum)
    local attemptCount = 1
    local personalBest = 0
    local cachedProfileStart = DataStoreManager.getCachedData(player.UserId)
    if cachedProfileStart then
        if cachedProfileStart.deathCounts and cachedProfileStart.deathCounts[levelKey] then
            attemptCount = cachedProfileStart.deathCounts[levelKey] + 1
        end
        if cachedProfileStart.personalBests and cachedProfileStart.personalBests[levelKey] then
            personalBest = cachedProfileStart.personalBests[levelKey]
        end
    end

    if remoteEvents["LevelStarted"] then
        remoteEvents["LevelStarted"]:FireClient(player, {
            packId = packId,
            levelNum = levelNum,
            conveyorSpeed = layout.conveyorSpeed,
            morassVisual = layout.morassVisual,
            modeId = resolvedModeId,
            hasTimer = modeConfig and modeConfig.hasTimer or false,
            timerDirection = modeConfig and modeConfig.timerDirection or nil,
            timerDuration = modeConfig and modeConfig.timerDuration or nil,
            attemptCount = attemptCount,
            personalBest = personalBest,
        })
    end
end

--============================================================================
-- Level Completion
--============================================================================

--- Handle level completion when player reaches the 1000-block mark.
--- For Sprint mode, this is triggered when the timer expires (distance-based scoring).
local function completeLevel(player: Player)
    local state = playerStates[player]
    if not state or not state.isActive then
        return
    end

    -- Deactivate level (stop morass if applicable, stop XP tracking)
    state.isActive = false
    local modeConfig = state.modeConfig
    if not modeConfig or modeConfig.hasMorass then
        MorassManager.stopMorass(player)
    end

    -- Award completion bonus
    local completionBonus = LevelUtils.calculateCompletionBonus()
    state.currentXP += completionBonus
    state.runXP += completionBonus

    -- Record level completion
    recordLevelCompletion(state, state.packId, state.levelNum)

    -- Pass current completions to AchievementService and check for pack achievement
    AchievementService.setPlayerCompletions(player, state.completions)
    AchievementService.checkPackCompletion(player, state.packId)

    -- Check mascot unlocks after pack completion (pack_complete + xp_threshold triggers)
    local cachedProfile = DataStoreManager.getCachedData(player.UserId)
    local comboHighest: number = 0
    local loginStreak: number = 0
    if cachedProfile then
        comboHighest = cachedProfile.comboHighest or 0
        loginStreak = cachedProfile.loginStreak or 0
    end
    tryUnlockMascots(player, {
        xp = state.currentXP,
        completions = state.completions,
        comboHighest = comboHighest,
        loginStreak = loginStreak,
    })

    -- Write mode-specific leaderboard score for Time Attack and Sprint
    if state.modeId == "time_attack" and state.timerStartTime then
        -- Time Attack: score = elapsed time in seconds (lower is better)
        local elapsedTime = tick() - state.timerStartTime
        LeaderboardService.updateModeScore(player.UserId, state.modeId, state.packId, elapsedTime)
    elseif state.modeId == "sprint" and state.timerStartTime then
        -- Sprint: score = distance traveled in blocks (higher is better)
        local distanceStuds = math.max(0, state.lastBlockZ - LEVEL_START_POSITION.Z)
        local distanceBlocks = math.floor(distanceStuds / BLOCK_SCALE)
        LeaderboardService.updateModeScore(player.UserId, state.modeId, state.packId, distanceBlocks)
    end

    -- Determine choices to present to the player
    local choices: {string} = {"continue", "next"}

    -- If player completed level 10, offer lobby instead of next
    if state.levelNum >= 10 then
        choices = {"continue", "lobby"}
    end

    -- Fire LevelCompleted event to client
    if remoteEvents["LevelCompleted"] then
        -- Calculate final timer value for timed modes
        local finalTimerValue: number? = nil
        if state.modeConfig and state.modeConfig.hasTimer and state.timerStartTime then
            local elapsed = tick() - state.timerStartTime
            if state.modeConfig.timerDirection == "down" then
                finalTimerValue = math.max(0, (state.modeConfig.timerDuration or 60) - elapsed)
            else
                finalTimerValue = elapsed
            end
        end

        remoteEvents["LevelCompleted"]:FireClient(player, {
            bonus = completionBonus,
            totalXP = state.currentXP,
            runXP = state.runXP,
            levelNum = state.levelNum,
            packId = state.packId,
            choices = choices,
            modeId = state.modeId,
            finalTimerValue = finalTimerValue,
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
        -- Restart the same level with the same mode
        startLevel(player, state.packId, state.levelNum, state.modeId)
    elseif choice == "next" then
        -- Advance to next level (capped at 10), keep mode
        local nextLevel = math.min(state.levelNum + 1, 10)
        startLevel(player, state.packId, nextLevel, state.modeId)
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

    -- Track death count and personal best for this level
    local levelKey = state.packId .. "_" .. tostring(state.levelNum)
    local cachedProfileDeath = DataStoreManager.getCachedData(player.UserId)
    if cachedProfileDeath then
        -- Increment death count
        if not cachedProfileDeath.deathCounts then
            cachedProfileDeath.deathCounts = {}
        end
        cachedProfileDeath.deathCounts[levelKey] = (cachedProfileDeath.deathCounts[levelKey] or 0) + 1

        -- Update personal best distance (convert studs to blocks)
        local distanceStuds = math.max(0, state.lastBlockZ - LEVEL_START_POSITION.Z)
        local distanceBlocks = math.floor(distanceStuds / BLOCK_SCALE)
        if not cachedProfileDeath.personalBests then
            cachedProfileDeath.personalBests = {}
        end
        local currentBest = cachedProfileDeath.personalBests[levelKey] or 0
        if distanceBlocks > currentBest then
            cachedProfileDeath.personalBests[levelKey] = distanceBlocks
        end
    end

    -- XP is retained — runXP was already added to currentXP incrementally
    -- Reset runXP counter for next run but keep currentXP intact
    state.runXP = 0
    state.lastBlockZ = LEVEL_START_POSITION.Z

    -- Reset combo on elimination
    state.comboState = ComboManager.resetCombo(state.comboState)
    state.passedObstacleIndex = 0

    -- Notify client of combo reset
    if remoteEvents["ComboUpdate"] then
        remoteEvents["ComboUpdate"]:FireClient(player, {
            streak = 0,
            multiplier = 1.0,
            tierName = nil,
        })
    end

    -- Respawn player at level start position
    local character = player.Character
    if character then
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if humanoidRootPart then
            humanoidRootPart.CFrame = CFrame.new(LEVEL_START_POSITION)
        end
    end

    -- Reset morass to spawn position (50 blocks behind) and restart (only if mode has morass)
    local modeConfig = state.modeConfig
    if not modeConfig or modeConfig.hasMorass then
        MorassManager.resetMorass(player)
        MorassManager.startMorass(player)
    end

    -- Reset timer on elimination if mode has a timer
    if modeConfig and modeConfig.hasTimer then
        state.timerStartTime = tick()
        state.timerElapsed = nil
    end

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

    -- Set player collision height to 3 blocks (6 studs) so they cannot walk
    -- through gaps smaller than 3 blocks. The default R15 character is ~5 studs;
    -- we increase HipHeight to make the collision capsule 6 studs tall.
    local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
    if humanoid then
        humanoid.HipHeight = 2.5 -- Raises the capsule so total height ≈ 6 studs (3 blocks)

        -- Listen for initial character death (obstacle collision resets combo)
        humanoid.Died:Connect(function()
            local state = playerStates[player]
            if state and state.isActive then
                if state.comboState.streak > 0 then
                    state.comboState = ComboManager.resetCombo(state.comboState)
                    state.passedObstacleIndex = 0
                    if remoteEvents["ComboUpdate"] then
                        remoteEvents["ComboUpdate"]:FireClient(player, {
                            streak = 0,
                            multiplier = 1.0,
                            tierName = nil,
                        })
                    end
                end
            end
        end)
    end

    -- Also set this on future respawns
    player.CharacterAdded:Connect(function(newCharacter: Model)
        local newHumanoid = newCharacter:WaitForChild("Humanoid") :: Humanoid
        newHumanoid.HipHeight = 2.5

        -- Listen for character death (obstacle collision resets combo)
        newHumanoid.Died:Connect(function()
            local state = playerStates[player]
            if state and state.isActive then
                -- Reset combo on any death (obstacle hit, etc.)
                if state.comboState.streak > 0 then
                    state.comboState = ComboManager.resetCombo(state.comboState)
                    state.passedObstacleIndex = 0
                    if remoteEvents["ComboUpdate"] then
                        remoteEvents["ComboUpdate"]:FireClient(player, {
                            streak = 0,
                            multiplier = 1.0,
                            tierName = nil,
                        })
                    end
                end
            end
        end)
    end)

    -- Load player data from DataStore (or use defaults on failure)
    local profileData = DataStoreManager.loadPlayerData(player.UserId)
    if not profileData then
        profileData = Types.DEFAULT_PLAYER_PROFILE
    end

    -- Calculate and update login streak
    local loginStreak = calculateLoginStreak(profileData.lastLoginDate, profileData.loginStreak)
    profileData.loginStreak = loginStreak
    profileData.lastLoginDate = os.time()

    -- Initialize player state with persisted data (not actively in a level yet)
    playerStates[player] = {
        player = player,
        packId = "",
        levelNum = 0,
        levelModel = nil,
        levelLayout = nil,
        startTime = tick(),
        isActive = false,
        currentXP = profileData.xp,
        runXP = 0,
        lastBlockZ = 0,
        completions = profileData.completions,
        packMultiplier = 1,
        powerUps = profileData.powerUps,
        comboState = ComboManager.createDefaultState(),
        passedObstacleIndex = 0,
        modeId = "classic",
        modeConfig = nil,
        timerStartTime = nil,
        timerElapsed = nil,
    }

    -- Spawn player in lobby and send pack data to client
    sendToLobby(player)

    -- Check mascot unlocks on login (for login_streak condition)
    tryUnlockMascots(player, {
        xp = profileData.xp,
        completions = profileData.completions,
        comboHighest = profileData.comboHighest or 0,
        loginStreak = loginStreak,
    })

    -- Load redeemed codes from player profile
    CodesManager.loadPlayerRedemptions(player.UserId, profileData.redeemedCodes)

    -- Send saved settings to client
    if remoteEvents["SettingsLoaded"] and profileData.settings then
        remoteEvents["SettingsLoaded"]:FireClient(player, profileData.settings)
    end
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

    -- Clean up codes manager state
    CodesManager.clearPlayer(player.UserId)

    -- Clean up gate cooldown
    gateCooldowns[player] = nil

    -- Clean up mascot unlock throttle
    lastMascotCheckTime[player] = nil
end

--============================================================================
-- Heartbeat: Morass Collision + XP Accumulation + Level Completion
--============================================================================

--- Each frame: check morass collision, detect near-misses, accumulate XP, detect level completion.
--- Also handles mode-specific timer logic (Time Attack count-up, Sprint countdown).
local function onHeartbeat(_deltaTime: number)
    local currentTime = tick()

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

        local playerPosition = humanoidRootPart.Position
        local playerZ = playerPosition.Z

        -- Check morass collision (only if mode has morass)
        local modeConfig = state.modeConfig
        if not modeConfig or modeConfig.hasMorass then
            if MorassManager.checkCollision(player) then
                eliminatePlayer(player, "morass")
                continue
            end
        end

        -- Sprint timer: check if countdown expired
        if modeConfig and modeConfig.hasTimer and modeConfig.timerDirection == "down" and state.timerStartTime then
            local elapsed = currentTime - state.timerStartTime
            local remaining = (modeConfig.timerDuration or 60) - elapsed
            if remaining <= 0 then
                -- Sprint time is up — complete the level (distance-based scoring)
                completeLevel(player)
                continue
            end
        end

        -- Combo: check timeout (reset if no near-miss for > 1 second)
        if state.comboState.streak > 0 and ComboManager.shouldTimeout(state.comboState, currentTime) then
            state.comboState = ComboManager.resetCombo(state.comboState)

            -- Notify client of combo reset
            if remoteEvents["ComboUpdate"] then
                remoteEvents["ComboUpdate"]:FireClient(player, {
                    streak = 0,
                    multiplier = 1.0,
                    tierName = nil,
                })
            end
        end

        -- Combo: detect near-miss events for obstacles the player has just passed
        if state.levelLayout and state.levelLayout.obstacles then
            local obstacles = state.levelLayout.obstacles
            local startIndex = state.passedObstacleIndex + 1

            for i = startIndex, #obstacles do
                local obstacle = obstacles[i]
                local obstacleZ = obstacle.position.Z * BLOCK_SCALE

                -- Only process obstacles the player has passed (playerZ > obstacleZ)
                if playerZ <= obstacleZ then
                    break -- Obstacles are sorted by Z, so no more have been passed
                end

                -- Player has passed this obstacle — check if it was a near-miss
                -- Calculate closest lateral distance (X axis) from player to obstacle blocks
                local obstacleX = obstacle.position.X * BLOCK_SCALE
                local lateralDist = math.abs(playerPosition.X - obstacleX)

                -- Check Z distance (how close we passed)
                local zDist = math.abs(playerZ - obstacleZ)

                -- Near-miss: passed within NEAR_MISS_DISTANCE_STUDS without collision
                -- (if collision happened, eliminatePlayer would have been called already)
                if lateralDist <= NEAR_MISS_DISTANCE_STUDS * 3 or zDist <= NEAR_MISS_DISTANCE_STUDS * 2 then
                    -- This obstacle was close enough to count as a near-miss
                    local prevTierName = state.comboState.tierName

                    if state.comboState.streak == 0 then
                        state.comboState = ComboManager.startCombo(state.comboState, currentTime)
                    else
                        state.comboState = ComboManager.incrementCombo(state.comboState, currentTime)
                    end

                    -- Fire ComboUpdate to client
                    if remoteEvents["ComboUpdate"] then
                        remoteEvents["ComboUpdate"]:FireClient(player, {
                            streak = state.comboState.streak,
                            multiplier = state.comboState.multiplier,
                            tierName = state.comboState.tierName,
                            tierChanged = (state.comboState.tierName ~= prevTierName and state.comboState.tierName ~= nil),
                        })
                    end

                    -- Check combo milestone mascot unlock (e.g., Flame Fox at 50-combo)
                    -- Update comboHighest in profile and check if milestone triggers unlock
                    local cachedProfileCombo = DataStoreManager.getCachedData(player.UserId)
                    if cachedProfileCombo then
                        local prevHighest = cachedProfileCombo.comboHighest or 0
                        if state.comboState.streak > prevHighest then
                            cachedProfileCombo.comboHighest = state.comboState.streak
                            -- Only check unlock when crossing a milestone threshold
                            tryUnlockMascots(player, {
                                xp = state.currentXP,
                                completions = state.completions,
                                comboHighest = state.comboState.streak,
                                loginStreak = cachedProfileCombo.loginStreak or 0,
                            })
                        end
                    end
                end

                state.passedObstacleIndex = i
            end
        end

        -- XP Accumulation: award XP for each new block traveled (convert studs to blocks)
        if playerZ > state.lastBlockZ then
            local blocksAdvanced = math.floor(playerZ / BLOCK_SCALE) - math.floor(state.lastBlockZ / BLOCK_SCALE)
            if blocksAdvanced > 0 then
                -- Apply combo multiplier on top of pack multiplier
                local comboMultiplier = ComboManager.getCurrentMultiplier(state.comboState)
                local xpEarned = LevelUtils.calculateXP(blocksAdvanced, state.packMultiplier)
                xpEarned = math.floor(xpEarned * comboMultiplier)
                state.currentXP += xpEarned
                state.runXP += xpEarned
                state.lastBlockZ = playerZ

                -- Throttled mascot unlock check for XP threshold (Golden Dragon)
                local lastCheck = lastMascotCheckTime[player] or 0
                if currentTime - lastCheck >= MASCOT_UNLOCK_THROTTLE then
                    lastMascotCheckTime[player] = currentTime
                    local cachedProfileXP = DataStoreManager.getCachedData(player.UserId)
                    if cachedProfileXP then
                        cachedProfileXP.xp = state.currentXP
                        tryUnlockMascots(player, {
                            xp = state.currentXP,
                            completions = state.completions,
                            comboHighest = cachedProfileXP.comboHighest or 0,
                            loginStreak = cachedProfileXP.loginStreak or 0,
                        })
                    end
                end
            end
        end

        -- Level Completion Detection: player reached the end (scaled)
        -- Sprint mode has no target distance — level ends when timer expires (handled above)
        if state.modeConfig and state.modeConfig.targetDistance == nil then
            -- No distance target (Sprint mode): completion is timer-driven only
        elseif playerZ >= LEVEL_LENGTH_STUDS then
            completeLevel(player)
        end
    end
end

--============================================================================
-- XP Update Timer
--============================================================================

--- Periodically sends XP updates to clients (every 1 second).
--- Also sends TimerUpdate events for modes with timers.
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

        -- Send timer update if mode has a timer and level is active
        if state.isActive and state.modeConfig and state.modeConfig.hasTimer and state.timerStartTime then
            local elapsed = currentTime - state.timerStartTime
            local timerValue: number
            if state.modeConfig.timerDirection == "down" then
                -- Countdown: show remaining time
                timerValue = math.max(0, (state.modeConfig.timerDuration or 60) - elapsed)
            else
                -- Count-up: show elapsed time
                timerValue = elapsed
            end

            if remoteEvents["TimerUpdate"] then
                remoteEvents["TimerUpdate"]:FireClient(player, {
                    timerValue = timerValue,
                    timerDirection = state.modeConfig.timerDirection,
                    modeId = state.modeId,
                })
            end
        end
    end
end

--============================================================================
-- Initialization
--============================================================================

local function init()
    -- Initialize PackRegistry: auto-discover and register all level packs
    PackRegistry.init()

    -- Initialize CodesManager: seed default codes
    CodesManager.init()

    -- Build the physical 3D lobby (ground, gate, shop, signs)
    local gateTrigger = LobbyBuilder.init()
    LOBBY_SPAWN_POSITION = LobbyBuilder.getSpawnPosition()

    -- Start DataStoreManager auto-save loop
    DataStoreManager.startAutoSave()

    -- Create RemoteEvents folder for client communication
    createRemoteEvents()

    -- Wire the Tetris gate touch trigger to start level when a player walks through
    if gateTrigger then
        gateTrigger.Touched:Connect(function(hit: BasePart)
            -- Find the player from the touched part
            local character = hit.Parent
            if not character then
                return
            end
            local player = Players:GetPlayerFromCharacter(character)
            if not player then
                return
            end

            -- Cooldown check (prevent repeated triggers)
            local now = tick()
            if gateCooldowns[player] and (now - gateCooldowns[player]) < GATE_COOLDOWN then
                return
            end
            gateCooldowns[player] = now

            -- Only trigger if player is in lobby (not actively in a level)
            local state = playerStates[player]
            if state and state.isActive then
                return
            end

            -- Determine next level to play
            local packId = "tetris"
            local levelNum = 1
            if state and state.completions[packId] then
                -- Start at the next uncompleted level
                local completed = #state.completions[packId]
                if completed < LEVELS_PER_PACK then
                    levelNum = completed + 1
                end
            end

            -- Check if pack is fully completed (all 10 levels done)
            -- If complete, show mode selection UI instead of starting Classic immediately
            local completions: {[string]: {number}} = {}
            if state then
                completions = state.completions
            end

            local packFullyCompleted = getCompletedLevelCount(completions, packId) >= LEVELS_PER_PACK
            if packFullyCompleted then
                -- Build available modes list (only unlocked modes)
                local allModes = GameModeManager.getAvailableModes()
                local availableModes: {{ id: string, name: string, description: string }} = {}
                for _, mode in allModes do
                    if GameModeManager.isModeUnlocked(mode.id, packId, completions) then
                        table.insert(availableModes, {
                            id = mode.id,
                            name = mode.name,
                            description = mode.description,
                        })
                    end
                end

                -- If more than just Classic is available, show mode selection
                if #availableModes > 1 and remoteEvents["ShowModeSelection"] then
                    remoteEvents["ShowModeSelection"]:FireClient(player, {
                        packId = packId,
                        levelNum = levelNum,
                        modes = availableModes,
                    })
                    return
                end
            end

            -- Default: start Classic mode immediately (uncompleted pack or only Classic unlocked)
            startLevel(player, packId, levelNum)
        end)
    end

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
            local requestedModeId = data.modeId or "classic"
            if type(packId) ~= "string" then
                return
            end
            if type(requestedModeId) ~= "string" then
                requestedModeId = "classic"
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

            -- Validate mode is unlocked for this pack (non-classic modes require pack completion)
            if requestedModeId ~= "classic" then
                local completions: {[string]: {number}} = {}
                local state = playerStates[player]
                if state then
                    completions = state.completions
                end
                if not GameModeManager.isModeUnlocked(requestedModeId, packId, completions) then
                    fireServerError(player, "Mode locked: complete this pack in Classic first")
                    return
                end
            end

            -- Start the level for the player
            startLevel(player, packId, math.clamp(levelNum, 1, 10), requestedModeId)
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

    -- Set up RedeemCode RemoteFunction handler
    if remoteFunctions["RedeemCode"] then
        remoteFunctions["RedeemCode"].OnServerInvoke = function(player: Player, data: any)
            -- Rate limit check
            if not RateLimiter.check(player.UserId) then
                return { success = false, message = "Rate limit exceeded, please slow down" }
            end

            -- Validate input
            if type(data) ~= "string" then
                return { success = false, message = "Invalid code input" }
            end

            -- Attempt redemption
            local result = CodesManager.redeemCode(player.UserId, data)

            -- If successful, apply the reward and persist
            if result.success and result.reward then
                local state = playerStates[player]
                if state and result.reward.rewardType == "xp" then
                    local xpAmount = result.reward.amount or 0
                    state.currentXP += xpAmount
                end

                -- Update the DataStore cache with the redeemed codes list
                local cachedProfile = DataStoreManager.getCachedData(player.UserId)
                if cachedProfile then
                    cachedProfile.redeemedCodes = CodesManager.getRedeemedList(player.UserId)
                    if state then
                        cachedProfile.xp = state.currentXP
                    end
                end
            end

            return {
                success = result.success,
                message = result.message,
            }
        end
    end

    -- Set up ClaimDailySpin RemoteFunction handler
    if remoteFunctions["ClaimDailySpin"] then
        remoteFunctions["ClaimDailySpin"].OnServerInvoke = function(player: Player, _data: any)
            -- Rate limit check
            if not RateLimiter.check(player.UserId) then
                return { success = false, message = "Rate limit exceeded, please slow down" }
            end

            -- Get player state
            local state = playerStates[player]
            if not state then
                return { success = false, message = "No player state" }
            end

            -- Check if player already spun today (server-authoritative via RewardsManager)
            local now = os.time()
            local cachedProfile = DataStoreManager.getCachedData(player.UserId)
            local lastSpinDate: number? = nil
            if cachedProfile then
                lastSpinDate = cachedProfile.lastDailySpinDate
            end

            if not RewardsManager.canSpinToday(lastSpinDate, now) then
                return { success = false, message = "Come back tomorrow!" }
            end

            -- Determine reward via RewardsManager (nil seed = random)
            local rewardResult = RewardsManager.determineReward(nil)

            -- Apply reward
            state.currentXP += rewardResult.xpAmount

            -- Persist the spin timestamp
            if cachedProfile then
                cachedProfile.lastDailySpinDate = now
                cachedProfile.xp = state.currentXP
            end

            return {
                success = true,
                message = "You won " .. rewardResult.label .. "!",
                reward = rewardResult.xpAmount,
                segmentIndex = rewardResult.segmentIndex,
            }
        end
    end

    -- Set up EquipMascot RemoteFunction handler
    if remoteFunctions["EquipMascot"] then
        remoteFunctions["EquipMascot"].OnServerInvoke = function(player: Player, data: any)
            -- Rate limit check
            if not RateLimiter.check(player.UserId) then
                return { success = false, message = "Rate limit exceeded, please slow down" }
            end

            -- Validate input
            if type(data) ~= "string" then
                return { success = false, message = "Invalid mascot ID" }
            end

            local mascotId = data

            -- Get player state
            local state = playerStates[player]
            if not state then
                return { success = false, message = "No player state" }
            end

            -- Get unlocked mascots from DataStore cache
            local cachedProfile = DataStoreManager.getCachedData(player.UserId)
            local unlockedList: {string} = { "pixel_pup" }
            if cachedProfile and cachedProfile.unlockedMascots then
                unlockedList = cachedProfile.unlockedMascots
            end

            -- Validate equip via MascotManager
            local equippedId, equipError = MascotManager.equip(mascotId, unlockedList)
            if not equippedId then
                return { success = false, message = equipError or "Cannot equip mascot" }
            end

            -- Persist equipped mascot
            if cachedProfile then
                cachedProfile.equippedMascot = equippedId
            end

            return { success = true, mascotId = equippedId }
        end
    end

    -- Listen for SaveSettings event from client
    if remoteEvents["SaveSettings"] then
        remoteEvents["SaveSettings"].OnServerEvent:Connect(function(player: Player, data: any)
            -- Rate limit check
            if not RateLimiter.check(player.UserId) then
                return
            end

            -- Validate input
            if type(data) ~= "table" then
                return
            end

            local newMusicVolume = data.musicVolume
            local newSfxVolume = data.sfxVolume
            local newScreenShake = data.screenShake

            -- Validate types and ranges
            if type(newMusicVolume) ~= "number" or type(newSfxVolume) ~= "number" or type(newScreenShake) ~= "boolean" then
                return
            end

            newMusicVolume = math.clamp(math.floor(newMusicVolume), 0, 100)
            newSfxVolume = math.clamp(math.floor(newSfxVolume), 0, 100)

            -- Persist settings in the DataStore cache
            local cachedProfile = DataStoreManager.getCachedData(player.UserId)
            if cachedProfile then
                cachedProfile.settings = {
                    musicVolume = newMusicVolume,
                    sfxVolume = newSfxVolume,
                    screenShake = newScreenShake,
                }
            end
        end)
    end

    -- Listen for SaveTutorial event from client
    if remoteEvents["SaveTutorial"] then
        remoteEvents["SaveTutorial"].OnServerEvent:Connect(function(player: Player, _data: any)
            -- Rate limit check
            if not RateLimiter.check(player.UserId) then
                return
            end

            -- Persist tutorialCompleted flag in the DataStore cache
            local cachedProfile = DataStoreManager.getCachedData(player.UserId)
            if cachedProfile then
                cachedProfile.tutorialCompleted = true
            end
        end)
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

    -- Periodically update the physical leaderboard boards in the lobby (every 30s)
    task.spawn(function()
        while true do
            task.wait(30)
            local topXP = LeaderboardService.getTopXP(5)
            local topLevel = LeaderboardService.getTopLevel(5)
            LobbyBuilder.updateLeaderboards(topXP, topLevel)
        end
    end)
end

-- Run initialization
init()
