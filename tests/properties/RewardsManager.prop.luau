--!strict
--[[
    RewardsManager.prop.luau - Property-based tests for RewardsManager / Daily Spin

    Feature: pixel-run-obby
    Task 3.3: Write property tests for RewardsManager / Daily Spin

    **Validates: Requirements 3.1, 3.2, 3.3**

    Since RewardsManager uses Roblox services, we inline the pure daily-spin
    logic for Lune compatibility with a controllable clock.
]]

local TestHarness = require("../TestHarness")

--============================================================================
-- Inlined RewardsManager Logic (mirrors src/shared/RewardsManager.luau)
--============================================================================

local SECONDS_PER_DAY = 86400

type RewardSegment = {
    xpAmount: number,
    label: string,
    weight: number,
}

type RewardResult = {
    xpAmount: number,
    segmentIndex: number,
    label: string,
}

local REWARD_SEGMENTS: { RewardSegment } = {
    { xpAmount = 100,  label = "100 XP",     weight = 1 },  -- index 1
    { xpAmount = 100,  label = "100 XP",     weight = 1 },  -- index 2
    { xpAmount = 100,  label = "100 XP",     weight = 1 },  -- index 3
    { xpAmount = 200,  label = "200 XP",     weight = 1 },  -- index 4
    { xpAmount = 200,  label = "200 XP",     weight = 1 },  -- index 5
    { xpAmount = 500,  label = "500 XP",     weight = 1 },  -- index 6
    { xpAmount = 500,  label = "500 XP",     weight = 1 },  -- index 7
    { xpAmount = 1000, label = "1000 XP",    weight = 1 },  -- index 8
    { xpAmount = 2000, label = "2000 XP",    weight = 1 },  -- index 9
    { xpAmount = 500,  label = "Bonus Spin", weight = 1 },  -- index 10
}

--- Determines whether a player can spin today based on their last spin timestamp.
--- Uses UTC day comparison: math.floor(timestamp / 86400).
local function canSpinToday(lastSpinTimestamp: number?, currentTime: number): boolean
    if lastSpinTimestamp == nil then
        return true
    end

    local lastDay = math.floor(lastSpinTimestamp / SECONDS_PER_DAY)
    local today = math.floor(currentTime / SECONDS_PER_DAY)

    return today > lastDay
end

--- Determines the reward for a spin based on a seed value.
local function determineReward(seed: number?): RewardResult
    local segmentCount = #REWARD_SEGMENTS
    local segmentIndex: number

    if seed ~= nil then
        segmentIndex = ((seed - 1) % segmentCount) + 1
    else
        segmentIndex = math.random(1, segmentCount)
    end

    local segment = REWARD_SEGMENTS[segmentIndex]

    return {
        xpAmount = segment.xpAmount,
        segmentIndex = segmentIndex,
        label = segment.label,
    }
end

--- Returns the reward segments table.
local function getRewardSegments(): { RewardSegment }
    return REWARD_SEGMENTS
end

--============================================================================
-- Property: Cannot spin twice same day
-- **Validates: Requirements 3.1**
--============================================================================

print("\n=== Property: Cannot spin twice same day ===")

TestHarness.property("Cannot spin twice on the same UTC day", 100, function(rng)
    -- Generate a random current time (some point in time)
    local currentTime = TestHarness.randomFloat(rng, 86400, 2000000000)

    -- First spin: player has never spun (nil), so canSpinToday should be true
    local canFirstSpin = canSpinToday(nil, currentTime)
    if not canFirstSpin then
        return false, string.format(
            "First spin (nil lastSpin) should be allowed. currentTime=%.0f",
            currentTime
        )
    end

    -- After spinning, lastSpinTimestamp = currentTime
    -- Same day: try again with a time on the same UTC day
    local currentDay = math.floor(currentTime / SECONDS_PER_DAY)
    -- Generate a second time that's still the same UTC day
    local dayStart = currentDay * SECONDS_PER_DAY
    local dayEnd = dayStart + SECONDS_PER_DAY - 1
    local secondTime = TestHarness.randomFloat(rng, currentTime, dayEnd)

    local canSecondSpin = canSpinToday(currentTime, secondTime)
    if canSecondSpin then
        return false, string.format(
            "Should NOT be able to spin again on same UTC day. lastSpin=%.0f, currentTime=%.0f, lastDay=%d, today=%d",
            currentTime, secondTime, math.floor(currentTime / SECONDS_PER_DAY), math.floor(secondTime / SECONDS_PER_DAY)
        )
    end

    return true, nil
end)

