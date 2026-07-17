--!strict
--[[
    LevelGenerator.spec.luau - Unit tests for mode-specific LevelGenerator behavior

    Tests the conveyor speed modification based on game mode configuration:
    - Time Attack (hasMorass=false): conveyorSpeed = base * 0.7
    - Sprint (timerDirection="down"): conveyorSpeed = base * 0.3
    - Classic / nil: no modification

    Validates: Task 7.2 - Mode-specific LevelGenerator behavior
]]

--============================================================================
-- Inlined LevelGenerator conveyor speed logic (mirrors generateLevel calculation)
--============================================================================

--- Calculates conveyor speed for a given level and optional mode config.
--- Mirrors the logic in LevelGenerator.generateLevel.
local function calculateConveyorSpeed(levelNum: number, modeConfig: {
    hasMorass: boolean?,
    hasTimer: boolean?,
    timerDirection: string?,
    timerDuration: number?,
    targetDistance: number?,
}?): number
    local level = math.clamp(levelNum, 1, 10)
    local baseSpeed = 5
    local maxSpeed = 12
    local t = (level - 1) / 9
    local conveyorSpeed = baseSpeed + t * (maxSpeed - baseSpeed)

    -- Apply mode-specific speed multiplier
    if modeConfig then
        if not modeConfig.hasMorass then
            -- Time Attack: no morass, slower conveyor (0.7x)
            conveyorSpeed = conveyorSpeed * 0.7
        elseif modeConfig.timerDirection == "down" then
            -- Sprint: very slow morass (0.3x)
            conveyorSpeed = conveyorSpeed * 0.3
        end
    end

    return conveyorSpeed
end

--============================================================================
-- Test Helpers
--============================================================================

local passed = 0
local failed = 0

local function assertEquals(actual: any, expected: any, testName: string)
    if actual == expected then
        passed += 1
        print(`  \u{2713} {testName}`)
    else
        failed += 1
        print(`  \u{2717} {testName}: expected {expected}, got {actual}`)
    end
end

local function assertApprox(actual: number, expected: number, tolerance: number, testName: string)
    if math.abs(actual - expected) <= tolerance then
        passed += 1
        print(`  \u{2713} {testName}`)
    else
        failed += 1
        print(`  \u{2717} {testName}: expected ~{expected} (±{tolerance}), got {actual}`)
    end
end

local function assertTrue(condition: boolean, testName: string)
    if condition then
        passed += 1
        print(`  \u{2713} {testName}`)
    else
        failed += 1
        print(`  \u{2717} {testName}: expected true, got false`)
    end
end

--============================================================================
-- Mode Configs (mirrors GameModeManager definitions)
--============================================================================

local CLASSIC_MODE = {
    hasMorass = true,
    hasTimer = false,
    timerDirection = nil,
    timerDuration = nil,
    targetDistance = 1000,
}

local TIME_ATTACK_MODE = {
    hasMorass = false,
    hasTimer = true,
    timerDirection = "up",
    timerDuration = nil,
    targetDistance = 1000,
}

local SPRINT_MODE = {
    hasMorass = true,
    hasTimer = true,
    timerDirection = "down",
    timerDuration = 60,
    targetDistance = nil,
}

--============================================================================
-- Tests: Classic mode (no modification)
--============================================================================
print("\n=== Classic Mode: No Speed Modification ===")

-- Level 1 base speed = 5
assertApprox(calculateConveyorSpeed(1, CLASSIC_MODE), 5.0, 0.001, "Classic Level 1: speed = 5.0")

-- Level 10 base speed = 12
assertApprox(calculateConveyorSpeed(10, CLASSIC_MODE), 12.0, 0.001, "Classic Level 10: speed = 12.0")

-- nil mode config = same as classic
assertApprox(calculateConveyorSpeed(1, nil), 5.0, 0.001, "nil modeConfig Level 1: speed = 5.0")
assertApprox(calculateConveyorSpeed(10, nil), 12.0, 0.001, "nil modeConfig Level 10: speed = 12.0")

