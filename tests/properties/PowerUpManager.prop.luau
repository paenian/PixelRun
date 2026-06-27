--!strict
--[[
    PowerUpManager.prop.luau - Property-based tests for PowerUpManager
    
    Feature: pixel-run-obby
    Property 7: Successful Purchase Updates State Correctly
    Property 8: Insufficient XP Rejects Purchase
    Property 9: Sequential Tier Enforcement
    
    Validates: Requirements 7.2, 7.3, 7.4
    
    Since PowerUpManager uses require(script.Parent.Types), we inline the
    power-up definitions and reimplement the pure validation logic for Lune testing.
]]

local TestHarness = require("../TestHarness")

--============================================================================
-- Inlined Power-Up Definitions (from Types.POWER_UP_DEFINITIONS)
--============================================================================

type PowerUpDefinition = {
    id: string,
    name: string,
    maxTier: number,
    costs: {number},
    multipliers: {number},
}

type PlayerProfile = {
    version: number,
    xp: number,
    powerUps: {
        higherJump: number,
        doubleJump: number,
        fasterSpeed: number,
    },
    completions: { [string]: {number} },
    achievements: {string},
    highestLevel: number,
    totalBlocksRun: number,
}

local POWER_UP_DEFINITIONS: {PowerUpDefinition} = {
    {
        id = "higherJump",
        name = "Higher Jump",
        maxTier = 3,
        costs = {2000, 5000, 12000},
        multipliers = {1.25, 1.5, 2.0},
    },
    {
        id = "doubleJump",
        name = "Double Jump",
        maxTier = 1,
        costs = {8000},
        multipliers = {1.0},
    },
    {
        id = "fasterSpeed",
        name = "Faster Speed",
        maxTier = 3,
        costs = {2000, 5000, 12000},
        multipliers = {1.25, 1.5, 2.0},
    },
}

--============================================================================
-- Inlined PowerUpManager Logic (mirrors src/shared/PowerUpManager.luau)
--============================================================================

local function findDefinition(powerUpId: string): PowerUpDefinition?
    for _, def in POWER_UP_DEFINITIONS do
        if def.id == powerUpId then
            return def
        end
    end
    return nil
end

local function getPlayerTier(playerData: PlayerProfile, powerUpId: string): number
    if powerUpId == "higherJump" then
        return playerData.powerUps.higherJump
    elseif powerUpId == "doubleJump" then
        return playerData.powerUps.doubleJump
    elseif powerUpId == "fasterSpeed" then
        return playerData.powerUps.fasterSpeed
    end
    return 0
end

local function canPurchase(playerData: PlayerProfile, powerUpId: string, tier: number): (boolean, string?)
    local def = findDefinition(powerUpId)
    if not def then
        return false, "Invalid power-up ID"
    end

    if tier < 1 or tier > def.maxTier then
        return false, "Invalid tier"
    end

    local currentTier = getPlayerTier(playerData, powerUpId)
    if currentTier >= tier then
        return false, "Already own this tier"
    end

    if tier > 1 and currentTier < tier - 1 then
        return false, "Must purchase previous tier first"
    end

    local cost = def.costs[tier]
    if playerData.xp < cost then
        return false, "Insufficient XP"
    end

    return true, nil
end

local function applyPurchase(playerData: PlayerProfile, powerUpId: string, tier: number): PlayerProfile
    local def = findDefinition(powerUpId)
    if not def then
        return playerData
    end

    if tier < 1 or tier > def.maxTier then
        return playerData
    end

    local cost = def.costs[tier]
    playerData.xp = playerData.xp - cost

    if powerUpId == "higherJump" then
        playerData.powerUps.higherJump = tier
    elseif powerUpId == "doubleJump" then
        playerData.powerUps.doubleJump = tier
    elseif powerUpId == "fasterSpeed" then
        playerData.powerUps.fasterSpeed = tier
    end

    return playerData
end

--============================================================================
-- Test Helpers
--============================================================================

local POWER_UP_IDS = {"higherJump", "doubleJump", "fasterSpeed"}

--- Create a fresh default player profile.
local function createDefaultProfile(): PlayerProfile
    return {
        version = 1,
        xp = 0,
        powerUps = {
            higherJump = 0,
            doubleJump = 0,
            fasterSpeed = 0,
        },
        completions = {},
        achievements = {},
        highestLevel = 0,
        totalBlocksRun = 0,
    }
