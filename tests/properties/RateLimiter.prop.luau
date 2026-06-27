--!strict
--[[
    RateLimiter.prop.luau - Property-based tests for RateLimiter

    Feature: pixel-run-obby
    Property 19: Rate Limiter Enforces Cap

    Validates: Requirements 13.6

    Since RateLimiter uses Roblox services (tick(), game:GetService), we inline
    the pure rate limiting logic for Lune compatibility with a controllable clock.
]]

local TestHarness = require("../TestHarness")

--============================================================================
-- Inlined Rate Limiter Logic (mirrors src/server/RateLimiter.luau)
-- Uses an injectable clock function instead of tick() for testability.
--============================================================================

local MAX_CALLS_PER_SECOND = 30

type RateLimitState = {
    count: number,
    lastReset: number,
}

type RateLimiterInstance = {
    state: { [number]: RateLimitState },
    clock: () -> number,
}

--- Create a new rate limiter instance with a controllable clock.
local function createRateLimiter(clockFn: () -> number): RateLimiterInstance
    return {
        state = {},
        clock = clockFn,
    }
end

--- Check whether a call from the given userId should be allowed.
--- Returns true if under the rate limit, false if dropped.
local function rateLimiterCheck(limiter: RateLimiterInstance, userId: number): boolean
    local now = limiter.clock()
    local playerState = limiter.state[userId]

    if not playerState then
        -- First call from this player; initialize state
        limiter.state[userId] = {
            count = 1,
            lastReset = now,
        }
        return true
    end

    -- If more than 1 second has elapsed since last reset, reset the counter
    if now - playerState.lastReset > 1 then
        playerState.count = 1
        playerState.lastReset = now
        return true
    end

    -- Increment call count
    playerState.count += 1

    -- Check if over the limit
    if playerState.count > MAX_CALLS_PER_SECOND then
        return false
    end

    return true
end

--- Reset rate limiter state for a given user.
local function rateLimiterReset(limiter: RateLimiterInstance, userId: number)
    limiter.state[userId] = nil
end

--============================================================================
-- Property 19: Rate Limiter Enforces Cap
-- **Validates: Requirements 13.6**
--
-- - First 30 calls within 1 second → all return true
-- - Call 31+ within same second → return false
-- - After 1 second window resets → calls pass again
--============================================================================

print("\n=== Property 19: Rate Limiter Enforces Cap ===")

TestHarness.property("First 30 calls within 1 second all pass", 100, function(rng)
    -- Use a fixed timestamp (simulate all calls within same second)
    local startTime = TestHarness.randomFloat(rng, 0, 100000)
    local currentTime = startTime

    local limiter = createRateLimiter(function()
        return currentTime
    end)

    local userId = TestHarness.randomInt(rng, 1, 1000000)

    -- Make exactly 30 calls within the same second
    for i = 1, 30 do
        -- Advance time slightly but stay within 1 second window
        currentTime = startTime + (i - 1) * 0.01 -- 10ms between calls, total < 1s
        local allowed = rateLimiterCheck(limiter, userId)
        if not allowed then
            return false, string.format(
                "Call %d of 30 was rejected (should all pass). userId=%d, time=%.4f",
                i, userId, currentTime
            )
        end
    end

    return true, nil
end)

TestHarness.property("Call 31+ within same second are dropped", 150, function(rng)
    -- Fixed time for all calls (simulate burst)
    local fixedTime = TestHarness.randomFloat(rng, 0, 100000)

    local limiter = createRateLimiter(function()
        return fixedTime
    end)

    local userId = TestHarness.randomInt(rng, 1, 1000000)

    -- Make the first 30 calls (these should pass)
    for _ = 1, 30 do
        rateLimiterCheck(limiter, userId)
    end

    -- Now make additional calls (31 to 30 + N) — all should be dropped
    local extraCalls = TestHarness.randomInt(rng, 1, 50)
    for i = 1, extraCalls do
        local allowed = rateLimiterCheck(limiter, userId)
        if allowed then
            return false, string.format(
                "Call %d (total call %d) was allowed but should be dropped. userId=%d",
                i, 30 + i, userId
            )
        end
    end

    return true, nil
end)

TestHarness.property("After 1 second window resets, calls pass again", 150, function(rng)
    local startTime = TestHarness.randomFloat(rng, 100, 100000)
    local currentTime = startTime

    local limiter = createRateLimiter(function()
        return currentTime
    end)

    local userId = TestHarness.randomInt(rng, 1, 1000000)

    -- Exhaust the rate limit (make 30 calls)
    for _ = 1, 30 do
        rateLimiterCheck(limiter, userId)
    end

    -- Verify call 31 is dropped
    local dropped = rateLimiterCheck(limiter, userId)
    if dropped then
        return false, string.format(
            "Call 31 should be dropped before window reset. userId=%d",
            userId
        )
    end

    -- Advance time by more than 1 second
    local timeAdvance = TestHarness.randomFloat(rng, 1.001, 5.0)
    currentTime = startTime + timeAdvance

    -- Now the next call should pass (window has reset)
    local allowedAfterReset = rateLimiterCheck(limiter, userId)
    if not allowedAfterReset then
        return false, string.format(
            "First call after window reset should pass. userId=%d, timeAdvance=%.3f",
            userId, timeAdvance
        )
    end

    -- And we should be able to make another 29 calls (total 30 in new window)
    for i = 2, 30 do
        -- Stay within the new 1-second window
        currentTime = startTime + timeAdvance + (i - 1) * 0.01
        local allowed = rateLimiterCheck(limiter, userId)
        if not allowed then
            return false, string.format(
                "Call %d in new window was rejected (should pass). userId=%d",
                i, userId
            )
        end
    end

    return true, nil
end)

TestHarness.property("Different users have independent rate limits", 100, function(rng)
    local fixedTime = TestHarness.randomFloat(rng, 0, 100000)

    local limiter = createRateLimiter(function()
        return fixedTime
    end)

    -- Generate two distinct user IDs
    local userId1 = TestHarness.randomInt(rng, 1, 500000)
    local userId2 = userId1 + TestHarness.randomInt(rng, 1, 500000)

    -- Exhaust rate limit for user 1
    for _ = 1, 30 do
        rateLimiterCheck(limiter, userId1)
    end

    -- Verify user 1 is now rate limited
    local user1Blocked = rateLimiterCheck(limiter, userId1)
    if user1Blocked then
        return false, string.format(
            "User %d should be rate limited after 30 calls",
            userId1
        )
    end

    -- User 2 should still be able to make calls
    local user2Allowed = rateLimiterCheck(limiter, userId2)
    if not user2Allowed then
        return false, string.format(
            "User %d should not be affected by user %d's rate limit",
            userId2, userId1
        )
    end

    -- User 2 should be able to make all 30 calls
    -- Already made 1, so 29 more
    for i = 2, 30 do
        local allowed = rateLimiterCheck(limiter, userId2)
        if not allowed then
            return false, string.format(
                "User %d's call %d should pass (independent limit). userId1=%d already exhausted.",
                userId2, i, userId1
            )
        end
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
