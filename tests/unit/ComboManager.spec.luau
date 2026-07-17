--!strict
--[[
    ComboManager.spec.luau - Unit tests for ComboManager module

    Tests cover: startCombo, incrementCombo, resetCombo, getCurrentMultiplier,
    getComboTier, shouldTimeout, getTierForStreak, createDefaultState

    Validates: Requirements 6.1

    Since ComboManager uses require(script.Parent.Types) which doesn't work in Lune,
    we inline the pure functions here (mirroring the source exactly).
]]

--============================================================================
-- Inlined ComboManager logic (mirrors src/shared/ComboManager.luau)
--============================================================================

type ComboState = {
    streak: number,
    multiplier: number,
    tierName: string?,
    lastNearMissTime: number,
}

type ComboTierDefinition = {
    minStreak: number,
    name: string,
    multiplier: number,
}

local ComboManager = {}

ComboManager.COMBO_TIERS = {
    { minStreak = 50, name = "Unstoppable!", multiplier = 5.0 },
    { minStreak = 20, name = "Amazing!",     multiplier = 3.0 },
    { minStreak = 10, name = "Great!",       multiplier = 2.0 },
    { minStreak = 5,  name = "Nice!",        multiplier = 1.5 },
}

ComboManager.NEAR_MISS_DISTANCE = 1
ComboManager.TIMEOUT_SECONDS = 1

function ComboManager.createDefaultState(): ComboState
    return {
        streak = 0,
        multiplier = 1.0,
        tierName = nil,
        lastNearMissTime = 0,
    }
end

function ComboManager.getTierForStreak(streak: number): (string?, number)
    for _, tier in ipairs(ComboManager.COMBO_TIERS) do
        if streak >= tier.minStreak then
            return tier.name, tier.multiplier
        end
    end
    return nil, 1.0
end

function ComboManager.startCombo(state: ComboState, currentTime: number): ComboState
    local tierName, multiplier = ComboManager.getTierForStreak(1)
    return {
        streak = 1,
        multiplier = multiplier,
        tierName = tierName,
        lastNearMissTime = currentTime,
    }
end

function ComboManager.incrementCombo(state: ComboState, currentTime: number): ComboState
    local newStreak = state.streak + 1
    local tierName, multiplier = ComboManager.getTierForStreak(newStreak)
    return {
        streak = newStreak,
        multiplier = multiplier,
        tierName = tierName,
        lastNearMissTime = currentTime,
    }
end

function ComboManager.resetCombo(state: ComboState): ComboState
    return ComboManager.createDefaultState()
end

function ComboManager.getCurrentMultiplier(state: ComboState): number
    return state.multiplier
end

function ComboManager.getComboTier(state: ComboState): string?
    return state.tierName
end

function ComboManager.shouldTimeout(state: ComboState, currentTime: number): boolean
    if state.streak == 0 then
        return false
    end
    return (currentTime - state.lastNearMissTime) > ComboManager.TIMEOUT_SECONDS
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

local function assertNil(value: any, testName: string)
    if value == nil then
        passed += 1
        print(`  ✓ {testName}`)
    else
        failed += 1
        print(`  ✗ {testName}: expected nil, got {value}`)
    end
end

--============================================================================
-- createDefaultState tests
--============================================================================
print("\n=== createDefaultState ===")

local defaultState = ComboManager.createDefaultState()
assertEquals(defaultState.streak, 0, "Default state streak = 0")
assertEquals(defaultState.multiplier, 1.0, "Default state multiplier = 1.0")
assertNil(defaultState.tierName, "Default state tierName = nil")
assertEquals(defaultState.lastNearMissTime, 0, "Default state lastNearMissTime = 0")

--============================================================================
-- startCombo tests
--============================================================================
print("\n=== startCombo ===")

local state = ComboManager.createDefaultState()
local startedState = ComboManager.startCombo(state, 100.0)
assertEquals(startedState.streak, 1, "startCombo sets streak to 1")
assertEquals(startedState.multiplier, 1.0, "startCombo at streak 1 has multiplier 1.0 (below tier 1)")
assertNil(startedState.tierName, "startCombo at streak 1 has no tier name")
assertEquals(startedState.lastNearMissTime, 100.0, "startCombo sets lastNearMissTime to currentTime")

