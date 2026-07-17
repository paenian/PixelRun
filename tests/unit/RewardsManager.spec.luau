--!strict
--[[
    RewardsManager.spec.luau - Unit tests for RewardsManager module

    Tests the daily spin reward logic:
    - canSpinToday correctly compares UTC days
    - determineReward returns valid segments
    - getRewardSegments returns the expected table
    - getLastSpinDate converts timestamps to day numbers
]]

local process = require("@lune/process")

-- Inline the RewardsManager logic for Lune compatibility
-- (mirrors src/shared/RewardsManager.luau without Roblox require paths)

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
    { xpAmount = 100,  label = "100 XP",     weight = 1 },
    { xpAmount = 100,  label = "100 XP",     weight = 1 },
    { xpAmount = 100,  label = "100 XP",     weight = 1 },
    { xpAmount = 200,  label = "200 XP",     weight = 1 },
    { xpAmount = 200,  label = "200 XP",     weight = 1 },
    { xpAmount = 500,  label = "500 XP",     weight = 1 },
    { xpAmount = 500,  label = "500 XP",     weight = 1 },
    { xpAmount = 1000, label = "1000 XP",    weight = 1 },
    { xpAmount = 2000, label = "2000 XP",    weight = 1 },
    { xpAmount = 500,  label = "Bonus Spin", weight = 1 },
}

local function canSpinToday(lastSpinTimestamp: number?, currentTime: number): boolean
    if lastSpinTimestamp == nil then
        return true
    end
    local lastDay = math.floor(lastSpinTimestamp / SECONDS_PER_DAY)
    local today = math.floor(currentTime / SECONDS_PER_DAY)
    return today > lastDay
end

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

local function getLastSpinDate(timestamp: number): number
    return math.floor(timestamp / SECONDS_PER_DAY)
end

local function getRewardSegments(): { RewardSegment }
    return REWARD_SEGMENTS
end

--============================================================================
-- Test Helpers
--============================================================================

local passed = 0
local failed = 0

local function assert_eq(actual: any, expected: any, message: string)
    if actual == expected then
        passed += 1
        print(string.format("  ✓ %s", message))
    else
        failed += 1
        print(string.format("  ✗ %s (expected %s, got %s)", message, tostring(expected), tostring(actual)))
    end
end

local function assert_true(value: boolean, message: string)
    if value then
        passed += 1
        print(string.format("  ✓ %s", message))
    else
        failed += 1
        print(string.format("  ✗ %s (expected true, got false)", message))
    end
end

local function assert_false(value: boolean, message: string)
    if not value then
        passed += 1
        print(string.format("  ✓ %s", message))
    else
        failed += 1
        print(string.format("  ✗ %s (expected false, got true)", message))
    end
end

--============================================================================
-- Tests: getRewardSegments
--============================================================================

print("\n=== getRewardSegments ===")

local segments = getRewardSegments()
assert_eq(#segments, 10, "Should have exactly 10 segments")
assert_eq(segments[1].xpAmount, 100, "Segment 1 is 100 XP")
assert_eq(segments[4].xpAmount, 200, "Segment 4 is 200 XP")
assert_eq(segments[6].xpAmount, 500, "Segment 6 is 500 XP")
assert_eq(segments[8].xpAmount, 1000, "Segment 8 is 1000 XP")
assert_eq(segments[9].xpAmount, 2000, "Segment 9 is 2000 XP")
assert_eq(segments[10].label, "Bonus Spin", "Segment 10 is Bonus Spin")
assert_eq(segments[10].xpAmount, 500, "Bonus Spin awards 500 XP")

--============================================================================
-- Tests: canSpinToday
--============================================================================

print("\n=== canSpinToday ===")

-- nil lastSpin means first ever spin, always allowed
assert_true(canSpinToday(nil, 1000000), "First ever spin (nil lastSpin) is allowed")

-- Same day: should return false
local baseTime = 86400 * 20000 + 43200  -- Midday of day 20000
assert_false(canSpinToday(baseTime, baseTime + 100), "Same day, 100 seconds later: cannot spin")
assert_false(canSpinToday(baseTime, baseTime + 43000), "Same day, near end: cannot spin")

-- Next day: should return true
local nextDayTime = 86400 * 20001 + 100  -- Early on day 20001
assert_true(canSpinToday(baseTime, nextDayTime), "Next UTC day: can spin")

-- Many days later: should return true
local weekLater = 86400 * 20007 + 50000
assert_true(canSpinToday(baseTime, weekLater), "A week later: can spin")

-- Edge case: last second of day vs first second of next day
local endOfDay = 86400 * 20000 + 86399
local startOfNext = 86400 * 20001
assert_true(canSpinToday(endOfDay, startOfNext), "End of day vs start of next: can spin")

-- Edge case: start of day vs end of same day
local startOfDay = 86400 * 20000
local endSameDay = 86400 * 20000 + 86399
assert_false(canSpinToday(startOfDay, endSameDay), "Start vs end of same day: cannot spin")

--============================================================================
-- Tests: determineReward
--============================================================================

print("\n=== determineReward ===")

-- Deterministic: seed 1 -> segment 1 (100 XP)
local r1 = determineReward(1)
assert_eq(r1.segmentIndex, 1, "Seed 1 -> segment index 1")
assert_eq(r1.xpAmount, 100, "Seed 1 -> 100 XP")

-- Seed 4 -> segment 4 (200 XP)
local r4 = determineReward(4)
assert_eq(r4.segmentIndex, 4, "Seed 4 -> segment index 4")
assert_eq(r4.xpAmount, 200, "Seed 4 -> 200 XP")

-- Seed 9 -> segment 9 (2000 XP)
local r9 = determineReward(9)
assert_eq(r9.segmentIndex, 9, "Seed 9 -> segment index 9")
assert_eq(r9.xpAmount, 2000, "Seed 9 -> 2000 XP")

-- Seed 10 -> segment 10 (Bonus Spin / 500 XP)
local r10 = determineReward(10)
assert_eq(r10.segmentIndex, 10, "Seed 10 -> segment index 10")
assert_eq(r10.label, "Bonus Spin", "Seed 10 -> Bonus Spin label")

-- Seed wraps around: seed 11 -> segment 1
local r11 = determineReward(11)
assert_eq(r11.segmentIndex, 1, "Seed 11 wraps to segment 1")

-- Seed 20 -> segment 10
local r20 = determineReward(20)
assert_eq(r20.segmentIndex, 10, "Seed 20 wraps to segment 10")

-- Random (no seed): just verify it returns a valid result
local rRand = determineReward(nil)
assert_true(rRand.segmentIndex >= 1 and rRand.segmentIndex <= 10, "Random seed gives valid index (1-10)")
assert_true(rRand.xpAmount > 0, "Random reward has positive XP")

--============================================================================
-- Tests: getLastSpinDate
--============================================================================

print("\n=== getLastSpinDate ===")

assert_eq(getLastSpinDate(0), 0, "Timestamp 0 -> day 0")
assert_eq(getLastSpinDate(86400), 1, "Timestamp 86400 -> day 1")
assert_eq(getLastSpinDate(86400 * 365), 365, "Timestamp for 365 days -> day 365")
assert_eq(getLastSpinDate(86399), 0, "Last second of day 0 -> day 0")
assert_eq(getLastSpinDate(86400 + 1), 1, "First second of day 1 -> day 1")

--============================================================================
-- Summary
--============================================================================

print(string.format("\n=== Results: %d passed, %d failed ===", passed, failed))

if failed > 0 then
    process.exit(1)
end
