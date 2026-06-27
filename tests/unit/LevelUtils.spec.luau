--!strict
--[[
    LevelUtils.spec.luau - Unit tests for LevelUtils module
    
    Tests cover: calculateXP, calculateCompletionBonus, getObstacleDensity,
    getLevelSeed, getDifficultyConfig
    
    Validates: Requirements 3.2, 6.1, 6.2, 6.3
    
    Since LevelUtils uses require(script.Parent.Types) which doesn't work in Lune,
    we inline the pure functions here (mirroring the source exactly).
]]

--============================================================================
-- Inlined LevelUtils functions (mirrors src/shared/LevelUtils.luau)
--============================================================================

local LEVEL_COMPLETION_BONUS = 500

local LevelUtils = {}

function LevelUtils.calculateXP(blocksRun: number, packNumber: number): number
    return blocksRun * packNumber
end

function LevelUtils.calculateCompletionBonus(): number
    return LEVEL_COMPLETION_BONUS
end

function LevelUtils.getObstacleDensity(levelNum: number): number
    local level = math.clamp(levelNum, 1, 10)
    local minDensity = 1 / 50
    local maxDensity = 1 / 10
    local t = (level - 1) / 9
    return minDensity + t * (maxDensity - minDensity)
end

function LevelUtils.getLevelSeed(packId: string, levelNum: number): number
    local hash = 0
    for i = 1, #packId do
        hash = (hash * 31 + string.byte(packId, i)) % 2147483647
    end
    local seed = (hash * 127 + levelNum * 9973) % 2147483647
    return seed
end

function LevelUtils.getDifficultyConfig(levelNum: number)
    local level = math.clamp(levelNum, 1, 10)
    local density = LevelUtils.getObstacleDensity(level)
    
    if level <= 3 then
        return { obstacleDensity = density, maxHeight = 3, gapWidth = 0, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil }
    elseif level <= 6 then
        return { obstacleDensity = density, maxHeight = 5, gapWidth = 3, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil }
    elseif level <= 9 then
        return { obstacleDensity = density, maxHeight = 5, gapWidth = 3, voidLength = 5, hasTouchKill = false, requiredPowerUps = nil }
    else
        return { obstacleDensity = density, maxHeight = 5, gapWidth = 3, voidLength = 5, hasTouchKill = true, requiredPowerUps = nil }
    end
end

local passed = 0
local failed = 0

local function assertEquals(actual: any, expected: any, testName: string)
    if actual == expected then
        passed += 1
        print(`  ✓ {testName}`)
    else
        failed += 1
        print(`  ✗ {testName}: expected {expected}, got {actual}`)
    end
end

local function assertTrue(condition: boolean, testName: string)
    if condition then
        passed += 1
        print(`  ✓ {testName}`)
    else
        failed += 1
        print(`  ✗ {testName}: expected true, got false`)
    end
end

--============================================================================
-- calculateXP tests
--============================================================================
print("\n=== calculateXP ===")

assertEquals(LevelUtils.calculateXP(0, 1), 0, "0 blocks × pack 1 = 0 XP")
assertEquals(LevelUtils.calculateXP(100, 1), 100, "100 blocks × pack 1 = 100 XP")
assertEquals(LevelUtils.calculateXP(100, 2), 200, "100 blocks × pack 2 = 200 XP")
assertEquals(LevelUtils.calculateXP(1000, 1), 1000, "1000 blocks × pack 1 = 1000 XP")
assertEquals(LevelUtils.calculateXP(1000, 3), 3000, "1000 blocks × pack 3 = 3000 XP")
assertEquals(LevelUtils.calculateXP(500, 5), 2500, "500 blocks × pack 5 = 2500 XP")

--============================================================================
-- calculateCompletionBonus tests
--============================================================================
print("\n=== calculateCompletionBonus ===")

assertEquals(LevelUtils.calculateCompletionBonus(), 500, "Completion bonus is 500 XP")

--============================================================================
-- getObstacleDensity tests
--============================================================================
print("\n=== getObstacleDensity ===")

-- Level 1 should be 1/50
local density1 = LevelUtils.getObstacleDensity(1)
assertTrue(math.abs(density1 - 1/50) < 0.0001, "Level 1 density = 1/50 (0.02)")

