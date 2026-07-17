--!strict
--[[
    CodesManager.prop.luau - Property-based tests for CodesManager

    Feature: pixel-run-obby
    Task 2.4: Write property tests for CodesManager

    **Validates: Requirements 2.1, 2.2, 2.3, 2.4**

    Since CodesManager uses Roblox services (os.time for expiry), we inline
    the pure code redemption logic for Lune compatibility with a controllable clock.
]]

local TestHarness = require("../TestHarness")

--============================================================================
-- Inlined CodesManager Logic (mirrors src/server/CodesManager.luau)
-- Uses an injectable clock function instead of os.time() for testability.
--============================================================================

type CodeReward = {
    rewardType: string,
    amount: number?,
    mascotId: string?,
}

type CodeDefinition = {
    code: string,
    reward: CodeReward,
    maxRedemptions: number?,
    expiresAt: number?,
}

type RedemptionResult = {
    success: boolean,
    message: string,
    reward: CodeReward?,
}

type CodesManagerInstance = {
    codeDefinitions: { [string]: CodeDefinition },
    globalRedemptionCounts: { [string]: number },
    playerRedemptions: { [number]: { [string]: boolean } },
    clock: () -> number,
}

--- Normalizes a code string: uppercase, trimmed of whitespace.
local function normalizeCode(input: string): string
    return string.upper(string.gsub(input, "%s+", ""))
end

--- Create a new CodesManager instance with a controllable clock.
local function createCodesManager(clockFn: () -> number): CodesManagerInstance
    return {
        codeDefinitions = {},
        globalRedemptionCounts = {},
        playerRedemptions = {},
        clock = clockFn,
    }
end

--- Register a code definition.
local function addCode(mgr: CodesManagerInstance, definition: CodeDefinition)
    local normalized = normalizeCode(definition.code)
    mgr.codeDefinitions[normalized] = {
        code = normalized,
        reward = definition.reward,
        maxRedemptions = definition.maxRedemptions,
        expiresAt = definition.expiresAt,
    }
    if not mgr.globalRedemptionCounts[normalized] then
        mgr.globalRedemptionCounts[normalized] = 0
    end
end

--- Load a player's previously redeemed codes.
local function loadPlayerRedemptions(mgr: CodesManagerInstance, userId: number, redeemedCodes: { string }?)
    mgr.playerRedemptions[userId] = {}
    if redeemedCodes then
        for _, code in redeemedCodes do
            mgr.playerRedemptions[userId][normalizeCode(code)] = true
        end
    end
end

--- Check if a player has already redeemed a specific code.
local function hasRedeemed(mgr: CodesManagerInstance, userId: number, code: string): boolean
    local normalized = normalizeCode(code)
    local playerCodes = mgr.playerRedemptions[userId]
    if not playerCodes then
        return false
    end
    return playerCodes[normalized] == true
end

--- Attempt to redeem a code for a player.
local function redeemCode(mgr: CodesManagerInstance, userId: number, inputCode: string): RedemptionResult
    -- Validate input
    if type(inputCode) ~= "string" or #inputCode == 0 then
        return { success = false, message = "Please enter a code.", reward = nil }
    end

    local normalized = normalizeCode(inputCode)

    -- Check code exists
    local definition = mgr.codeDefinitions[normalized]
    if not definition then
        return { success = false, message = "Invalid code.", reward = nil }
    end

    -- Check expiry
    if definition.expiresAt and mgr.clock() >= definition.expiresAt then
        return { success = false, message = "This code has expired.", reward = nil }
    end

    -- Check max redemptions
    if definition.maxRedemptions then
        local count = mgr.globalRedemptionCounts[normalized] or 0
        if count >= definition.maxRedemptions then
            return { success = false, message = "This code has reached its redemption limit.", reward = nil }
        end
    end

    -- Check if player already redeemed
    if hasRedeemed(mgr, userId, normalized) then
        return { success = false, message = "You have already redeemed this code.", reward = nil }
    end

    -- All checks passed - mark as redeemed
    if not mgr.playerRedemptions[userId] then
        mgr.playerRedemptions[userId] = {}
    end
    mgr.playerRedemptions[userId][normalized] = true

    -- Increment global count
    mgr.globalRedemptionCounts[normalized] = (mgr.globalRedemptionCounts[normalized] or 0) + 1

    return {
        success = true,
        message = "Code redeemed!",
        reward = definition.reward,
    }
end

--============================================================================
-- Property: Valid code + first redemption -> success + XP awarded
-- **Validates: Requirements 2.1**
--============================================================================

print("\n=== Property: Valid code + first redemption -> success + XP awarded ===")

