--!strict
--[[
    Types.luau - Shared type definitions and constants for Pixel Run Obby
    
    This module defines all shared types used across client, server, and shared modules,
    as well as static power-up configuration constants.
    
    Validates: Requirements 7.1, 12.1
]]

local Types = {}

--============================================================================
-- Type Definitions
--============================================================================

--- Player profile persisted via DataStoreService.
--- Storage Key: "player_" .. tostring(userId)
export type PlayerProfile = {
    version: number,               -- Schema version (currently 1)
    xp: number,                    -- Total accumulated XP
    powerUps: {
        higherJump: number,        -- 0-3 (tier)
        doubleJump: number,        -- 0-1 (boolean as tier)
        fasterSpeed: number,       -- 0-3 (tier)
    },
    completions: {
        [string]: {number},        -- packId -> list of completed level numbers
    },
    achievements: {string},        -- List of earned achievement IDs
    highestLevel: number,          -- Overall highest level number (for leaderboard)
    totalBlocksRun: number,        -- Lifetime stat
}

--- Defines a single obstacle type within a level pack.
export type ObstacleDefinition = {
    shape: string,                 -- Shape identifier (e.g., "I", "O", "T", "S", "Z", "L", "J")
    orientations: {number},        -- Degrees: {0, 90, 180, 270}
    color: Color3,                 -- Visual color of the obstacle
    maxHeight: number,             -- Maximum height in blocks
    isTouchKill: boolean,          -- Whether contact eliminates the player
}

--- Difficulty configuration for a specific level number within a pack.
export type LevelDifficulty = {
    obstacleDensity: number,       -- Obstacles per block (1/50 to 1/10)
    maxHeight: number,             -- Maximum obstacle height for this level
    gapWidth: number,              -- Maximum gap width in blocks
    voidLength: number,            -- Maximum void section length in blocks
    hasTouchKill: boolean,         -- Whether touch-and-die obstacles appear
    requiredPowerUps: {string}?,   -- Power-ups needed to pass this level (nil = none)
}

--- Configuration schema for a Level Pack module.
--- Each pack module must export a table conforming to this schema.
export type LevelPackConfig = {
    name: string,                  -- Display name of the pack
    displayOrder: number,          -- Numeric ordering for portal placement
    themeId: string,               -- Theme identifier for visuals/music
    obstacleTypes: {ObstacleDefinition}, -- Available obstacle types in this pack
    difficulty: {[number]: LevelDifficulty}, -- Level 1-10 difficulty configs
    morassVisual: string,          -- Visual style for the advancing morass
    achievementName: string,       -- Achievement awarded on pack completion
    musicTrack: string,            -- Background music track identifier
    prerequisitePack: string?,     -- Pack that must be completed first (nil for first pack)
}

--- Runtime configuration for generating a specific level instance.
export type LevelConfig = {
    width: number,                 -- Level width in blocks (always 10)
    length: number,                -- Level length in blocks (always 1000)
    seed: number,                  -- Deterministic seed derived from packId + levelNum
    obstacleDensity: number,       -- Obstacles per block for this level
    obstacleTypes: {ObstacleDefinition}, -- Obstacle types available at this difficulty
    maxHeight: number,             -- Maximum obstacle height
    gapWidth: number,              -- Maximum gap width
    voidLength: number,            -- Maximum void section length
    hasTouchKill: boolean,         -- Whether touch-kill obstacles are active
}

--- Generated layout output from the level generator.
export type LevelLayout = {
    obstacles: {{
        position: Vector3,
        shape: string,
        orientation: number,
        color: Color3,
        isTouchKill: boolean,
    }},
    conveyorSpeed: number,         -- Minimum speed in blocks per second
    morassVisual: string,          -- Visual style for the morass
}

--- Definition of a purchasable power-up with tiered costs and effects.
export type PowerUpDefinition = {
    id: string,                    -- Unique identifier (e.g., "higherJump")
    name: string,                  -- Display name (e.g., "Higher Jump")
    maxTier: number,               -- Maximum purchasable tier
    costs: {number},               -- XP cost per tier (indexed 1 to maxTier)
    multipliers: {number},         -- Effect multiplier per tier (indexed 1 to maxTier)
}

--- A single entry in the leaderboard display.
export type LeaderboardEntry = {
    userId: number,                -- Roblox user ID
    displayName: string,           -- Player display name
    value: number,                 -- Score value (XP or highest level)
}

--============================================================================
-- Power-Up Constants
--============================================================================

--- Static power-up definitions matching the design data model.
--- Higher Jump: 3 tiers (1.25x, 1.5x, 2.0x) costing 2000, 5000, 12000 XP
--- Double Jump: 1 tier (enabled) costing 8000 XP
--- Faster Speed: 3 tiers (1.25x, 1.5x, 2.0x) costing 2000, 5000, 12000 XP
Types.POWER_UP_DEFINITIONS = {
    {
        id = "higherJump",
        name = "Higher Jump",
        maxTier = 3,
        costs = {2000, 5000, 12000},
        multipliers = {1.25, 1.5, 2.0},
    },
    {
        id = "doubleJump",
        name = "Double Jump",
        maxTier = 1,
        costs = {8000},
        multipliers = {1.0},  -- Binary: enabled or not (1.0 = enabled)
    },
    {
        id = "fasterSpeed",
        name = "Faster Speed",
        maxTier = 3,
        costs = {2000, 5000, 12000},
        multipliers = {1.25, 1.5, 2.0},
    },
}

--============================================================================
-- Game Constants
--============================================================================

--- Level dimensions
Types.LEVEL_WIDTH = 10              -- Blocks wide
Types.LEVEL_LENGTH = 1000           -- Blocks long

--- XP configuration
Types.XP_PER_BLOCK = 1             -- Base XP per block traveled
Types.LEVEL_COMPLETION_BONUS = 500  -- Bonus XP for completing a level

--- Player profile schema version
Types.CURRENT_PROFILE_VERSION = 1

--- Default player profile for new players or failed data loads
Types.DEFAULT_PLAYER_PROFILE = {
    version = Types.CURRENT_PROFILE_VERSION,
    xp = 0,
    powerUps = {
        higherJump = 0,
        doubleJump = 0,
        fasterSpeed = 0,
    },
    completions = {},
    achievements = {},
    highestLevel = 0,
    totalBlocksRun = 0,
}

--- Morass spawn offset (blocks behind player start)
Types.MORASS_SPAWN_OFFSET = 50

--- Rate limiting
Types.MAX_REMOTE_CALLS_PER_SECOND = 30

--- Data persistence
Types.AUTO_SAVE_INTERVAL = 60       -- Seconds between auto-saves
Types.DATA_LOAD_RETRIES = 3         -- Maximum retry attempts for data load
Types.DATA_LOAD_RETRY_DELAY = 2     -- Seconds between retry attempts
Types.DATA_SAVE_RETRIES = 3         -- Maximum retry attempts for data save

--- Leaderboard
Types.LEADERBOARD_TOP_COUNT = 100   -- Number of top players to display

return Types