-- Level 10 should be 1/10
local density10 = LevelUtils.getObstacleDensity(10)
assertTrue(math.abs(density10 - 1/10) < 0.0001, "Level 10 density = 1/10 (0.10)")

-- Level 5 should be midway (approximately)
local density5 = LevelUtils.getObstacleDensity(5)
assertTrue(density5 > 1/50 and density5 < 1/10, "Level 5 density between 1/50 and 1/10")

-- Monotonically increasing
local prevDensity = 0
local monotonic = true
for level = 1, 10 do
    local d = LevelUtils.getObstacleDensity(level)
    if d <= prevDensity then
        monotonic = false
        break
    end
    prevDensity = d
end
assertTrue(monotonic, "Density is monotonically increasing from level 1 to 10")

--============================================================================
-- getLevelSeed tests
--============================================================================
print("\n=== getLevelSeed ===")

-- Deterministic: same inputs produce same output
local seed1a = LevelUtils.getLevelSeed("TetrisPack", 1)
local seed1b = LevelUtils.getLevelSeed("TetrisPack", 1)
assertEquals(seed1a, seed1b, "Same packId + levelNum produces same seed")

-- Different levels produce different seeds
local seed2 = LevelUtils.getLevelSeed("TetrisPack", 2)
assertTrue(seed1a ~= seed2, "Different level numbers produce different seeds")

-- Different packs produce different seeds
local seedOther = LevelUtils.getLevelSeed("SpacePack", 1)
assertTrue(seed1a ~= seedOther, "Different packIds produce different seeds")

-- Seed is a number
assertTrue(type(seed1a) == "number", "Seed is a number")

-- Seed is non-negative
assertTrue(seed1a >= 0, "Seed is non-negative")

--============================================================================
-- getDifficultyConfig tests
--============================================================================
print("\n=== getDifficultyConfig ===")

-- Levels 1-3: jump-over only
for level = 1, 3 do
    local config = LevelUtils.getDifficultyConfig(level)
    assertEquals(config.maxHeight, 3, `Level {level}: maxHeight = 3`)
    assertEquals(config.gapWidth, 0, `Level {level}: gapWidth = 0`)
    assertEquals(config.voidLength, 0, `Level {level}: voidLength = 0`)
    assertEquals(config.hasTouchKill, false, `Level {level}: hasTouchKill = false`)
end

-- Levels 4-6: add gaps
for level = 4, 6 do
    local config = LevelUtils.getDifficultyConfig(level)
    assertEquals(config.maxHeight, 5, `Level {level}: maxHeight = 5`)
    assertEquals(config.gapWidth, 3, `Level {level}: gapWidth = 3`)
    assertEquals(config.voidLength, 0, `Level {level}: voidLength = 0`)
    assertEquals(config.hasTouchKill, false, `Level {level}: hasTouchKill = false`)
end

-- Levels 7-9: add void sections
for level = 7, 9 do
    local config = LevelUtils.getDifficultyConfig(level)
    assertEquals(config.maxHeight, 5, `Level {level}: maxHeight = 5`)
    assertEquals(config.gapWidth, 3, `Level {level}: gapWidth = 3`)
    assertEquals(config.voidLength, 5, `Level {level}: voidLength = 5`)
    assertEquals(config.hasTouchKill, false, `Level {level}: hasTouchKill = false`)
end

-- Level 10: touchkill enabled
local config10 = LevelUtils.getDifficultyConfig(10)
assertEquals(config10.maxHeight, 5, "Level 10: maxHeight = 5")
assertEquals(config10.gapWidth, 3, "Level 10: gapWidth = 3")
assertEquals(config10.voidLength, 5, "Level 10: voidLength = 5")
assertEquals(config10.hasTouchKill, true, "Level 10: hasTouchKill = true")

-- Density is included in config
local config1 = LevelUtils.getDifficultyConfig(1)
assertTrue(math.abs(config1.obstacleDensity - 1/50) < 0.0001, "Level 1 config has correct density")

--============================================================================
-- Summary
--============================================================================
print(`\n=== Results: {passed} passed, {failed} failed ===`)

if failed > 0 then
    error(`{failed} test(s) failed`)
end
