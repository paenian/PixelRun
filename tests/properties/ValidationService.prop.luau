--!strict
--[[
    ValidationService.prop.luau - Property-based tests for ValidationService

    Feature: pixel-run-obby
    Property 1: Pack Unlock Sequential Logic
    Property 10: Required Power-Ups Gate Obstacles
    Property 18: Server Rejects Invalid State Changes

    Validates: Requirements 2.6, 7.8, 13.3, 13.5

    Since ValidationService uses Roblox services (game:GetService, DataStoreManager,
    PackRegistry), we inline the pure logic for Lune compatibility.
]]

local TestHarness = require("../TestHarness")

--============================================================================
-- Inlined Types (from src/shared/Types.luau)
--============================================================================

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

type LevelDifficulty = {
    obstacleDensity: number,
    maxHeight: number,
    gapWidth: number,
    voidLength: number,
    hasTouchKill: boolean,
    requiredPowerUps: {string}?,
}

type PowerUpDefinition = {
    id: string,
    name: string,
    maxTier: number,
    costs: {number},
    multipliers: {number},
}

--============================================================================
-- Inlined Constants
--============================================================================

local LEVELS_PER_PACK = 10

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
-- Inlined Pure Logic: isPackUnlocked (mirrors ValidationService.isPackUnlocked)
--============================================================================

--- Checks if a pack is unlocked for a player based on sequential unlock logic.
--- Pack at index 1 in orderedPacks is always unlocked.
--- Pack at index N (N>1) requires all 10 levels of pack N-1 completed.
local function isPackUnlocked(playerData: PlayerProfile, packId: string, orderedPacks: {string}): boolean
    -- Find the index of this pack in the ordered list
    local packIndex = 0
    for i, id in orderedPacks do
        if id == packId then
            packIndex = i
            break
        end
    end

    -- If pack not found in the ordered list, treat as not unlocked
    if packIndex == 0 then
        return false
    end

    -- First pack is always unlocked
    if packIndex == 1 then
        return true
    end

    -- Pack N is unlocked if player completed all 10 levels of pack N-1
    local previousPackId = orderedPacks[packIndex - 1]
    local packCompletions = playerData.completions[previousPackId]

    if not packCompletions then
        return false
    end

    return #packCompletions >= LEVELS_PER_PACK
end

--============================================================================
-- Inlined Pure Logic: Power-Up Gating (mirrors ValidationService validation)
--============================================================================

--- Checks if a player has the required power-ups to attempt a level difficulty.
--- Returns true if player meets all requirements, false otherwise.
local function hasRequiredPowerUps(playerData: PlayerProfile, requiredPowerUps: {string}): boolean
    for _, requiredId in requiredPowerUps do
        -- Check if the player owns at least tier 1 of the required power-up
        if requiredId == "higherJump" then
            if playerData.powerUps.higherJump < 1 then
                return false
            end
        elseif requiredId == "doubleJump" then
            if playerData.powerUps.doubleJump < 1 then
                return false
            end
        elseif requiredId == "fasterSpeed" then
            if playerData.powerUps.fasterSpeed < 1 then
                return false
            end
        else
            -- Unknown power-up requirement, player cannot satisfy
            return false
        end
    end
    return true
end

--============================================================================
-- Inlined Pure Logic: Purchase Validation (mirrors ValidationService + PowerUpManager)
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
    -- Deep copy completions
    local completionsCopy: { [string]: {number} } = {}
    for packId, levels in p.completions do
        local levelsCopy: {number} = {}
        for _, lvl in levels do
            table.insert(levelsCopy, lvl)
        end
        completionsCopy[packId] = levelsCopy
    end

    -- Deep copy achievements
    local achievementsCopy: {string} = {}
    for _, a in p.achievements do
        table.insert(achievementsCopy, a)
    end

    return {
        version = p.version,
        xp = p.xp,
        powerUps = {
            higherJump = p.powerUps.higherJump,
            doubleJump = p.powerUps.doubleJump,
            fasterSpeed = p.powerUps.fasterSpeed,
        },
        completions = completionsCopy,
        achievements = achievementsCopy,
        highestLevel = p.highestLevel,
        totalBlocksRun = p.totalBlocksRun,
    }
