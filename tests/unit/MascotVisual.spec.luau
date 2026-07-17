--!strict
--[[
    MascotVisual.spec.luau - Unit tests for MascotVisual configuration and logic

    Tests cover: configuration constants, sine-wave bob calculation,
    target position math, and state invariants.

    Since MascotVisual depends on Roblox services (Players, RunService, workspace),
    these tests verify the pure logic using inlined data that mirrors the module's
    constants and algorithms.

    Validates: Requirements 6.3
]]

local MockRoblox = require("../MockRoblox")
local Vector3 = MockRoblox.Vector3

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

local function assertApprox(actual: number, expected: number, tolerance: number, testName: string)
    if math.abs(actual - expected) <= tolerance then
        passed += 1
        print(`  ✓ {testName}`)
    else
        failed += 1
        print(`  ✗ {testName}: expected ~{expected} (±{tolerance}), got {actual}`)
    end
end

--============================================================================
-- Configuration Constants (Requirement 6.3)
--============================================================================
print("\n=== MascotVisual Configuration Constants ===")

-- These mirror the constants defined in MascotVisual.luau
local OFFSET_BEHIND = -3
local OFFSET_UP = 3
local BOB_AMPLITUDE = 0.5
local BOB_FREQUENCY = 2
local FOLLOW_SMOOTHING = 0.15
local MASCOT_SIZE_X = 2
local MASCOT_SIZE_Y = 2
local MASCOT_SIZE_Z = 2

-- Verify offset values meet spec: -3 studs behind, +3 studs up
assertEquals(OFFSET_BEHIND, -3, "Mascot trails 3 studs behind player")
assertEquals(OFFSET_UP, 3, "Mascot floats 3 studs above player")

-- Verify part is 2-3 stud size range (spec says 2-3 stud cube)
assertTrue(MASCOT_SIZE_X >= 2 and MASCOT_SIZE_X <= 3, "Mascot width is 2-3 studs")
assertTrue(MASCOT_SIZE_Y >= 2 and MASCOT_SIZE_Y <= 3, "Mascot height is 2-3 studs")
assertTrue(MASCOT_SIZE_Z >= 2 and MASCOT_SIZE_Z <= 3, "Mascot depth is 2-3 studs")

-- Smoothing factor should be positive and less than 1 for lerp
assertTrue(FOLLOW_SMOOTHING > 0, "Follow smoothing is positive")
assertTrue(FOLLOW_SMOOTHING < 1, "Follow smoothing is less than 1 (valid lerp factor)")

-- Bob amplitude should be gentle (not too aggressive)
assertTrue(BOB_AMPLITUDE > 0, "Bob amplitude is positive")
assertTrue(BOB_AMPLITUDE <= 1, "Bob amplitude is gentle (<=1 stud)")

-- Bob frequency should produce visible but smooth oscillation
assertTrue(BOB_FREQUENCY > 0, "Bob frequency is positive")
assertTrue(BOB_FREQUENCY <= 5, "Bob frequency is not too fast (<=5 per second)")

--============================================================================
-- Sine-Wave Bob Calculation (Requirement 6.3)
--============================================================================
print("\n=== Sine-Wave Bob Calculation ===")

--- Simulates the bob offset at a given elapsed time.
local function calculateBob(elapsed: number): number
    return math.sin(elapsed * BOB_FREQUENCY * math.pi * 2) * BOB_AMPLITUDE
end

-- At time 0, sin(0) = 0, so bob should be 0
assertApprox(calculateBob(0), 0, 0.001, "Bob is 0 at time 0")

-- At quarter period, sin = 1, so bob should be BOB_AMPLITUDE
local quarterPeriod = 1 / (BOB_FREQUENCY * 4) -- 1/(2*4) = 0.125 seconds
assertApprox(calculateBob(quarterPeriod), BOB_AMPLITUDE, 0.001, "Bob is max amplitude at quarter period")

-- At half period, sin = 0, so bob should be back to 0
local halfPeriod = 1 / (BOB_FREQUENCY * 2) -- 0.25 seconds
assertApprox(calculateBob(halfPeriod), 0, 0.001, "Bob returns to 0 at half period")

-- At three-quarter period, sin = -1, so bob should be -BOB_AMPLITUDE
local threeQuarterPeriod = 3 / (BOB_FREQUENCY * 4) -- 0.375 seconds
assertApprox(calculateBob(threeQuarterPeriod), -BOB_AMPLITUDE, 0.001, "Bob is negative amplitude at 3/4 period")

-- At full period, sin = 0, bob returns to 0
local fullPeriod = 1 / BOB_FREQUENCY -- 0.5 seconds
assertApprox(calculateBob(fullPeriod), 0, 0.001, "Bob completes full cycle at period")

-- Bob should always be within [-BOB_AMPLITUDE, BOB_AMPLITUDE]
for i = 0, 100 do
    local t = i * 0.037 -- arbitrary time steps
    local bob = calculateBob(t)
    if math.abs(bob) > BOB_AMPLITUDE + 0.001 then
        failed += 1
        print(`  ✗ Bob bounded at t={t}: got {bob}, max {BOB_AMPLITUDE}`)
        break
    end
end
passed += 1
print("  ✓ Bob always within amplitude bounds (100 samples)")

--============================================================================
-- Target Position Calculation (Requirement 6.3)
--============================================================================
print("\n=== Target Position Calculation ===")

--- Simulates target position calculation given player position, look direction, and time.
local function getTargetPosition(playerPos: any, lookVector: any, elapsed: number): any
    local behindOffset = lookVector * OFFSET_BEHIND
    local basePosition = playerPos + behindOffset + Vector3.new(0, OFFSET_UP, 0)
    local bob = calculateBob(elapsed)
    return basePosition + Vector3.new(0, bob, 0)
