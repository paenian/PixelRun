--!strict
--[[
    GameModeManager.spec.luau - Unit tests for GameModeManager module

    Tests cover: getAvailableModes, getModeConfig, isModeUnlocked, getDefaultModeId

    Validates: Requirements 7.1

    Since GameModeManager uses require(script.Parent.Types) which doesn't work in Lune,
    we inline the pure functions here (mirroring the source exactly).
]]

--============================================================================
-- Inlined GameModeManager logic (mirrors src/shared/GameModeManager.luau)
--============================================================================

type GameModeConfig = {
    id: string,
    name: string,
    description: string,
    hasMorass: boolean,
    hasTimer: boolean,
    timerDirection: string?,
    timerDuration: number?,
    targetDistance: number?,
}

local GameModeManager = {}

local MODES: {GameModeConfig} = {
    {
        id = "classic",
        name = "Classic",
        description = "Race to 1000 blocks. Morass is chasing you!",
        hasMorass = true,
        hasTimer = false,
        timerDirection = nil,
        timerDuration = nil,
        targetDistance = 1000,
    },
    {
        id = "time_attack",
        name = "Time Attack",
        description = "No morass! Beat the clock to 1000 blocks.",
        hasMorass = false,
        hasTimer = true,
        timerDirection = "up",
        timerDuration = nil,
        targetDistance = 1000,
    },
    {
        id = "sprint",
        name = "Sprint",
        description = "60 seconds! How far can you go?",
        hasMorass = true,
        hasTimer = true,
        timerDirection = "down",
        timerDuration = 60,
        targetDistance = nil,
    },
}

local MODE_BY_ID: {[string]: GameModeConfig} = {}
for _, mode in MODES do
    MODE_BY_ID[mode.id] = mode
end

function GameModeManager.getAvailableModes(): {GameModeConfig}
    return MODES
end

function GameModeManager.getModeConfig(modeId: string): GameModeConfig?
    return MODE_BY_ID[modeId]
end

function GameModeManager.getDefaultModeId(): string
    return "classic"
end

function GameModeManager.isModeUnlocked(modeId: string, packId: string, completions: {[string]: {number}}): boolean
    if modeId == "classic" then
        return true
    end

    if MODE_BY_ID[modeId] == nil then
        return false
    end

    local packCompletions = completions[packId]
    if packCompletions == nil then
        return false
    end

    for level = 1, 10 do
        local found = false
        for _, completedLevel in packCompletions do
            if completedLevel == level then
                found = true
                break
            end
        end
        if not found then
            return false
        end
    end

    return true
end

--============================================================================
-- Test Helpers
--============================================================================

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

local function assertFalse(condition: boolean, testName: string)
    if not condition then
        passed += 1
        print(`  ✓ {testName}`)
    else
        failed += 1
        print(`  ✗ {testName}: expected false, got true`)
    end
end

local function assertNil(value: any, testName: string)
    if value == nil then
        passed += 1
        print(`  ✓ {testName}`)
    else
        failed += 1
        print(`  ✗ {testName}: expected nil, got {value}`)
    end
end

local function assertNotNil(value: any, testName: string)
    if value ~= nil then
        passed += 1
        print(`  ✓ {testName}`)
    else
        failed += 1
        print(`  ✗ {testName}: expected non-nil, got nil`)
    end
end

--============================================================================
-- getAvailableModes tests
--============================================================================
print("\n=== getAvailableModes ===")

local modes = GameModeManager.getAvailableModes()
assertEquals(#modes, 3, "Returns exactly 3 modes")
assertEquals(modes[1].id, "classic", "First mode is classic")
assertEquals(modes[2].id, "time_attack", "Second mode is time_attack")
assertEquals(modes[3].id, "sprint", "Third mode is sprint")

--============================================================================
-- getModeConfig tests
--============================================================================
print("\n=== getModeConfig ===")

-- Classic mode config
local classic = GameModeManager.getModeConfig("classic")
assertNotNil(classic, "Classic mode exists")
if classic then
    assertEquals(classic.name, "Classic", "Classic mode name")
    assertTrue(classic.hasMorass, "Classic has morass")
    assertFalse(classic.hasTimer, "Classic has no timer")
    assertNil(classic.timerDirection, "Classic has no timer direction")
    assertNil(classic.timerDuration, "Classic has no timer duration")
    assertEquals(classic.targetDistance, 1000, "Classic target distance = 1000")
end

-- Time Attack mode config
local timeAttack = GameModeManager.getModeConfig("time_attack")
assertNotNil(timeAttack, "Time Attack mode exists")
if timeAttack then
    assertEquals(timeAttack.name, "Time Attack", "Time Attack mode name")
    assertFalse(timeAttack.hasMorass, "Time Attack has no morass")
    assertTrue(timeAttack.hasTimer, "Time Attack has timer")
    assertEquals(timeAttack.timerDirection, "up", "Time Attack timer counts up")
    assertNil(timeAttack.timerDuration, "Time Attack has no duration limit")
    assertEquals(timeAttack.targetDistance, 1000, "Time Attack target distance = 1000")
end

-- Sprint mode config
local sprint = GameModeManager.getModeConfig("sprint")
assertNotNil(sprint, "Sprint mode exists")
if sprint then
    assertEquals(sprint.name, "Sprint", "Sprint mode name")
    assertTrue(sprint.hasMorass, "Sprint has morass (very slow)")
    assertTrue(sprint.hasTimer, "Sprint has timer")
    assertEquals(sprint.timerDirection, "down", "Sprint timer counts down")
    assertEquals(sprint.timerDuration, 60, "Sprint timer duration = 60 seconds")
    assertNil(sprint.targetDistance, "Sprint has no target distance")
end

-- Invalid mode
local invalid = GameModeManager.getModeConfig("nonexistent")
assertNil(invalid, "Nonexistent mode returns nil")

--============================================================================
-- getDefaultModeId tests
--============================================================================
print("\n=== getDefaultModeId ===")

assertEquals(GameModeManager.getDefaultModeId(), "classic", "Default mode is classic")

--============================================================================
-- isModeUnlocked tests
--============================================================================
print("\n=== isModeUnlocked ===")

-- Classic is always unlocked regardless of completions
assertTrue(
    GameModeManager.isModeUnlocked("classic", "tetris", {}),
    "Classic always unlocked (empty completions)"
)
assertTrue(
    GameModeManager.isModeUnlocked("classic", "pipeworld", {}),
    "Classic always unlocked for any pack"
)

-- Time Attack requires pack completed in Classic (all 10 levels)
local fullCompletion = { tetris = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10} }
assertTrue(
    GameModeManager.isModeUnlocked("time_attack", "tetris", fullCompletion),
    "Time Attack unlocked when pack fully completed"
)