TestHarness.property("Valid code first redemption succeeds with correct reward", 100, function(rng)
    local currentTime = TestHarness.randomFloat(rng, 1000, 100000)
    local mgr = createCodesManager(function()
        return currentTime
    end)

    -- Create a valid code with XP reward
    local xpAmount = TestHarness.randomInt(rng, 100, 10000)
    local codeStr = "CODE" .. tostring(TestHarness.randomInt(rng, 1, 99999))

    addCode(mgr, {
        code = codeStr,
        reward = { rewardType = "xp", amount = xpAmount },
        maxRedemptions = nil,
        expiresAt = currentTime + 86400, -- expires tomorrow
    })

    local userId = TestHarness.randomInt(rng, 1, 1000000)
    loadPlayerRedemptions(mgr, userId, {})

    -- Redeem the code
    local result = redeemCode(mgr, userId, codeStr)

    if not result.success then
        return false, string.format(
            "Expected success=true for valid first redemption. Got message: %s. code=%s, userId=%d",
            result.message, codeStr, userId
        )
    end

    if not result.reward then
        return false, string.format(
            "Expected reward to be present on successful redemption. code=%s",
            codeStr
        )
    end

    if result.reward.rewardType ~= "xp" then
        return false, string.format(
            "Expected rewardType='xp', got '%s'. code=%s",
            result.reward.rewardType, codeStr
        )
    end

    if result.reward.amount ~= xpAmount then
        return false, string.format(
            "Expected reward amount=%d, got %s. code=%s",
            xpAmount, tostring(result.reward.amount), codeStr
        )
    end

    -- Verify the player is now marked as having redeemed the code
    if not hasRedeemed(mgr, userId, codeStr) then
        return false, string.format(
            "Player should be marked as having redeemed the code after success. code=%s, userId=%d",
            codeStr, userId
        )
    end

    return true, nil
end)

--============================================================================
-- Property: Same code + same player again -> rejected, unchanged
-- **Validates: Requirements 2.2**
--============================================================================

print("\n=== Property: Same code + same player again -> rejected, unchanged ===")

TestHarness.property("Same code redeemed twice by same player is rejected", 100, function(rng)
    local currentTime = TestHarness.randomFloat(rng, 1000, 100000)
    local mgr = createCodesManager(function()
        return currentTime
    end)

    local xpAmount = TestHarness.randomInt(rng, 100, 10000)
    local codeStr = "DOUBLE" .. tostring(TestHarness.randomInt(rng, 1, 99999))

    addCode(mgr, {
        code = codeStr,
        reward = { rewardType = "xp", amount = xpAmount },
        maxRedemptions = nil,
        expiresAt = currentTime + 86400,
    })

    local userId = TestHarness.randomInt(rng, 1, 1000000)
    loadPlayerRedemptions(mgr, userId, {})

    -- First redemption should succeed
    local result1 = redeemCode(mgr, userId, codeStr)
    if not result1.success then
        return false, string.format(
            "First redemption should succeed. Got message: %s. code=%s, userId=%d",
            result1.message, codeStr, userId
        )
    end

    -- Record global count after first redemption
    local countAfterFirst = mgr.globalRedemptionCounts[normalizeCode(codeStr)]

    -- Second redemption by same player should fail
    local result2 = redeemCode(mgr, userId, codeStr)
    if result2.success then
        return false, string.format(
            "Second redemption should be rejected. code=%s, userId=%d",
            codeStr, userId
        )
    end

    -- Global count should NOT have incremented
    local countAfterSecond = mgr.globalRedemptionCounts[normalizeCode(codeStr)]
    if countAfterSecond ~= countAfterFirst then
        return false, string.format(
            "Global redemption count should not change on rejected redemption. Before=%d, After=%d",
            countAfterFirst, countAfterSecond
        )
    end

    return true, nil
end)

--============================================================================
-- Property: Expired code -> rejected
-- **Validates: Requirements 2.3**
--============================================================================

print("\n=== Property: Expired code -> rejected ===")

TestHarness.property("Expired code is rejected", 100, function(rng)
    local currentTime = TestHarness.randomFloat(rng, 100000, 200000)
    local mgr = createCodesManager(function()
        return currentTime
    end)

    local xpAmount = TestHarness.randomInt(rng, 100, 5000)
    local codeStr = "EXPIRED" .. tostring(TestHarness.randomInt(rng, 1, 99999))

    -- Set expiresAt to some time before currentTime
    local expiredTime = currentTime - TestHarness.randomFloat(rng, 1, 50000)

    addCode(mgr, {
        code = codeStr,
        reward = { rewardType = "xp", amount = xpAmount },
        maxRedemptions = nil,
        expiresAt = expiredTime,
    })

    local userId = TestHarness.randomInt(rng, 1, 1000000)
    loadPlayerRedemptions(mgr, userId, {})

    -- Attempt redemption
    local result = redeemCode(mgr, userId, codeStr)

    if result.success then
        return false, string.format(
            "Expired code should be rejected. code=%s, expiresAt=%.0f, currentTime=%.0f",
            codeStr, expiredTime, currentTime
        )
    end

    -- Player should NOT be marked as having redeemed
    if hasRedeemed(mgr, userId, codeStr) then
        return false, string.format(
            "Player should not be marked as redeemed for expired code. code=%s, userId=%d",
            codeStr, userId
        )
    end

    -- Global count should remain 0
    local count = mgr.globalRedemptionCounts[normalizeCode(codeStr)]
    if count ~= 0 then
        return false, string.format(
            "Global count should be 0 for rejected expired code. Got %d. code=%s",
            count, codeStr
        )
    end

    return true, nil
end)