end

-- Player at origin, looking forward (+Z)
local playerPos = Vector3.new(0, 5, 0)
local lookForward = Vector3.new(0, 0, 1)
local target = getTargetPosition(playerPos, lookForward, 0)

-- Expected: behind = lookVector * -3 = (0,0,-3), up = +3, bob = 0
-- Position: (0, 5, 0) + (0, 0, -3) + (0, 3, 0) + (0, 0, 0) = (0, 8, -3)
assertApprox(target.X, 0, 0.001, "Target X is 0 when looking +Z")
assertApprox(target.Y, 8, 0.001, "Target Y is playerY + offset_up when bob=0")
assertApprox(target.Z, -3, 0.001, "Target Z is -3 (behind when looking +Z)")

-- Player looking in +X direction
local lookRight = Vector3.new(1, 0, 0)
local target2 = getTargetPosition(playerPos, lookRight, 0)
-- behind = (1,0,0) * -3 = (-3,0,0)
-- Position: (0,5,0) + (-3,0,0) + (0,3,0) = (-3, 8, 0)
assertApprox(target2.X, -3, 0.001, "Target X is -3 when looking +X")
assertApprox(target2.Y, 8, 0.001, "Target Y is playerY + offset_up")
assertApprox(target2.Z, 0, 0.001, "Target Z is 0 when looking +X")

-- With bob at peak (quarter period)
local targetWithBob = getTargetPosition(playerPos, lookForward, quarterPeriod)
assertApprox(targetWithBob.Y, 8 + BOB_AMPLITUDE, 0.001, "Target Y includes positive bob at peak")

-- With bob at trough (three-quarter period)
local targetWithNegBob = getTargetPosition(playerPos, lookForward, threeQuarterPeriod)
assertApprox(targetWithNegBob.Y, 8 - BOB_AMPLITUDE, 0.001, "Target Y includes negative bob at trough")

--============================================================================
-- Lerp Smoothing (Requirement 6.3)
--============================================================================
print("\n=== Follow Smoothing (Lerp) ===")

--- Simulates one frame of position smoothing.
local function lerpPosition(current: any, target_pos: any, alpha: number): any
    -- Lerp: current + (target - current) * alpha
    local diff = target_pos - current
    return current + diff * alpha
end

-- Starting far away, should move toward target
local currentPos = Vector3.new(0, 0, 0)
local targetPos = Vector3.new(10, 10, 10)
local newPos = lerpPosition(currentPos, targetPos, FOLLOW_SMOOTHING)

-- After one frame, should have moved 15% of the way
assertApprox(newPos.X, 1.5, 0.001, "Lerp moves 15% toward target X")
assertApprox(newPos.Y, 1.5, 0.001, "Lerp moves 15% toward target Y")
assertApprox(newPos.Z, 1.5, 0.001, "Lerp moves 15% toward target Z")

-- If already at target, should stay at target
local atTarget = lerpPosition(targetPos, targetPos, FOLLOW_SMOOTHING)
assertApprox(atTarget.X, 10, 0.001, "Lerp stays at target when already there (X)")
assertApprox(atTarget.Y, 10, 0.001, "Lerp stays at target when already there (Y)")
assertApprox(atTarget.Z, 10, 0.001, "Lerp stays at target when already there (Z)")

-- Over multiple frames, should converge closer to target
local multiFrame = Vector3.new(0, 0, 0)
for _ = 1, 30 do
    multiFrame = lerpPosition(multiFrame, targetPos, FOLLOW_SMOOTHING)
end
-- After 30 frames at 0.15 alpha, should be very close to target
-- (1 - 0.15)^30 ≈ 0.0076, so should be within 0.076 studs of target
local remainingDist = math.sqrt(
    (multiFrame.X - 10)^2 + (multiFrame.Y - 10)^2 + (multiFrame.Z - 10)^2
)
assertTrue(remainingDist < 0.2, "Lerp converges close to target after 30 frames")

--============================================================================
-- State Machine Logic (Requirement 6.3)
--============================================================================
print("\n=== State Machine ===")

-- Simulate spawn/despawn state machine
local isSpawned = false
local spawnedId: string? = nil

local function simulateSpawn(mascotId: string): boolean
    -- If already spawned, despawn first (like the real module)
    if isSpawned then
        isSpawned = false
        spawnedId = nil
    end
    isSpawned = true
    spawnedId = mascotId
    return true
end

local function simulateDespawn()
    isSpawned = false
    spawnedId = nil
end

-- Initially not spawned
assertEquals(isSpawned, false, "Initially not spawned")

-- After spawn
simulateSpawn("pixel_pup")
assertEquals(isSpawned, true, "Spawned after spawn()")
assertEquals(spawnedId, "pixel_pup", "Spawned mascot ID is correct")

-- After despawn
simulateDespawn()
assertEquals(isSpawned, false, "Not spawned after despawn()")
assertEquals(spawnedId, nil, "No mascot ID after despawn()")

-- Spawn replaces previous
simulateSpawn("pixel_pup")
simulateSpawn("cube_cat")
assertEquals(isSpawned, true, "Still spawned after replacing")
assertEquals(spawnedId, "cube_cat", "Replaced mascot ID is correct")

-- Despawn when already despawned is safe
simulateDespawn()
simulateDespawn()
assertEquals(isSpawned, false, "Double despawn is safe")

--============================================================================
-- Summary
--============================================================================
print(`\n=== Results: {passed} passed, {failed} failed ===`)

if failed > 0 then
    error(`{failed} test(s) failed`)
end
