--!strict
--[[
    ComboManager.prop.luau - Property-based tests for ComboManager

    Feature: pixel-run-obby
    Task 4.4: Write property tests for ComboManager

    **Validates: Requirements 4.1, 4.2**

    Tests the combo system's core invariants:
    1. Multiplier increases monotonically with streak
    2. Reset always returns default state (streak=0, multiplier=1.0, tierName=nil)
    3. Tier boundaries are correct at 5, 10, 20, 50
]]

local TestHarness = require("../TestHarness")

--============================================================================
-- Inlined ComboManager Logic (mirrors src/shared/ComboManager.luau)
-- Inlined for Lune compatibility without Roblox require resolution.
--============================================================================

type ComboTierDefinition = {
    minStreak: number,
    name: string,
    multiplier: number,
}

type ComboState = {
    streak: number,
    multiplier: number,
    tierName: string?,
    lastNearMissTime: number,
}

local COMBO_TIERS: {ComboTierDefinition} = {
    { minStreak = 50, name = "Unstoppable!", multiplier = 5.0 },
    { minStreak = 20, name = "Amazing!",     multiplier = 3.0 },
    { minStreak = 10, name = "Great!",       multiplier = 2.0 },
    { minStreak = 5,  name = "Nice!",        multiplier = 1.5 },
}

local function createDefaultState(): ComboState
    return {
        streak = 0,
        multiplier = 1.0,
        tierName = nil,
        lastNearMissTime = 0,
    }
end

local function getTierForStreak(streak: number): (string?, number)
    for _, tier in ipairs(COMBO_TIERS) do
        if streak >= tier.minStreak then
            return tier.name, tier.multiplier
        end
    end
    return nil, 1.0
end

local function startCombo(state: ComboState, currentTime: number): ComboState
    local tierName, multiplier = getTierForStreak(1)
    return {
        streak = 1,
        multiplier = multiplier,
        tierName = tierName,
        lastNearMissTime = currentTime,
    }
end

local function incrementCombo(state: ComboState, currentTime: number): ComboState
    local newStreak = state.streak + 1
    local tierName, multiplier = getTierForStreak(newStreak)
    return {
        streak = newStreak,
        multiplier = multiplier,
        tierName = tierName,
        lastNearMissTime = currentTime,
    }
end

local function resetCombo(state: ComboState): ComboState
    return createDefaultState()
end

--============================================================================
-- Property: Multiplier increases monotonically with streak
-- **Validates: Requirements 4.1**
--
-- For any two streak values a < b, multiplier(a) <= multiplier(b).
-- The multiplier should never decrease as the streak grows.
--============================================================================

print("\n=== Property: Multiplier increases monotonically with streak ===")

TestHarness.property("Multiplier increases monotonically with streak", 100, function(rng)
    -- Pick two random streak values and ensure the higher one has >= multiplier
    local a = TestHarness.randomInt(rng, 0, 100)
    local b = TestHarness.randomInt(rng, a + 1, 200)

    local _nameA, multA = getTierForStreak(a)
    local _nameB, multB = getTierForStreak(b)

    if multB < multA then
        return false, string.format(
            "Multiplier decreased: streak %d -> %.1fx, streak %d -> %.1fx",
            a, multA, b, multB
        )
    end

    return true, nil
end)

TestHarness.property("Multiplier is monotonic through sequential increments", 100, function(rng)
    -- Build up a combo from 0 to a random length and verify multiplier never decreases
    local maxStreak = TestHarness.randomInt(rng, 10, 80)
    local currentTime = TestHarness.randomFloat(rng, 1000, 50000)

    local state = createDefaultState()
    state = startCombo(state, currentTime)
    local prevMultiplier = state.multiplier

    for i = 2, maxStreak do
        currentTime = currentTime + 0.5 -- stay within timeout
        state = incrementCombo(state, currentTime)

        if state.multiplier < prevMultiplier then
            return false, string.format(
                "Multiplier decreased at streak %d: was %.1fx, now %.1fx",
                i, prevMultiplier, state.multiplier
            )
        end
        prevMultiplier = state.multiplier
    end

    return true, nil
end)

--============================================================================
-- Property: Reset always returns default state
-- **Validates: Requirements 4.1**
--
-- For any combo state (regardless of streak, multiplier, or tier),
-- resetCombo must produce streak=0, multiplier=1.0, tierName=nil.
--============================================================================

print("\n=== Property: Reset always returns default state ===")

