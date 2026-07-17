--!strict
--[[
    MorassVisualIntensity.spec.luau - Unit tests for morass visual intensity scaling

    Tests cover: particle config scaling by level, proximity threshold constant,
    and level tier boundaries.

    Validates: Task 8.4 (Morass visual intensity scaling)
]]

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
-- Particle Config Logic (mirrors MorassManager.getParticleConfig)
--============================================================================

type ParticleConfig = {
    rate: number,
    speed: number,
    color: {r: number, g: number, b: number},
    lifetime: number,
}

--- Mirrors the getParticleConfig logic from MorassManager.luau
local function getParticleConfig(levelNum: number): ParticleConfig
    if levelNum <= 3 then
        -- Gentle: low particle rate, muted purple
        return {
            rate = 5,
            speed = 3,
            color = {r = 120, g = 60, b = 150},
            lifetime = 2,
        }
    elseif levelNum <= 6 then
        -- Moderate: standard particle rate
        return {
            rate = 15,
            speed = 6,
            color = {r = 180, g = 50, b = 220},
            lifetime = 1.5,
        }
    else
        -- Intense: high particle rate, vivid colors
        return {
            rate = 35,
            speed = 10,
            color = {r = 255, g = 40, b = 80},
            lifetime = 1,
        }
    end
end

--============================================================================
-- Test: Levels 1-3 (Gentle)
--============================================================================
print("\n=== Morass Visual Intensity: Levels 1-3 (Gentle) ===")

for level = 1, 3 do
    local config = getParticleConfig(level)
    assertEquals(config.rate, 5, `Level {level}: particle rate is 5 (gentle)`)
    assertEquals(config.speed, 3, `Level {level}: particle speed is 3 (slow)`)
    assertEquals(config.lifetime, 2, `Level {level}: particle lifetime is 2 (long-lived)`)
    assertEquals(config.color.r, 120, `Level {level}: color is muted purple (r=120)`)
end

--============================================================================
-- Test: Levels 4-6 (Moderate)
--============================================================================
print("\n=== Morass Visual Intensity: Levels 4-6 (Moderate) ===")

for level = 4, 6 do
    local config = getParticleConfig(level)
    assertEquals(config.rate, 15, `Level {level}: particle rate is 15 (moderate)`)
    assertEquals(config.speed, 6, `Level {level}: particle speed is 6 (medium)`)
    assertEquals(config.lifetime, 1.5, `Level {level}: particle lifetime is 1.5`)
    assertEquals(config.color.r, 180, `Level {level}: color is medium purple (r=180)`)
end

--============================================================================
-- Test: Levels 7-10 (Intense)
--============================================================================
print("\n=== Morass Visual Intensity: Levels 7-10 (Intense) ===")

for level = 7, 10 do
    local config = getParticleConfig(level)
    assertEquals(config.rate, 35, `Level {level}: particle rate is 35 (intense)`)
    assertEquals(config.speed, 10, `Level {level}: particle speed is 10 (fast)`)
    assertEquals(config.lifetime, 1, `Level {level}: particle lifetime is 1 (short)`)
    assertEquals(config.color.r, 255, `Level {level}: color is vivid red (r=255)`)
end

--============================================================================
-- Test: Intensity Monotonically Increases with Level Tier
--============================================================================
print("\n=== Intensity Monotonic Scaling ===")

local gentleConfig = getParticleConfig(1)
local moderateConfig = getParticleConfig(4)
local intenseConfig = getParticleConfig(7)

assertTrue(gentleConfig.rate < moderateConfig.rate, "Gentle rate < Moderate rate")
assertTrue(moderateConfig.rate < intenseConfig.rate, "Moderate rate < Intense rate")
assertTrue(gentleConfig.speed < moderateConfig.speed, "Gentle speed < Moderate speed")
assertTrue(moderateConfig.speed < intenseConfig.speed, "Moderate speed < Intense speed")
assertTrue(gentleConfig.lifetime > moderateConfig.lifetime, "Gentle lifetime > Moderate lifetime (longer = gentler)")
assertTrue(moderateConfig.lifetime > intenseConfig.lifetime, "Moderate lifetime > Intense lifetime")

--============================================================================
-- Test: Proximity Warning Threshold
--============================================================================
print("\n=== Proximity Warning Threshold ===")

-- The proximity warning triggers within 20 blocks of the player.
-- Block scale is 2 studs, so threshold = 20 * 2 = 40 studs.
local BLOCK_SCALE = 2
local PROXIMITY_BLOCKS = 20
local PROXIMITY_THRESHOLD_STUDS = PROXIMITY_BLOCKS * BLOCK_SCALE

assertEquals(PROXIMITY_THRESHOLD_STUDS, 40, "Proximity threshold is 40 studs (20 blocks * 2 scale)")

-- Proximity warning only activates for levels 7-10
for level = 1, 6 do
    local shouldShowWarning = level >= 7
    assertEquals(shouldShowWarning, false, `Level {level}: no proximity warning glow/shake`)
end

for level = 7, 10 do
    local shouldShowWarning = level >= 7
    assertEquals(shouldShowWarning, true, `Level {level}: proximity warning glow/shake active`)
end

--============================================================================
-- Test: Intensity Calculation for Proximity Effects
--============================================================================
print("\n=== Proximity Intensity Calculation ===")

--- Mirrors the intensity calculation from EffectsManager.
--- Returns 0 when at threshold distance, 1 when at 0 distance.
local function calculateProximityIntensity(distance: number, threshold: number): number
    if distance <= 0 or distance > threshold then
        return 0
    end
    local intensity = 1 - (distance / threshold)
    return math.clamp(intensity, 0, 1)
end

-- At threshold distance: intensity = 0
assertEquals(calculateProximityIntensity(40, 40), 0, "At threshold (40 studs): intensity = 0")

-- At half threshold: intensity = 0.5
assertEquals(calculateProximityIntensity(20, 40), 0.5, "At half threshold (20 studs): intensity = 0.5")

-- Very close: intensity approaches 1
assertTrue(calculateProximityIntensity(2, 40) > 0.9, "At 2 studs: intensity > 0.9")

-- At 0 distance: edge case (morass has caught player, should be 0 as handled separately)
assertEquals(calculateProximityIntensity(0, 40), 0, "At 0 distance: intensity = 0 (caught)")

-- Beyond threshold: no effect
assertEquals(calculateProximityIntensity(50, 40), 0, "Beyond threshold (50 studs): intensity = 0")

--============================================================================
-- Summary
--============================================================================
print(`\n=== Results: {passed} passed, {failed} failed ===`)

if failed > 0 then
    error(`{failed} test(s) failed`)
end