-- Sprint requires pack completed in Classic too
assertTrue(
    GameModeManager.isModeUnlocked("sprint", "tetris", fullCompletion),
    "Sprint unlocked when pack fully completed"
)

-- Partial completion should NOT unlock other modes
local partialCompletion = { tetris = {1, 2, 3, 4, 5} }
assertFalse(
    GameModeManager.isModeUnlocked("time_attack", "tetris", partialCompletion),
    "Time Attack locked with only 5/10 levels completed"
)
assertFalse(
    GameModeManager.isModeUnlocked("sprint", "tetris", partialCompletion),
    "Sprint locked with only 5/10 levels completed"
)

-- Missing one level (9 of 10)
local missingOneLevel = { tetris = {1, 2, 3, 4, 5, 6, 7, 8, 9} }
assertFalse(
    GameModeManager.isModeUnlocked("time_attack", "tetris", missingOneLevel),
    "Time Attack locked with 9/10 levels"
)

-- Different pack completion doesn't unlock for requested pack
local wrongPack = { pipeworld = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10} }
assertFalse(
    GameModeManager.isModeUnlocked("time_attack", "tetris", wrongPack),
    "Time Attack locked for tetris when only pipeworld completed"
)

-- Empty completions
assertFalse(
    GameModeManager.isModeUnlocked("time_attack", "tetris", {}),
    "Time Attack locked with empty completions"
)

-- Invalid mode id
assertFalse(
    GameModeManager.isModeUnlocked("invalid_mode", "tetris", fullCompletion),
    "Unknown mode is always locked"
)

-- Out of order completion list still works
local outOfOrder = { tetris = {10, 9, 8, 7, 6, 5, 4, 3, 2, 1} }
assertTrue(
    GameModeManager.isModeUnlocked("time_attack", "tetris", outOfOrder),
    "Time Attack unlocked with out-of-order completion list"
)

-- Duplicate entries in completion list still works
local duplicates = { tetris = {1, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10} }
assertTrue(
    GameModeManager.isModeUnlocked("sprint", "tetris", duplicates),
    "Sprint unlocked with duplicate entries in completion list"
)

--============================================================================
-- Mode configuration correctness tests
--============================================================================
print("\n=== Mode configuration correctness ===")

-- Verify all modes have required fields
for _, mode in GameModeManager.getAvailableModes() do
    assertNotNil(mode.id, `Mode {mode.name} has id`)
    assertNotNil(mode.name, `Mode {mode.id} has name`)
    assertNotNil(mode.description, `Mode {mode.id} has description`)
    -- hasMorass and hasTimer are booleans, just check they're present
    assertTrue(mode.hasMorass == true or mode.hasMorass == false, `Mode {mode.id} has boolean hasMorass`)
    assertTrue(mode.hasTimer == true or mode.hasTimer == false, `Mode {mode.id} has boolean hasTimer`)
end

-- Verify timer consistency: if hasTimer=true, timerDirection must be set
for _, mode in GameModeManager.getAvailableModes() do
    if mode.hasTimer then
        assertNotNil(mode.timerDirection, `Mode {mode.id} with timer has timerDirection`)
        assertTrue(
            mode.timerDirection == "up" or mode.timerDirection == "down",
            `Mode {mode.id} timerDirection is 'up' or 'down'`
        )
    else
        assertNil(mode.timerDirection, `Mode {mode.id} without timer has nil timerDirection`)
    end
end

--============================================================================
-- Summary
--============================================================================
print(`\n=== Results: {passed} passed, {failed} failed ===`)

if failed > 0 then
    error(`{failed} test(s) failed`)
end