end

--- Generate a list of all 10 level numbers {1,2,3,...,10}
local function allTenLevels(): {number}
    local levels: {number} = {}
    for i = 1, 10 do
        table.insert(levels, i)
    end
    return levels
end

--============================================================================
-- Property 1: Pack Unlock Sequential Logic
-- **Validates: Requirements 2.6**
--
-- For any pack at index 1: always unlocked regardless of completions.
-- For pack N (N>1): unlocked iff completions[pack_N-1] has all 10 levels.
--============================================================================

print("\n=== Property 1: Pack Unlock Sequential Logic ===")

TestHarness.property("Pack 1 is always unlocked regardless of completions", 100, function(rng)
    -- Generate a random ordered pack list (2-10 packs)
    local numPacks = TestHarness.randomInt(rng, 2, 10)
    local orderedPacks: {string} = {}
    for i = 1, numPacks do
        table.insert(orderedPacks, "pack_" .. tostring(i))
    end

    -- Create a profile with random completions (or none)
    local profile = createDefaultProfile()
    -- Randomly add some completions for various packs
    for _, packId in orderedPacks do
        if TestHarness.randomBool(rng) then
            local numLevels = TestHarness.randomInt(rng, 0, 10)
            local levels: {number} = {}
            for j = 1, numLevels do
                table.insert(levels, j)
            end
            profile.completions[packId] = levels
        end
    end

    -- Pack 1 (index 1) should always be unlocked
    local firstPack = orderedPacks[1]
    local unlocked = isPackUnlocked(profile, firstPack, orderedPacks)
    if not unlocked then
        return false, string.format(
            "Pack 1 ('%s') should always be unlocked, but isPackUnlocked returned false",
            firstPack
        )
    end

    return true, nil
end)

TestHarness.property("Pack N (N>1) unlocked iff pack N-1 fully complete", 150, function(rng)
    -- Generate a random ordered pack list (3-8 packs)
    local numPacks = TestHarness.randomInt(rng, 3, 8)
    local orderedPacks: {string} = {}
    for i = 1, numPacks do
        table.insert(orderedPacks, "pack_" .. tostring(i))
    end

    -- Pick a random pack index > 1 to test
    local targetIndex = TestHarness.randomInt(rng, 2, numPacks)
    local targetPack = orderedPacks[targetIndex]
    local previousPack = orderedPacks[targetIndex - 1]

    -- Create profile
    local profile = createDefaultProfile()

    -- Decide whether the previous pack is fully complete
    local previousComplete = TestHarness.randomBool(rng)

    if previousComplete then
        -- Set previous pack completions to all 10 levels
        profile.completions[previousPack] = allTenLevels()
    else
        -- Set previous pack completions to fewer than 10 levels (0-9)
        local numLevels = TestHarness.randomInt(rng, 0, 9)
        if numLevels > 0 then
            local levels: {number} = {}
            for j = 1, numLevels do
                table.insert(levels, j)
            end
            profile.completions[previousPack] = levels
        end
        -- If numLevels == 0, leave completions empty for that pack
    end

    -- Check the target pack unlock status
    local unlocked = isPackUnlocked(profile, targetPack, orderedPacks)

    if previousComplete and not unlocked then
        return false, string.format(
            "Pack '%s' (index %d) should be unlocked because '%s' is fully complete (10 levels), but got false",
            targetPack, targetIndex, previousPack
        )
    end

    if not previousComplete and unlocked then
        local completionCount = 0
        if profile.completions[previousPack] then
            completionCount = #profile.completions[previousPack]
        end
        return false, string.format(
            "Pack '%s' (index %d) should be LOCKED because '%s' only has %d/10 completions, but got true",
            targetPack, targetIndex, previousPack, completionCount
        )
    end

    return true, nil
end)

--============================================================================
-- Property 10: Required Power-Ups Gate Obstacles
-- **Validates: Requirements 7.8**
--
-- If a level difficulty has requiredPowerUps specified, a player without
-- those power-ups should be rejected (hasRequiredPowerUps returns false).
--============================================================================