--============================================================================
-- Tests: Time Attack mode (0.7x slower)
--============================================================================
print("\n=== Time Attack Mode: 0.7x Conveyor Speed ===")

-- Level 1: 5 * 0.7 = 3.5
assertApprox(calculateConveyorSpeed(1, TIME_ATTACK_MODE), 3.5, 0.001, "Time Attack Level 1: speed = 3.5 (5 * 0.7)")

-- Level 10: 12 * 0.7 = 8.4
assertApprox(calculateConveyorSpeed(10, TIME_ATTACK_MODE), 8.4, 0.001, "Time Attack Level 10: speed = 8.4 (12 * 0.7)")

-- Mid-level: Level 5 base = 5 + (4/9) * 7 ≈ 8.11; * 0.7 ≈ 5.68
local level5Base = 5 + (4 / 9) * 7
local level5TA = level5Base * 0.7
assertApprox(calculateConveyorSpeed(5, TIME_ATTACK_MODE), level5TA, 0.001, "Time Attack Level 5: speed ≈ 5.68")

-- Time Attack is slower than Classic
assertTrue(
    calculateConveyorSpeed(5, TIME_ATTACK_MODE) < calculateConveyorSpeed(5, CLASSIC_MODE),
    "Time Attack is slower than Classic at Level 5"
)

--============================================================================
-- Tests: Sprint mode (0.3x very slow morass)
--============================================================================
print("\n=== Sprint Mode: 0.3x Conveyor Speed (very slow morass) ===")

-- Level 1: 5 * 0.3 = 1.5
assertApprox(calculateConveyorSpeed(1, SPRINT_MODE), 1.5, 0.001, "Sprint Level 1: speed = 1.5 (5 * 0.3)")

-- Level 10: 12 * 0.3 = 3.6
assertApprox(calculateConveyorSpeed(10, SPRINT_MODE), 3.6, 0.001, "Sprint Level 10: speed = 3.6 (12 * 0.3)")

-- Sprint is the slowest mode
assertTrue(
    calculateConveyorSpeed(5, SPRINT_MODE) < calculateConveyorSpeed(5, TIME_ATTACK_MODE),
    "Sprint is slower than Time Attack at Level 5"
)
assertTrue(
    calculateConveyorSpeed(5, SPRINT_MODE) < calculateConveyorSpeed(5, CLASSIC_MODE),
    "Sprint is slower than Classic at Level 5"
)

--============================================================================
-- Tests: Mode relationships and edge cases
--============================================================================
print("\n=== Mode Relationships and Edge Cases ===")

-- Speed ordering: Sprint < Time Attack < Classic (for all levels)
for level = 1, 10 do
    local classicSpeed = calculateConveyorSpeed(level, CLASSIC_MODE)
    local taSpeed = calculateConveyorSpeed(level, TIME_ATTACK_MODE)
    local sprintSpeed = calculateConveyorSpeed(level, SPRINT_MODE)

    assertTrue(
        sprintSpeed < taSpeed and taSpeed < classicSpeed,
        `Level {level}: Sprint ({string.format("%.2f", sprintSpeed)}) < TA ({string.format("%.2f", taSpeed)}) < Classic ({string.format("%.2f", classicSpeed)})`
    )
end

-- Level clamping: level 0 treated as 1, level 11 treated as 10
assertApprox(calculateConveyorSpeed(0, nil), 5.0, 0.001, "Level 0 clamped to level 1: speed = 5.0")
assertApprox(calculateConveyorSpeed(11, nil), 12.0, 0.001, "Level 11 clamped to level 10: speed = 12.0")

--============================================================================
-- Summary
--============================================================================
print(`\n=== Results: {passed} passed, {failed} failed ===`)

if failed > 0 then
    error(`{failed} test(s) failed`)
end