TestHarness.property("Reset produces streak=0, multiplier=1.0, tierName=nil", 100, function(rng)
    -- Build up a random combo state
    local numIncrements = TestHarness.randomInt(rng, 0, 100)
    local currentTime = TestHarness.randomFloat(rng, 1000, 50000)

    local state = createDefaultState()
    if numIncrements > 0 then
        state = startCombo(state, currentTime)
        for _ = 2, numIncrements do
            currentTime = currentTime + 0.3
            state = incrementCombo(state, currentTime)
        end
    end

    -- Reset should always return default regardless of prior state
    local resetState = resetCombo(state)

    if resetState.streak ~= 0 then
        return false, string.format(
            "After reset, streak should be 0, got %d (was at streak %d)",
            resetState.streak, state.streak
        )
    end

    if resetState.multiplier ~= 1.0 then
        return false, string.format(
            "After reset, multiplier should be 1.0, got %.1f (was at streak %d)",
            resetState.multiplier, state.streak
        )
    end

    if resetState.tierName ~= nil then
        return false, string.format(
            "After reset, tierName should be nil, got '%s' (was at streak %d)",
            tostring(resetState.tierName), state.streak
        )
    end

    return true, nil
end)

--============================================================================
-- Property: Tier boundaries are correct at 5, 10, 20, 50
-- **Validates: Requirements 4.1**
--
-- At exact tier thresholds:
--   streak=5  → "Nice!", 1.5x
--   streak=10 → "Great!", 2.0x
--   streak=20 → "Amazing!", 3.0x
--   streak=50 → "Unstoppable!", 5.0x
-- Between thresholds, the tier from the lower boundary holds.
--============================================================================

print("\n=== Property: Tier boundaries correct at 5, 10, 20, 50 ===")

TestHarness.property("Tier boundaries produce correct name and multiplier", 100, function(rng)
    -- Define expected tier values at exact boundaries
    local boundaries = {
        { streak = 5,  expectedName = "Nice!",        expectedMult = 1.5 },
        { streak = 10, expectedName = "Great!",       expectedMult = 2.0 },
        { streak = 20, expectedName = "Amazing!",     expectedMult = 3.0 },
        { streak = 50, expectedName = "Unstoppable!", expectedMult = 5.0 },
    }

    -- Pick a random boundary to test
    local boundary = boundaries[TestHarness.randomInt(rng, 1, #boundaries)]

    local tierName, multiplier = getTierForStreak(boundary.streak)

    if tierName ~= boundary.expectedName then
        return false, string.format(
            "At streak %d: expected tier '%s', got '%s'",
            boundary.streak, boundary.expectedName, tostring(tierName)
        )
    end

    if multiplier ~= boundary.expectedMult then
        return false, string.format(
            "At streak %d: expected multiplier %.1f, got %.1f",
            boundary.streak, boundary.expectedMult, multiplier
        )
    end

    return true, nil
end)

TestHarness.property("Below tier 1 threshold has no tier and 1.0x multiplier", 100, function(rng)
    -- Any streak from 0 to 4 should have no tier and 1.0x multiplier
    local streak = TestHarness.randomInt(rng, 0, 4)

    local tierName, multiplier = getTierForStreak(streak)

    if tierName ~= nil then
        return false, string.format(
            "At streak %d (below min tier 5): expected nil tier, got '%s'",
            streak, tostring(tierName)
        )
    end

    if multiplier ~= 1.0 then
        return false, string.format(
            "At streak %d (below min tier 5): expected 1.0x, got %.1f",
            streak, multiplier
        )
    end

    return true, nil
end)

TestHarness.property("Between tiers, lower tier boundary holds", 100, function(rng)
    -- Test streaks between tier boundaries to confirm correct tier is assigned
    local ranges = {
        { min = 5,  max = 9,  expectedName = "Nice!",        expectedMult = 1.5 },
        { min = 10, max = 19, expectedName = "Great!",       expectedMult = 2.0 },
        { min = 20, max = 49, expectedName = "Amazing!",     expectedMult = 3.0 },
        { min = 50, max = 150, expectedName = "Unstoppable!", expectedMult = 5.0 },
    }

    local range = ranges[TestHarness.randomInt(rng, 1, #ranges)]
    local streak = TestHarness.randomInt(rng, range.min, range.max)

    local tierName, multiplier = getTierForStreak(streak)

    if tierName ~= range.expectedName then
        return false, string.format(
            "At streak %d (range %d-%d): expected tier '%s', got '%s'",
            streak, range.min, range.max, range.expectedName, tostring(tierName)
        )
    end

    if multiplier ~= range.expectedMult then
        return false, string.format(
            "At streak %d (range %d-%d): expected multiplier %.1f, got %.1f",
            streak, range.min, range.max, range.expectedMult, multiplier
        )
    end

    return true, nil
end)

--============================================================================
-- Report Results
--============================================================================

local allPassed = TestHarness.report()

if not allPassed then
    local process = require("@lune/process")
    process.exit(1)
end