print("\n=== Property 10: Required Power-Ups Gate Obstacles ===")

TestHarness.property("Players without required power-ups are rejected", 150, function(rng)
    -- Pick a random set of required power-ups (1-3 requirements)
    local numRequired = TestHarness.randomInt(rng, 1, 3)
    local requiredPowerUps: {string} = {}
    local usedIds: {[string]: boolean} = {}

    for _ = 1, numRequired do
        local id = TestHarness.randomChoice(rng, POWER_UP_IDS) :: string
        if not usedIds[id] then
            table.insert(requiredPowerUps, id)
            usedIds[id] = true
        end
    end

    -- Create a player profile that does NOT have any of the required power-ups
    local profile = createDefaultProfile()
    -- Ensure all required power-ups are at tier 0 (default)
    -- The profile already has all tiers at 0 by default

    -- Verify player is rejected
    local hasAll = hasRequiredPowerUps(profile, requiredPowerUps)
    if hasAll then
        return false, string.format(
            "Player with no power-ups should be rejected for requirements: {%s}",
            table.concat(requiredPowerUps, ", ")
        )
    end

    return true, nil
end)

TestHarness.property("Players with all required power-ups are accepted", 150, function(rng)
    -- Pick a random set of required power-ups (1-3 requirements)
    local numRequired = TestHarness.randomInt(rng, 1, 3)
    local requiredPowerUps: {string} = {}
    local usedIds: {[string]: boolean} = {}

    for _ = 1, numRequired do
        local id = TestHarness.randomChoice(rng, POWER_UP_IDS) :: string
        if not usedIds[id] then
            table.insert(requiredPowerUps, id)
            usedIds[id] = true
        end
    end

    -- Create a player profile that HAS all required power-ups at tier >= 1
    local profile = createDefaultProfile()
    for _, requiredId in requiredPowerUps do
        if requiredId == "higherJump" then
            profile.powerUps.higherJump = TestHarness.randomInt(rng, 1, 3)
        elseif requiredId == "doubleJump" then
            profile.powerUps.doubleJump = 1
        elseif requiredId == "fasterSpeed" then
            profile.powerUps.fasterSpeed = TestHarness.randomInt(rng, 1, 3)
        end
    end

    -- Verify player is accepted
    local hasAll = hasRequiredPowerUps(profile, requiredPowerUps)
    if not hasAll then
        return false, string.format(
            "Player with all required power-ups should be accepted. Requirements: {%s}, Profile: hj=%d, dj=%d, fs=%d",
            table.concat(requiredPowerUps, ", "),
            profile.powerUps.higherJump,
            profile.powerUps.doubleJump,
            profile.powerUps.fasterSpeed
        )
    end

    return true, nil
end)

