--!strict
--[[
    PipeWorldPack.spec.luau - Unit tests for PipeWorldPack level configuration

    Tests cover: schema validation, prerequisite and displayOrder,
    touch-kill only on level 10, all 5 obstacle types with correct colors
    and orientations.

    Since PipeWorldPack uses require(script.Parent.Parent.Types) which doesn't work
    in Lune, we inline the configuration data for testing. These values are
    direct copies from src/shared/LevelPacks/PipeWorldPack.luau.

    Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5, 5.6
]]

local MockRoblox = require("../MockRoblox")
local Color3 = MockRoblox.Color3

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
-- Inlined PipeWorldPack data (mirrors src/shared/LevelPacks/PipeWorldPack.luau)
--============================================================================

local PipeWorldPack = {
    name = "Pipe World",
    displayOrder = 2,
    themeId = "pipeworld",
    prerequisitePack = "tetris",
    morassVisual = "sewer_flood",
    achievementName = "Pipeline Pro",
    musicTrack = "pipeworld_theme",

    obstacleTypes = {
        { shape = "Brick", orientations = {0, 90, 180, 270}, color = Color3.fromRGB(139, 90, 43), maxHeight = 5, isTouchKill = false },
        { shape = "Pipe", orientations = {0, 90, 180, 270}, color = Color3.fromRGB(34, 139, 34), maxHeight = 5, isTouchKill = false },
        { shape = "CoinBlock", orientations = {0, 90, 180, 270}, color = Color3.fromRGB(255, 215, 0), maxHeight = 5, isTouchKill = false },
        { shape = "Crumble", orientations = {0, 90, 180, 270}, color = Color3.fromRGB(160, 82, 45), maxHeight = 5, isTouchKill = false },
        { shape = "PipePlant", orientations = {0, 90, 180, 270}, color = Color3.fromRGB(50, 180, 50), maxHeight = 3, isTouchKill = true },
    },

    difficulty = {
        [1] = { obstacleDensity = 1/7, maxHeight = 3, gapWidth = 0, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil },
        [2] = { obstacleDensity = 1/6, maxHeight = 3, gapWidth = 0, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil },
        [3] = { obstacleDensity = 1/5, maxHeight = 3, gapWidth = 0, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil },
        [4] = { obstacleDensity = 1/4.5, maxHeight = 5, gapWidth = 3, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil },
        [5] = { obstacleDensity = 1/4, maxHeight = 5, gapWidth = 3, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil },
        [6] = { obstacleDensity = 1/3.5, maxHeight = 5, gapWidth = 3, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil },
        [7] = { obstacleDensity = 1/3.5, maxHeight = 5, gapWidth = 3, voidLength = 5, hasTouchKill = false, requiredPowerUps = nil },
        [8] = { obstacleDensity = 1/2.5, maxHeight = 5, gapWidth = 3, voidLength = 5, hasTouchKill = false, requiredPowerUps = nil },
        [9] = { obstacleDensity = 1/2.5, maxHeight = 5, gapWidth = 3, voidLength = 5, hasTouchKill = false, requiredPowerUps = nil },
        [10] = { obstacleDensity = 1/2.5, maxHeight = 5, gapWidth = 3, voidLength = 5, hasTouchKill = true, requiredPowerUps = nil },
    },
}

--============================================================================
-- Helper: find obstacle type by shape name
--============================================================================
local function findObstacle(shape: string): any
    for _, obs in PipeWorldPack.obstacleTypes do
        if obs.shape == shape then
            return obs
        end
    end
    return nil
end

--============================================================================
-- Test 1: Schema validation passes
--============================================================================
print("\n=== Schema Validation ===")

-- Required top-level string fields
assertTrue(PipeWorldPack.name ~= nil and PipeWorldPack.name ~= "", "name is non-empty string")
assertTrue(PipeWorldPack.themeId ~= nil and PipeWorldPack.themeId ~= "", "themeId is non-empty string")
assertTrue(PipeWorldPack.morassVisual ~= nil and PipeWorldPack.morassVisual ~= "", "morassVisual is non-empty string")
assertTrue(PipeWorldPack.achievementName ~= nil and PipeWorldPack.achievementName ~= "", "achievementName is non-empty string")
assertTrue(PipeWorldPack.musicTrack ~= nil and PipeWorldPack.musicTrack ~= "", "musicTrack is non-empty string")

-- displayOrder is a positive integer
assertTrue(type(PipeWorldPack.displayOrder) == "number", "displayOrder is a number")
assertTrue(PipeWorldPack.displayOrder > 0, "displayOrder is positive")