end

--- Deep-copy a player profile to avoid mutation side effects in assertions.
local function cloneProfile(p: PlayerProfile): PlayerProfile
    return {
        version = p.version,
        xp = p.xp,
        powerUps = {
            higherJump = p.powerUps.higherJump,
            doubleJump = p.powerUps.doubleJump,
            fasterSpeed = p.powerUps.fasterSpeed,
        },
        completions = p.completions,
        achievements = p.achievements,
        highestLevel = p.highestLevel,
        totalBlocksRun = p.totalBlocksRun,
    }
end

--============================================================================
-- Property 7: Successful Purchase Updates State Correctly
-- **Validates: Requirements 7.2**
--
-- For any player with XP >= cost and the correct prerequisite tier,
-- applying a purchase should:
--   - Reduce XP by exactly the cost amount
--   - Increment the power-up tier by exactly 1
--============================================================================

TestHarness.property("Property 7: Successful Purchase Updates State Correctly", 150, function(rng)
    -- Pick a random power-up
    local powerUpId = TestHarness.randomChoice(rng, POWER_UP_IDS) :: string
    local def = findDefinition(powerUpId) :: PowerUpDefinition

    -- Pick a random valid tier to purchase (1 to maxTier)
    local tier = TestHarness.randomInt(rng, 1, def.maxTier)

    -- Create a profile with sufficient XP and the prerequisite tier already owned
    local profile = createDefaultProfile()
    local cost = def.costs[tier]
    -- Give enough XP (cost + random surplus)
    profile.xp = cost + TestHarness.randomInt(rng, 0, 50000)

    -- Set prerequisite tier (tier - 1)
    if powerUpId == "higherJump" then
        profile.powerUps.higherJump = tier - 1
    elseif powerUpId == "doubleJump" then
        profile.powerUps.doubleJump = tier - 1
    elseif powerUpId == "fasterSpeed" then
        profile.powerUps.fasterSpeed = tier - 1
    end

    local oldXP = profile.xp
    local oldTier = getPlayerTier(profile, powerUpId)

    -- Verify canPurchase returns true
    local allowed, errMsg = canPurchase(profile, powerUpId, tier)
    if not allowed then
        return false, string.format(
            "canPurchase returned false for valid purchase: id=%s, tier=%d, xp=%d, currentTier=%d, error=%s",
            powerUpId, tier, oldXP, oldTier, tostring(errMsg)
        )
    end

    -- Apply the purchase
    local updated = applyPurchase(profile, powerUpId, tier)

    -- Check XP decreased by exactly the cost
    local expectedXP = oldXP - cost
    if updated.xp ~= expectedXP then
        return false, string.format(
            "XP mismatch: expected %d, got %d (cost=%d, oldXP=%d, id=%s, tier=%d)",
            expectedXP, updated.xp, cost, oldXP, powerUpId, tier
        )
    end

    -- Check tier incremented by exactly 1
    local newTier = getPlayerTier(updated, powerUpId)
    if newTier ~= oldTier + 1 then
        return false, string.format(
            "Tier mismatch: expected %d, got %d (id=%s, tier=%d)",
            oldTier + 1, newTier, powerUpId, tier
        )
    end

    return true, nil
end)

--============================================================================
-- Property 8: Insufficient XP Rejects Purchase
-- **Validates: Requirements 7.3**
--
-- If XP < cost for a power-up tier, canPurchase returns false and
-- the profile remains completely unchanged.
--============================================================================

