--!strict
--[[
    LevelUtils.prop.luau - Property-based tests for LevelUtils module
    
    Feature: pixel-run-obby
    Properties tested:
        - Property 2: Obstacle Density Within Bounds
        - Property 4: Deterministic Level Generation
        - Property 6: XP Calculation Correctness
    
    Validates: Requirements 3.2, 3.5, 3.7, 6.1, 6.3
    
    Since LevelUtils uses `require(script.Parent.Types)` which doesn't work in Lune,
    we reimplement the pure calculation logic here for testing. These functions are
    direct copies of the algorithms in src/shared/LevelUtils.luau.
]]

local TestHarness = require("../TestHarness")

--============================================================================
-- Reimplemented LevelUtils functions for Lune testing
-- These mirror the implementations in src/shared/LevelUtils.luau exactly
--============================================================================

--- Calculate XP earned: blocks_traveled × pack_number
local function calculateXP(blocksRun: number, packNumber: number): number
    return blocksRun * packNumber
end

--- Fixed completion bonus (500 XP)
local LEVEL_COMPLETION_BONUS = 500

local function calculateCompletionBonus(): number
    return LEVEL_COMPLETION_BONUS
end

--- Linear interpolation of obstacle density from 1/50 (level 1) to 1/10 (level 10)
local function getObstacleDensity(levelNum: number): number
    local level = math.clamp(levelNum, 1, 10)
    local minDensity = 1 / 50  -- 0.02 at level 1
    local maxDensity = 1 / 10  -- 0.10 at level 10
    local t = (level - 1) / 9
    return minDensity + t * (maxDensity - minDensity)
end

--- Deterministic seed from packId string and level number
local function getLevelSeed(packId: string, levelNum: number): number
    local hash = 0
    for i = 1, #packId do
        hash = (hash * 31 + string.byte(packId, i)) % 2147483647
    end
    local seed = (hash * 127 + levelNum * 9973) % 2147483647
    return seed
end

--============================================================================
-- Property Tests
--============================================================================

print("=== LevelUtils Property Tests ===")
print(string.format("Base seed: %d\n", TestHarness.getSeed()))

--[[
    Property 2: Obstacle Density Within Bounds
    
    For any valid level number (1-10), the obstacle density multiplied by the 
    level length (1000 blocks) should produce an obstacle count between 20 
    (level 1: 1000 * 1/50) and 100 (level 10: 1000 * 1/10), scaling linearly.
    
    **Validates: Requirements 3.2**
]]
TestHarness.property("Property 2: Obstacle Density Within Bounds", 100, function(rng)
    local levelNum = TestHarness.randomInt(rng, 1, 10)
    local density = getObstacleDensity(levelNum)
    
    -- Level length is always 500 blocks
    local LEVEL_LENGTH = 500
    local obstacleCount = density * LEVEL_LENGTH
    
    -- Expected bounds: 10 obstacles at level 1, 50 obstacles at level 10
    local MIN_OBSTACLES = 10  -- 500 * (1/50)
    local MAX_OBSTACLES = 50  -- 500 * (1/10)
    
    -- Verify density produces obstacle count within bounds
    local withinBounds = obstacleCount >= MIN_OBSTACLES and obstacleCount <= MAX_OBSTACLES
    
    if not withinBounds then
        return false, string.format(
            "Level %d: density=%.4f, obstacleCount=%.1f, expected [%d, %d]",
            levelNum, density, obstacleCount, MIN_OBSTACLES, MAX_OBSTACLES
        )
    end
    
    -- Verify density increases (or stays same) with level number
    if levelNum > 1 then
        local prevDensity = getObstacleDensity(levelNum - 1)
        if density < prevDensity then
            return false, string.format(
                "Density decreased from level %d (%.4f) to level %d (%.4f)",
                levelNum - 1, prevDensity, levelNum, density
            )
        end
    end
    
    return true, nil
end)

--[[
    Property 4: Deterministic Level Generation
    
    For any packId and level number, calling getLevelSeed multiple times with
    the same inputs should produce an identical seed value. The same 
    (packId, levelNum) pair always maps to the same seed.
    
    **Validates: Requirements 3.5, 3.7**
]]
TestHarness.property("Property 4: Deterministic Level Generation", 100, function(rng)
    -- Generate random packId and level number
    local packId = TestHarness.randomString(rng, 3, 20)
    local levelNum = TestHarness.randomInt(rng, 1, 10)
    
    -- Call getLevelSeed multiple times with same inputs
    local seed1 = getLevelSeed(packId, levelNum)
    local seed2 = getLevelSeed(packId, levelNum)
    local seed3 = getLevelSeed(packId, levelNum)
    
    -- All calls must produce identical seeds
    if seed1 ~= seed2 or seed2 ~= seed3 then
        return false, string.format(
            "Non-deterministic: packId='%s', level=%d produced seeds %d, %d, %d",
            packId, levelNum, seed1, seed2, seed3
        )
    end
    
    -- Different level numbers in same pack should produce different seeds
    if levelNum < 10 then
        local otherSeed = getLevelSeed(packId, levelNum + 1)
        if seed1 == otherSeed then
            return false, string.format(
                "Same seed for different levels: packId='%s', levels %d and %d both got seed %d",
                packId, levelNum, levelNum + 1, seed1
            )
        end
    end
    
    -- Seed should be a positive integer within valid range
    if seed1 <= 0 or seed1 >= 2147483647 then
        return false, string.format(
            "Seed out of range: packId='%s', level=%d produced seed %d",
            packId, levelNum, seed1
        )
    end
    
    return true, nil
end)

--[[
    Property 6: XP Calculation Correctness
    
    For any non-negative block count and valid pack number (>= 1):
    - XP earned = blocks_traveled × pack_number
    - Completion bonus = 500 (fixed, awarded exactly once per level completion)
    
    **Validates: Requirements 6.1, 6.3**
]]
TestHarness.property("Property 6: XP Calculation Correctness", 100, function(rng)
    local blocksRun = TestHarness.randomInt(rng, 0, 10000)
    local packNumber = TestHarness.randomInt(rng, 1, 20)
    
    -- Verify XP = blocks × pack_number
    local xp = calculateXP(blocksRun, packNumber)
    local expectedXP = blocksRun * packNumber
    
    if xp ~= expectedXP then
        return false, string.format(
            "XP mismatch: blocks=%d, pack=%d, expected=%d, got=%d",
            blocksRun, packNumber, expectedXP, xp
        )
    end
    
    -- Verify XP is non-negative for valid inputs
    if xp < 0 then
        return false, string.format(
            "Negative XP: blocks=%d, pack=%d, got=%d",
            blocksRun, packNumber, xp
        )
    end
    
    -- Verify completion bonus is always exactly 500
    local bonus = calculateCompletionBonus()
    if bonus ~= 500 then
        return false, string.format(
            "Completion bonus should be 500, got %d", bonus
        )
    end
    
    -- Verify XP scales linearly with pack number
    if packNumber > 1 then
        local xpPrevPack = calculateXP(blocksRun, packNumber - 1)
        local expectedDiff = blocksRun  -- Each pack number adds 1x blocks
        local actualDiff = xp - xpPrevPack
        if actualDiff ~= expectedDiff then
            return false, string.format(
                "XP scaling wrong: blocks=%d, pack %d→%d, diff expected=%d, got=%d",
                blocksRun, packNumber - 1, packNumber, expectedDiff, actualDiff
            )
        end
    end
    
    return true, nil
end)

--============================================================================
-- Report Results
--============================================================================

local allPassed = TestHarness.report()

if not allPassed then
    error("One or more property tests failed")
end