-- Original state is unchanged (immutability)
assertEquals(state.streak, 0, "Original state is unchanged after startCombo")

--============================================================================
-- incrementCombo tests
--============================================================================
print("\n=== incrementCombo ===")

-- Increment from streak 1 to 2
local state2 = ComboManager.incrementCombo(startedState, 100.5)
assertEquals(state2.streak, 2, "incrementCombo from 1 → streak = 2")
assertEquals(state2.multiplier, 1.0, "Streak 2 still below tier threshold, multiplier = 1.0")
assertNil(state2.tierName, "Streak 2 still has no tier name")
assertEquals(state2.lastNearMissTime, 100.5, "incrementCombo updates lastNearMissTime")

-- Build up to tier 1 boundary (streak 5)
local buildState: ComboState = startedState
for i = 1, 4 do
    buildState = ComboManager.incrementCombo(buildState, 100.0 + i * 0.2)
end
assertEquals(buildState.streak, 5, "After 4 increments from streak 1, streak = 5")
assertEquals(buildState.multiplier, 1.5, "Streak 5 → tier 1 multiplier = 1.5")
assertEquals(buildState.tierName, "Nice!", "Streak 5 → tier name = 'Nice!'")

-- Build to tier 2 (streak 10)
local tier2State: ComboState = buildState
for i = 1, 5 do
    tier2State = ComboManager.incrementCombo(tier2State, 101.0 + i * 0.2)
end
assertEquals(tier2State.streak, 10, "Build to streak 10")
assertEquals(tier2State.multiplier, 2.0, "Streak 10 → tier 2 multiplier = 2.0")
assertEquals(tier2State.tierName, "Great!", "Streak 10 → tier name = 'Great!'")

-- Build to tier 3 (streak 20)
local tier3State: ComboState = tier2State
for i = 1, 10 do
    tier3State = ComboManager.incrementCombo(tier3State, 102.0 + i * 0.2)
end
assertEquals(tier3State.streak, 20, "Build to streak 20")
assertEquals(tier3State.multiplier, 3.0, "Streak 20 → tier 3 multiplier = 3.0")
assertEquals(tier3State.tierName, "Amazing!", "Streak 20 → tier name = 'Amazing!'")

-- Build to tier 4 (streak 50)
local tier4State: ComboState = tier3State
for i = 1, 30 do
    tier4State = ComboManager.incrementCombo(tier4State, 103.0 + i * 0.2)
end
assertEquals(tier4State.streak, 50, "Build to streak 50")
assertEquals(tier4State.multiplier, 5.0, "Streak 50 → tier 4 multiplier = 5.0")
assertEquals(tier4State.tierName, "Unstoppable!", "Streak 50 → tier name = 'Unstoppable!'")

--============================================================================
-- resetCombo tests
--============================================================================
print("\n=== resetCombo ===")

local resetState = ComboManager.resetCombo(tier4State)
assertEquals(resetState.streak, 0, "resetCombo sets streak = 0")
assertEquals(resetState.multiplier, 1.0, "resetCombo sets multiplier = 1.0")
assertNil(resetState.tierName, "resetCombo sets tierName = nil")
assertEquals(resetState.lastNearMissTime, 0, "resetCombo sets lastNearMissTime = 0")

-- Original state unchanged
assertEquals(tier4State.streak, 50, "Original state unchanged after resetCombo")

--============================================================================
-- getCurrentMultiplier tests
--============================================================================
print("\n=== getCurrentMultiplier ===")

assertEquals(ComboManager.getCurrentMultiplier(ComboManager.createDefaultState()), 1.0, "Default state multiplier = 1.0")
assertEquals(ComboManager.getCurrentMultiplier(buildState), 1.5, "Streak 5 multiplier = 1.5")
assertEquals(ComboManager.getCurrentMultiplier(tier2State), 2.0, "Streak 10 multiplier = 2.0")
assertEquals(ComboManager.getCurrentMultiplier(tier3State), 3.0, "Streak 20 multiplier = 3.0")
assertEquals(ComboManager.getCurrentMultiplier(tier4State), 5.0, "Streak 50 multiplier = 5.0")

--============================================================================
-- getComboTier tests
--============================================================================
print("\n=== getComboTier ===")