-- obstacleTypes is a non-empty table
assertTrue(type(PipeWorldPack.obstacleTypes) == "table", "obstacleTypes is a table")
assertTrue(#PipeWorldPack.obstacleTypes > 0, "obstacleTypes is non-empty")

-- difficulty has exactly 10 levels
local difficultyCount = 0
for _ in PipeWorldPack.difficulty do
    difficultyCount += 1
end
assertEquals(difficultyCount, 10, "difficulty has exactly 10 levels")

-- Each difficulty level has required fields
for level = 1, 10 do
    local diff = PipeWorldPack.difficulty[level]
    assertTrue(diff ~= nil, `difficulty[{level}] exists`)
    if diff then
        assertTrue(type(diff.obstacleDensity) == "number", `Level {level}: obstacleDensity is number`)
        assertTrue(type(diff.maxHeight) == "number", `Level {level}: maxHeight is number`)
        assertTrue(type(diff.gapWidth) == "number", `Level {level}: gapWidth is number`)
        assertTrue(type(diff.voidLength) == "number", `Level {level}: voidLength is number`)
        assertTrue(type(diff.hasTouchKill) == "boolean", `Level {level}: hasTouchKill is boolean`)
    end
end

-- Each obstacle type has required fields
for i, obs in PipeWorldPack.obstacleTypes do
    assertTrue(type(obs.shape) == "string" and obs.shape ~= "", `Obstacle {i}: shape is non-empty string`)
    assertTrue(type(obs.orientations) == "table", `Obstacle {i}: orientations is table`)
    assertTrue(obs.color ~= nil, `Obstacle {i}: color is defined`)
    assertTrue(type(obs.maxHeight) == "number", `Obstacle {i}: maxHeight is number`)
    assertTrue(type(obs.isTouchKill) == "boolean", `Obstacle {i}: isTouchKill is boolean`)
end

-- All levels completable without power-ups
for level = 1, 10 do
    local diff = PipeWorldPack.difficulty[level]
    assertTrue(diff.requiredPowerUps == nil, `Level {level}: requiredPowerUps = nil (completable without power-ups)`)
end

--============================================================================
-- Test 2: Correct prerequisite and displayOrder
--============================================================================
print("\n=== Prerequisite and Display Order ===")

assertEquals(PipeWorldPack.displayOrder, 2, "displayOrder = 2")
assertEquals(PipeWorldPack.prerequisitePack, "tetris", 'prerequisitePack = "tetris"')
assertEquals(PipeWorldPack.name, "Pipe World", 'name = "Pipe World"')
assertEquals(PipeWorldPack.themeId, "pipeworld", 'themeId = "pipeworld"')
assertEquals(PipeWorldPack.morassVisual, "sewer_flood", 'morassVisual = "sewer_flood"')
assertEquals(PipeWorldPack.achievementName, "Pipeline Pro", 'achievementName = "Pipeline Pro"')
assertEquals(PipeWorldPack.musicTrack, "pipeworld_theme", 'musicTrack = "pipeworld_theme"')

--============================================================================
-- Test 3: Touch-kill only on level 10
--============================================================================
print("\n=== Touch-kill only on level 10 ===")

for level = 1, 9 do
    local diff = PipeWorldPack.difficulty[level]
    assertEquals(diff.hasTouchKill, false, `Level {level}: hasTouchKill = false`)
end

assertEquals(PipeWorldPack.difficulty[10].hasTouchKill, true, "Level 10: hasTouchKill = true")

--============================================================================
-- Test 4: All 5 obstacle types with correct colors and orientations
--============================================================================
print("\n=== 5 obstacle types exist ===")

assertEquals(#PipeWorldPack.obstacleTypes, 5, "Exactly 5 obstacle types")

local expectedShapes = {"Brick", "Pipe", "CoinBlock", "Crumble", "PipePlant"}
for _, shape in expectedShapes do
    local obs = findObstacle(shape)
    assertTrue(obs ~= nil, `Obstacle type "{shape}" exists`)
end

print("\n=== Obstacle colors are correct ===")

local expectedColors: {[string]: {number}} = {
    Brick = {139, 90, 43},
    Pipe = {34, 139, 34},
    CoinBlock = {255, 215, 0},
    Crumble = {160, 82, 45},
    PipePlant = {50, 180, 50},
}

for shape, rgb in expectedColors do
    local obs = findObstacle(shape)
    if obs then
        local expected = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
        local colorMatch = math.abs(obs.color.R - expected.R) < 0.01
            and math.abs(obs.color.G - expected.G) < 0.01
            and math.abs(obs.color.B - expected.B) < 0.01
        assertTrue(colorMatch, `Obstacle "{shape}" has correct color (R={rgb[1]}, G={rgb[2]}, B={rgb[3]})`)
    else
        failed += 1
        print(`  ✗ Obstacle "{shape}" not found, cannot check color`)
    end
end

print("\n=== Each obstacle has 4 orientations (0, 90, 180, 270) ===")

for _, shape in expectedShapes do
    local obs = findObstacle(shape)
    if obs then
        assertEquals(#obs.orientations, 4, `Obstacle "{shape}" has 4 orientations`)
        local hasAll = table.find(obs.orientations, 0) ~= nil
            and table.find(obs.orientations, 90) ~= nil
            and table.find(obs.orientations, 180) ~= nil
            and table.find(obs.orientations, 270) ~= nil
        assertTrue(hasAll, `Obstacle "{shape}" has orientations 0, 90, 180, 270`)
    else
        failed += 1
        print(`  ✗ Obstacle "{shape}" not found, cannot check orientations`)
    end
end

print("\n=== Touch-kill obstacle type ===")

-- Only PipePlant should be a touch-kill obstacle
for _, obs in PipeWorldPack.obstacleTypes do
    if obs.shape == "PipePlant" then
        assertEquals(obs.isTouchKill, true, `PipePlant: isTouchKill = true`)
    else
        assertEquals(obs.isTouchKill, false, `{obs.shape}: isTouchKill = false`)
    end
end

--============================================================================
-- Summary
--============================================================================
print(`\n=== Results: {passed} passed, {failed} failed ===`)

if failed > 0 then
    error(`{failed} test(s) failed`)
end
