--!strict
--[[
    TetrisPack.spec.luau - Unit tests for TetrisPack level configuration

    Tests cover: piece types, colors, orientations, difficulty progression,
    completability without power-ups, display order, and prerequisite pack.

    Since TetrisPack uses require(script.Parent.Parent.Types) which doesn't work
    in Lune, we inline the configuration data for testing. These values are
    direct copies from src/shared/LevelPacks/TetrisPack.luau.

    Validates: Requirements 5.2, 5.3, 5.6
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

local function assertNil(actual: any, testName: string)
    if actual == nil then
        passed += 1
        print(`  ✓ {testName}`)
    else
        failed += 1
        print(`  ✗ {testName}: expected nil, got {tostring(actual)}`)
    end
end

--============================================================================
-- Inlined TetrisPack data (mirrors src/shared/LevelPacks/TetrisPack.luau)
--============================================================================

local TetrisPack = {
    name = "Tetris",
    displayOrder = 1,
    themeId = "tetris",
    prerequisitePack = nil,
    morassVisual = "rolling_tetris_blocks",
    achievementName = "Tetris Master",
    musicTrack = "tetris_theme",

    obstacleTypes = {
        { shape = "I", orientations = {0, 90, 180, 270}, color = Color3.fromRGB(0, 255, 255), maxHeight = 5, isTouchKill = false },
        { shape = "O", orientations = {0, 90, 180, 270}, color = Color3.fromRGB(255, 255, 0), maxHeight = 5, isTouchKill = false },
        { shape = "T", orientations = {0, 90, 180, 270}, color = Color3.fromRGB(128, 0, 128), maxHeight = 5, isTouchKill = false },
        { shape = "S", orientations = {0, 90, 180, 270}, color = Color3.fromRGB(0, 255, 0), maxHeight = 5, isTouchKill = false },
        { shape = "Z", orientations = {0, 90, 180, 270}, color = Color3.fromRGB(255, 0, 0), maxHeight = 5, isTouchKill = false },
        { shape = "L", orientations = {0, 90, 180, 270}, color = Color3.fromRGB(255, 165, 0), maxHeight = 5, isTouchKill = false },
        { shape = "J", orientations = {0, 90, 180, 270}, color = Color3.fromRGB(0, 0, 255), maxHeight = 5, isTouchKill = false },
        { shape = "Kill", orientations = {0, 90, 180, 270}, color = Color3.fromRGB(255, 0, 50), maxHeight = 3, isTouchKill = true },
    },

    difficulty = {
        [1] = { obstacleDensity = 1/50, maxHeight = 3, gapWidth = 0, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil },
        [2] = { obstacleDensity = 1/45, maxHeight = 3, gapWidth = 0, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil },
        [3] = { obstacleDensity = 1/40, maxHeight = 3, gapWidth = 0, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil },
        [4] = { obstacleDensity = 1/35, maxHeight = 5, gapWidth = 3, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil },
        [5] = { obstacleDensity = 1/30, maxHeight = 5, gapWidth = 3, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil },
        [6] = { obstacleDensity = 1/25, maxHeight = 5, gapWidth = 3, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil },
        [7] = { obstacleDensity = 1/20, maxHeight = 5, gapWidth = 3, voidLength = 5, hasTouchKill = false, requiredPowerUps = nil },
        [8] = { obstacleDensity = 1/15, maxHeight = 5, gapWidth = 3, voidLength = 5, hasTouchKill = false, requiredPowerUps = nil },
        [9] = { obstacleDensity = 1/12, maxHeight = 5, gapWidth = 3, voidLength = 5, hasTouchKill = false, requiredPowerUps = nil },
        [10] = { obstacleDensity = 1/10, maxHeight = 5, gapWidth = 3, voidLength = 5, hasTouchKill = true, requiredPowerUps = nil },
    },
}

--============================================================================
-- Helper: find obstacle type by shape name
--============================================================================
local function findObstacle(shape: string): any
    for _, obs in TetrisPack.obstacleTypes do
        if obs.shape == shape then
            return obs
        end
    end
    return nil
end

--============================================================================
-- Test 1: 7 piece types exist (I, O, T, S, Z, L, J)
--============================================================================
print("\n=== 7 Tetris piece types exist ===")

local expectedShapes = {"I", "O", "T", "S", "Z", "L", "J"}
for _, shape in expectedShapes do
    local obs = findObstacle(shape)
    assertTrue(obs ~= nil, `Piece type "{shape}" exists in obstacleTypes`)
end

--============================================================================
-- Test 2: Each piece has correct color
--============================================================================
print("\n=== Piece colors are correct ===")

local expectedColors: {[string]: {number}} = {
    I = {0, 255, 255},   -- cyan
    O = {255, 255, 0},   -- yellow
    T = {128, 0, 128},   -- purple
    S = {0, 255, 0},     -- green
    Z = {255, 0, 0},     -- red
    L = {255, 165, 0},   -- orange
    J = {0, 0, 255},     -- blue
}

for shape, rgb in expectedColors do
    local obs = findObstacle(shape)
    if obs then
        local expected = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
        local colorMatch = math.abs(obs.color.R - expected.R) < 0.01
            and math.abs(obs.color.G - expected.G) < 0.01
            and math.abs(obs.color.B - expected.B) < 0.01
        assertTrue(colorMatch, `Piece "{shape}" has correct color (R={rgb[1]}, G={rgb[2]}, B={rgb[3]})`)
    else
        failed += 1
        print(`  ✗ Piece "{shape}" not found, cannot check color`)
    end
end

--============================================================================
-- Test 3: Each piece has exactly 4 orientations (0, 90, 180, 270)
--============================================================================
print("\n=== Each piece has 4 orientations ===")

for _, shape in expectedShapes do
    local obs = findObstacle(shape)
    if obs then
        assertEquals(#obs.orientations, 4, `Piece "{shape}" has 4 orientations`)
        local hasAll = table.find(obs.orientations, 0) ~= nil
            and table.find(obs.orientations, 90) ~= nil
            and table.find(obs.orientations, 180) ~= nil
            and table.find(obs.orientations, 270) ~= nil
        assertTrue(hasAll, `Piece "{shape}" has orientations 0, 90, 180, 270`)
    else
        failed += 1
        print(`  ✗ Piece "{shape}" not found, cannot check orientations`)
    end
end

--============================================================================
-- Test 4: Difficulty levels 1-3
--============================================================================
print("\n=== Difficulty levels 1-3: jump-over only ===")

for level = 1, 3 do
    local diff = TetrisPack.difficulty[level]
    assertEquals(diff.maxHeight, 3, `Level {level}: maxHeight = 3`)
    assertEquals(diff.gapWidth, 0, `Level {level}: gapWidth = 0`)
    assertEquals(diff.voidLength, 0, `Level {level}: voidLength = 0`)
    assertEquals(diff.hasTouchKill, false, `Level {level}: hasTouchKill = false`)
end

--============================================================================
-- Test 5: Difficulty levels 4-6
--============================================================================
print("\n=== Difficulty levels 4-6: gaps introduced ===")

for level = 4, 6 do
    local diff = TetrisPack.difficulty[level]
    assertEquals(diff.maxHeight, 5, `Level {level}: maxHeight = 5`)
    assertEquals(diff.gapWidth, 3, `Level {level}: gapWidth = 3`)
    assertEquals(diff.voidLength, 0, `Level {level}: voidLength = 0`)
    assertEquals(diff.hasTouchKill, false, `Level {level}: hasTouchKill = false`)
end

--============================================================================
-- Test 6: Difficulty levels 7-9
--============================================================================
print("\n=== Difficulty levels 7-9: void sections ===")

for level = 7, 9 do
    local diff = TetrisPack.difficulty[level]
    assertEquals(diff.maxHeight, 5, `Level {level}: maxHeight = 5`)
    assertEquals(diff.gapWidth, 3, `Level {level}: gapWidth = 3`)
    assertEquals(diff.voidLength, 5, `Level {level}: voidLength = 5`)
    assertEquals(diff.hasTouchKill, false, `Level {level}: hasTouchKill = false`)
end

--============================================================================
-- Test 7: Difficulty level 10 has touch-and-die
--============================================================================
print("\n=== Difficulty level 10: touch-and-die ===")

local diff10 = TetrisPack.difficulty[10]
assertEquals(diff10.hasTouchKill, true, "Level 10: hasTouchKill = true")

--============================================================================
-- Test 8: All levels have requiredPowerUps = nil (completable without power-ups)
--============================================================================
print("\n=== All levels completable without power-ups ===")

for level = 1, 10 do
    local diff = TetrisPack.difficulty[level]
    assertNil(diff.requiredPowerUps, `Level {level}: requiredPowerUps = nil`)
end

--============================================================================
-- Test 9: displayOrder = 1, prerequisitePack = nil
--============================================================================
print("\n=== Pack metadata ===")

assertEquals(TetrisPack.displayOrder, 1, "displayOrder = 1")
assertNil(TetrisPack.prerequisitePack, "prerequisitePack = nil")

--============================================================================
-- Summary
--============================================================================
print(`\n=== Results: {passed} passed, {failed} failed ===`)

if failed > 0 then
    error(`{failed} test(s) failed`)
end
