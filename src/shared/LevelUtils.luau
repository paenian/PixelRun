--!strict
--[[
    LevelUtils.luau - Pure utility functions for level calculations
    
    Usable by both client and server. All functions are deterministic
    and side-effect free.
    
    Validates: Requirements 3.2, 6.1, 6.2, 6.3
]]

local Types = require(script.Parent.Types)

local LevelUtils = {}

--============================================================================
-- XP Calculations
--============================================================================

--- Calculate XP earned for a run based on blocks traveled and pack multiplier.
--- XP = blocks_traveled × pack_number (pack 1 = 1x, pack 2 = 2x, etc.)
--- @param blocksRun number -- Non-negative number of blocks the player traveled
--- @param packNumber number -- Pack multiplier (1-based pack display order)
--- @return number -- Total XP earned for the run (before completion bonus)
function LevelUtils.calculateXP(blocksRun: number, packNumber: number): number
    return blocksRun * packNumber
end

--- Get the fixed completion bonus awarded when a player finishes a level.
--- @return number -- Completion bonus XP (always 500)
function LevelUtils.calculateCompletionBonus(): number
    return Types.LEVEL_COMPLETION_BONUS
end

--============================================================================
-- Level Configuration
--============================================================================

--- Calculate obstacle density for a given level number.
--- Linear interpolation from 1/50 (level 1) to 1/10 (level 10).
--- @param levelNum number -- Level number within a pack (1-10)
--- @return number -- Obstacles per block (density value)
function LevelUtils.getObstacleDensity(levelNum: number): number
    -- Clamp levelNum to valid range
    local level = math.clamp(levelNum, 1, 10)
    
    -- Linear interpolation between 1/50 (level 1) and 1/10 (level 10)
    local minDensity = 1 / 50  -- 0.02 at level 1
    local maxDensity = 1 / 10  -- 0.10 at level 10
    
    -- t goes from 0 (level 1) to 1 (level 10)
    local t = (level - 1) / 9
    
    return minDensity + t * (maxDensity - minDensity)
end

--- Generate a deterministic seed from a pack ID string and level number.
--- The same inputs always produce the same seed value.
--- @param packId string -- Unique string identifier for the level pack
--- @param levelNum number -- Level number within the pack (1-10)
--- @return number -- Deterministic integer seed for RNG
function LevelUtils.getLevelSeed(packId: string, levelNum: number): number
    -- Hash the packId string into a numeric value using character codes
    local hash = 0
    for i = 1, #packId do
        -- Use a simple but effective hash: multiply-and-add with prime numbers
        hash = (hash * 31 + string.byte(packId, i)) % 2147483647
    end
    
    -- Combine with level number to produce unique seed per level
    -- Use a different prime to avoid collisions between adjacent levels
    local seed = (hash * 127 + levelNum * 9973) % 2147483647
    
    return seed
end

--- Get the difficulty configuration for a specific level number.
--- Levels 1-3: jump-over only, max 3 height, no gaps, no void, no touchkill
--- Levels 4-6: gaps up to 3 wide, max 5 height, no void, no touchkill
--- Levels 7-9: void up to 5, max 5 height, no touchkill
--- Level 10: touchkill enabled, max 5 height, gap 3, void 5
--- @param levelNum number -- Level number within a pack (1-10)
--- @return Types.LevelDifficulty -- Difficulty configuration for the level
function LevelUtils.getDifficultyConfig(levelNum: number): Types.LevelDifficulty
    local level = math.clamp(levelNum, 1, 10)
    local density = LevelUtils.getObstacleDensity(level)
    
    if level <= 3 then
        -- Levels 1-3: Jump-over obstacles only
        return {
            obstacleDensity = density,
            maxHeight = 3,
            gapWidth = 0,
            voidLength = 0,
            hasTouchKill = false,
            requiredPowerUps = nil,
        }
    elseif level <= 6 then
        -- Levels 4-6: Add gaps up to 3 wide
        return {
            obstacleDensity = density,
            maxHeight = 5,
            gapWidth = 3,
            voidLength = 0,
            hasTouchKill = false,
            requiredPowerUps = nil,
        }
    elseif level <= 9 then
        -- Levels 7-9: Add void sections up to 5 long
        return {
            obstacleDensity = density,
            maxHeight = 5,
            gapWidth = 3,
            voidLength = 5,
            hasTouchKill = false,
            requiredPowerUps = nil,
        }
    else
        -- Level 10: Touchkill enabled
        return {
            obstacleDensity = density,
            maxHeight = 5,
            gapWidth = 3,
            voidLength = 5,
            hasTouchKill = true,
            requiredPowerUps = nil,
        }
    end
end

return LevelUtils
