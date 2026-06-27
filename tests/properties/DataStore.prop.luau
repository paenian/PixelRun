--!strict
--[[
    DataStore.prop.luau - Property-based tests for DataStore serialization

    Feature: pixel-run-obby
    Property 14: Player Profile Serialization Round-Trip

    Validates: Requirements 11.1

    Since DataStoreManager uses Roblox DataStoreService, we inline the pure
    serialization/deserialization logic for Lune compatibility.
    The DataStore stores PlayerProfile as a plain Luau table (JSON-compatible),
    so serialize = identity conversion to table, deserialize = type-cast back.
]]

local TestHarness = require("../TestHarness")

--============================================================================
-- Inlined Types
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

--============================================================================
-- Inlined Serialization Logic (mirrors DataStoreManager storage format)
--============================================================================

--- Serializes a PlayerProfile into the DataStore-compatible table format.
--- DataStoreService stores Luau tables as JSON, so we produce a plain table
--- matching the PlayerProfile structure with all fields explicitly set.
local function serialize(profile: PlayerProfile): {[string]: any}
    -- Build completions as a plain table (packId -> array of numbers)
    local completionsTable: {[string]: {number}} = {}
    for packId, levels in profile.completions do
        local levelsCopy: {number} = {}
        for _, level in levels do
            table.insert(levelsCopy, level)
        end
        completionsTable[packId] = levelsCopy
    end

    -- Build achievements as a plain array
    local achievementsCopy: {string} = {}
    for _, ach in profile.achievements do
        table.insert(achievementsCopy, ach)
    end

    return {
        version = profile.version,
        xp = profile.xp,
        powerUps = {
            higherJump = profile.powerUps.higherJump,
            doubleJump = profile.powerUps.doubleJump,
            fasterSpeed = profile.powerUps.fasterSpeed,
        },
        completions = completionsTable,
        achievements = achievementsCopy,
        highestLevel = profile.highestLevel,
        totalBlocksRun = profile.totalBlocksRun,
    }
end

--- Deserializes a DataStore table back into a PlayerProfile.
--- This mirrors what DataStoreManager does when loading from GetAsync().
local function deserialize(data: {[string]: any}): PlayerProfile
    -- Extract powerUps with defaults for safety
    local powerUpsData = data.powerUps or {}

    -- Extract completions
    local completions: { [string]: {number} } = {}
    local completionsData = data.completions or {}
    for packId, levels in completionsData :: any do
        local levelsList: {number} = {}
        for _, level in levels :: any do
            table.insert(levelsList, level)
        end
        completions[packId] = levelsList
    end

    -- Extract achievements
    local achievements: {string} = {}
    local achievementsData = data.achievements or {}
    for _, ach in achievementsData :: any do
        table.insert(achievements, ach)
    end

    return {
        version = data.version or 1,
        xp = data.xp or 0,
        powerUps = {
            higherJump = powerUpsData.higherJump or 0,
            doubleJump = powerUpsData.doubleJump or 0,
            fasterSpeed = powerUpsData.fasterSpeed or 0,
        },
        completions = completions,
        achievements = achievements,
        highestLevel = data.highestLevel or 0,
        totalBlocksRun = data.totalBlocksRun or 0,
    }
end

--============================================================================
-- Test Helpers
--============================================================================

local PACK_IDS = {"TetrisPack", "SpacePack", "OceanPack", "JunglePack", "DesertPack"}