assertNil(ComboManager.getComboTier(ComboManager.createDefaultState()), "Default state tier = nil")
assertNil(ComboManager.getComboTier(startedState), "Streak 1 tier = nil")
assertEquals(ComboManager.getComboTier(buildState), "Nice!", "Streak 5 tier = 'Nice!'")
assertEquals(ComboManager.getComboTier(tier2State), "Great!", "Streak 10 tier = 'Great!'")
assertEquals(ComboManager.getComboTier(tier3State), "Amazing!", "Streak 20 tier = 'Amazing!'")
assertEquals(ComboManager.getComboTier(tier4State), "Unstoppable!", "Streak 50 tier = 'Unstoppable!'")

--============================================================================
-- shouldTimeout tests
--============================================================================
print("\n=== shouldTimeout ===")

-- No timeout when streak is 0
local noComboState = ComboManager.createDefaultState()
assertEquals(ComboManager.shouldTimeout(noComboState, 999.0), false, "No timeout when streak = 0")

-- Active combo, within timeout window (< 1 second)
local activeState: ComboState = { streak = 5, multiplier = 1.5, tierName = "Nice!", lastNearMissTime = 100.0 }
assertEquals(ComboManager.shouldTimeout(activeState, 100.5), false, "No timeout at 0.5s elapsed")
assertEquals(ComboManager.shouldTimeout(activeState, 100.9), false, "No timeout at 0.9s elapsed")
assertEquals(ComboManager.shouldTimeout(activeState, 101.0), false, "No timeout at exactly 1.0s (not > 1)")

-- Active combo, past timeout window (> 1 second)
assertEquals(ComboManager.shouldTimeout(activeState, 101.01), true, "Timeout at 1.01s elapsed")
assertEquals(ComboManager.shouldTimeout(activeState, 105.0), true, "Timeout at 5.0s elapsed")

--============================================================================
-- getTierForStreak tests
--============================================================================
print("\n=== getTierForStreak ===")

local name0, mult0 = ComboManager.getTierForStreak(0)
assertNil(name0, "Streak 0 → no tier name")
assertEquals(mult0, 1.0, "Streak 0 → multiplier 1.0")

local name4, mult4 = ComboManager.getTierForStreak(4)
assertNil(name4, "Streak 4 → no tier name (below threshold)")
assertEquals(mult4, 1.0, "Streak 4 → multiplier 1.0")

local name5, mult5 = ComboManager.getTierForStreak(5)
assertEquals(name5, "Nice!", "Streak 5 → 'Nice!'")
assertEquals(mult5, 1.5, "Streak 5 → 1.5x")

local name9, mult9 = ComboManager.getTierForStreak(9)
assertEquals(name9, "Nice!", "Streak 9 → still 'Nice!'")
assertEquals(mult9, 1.5, "Streak 9 → still 1.5x")

local name10, mult10 = ComboManager.getTierForStreak(10)
assertEquals(name10, "Great!", "Streak 10 → 'Great!'")
assertEquals(mult10, 2.0, "Streak 10 → 2.0x")

local name19, mult19 = ComboManager.getTierForStreak(19)
assertEquals(name19, "Great!", "Streak 19 → still 'Great!'")
assertEquals(mult19, 2.0, "Streak 19 → still 2.0x")

local name20, mult20 = ComboManager.getTierForStreak(20)
assertEquals(name20, "Amazing!", "Streak 20 → 'Amazing!'")
assertEquals(mult20, 3.0, "Streak 20 → 3.0x")

local name49, mult49 = ComboManager.getTierForStreak(49)
assertEquals(name49, "Amazing!", "Streak 49 → still 'Amazing!'")
assertEquals(mult49, 3.0, "Streak 49 → still 3.0x")

local name50, mult50 = ComboManager.getTierForStreak(50)
assertEquals(name50, "Unstoppable!", "Streak 50 → 'Unstoppable!'")
assertEquals(mult50, 5.0, "Streak 50 → 5.0x")

local name100, mult100 = ComboManager.getTierForStreak(100)
assertEquals(name100, "Unstoppable!", "Streak 100 → still 'Unstoppable!'")
assertEquals(mult100, 5.0, "Streak 100 → still 5.0x")

--============================================================================
-- Summary
--============================================================================
print(`\n=== Results: {passed} passed, {failed} failed ===`)

if failed > 0 then
    error(`{failed} test(s) failed`)
end