--============================================================================
-- Property: Max redemptions reached -> rejected
-- **Validates: Requirements 2.3**
--============================================================================

print("\n=== Property: Max redemptions reached -> rejected ===")

TestHarness.property("Code at max redemptions is rejected for new player", 100, function(rng)
    local currentTime = TestHarness.randomFloat(rng, 1000, 100000)
    local mgr = createCodesManager(function()
        return currentTime
    end)

    local xpAmount = TestHarness.randomInt(rng, 100, 5000)
    local codeStr = "LIMITED" .. tostring(TestHarness.randomInt(rng, 1, 99999))
    local maxRedemptions = TestHarness.randomInt(rng, 1, 50)

    addCode(mgr, {
        code = codeStr,
        reward = { rewardType = "xp", amount = xpAmount },
        maxRedemptions = maxRedemptions,
        expiresAt = currentTime + 86400,
    })

    -- Simulate maxRedemptions players having already redeemed
    for i = 1, maxRedemptions do
        local prevUserId = 1000000 + i
        loadPlayerRedemptions(mgr, prevUserId, {})
        local prevResult = redeemCode(mgr, prevUserId, codeStr)
        if not prevResult.success then
            return false, string.format(
                "Pre-fill redemption %d/%d should succeed. Got: %s",
                i, maxRedemptions, prevResult.message
            )
        end
    end

    -- Now try with a new player - should be rejected
    local newUserId = TestHarness.randomInt(rng, 2000000, 3000000)
    loadPlayerRedemptions(mgr, newUserId, {})

    local result = redeemCode(mgr, newUserId, codeStr)

    if result.success then
        return false, string.format(
            "Code at max redemptions (%d) should be rejected. code=%s, userId=%d",
            maxRedemptions, codeStr, newUserId
        )
    end

    -- Player should NOT be marked as having redeemed
    if hasRedeemed(mgr, newUserId, codeStr) then
        return false, string.format(
            "Player should not be marked as redeemed when max reached. code=%s, userId=%d",
            codeStr, newUserId
        )
    end

    return true, nil
end)

--============================================================================
-- Property: Invalid code string -> rejected
-- **Validates: Requirements 2.1**
--============================================================================

print("\n=== Property: Invalid code string -> rejected ===")

TestHarness.property("Non-existent code string is rejected", 100, function(rng)
    local currentTime = TestHarness.randomFloat(rng, 1000, 100000)
    local mgr = createCodesManager(function()
        return currentTime
    end)

    -- Add a real code so the system isn't empty
    addCode(mgr, {
        code = "REALCODE",
        reward = { rewardType = "xp", amount = 500 },
        maxRedemptions = nil,
        expiresAt = currentTime + 86400,
    })

    local userId = TestHarness.randomInt(rng, 1, 1000000)
    loadPlayerRedemptions(mgr, userId, {})

    -- Generate a random string that doesn't match any registered code
    local invalidCode = "FAKE" .. TestHarness.randomString(rng, 3, 10)

    local result = redeemCode(mgr, userId, invalidCode)

    if result.success then
        return false, string.format(
            "Invalid code should be rejected. code=%s, userId=%d",
            invalidCode, userId
        )
    end

    -- Verify no state change occurred
    if hasRedeemed(mgr, userId, invalidCode) then
        return false, string.format(
            "Player should not be marked as redeemed for invalid code. code=%s",
            invalidCode
        )
    end

    return true, nil
end)

TestHarness.property("Empty string code is rejected", 100, function(rng)
    local currentTime = TestHarness.randomFloat(rng, 1000, 100000)
    local mgr = createCodesManager(function()
        return currentTime
    end)

    addCode(mgr, {
        code = "VALIDCODE",
        reward = { rewardType = "xp", amount = 500 },
        maxRedemptions = nil,
        expiresAt = currentTime + 86400,
    })

    local userId = TestHarness.randomInt(rng, 1, 1000000)
    loadPlayerRedemptions(mgr, userId, {})

    -- Try empty string
    local result = redeemCode(mgr, userId, "")

    if result.success then
        return false, string.format(
            "Empty string code should be rejected. userId=%d",
            userId
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