TestHarness.property("Missing even one required power-up causes rejection", 150, function(rng)
    -- Use at least 2 required power-ups so we can satisfy some but not all
    local allIds = {"higherJump", "doubleJump", "fasterSpeed"}
    -- Shuffle and take 2-3
    local numRequired = TestHarness.randomInt(rng, 2, 3)
    local requiredPowerUps: {string} = {}
    local available = {table.unpack(allIds)}

    for _ = 1, math.min(numRequired, #available) do
        local idx = TestHarness.randomInt(rng, 1, #available)
        table.insert(requiredPowerUps, available[idx])
        table.remove(available, idx)
    end

    -- Create a profile that has all BUT one of the required power-ups
    local profile = createDefaultProfile()
    -- Pick one to leave at 0
    local missingIdx = TestHarness.randomInt(rng, 1, #requiredPowerUps)

    for i, requiredId in requiredPowerUps do
        if i ~= missingIdx then
            -- Give the player this power-up
            if requiredId == "higherJump" then
                profile.powerUps.higherJump = TestHarness.randomInt(rng, 1, 3)
            elseif requiredId == "doubleJump" then
                profile.powerUps.doubleJump = 1
            elseif requiredId == "fasterSpeed" then
                profile.powerUps.fasterSpeed = TestHarness.randomInt(rng, 1, 3)
            end
        end
        -- else: leave at 0 (missing)
    end

    -- Verify player is rejected
    local hasAll = hasRequiredPowerUps(profile, requiredPowerUps)
    if hasAll then
        local missingId = requiredPowerUps[missingIdx]
        return false, string.format(
            "Player missing '%s' should be rejected. Requirements: {%s}, Profile: hj=%d, dj=%d, fs=%d",
            missingId,
            table.concat(requiredPowerUps, ", "),
            profile.powerUps.higherJump,
            profile.powerUps.doubleJump,
            profile.powerUps.fasterSpeed
        )
    end

    return true, nil
end)

--============================================================================
-- Property 18: Server Rejects Invalid State Changes
-- **Validates: Requirements 13.3, 13.5**
--
-- Invalid requests leave state unchanged:
-- - Purchase with insufficient XP → profile unchanged
-- - Purchase with wrong tier sequence → profile unchanged
--============================================================================

print("\n=== Property 18: Server Rejects Invalid State Changes ===")

TestHarness.property("Purchase with insufficient XP leaves profile unchanged", 150, function(rng)
    -- Pick a random power-up
    local powerUpId = TestHarness.randomChoice(rng, POWER_UP_IDS) :: string
    local def = findDefinition(powerUpId) :: PowerUpDefinition

    -- Pick a random valid tier to attempt
    local tier = TestHarness.randomInt(rng, 1, def.maxTier)

    -- Create a profile with the prerequisite tier but insufficient XP
    local profile = createDefaultProfile()
    local cost = def.costs[tier]

    -- Set XP to be strictly less than cost
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
    local allowed, _ = canPurchase(profile, powerUpId, tier)
    if allowed then
        return false, string.format(
            "canPurchase should reject insufficient XP: id=%s, tier=%d, xp=%d, cost=%d",
            powerUpId, tier, profile.xp, cost
        )
    end

    -- Verify profile is completely unchanged
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

TestHarness.property("Purchase with wrong tier sequence leaves profile unchanged", 150, function(rng)
    -- Only test power-ups with multiple tiers
    local multiTierIds = {"higherJump", "fasterSpeed"}
    local powerUpId = TestHarness.randomChoice(rng, multiTierIds) :: string
    local def = findDefinition(powerUpId) :: PowerUpDefinition

    -- Pick a tier >= 2 to attempt skipping to
    local targetTier = TestHarness.randomInt(rng, 2, def.maxTier)

    -- Create a profile with plenty of XP but without the prerequisite tier
    local profile = createDefaultProfile()
    profile.xp = 100000 -- More than enough

    -- Set current tier to be < targetTier - 1 (so prerequisite is NOT met)
    local maxAllowedTier = targetTier - 2
    local currentTier = TestHarness.randomInt(rng, 0, math.max(0, maxAllowedTier))

    if powerUpId == "higherJump" then
        profile.powerUps.higherJump = currentTier
    elseif powerUpId == "fasterSpeed" then
        profile.powerUps.fasterSpeed = currentTier
    end

    -- Snapshot before
    local before = cloneProfile(profile)

    -- canPurchase should return false
    local allowed, _ = canPurchase(profile, powerUpId, targetTier)
    if allowed then
        return false, string.format(
            "canPurchase should reject wrong tier sequence: id=%s, currentTier=%d, targetTier=%d",
            powerUpId, currentTier, targetTier
        )
    end

    -- Verify profile is completely unchanged
    if profile.xp ~= before.xp then
        return false, string.format(
            "Profile XP changed after tier-sequence rejection: before=%d, after=%d",
            before.xp, profile.xp
        )
    end
    if getPlayerTier(profile, powerUpId) ~= getPlayerTier(before, powerUpId) then
        return false, string.format(
            "Profile tier changed after tier-sequence rejection: id=%s, before=%d, after=%d",
            powerUpId, getPlayerTier(before, powerUpId), getPlayerTier(profile, powerUpId)
        )
    end

    -- Also verify other power-up tiers are unchanged
    for _, otherId in POWER_UP_IDS do
        if getPlayerTier(profile, otherId) ~= getPlayerTier(before, otherId) then
            return false, string.format(
                "Unrelated power-up tier changed: id=%s",
                otherId
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