--- Generate a random PlayerProfile using the test harness RNG.
local function generateRandomProfile(rng: any): PlayerProfile
    -- Random XP (0 to 500000)
    local xp = TestHarness.randomInt(rng, 0, 500000)

    -- Random power-up tiers
    local higherJump = TestHarness.randomInt(rng, 0, 3)
    local doubleJump = TestHarness.randomInt(rng, 0, 1)
    local fasterSpeed = TestHarness.randomInt(rng, 0, 3)

    -- Random completions (0 to 3 packs with random levels)
    local completions: { [string]: {number} } = {}
    local numPacks = TestHarness.randomInt(rng, 0, 3)
    for i = 1, numPacks do
        local packId = PACK_IDS[TestHarness.randomInt(rng, 1, #PACK_IDS)]
        local numLevels = TestHarness.randomInt(rng, 0, 10)
        local levels: {number} = {}
        local available = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
        for _ = 1, numLevels do
            if #available == 0 then break end
            local idx = TestHarness.randomInt(rng, 1, #available)
            table.insert(levels, available[idx])
            table.remove(available, idx)
        end
        -- Sort levels for deterministic comparison
        table.sort(levels)
        completions[packId] = levels
    end

    -- Random achievements (0 to 5)
    local achievements: {string} = {}
    local numAchievements = TestHarness.randomInt(rng, 0, 5)
    for _ = 1, numAchievements do
        local achName = "ach_" .. TestHarness.randomString(rng, 4, 10)
        table.insert(achievements, achName)
    end

    -- Random stats
    local highestLevel = TestHarness.randomInt(rng, 0, 100)
    local totalBlocksRun = TestHarness.randomInt(rng, 0, 1000000)

    return {
        version = 1,
        xp = xp,
        powerUps = {
            higherJump = higherJump,
            doubleJump = doubleJump,
            fasterSpeed = fasterSpeed,
        },
        completions = completions,
        achievements = achievements,
        highestLevel = highestLevel,
        totalBlocksRun = totalBlocksRun,
    }
end

--- Deep comparison of two PlayerProfiles. Returns (true, nil) if equal,
--- or (false, description) if they differ.
local function profilesEqual(a: PlayerProfile, b: PlayerProfile): (boolean, string?)
    -- Version
    if a.version ~= b.version then
        return false, string.format("version mismatch: %d vs %d", a.version, b.version)
    end

    -- XP
    if a.xp ~= b.xp then
        return false, string.format("xp mismatch: %d vs %d", a.xp, b.xp)
    end

    -- PowerUps
    if a.powerUps.higherJump ~= b.powerUps.higherJump then
        return false, string.format("powerUps.higherJump mismatch: %d vs %d",
            a.powerUps.higherJump, b.powerUps.higherJump)
    end
    if a.powerUps.doubleJump ~= b.powerUps.doubleJump then
        return false, string.format("powerUps.doubleJump mismatch: %d vs %d",
            a.powerUps.doubleJump, b.powerUps.doubleJump)
    end
    if a.powerUps.fasterSpeed ~= b.powerUps.fasterSpeed then
        return false, string.format("powerUps.fasterSpeed mismatch: %d vs %d",
            a.powerUps.fasterSpeed, b.powerUps.fasterSpeed)
    end

    -- Achievements (order-preserving comparison)
    if #a.achievements ~= #b.achievements then
        return false, string.format("achievements length mismatch: %d vs %d",
            #a.achievements, #b.achievements)
    end
    for i, ach in a.achievements do
        if b.achievements[i] ~= ach then
            return false, string.format("achievements[%d] mismatch: '%s' vs '%s'",
                i, ach, b.achievements[i] or "nil")
        end
    end

    -- HighestLevel
    if a.highestLevel ~= b.highestLevel then
        return false, string.format("highestLevel mismatch: %d vs %d",
            a.highestLevel, b.highestLevel)
    end

    -- TotalBlocksRun
    if a.totalBlocksRun ~= b.totalBlocksRun then
        return false, string.format("totalBlocksRun mismatch: %d vs %d",
            a.totalBlocksRun, b.totalBlocksRun)
    end

    -- Completions (compare pack by pack)
    -- Count packs in each
    local aPackCount = 0
    local bPackCount = 0
    for _ in a.completions do aPackCount += 1 end
    for _ in b.completions do bPackCount += 1 end
    if aPackCount ~= bPackCount then
        return false, string.format("completions pack count mismatch: %d vs %d",
            aPackCount, bPackCount)
    end

    for packId, aLevels in a.completions do
        local bLevels = b.completions[packId]
        if not bLevels then
            return false, string.format("completions missing pack: '%s'", packId)
        end
        if #aLevels ~= #bLevels then
            return false, string.format("completions[%s] length mismatch: %d vs %d",
                packId, #aLevels, #bLevels)
        end
        -- Sort both for comparison (serialization preserves insertion order)
        local aSorted = table.clone(aLevels)
        local bSorted = table.clone(bLevels)
        table.sort(aSorted)
        table.sort(bSorted)
        for i, level in aSorted do
            if bSorted[i] ~= level then
                return false, string.format("completions[%s][%d] mismatch: %d vs %d",
                    packId, i, level, bSorted[i] or -1)
            end
        end
    end

    return true, nil
end

--============================================================================
-- Property 14: Player Profile Serialization Round-Trip
-- **Validates: Requirements 11.1**
--
-- For any valid PlayerProfile, serializing it to DataStore-compatible format
-- and deserializing it back should produce a profile identical to the original
-- (all fields preserved: XP, powerUps, completions, achievements, version).
--============================================================================

TestHarness.property("Property 14: Player Profile Serialization Round-Trip", 150, function(rng)
    -- Generate a random player profile
    local original = generateRandomProfile(rng)

    -- Serialize to DataStore format
    local serialized = serialize(original)

    -- Deserialize back to PlayerProfile
    local deserialized = deserialize(serialized)

    -- Verify all fields match
    local equal, mismatch = profilesEqual(original, deserialized)
    if not equal then
        return false, string.format(
            "Round-trip failed: %s (xp=%d, achievements=%d, packs=%s)",
            mismatch or "unknown",
            original.xp,
            #original.achievements,
            tostring(next(original.completions) ~= nil)
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