TestHarness.property("Property 8: Insufficient XP Rejects Purchase", 150, function(rng)
    -- Pick a random power-up
    local powerUpId = TestHarness.randomChoice(rng, POWER_UP_IDS) :: string
    local def = findDefinition(powerUpId) :: PowerUpDefinition

    -- Pick a random valid tier to attempt
    local tier = TestHarness.randomInt(rng, 1, def.maxTier)

    -- Create a profile with the prerequisite tier but insufficient XP
    local profile = createDefaultProfile()
    local cost = def.costs[tier]

    -- Set XP to be strictly less than cost (0 to cost-1)
    profile.xp = TestHarness.randomInt(rng, 0, math.max(0, cost - 1))

    -- Set prerequisite tier so the only rejection reason is XP
    if powerUpId == "higherJump" then
        profile.powerUps.higherJump = tier - 1
    elseif powerUpId == "doubleJump" then
        profile.powerUps.doubleJump = tier - 1
    elseif powerUpId == "fasterSpeed" then
        profile.powerUps.fasterSpeed = tier - 1
    end

    -- Snapshot the profile before the attempt
    local before = cloneProfile(profile)

    -- canPurchase should return false
    local allowed, errMsg = canPurchase(profile, powerUpId, tier)
    if allowed then
        return false, string.format(
            "canPurchase returned true with insufficient XP: id=%s, tier=%d, xp=%d, cost=%d",
            powerUpId, tier, profile.xp, cost
        )
    end

    -- Verify error message mentions insufficient XP
    if errMsg ~= "Insufficient XP" then
        return false, string.format(
            "Expected 'Insufficient XP' error, got: '%s' (id=%s, tier=%d, xp=%d, cost=%d)",
            tostring(errMsg), powerUpId, tier, profile.xp, cost
        )
    end

    -- Verify profile is unchanged
    if profile.xp ~= before.xp then
        return false, string.format(
            "Profile XP changed after rejected purchase: before=%d, after=%d",
            before.xp, profile.xp
        )
    end
    if getPlayerTier(profile, powerUpId) ~= getPlayerTier(before, powerUpId) then
        return false, string.format(
            "Profile tier changed after rejected purchase: id=%s",
            powerUpId
        )
    end

    return true, nil
end)

--============================================================================
-- Property 9: Sequential Tier Enforcement
-- **Validates: Requirements 7.4**
--
-- Attempting to purchase tier N without owning tier N-1 should be rejected
-- regardless of XP balance. Tier 1 should always be purchasable given
-- sufficient XP and no prerequisite requirement.
--============================================================================

TestHarness.property("Property 9: Sequential Tier Enforcement", 150, function(rng)
    -- Only test power-ups with multiple tiers for the "skip" case
    local multiTierIds = {"higherJump", "fasterSpeed"}
    local powerUpId = TestHarness.randomChoice(rng, multiTierIds) :: string
    local def = findDefinition(powerUpId) :: PowerUpDefinition

    -- Pick a tier >= 2 to attempt skipping to (without owning tier-1)
    local targetTier = TestHarness.randomInt(rng, 2, def.maxTier)

    -- Create a profile with plenty of XP but tier 0 (owns nothing)
    local profile = createDefaultProfile()
    profile.xp = 100000 -- More than enough for any tier

    -- Ensure current tier is 0 (or at most targetTier - 2, so prerequisite is not met)
    -- We set to a random tier that is < targetTier - 1
    local maxAllowedTier = targetTier - 2 -- This ensures currentTier < targetTier - 1
    local currentTier = TestHarness.randomInt(rng, 0, math.max(0, maxAllowedTier))

    if powerUpId == "higherJump" then
        profile.powerUps.higherJump = currentTier
    elseif powerUpId == "fasterSpeed" then
        profile.powerUps.fasterSpeed = currentTier
    end

    -- canPurchase should return false due to sequential enforcement
    local allowed, errMsg = canPurchase(profile, powerUpId, targetTier)
    if allowed then
        return false, string.format(
            "canPurchase allowed skipping tiers: id=%s, currentTier=%d, targetTier=%d, xp=%d",
            powerUpId, currentTier, targetTier, profile.xp
        )
    end

    -- Verify the error message indicates prerequisite issue
    if errMsg ~= "Must purchase previous tier first" then
        return false, string.format(
            "Expected 'Must purchase previous tier first' error, got: '%s' (id=%s, currentTier=%d, targetTier=%d)",
            tostring(errMsg), powerUpId, currentTier, targetTier
        )
    end

    -- Additionally verify that tier 1 IS purchasable with sufficient XP (no prerequisite needed)
    local freshProfile = createDefaultProfile()
    freshProfile.xp = 100000
    local tier1Allowed, tier1Err = canPurchase(freshProfile, powerUpId, 1)
    if not tier1Allowed then
        return false, string.format(
            "Tier 1 should be purchasable without prerequisites but was rejected: id=%s, error=%s",
            powerUpId, tostring(tier1Err)
        )
    end

    return true, nil
end)

--============================================================================
-- Report
--============================================================================

local allPassed = TestHarness.report()

if not allPassed then
    local process = require("@lune/process")
    process.exit(1)
end