--============================================================================
-- Property: All rewards > 0
-- **Validates: Requirements 3.1**
--============================================================================

print("\n=== Property: All rewards > 0 ===")

TestHarness.property("All reward segments have xpAmount > 0", 100, function(rng)
    -- Use a random seed to pick a segment via determineReward
    local seed = TestHarness.randomInt(rng, 1, 10000)
    local result = determineReward(seed)

    if result.xpAmount <= 0 then
        return false, string.format(
            "Reward xpAmount must be > 0. Got %d for seed=%d, segmentIndex=%d, label=%s",
            result.xpAmount, seed, result.segmentIndex, result.label
        )
    end

    -- Also verify the segment table directly for completeness
    local segments = getRewardSegments()
    for i, segment in segments do
        if segment.xpAmount <= 0 then
            return false, string.format(
                "Segment %d has xpAmount=%d (must be > 0). label=%s",
                i, segment.xpAmount, segment.label
            )
        end
    end

    return true, nil
end)

--============================================================================
-- Property: canSpinToday true if last spin was yesterday or earlier
-- **Validates: Requirements 3.1**
--============================================================================

print("\n=== Property: canSpinToday true if last spin was yesterday or earlier ===")

TestHarness.property("canSpinToday returns true if last spin was yesterday or earlier", 100, function(rng)
    -- Generate a last spin timestamp
    local lastSpinTime = TestHarness.randomFloat(rng, 86400, 1500000000)
    local lastSpinDay = math.floor(lastSpinTime / SECONDS_PER_DAY)

    -- Current time is at least 1 day later (yesterday or earlier)
    local daysLater = TestHarness.randomInt(rng, 1, 365)
    local laterDay = lastSpinDay + daysLater
    -- Pick a random time within that later day
    local currentTime = laterDay * SECONDS_PER_DAY + TestHarness.randomFloat(rng, 0, SECONDS_PER_DAY - 1)

    local result = canSpinToday(lastSpinTime, currentTime)

    if not result then
        return false, string.format(
            "canSpinToday should be true when last spin was %d days ago. lastSpin=%.0f (day %d), current=%.0f (day %d)",
            daysLater, lastSpinTime, lastSpinDay, currentTime, math.floor(currentTime / SECONDS_PER_DAY)
        )
    end

    return true, nil
end)

--============================================================================
-- Property: canSpinToday false if last spin was today
-- **Validates: Requirements 3.1**
--============================================================================

print("\n=== Property: canSpinToday false if last spin was today ===")

TestHarness.property("canSpinToday returns false if last spin was today", 100, function(rng)
    -- Pick a random UTC day
    local dayNumber = TestHarness.randomInt(rng, 1, 20000)
    local dayStart = dayNumber * SECONDS_PER_DAY

    -- Last spin is some time within this day
    local lastSpinTime = dayStart + TestHarness.randomFloat(rng, 0, SECONDS_PER_DAY - 1)

    -- Current time is also within the same day (at or after lastSpinTime)
    local currentTime = TestHarness.randomFloat(rng, lastSpinTime, dayStart + SECONDS_PER_DAY - 1)

    local result = canSpinToday(lastSpinTime, currentTime)

    if result then
        return false, string.format(
            "canSpinToday should be false when last spin was today. lastSpin=%.0f (day %d), current=%.0f (day %d)",
            lastSpinTime, math.floor(lastSpinTime / SECONDS_PER_DAY), currentTime, math.floor(currentTime / SECONDS_PER_DAY)
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
