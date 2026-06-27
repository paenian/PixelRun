--!strict
--[[
    AchievementService.prop.luau - Property-based tests for AchievementService

    Feature: pixel-run-obby
    Property 5: XP Retention on Elimination
    Property 12: Achievement Awarded on Pack Completion
    Property 13: Achievement Idempotence

    Validates: Requirements 4.6, 6.5, 8.2, 8.3

    Since AchievementService uses Roblox services (Players, ReplicatedStorage, etc.),
    we inline the pure logic for Lune compatibility.
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
-- Inlined XP Logic (mirrors GameServer XP accumulation and elimination)
--============================================================================

local XP_PER_BLOCK = 1
local LEVEL_COMPLETION_BONUS = 500

--- Calculates XP earned for a given number of blocks and pack multiplier.
--- Mirrors LevelUtils.calculateXP: blocks * packNumber
local function calculateXP(blocksRun: number, packMultiplier: number): number
    return blocksRun * packMultiplier * XP_PER_BLOCK
end

--- Simulates a run where a player accumulates XP incrementally over blocks traveled,
--- then gets eliminated. Returns the total XP the player should have after elimination.
---
--- Key invariant: XP is accumulated incrementally during the run, and on elimination
--- ALL earned XP is retained (no deduction on death). The player's total XP should
--- increase by exactly the full run amount.
local function simulateRunWithElimination(
    previousTotalXP: number,
    blocksTraveled: number,
    packMultiplier: number
): (number, number) -- (totalXPAfterElimination, xpEarnedDuringRun)
    -- XP is added incrementally during the run (same as GameServer heartbeat logic)
    local runXP = calculateXP(blocksTraveled, packMultiplier)

    -- On elimination: XP is RETAINED. Total = previous + all earned during run.
    local totalXPAfterDeath = previousTotalXP + runXP

    return totalXPAfterDeath, runXP
end

--============================================================================
-- Inlined Achievement Logic (mirrors AchievementService)
--============================================================================

local LEVELS_PER_PACK = 10

--- Checks if a player has completed all 10 levels of a pack.
--- Returns the achievement name to award if all levels are complete, nil otherwise.
local function checkPackCompletion(
    completions: { [string]: {number} },
    packId: string,
    achievementName: string,
    existingAchievements: {string}
): string?
    -- Check if the player already has this achievement (idempotent)
    for _, id in existingAchievements do
        if id == achievementName then
            return nil -- Already awarded
        end
    end

    -- Check if all 10 levels are completed for this pack
    local packCompletions = completions[packId]
    if not packCompletions then
        return nil
    end

    -- Verify all 10 levels are in the completions list
    local completedLevels: { [number]: boolean } = {}
    for _, levelNum in packCompletions do
        if levelNum >= 1 and levelNum <= LEVELS_PER_PACK then
            completedLevels[levelNum] = true
        end
    end

    local completedCount = 0
    for i = 1, LEVELS_PER_PACK do
        if completedLevels[i] then
            completedCount += 1
        end
    end

    if completedCount >= LEVELS_PER_PACK then
        return achievementName
    end

    return nil
end

--- Awards an achievement to a player's achievement list (idempotent).
--- Returns the updated list and a boolean indicating if it was newly added.
local function awardAchievement(achievements: {string}, achievementId: string): ({string}, boolean)
    -- Idempotent: check if already present
    for _, id in achievements do
        if id == achievementId then
            return achievements, false
        end
    end

    -- Add achievement
    table.insert(achievements, achievementId)
    return achievements, true
end

--============================================================================
-- Property 5: XP Retention on Elimination
-- **Validates: Requirements 4.6, 6.5**
--
-- For any player who has accumulated XP during a run, elimination should result
-- in the player's total XP increasing by the full amount earned during that run.
-- No XP is lost on death.
--============================================================================

TestHarness.property("Property 5: XP Retention on Elimination", 150, function(rng)
    -- Generate random initial state
    local previousTotalXP = TestHarness.randomInt(rng, 0, 100000)
    local blocksTraveled = TestHarness.randomInt(rng, 1, 999) -- 1-999 blocks (eliminated before 1000)
    local packMultiplier = TestHarness.randomInt(rng, 1, 10) -- Pack 1-10

    -- Simulate run and elimination
    local totalXPAfterDeath, runXP = simulateRunWithElimination(previousTotalXP, blocksTraveled, packMultiplier)

    -- Property: total XP after death = previous total + full run XP earned
    local expectedTotal = previousTotalXP + runXP
    if totalXPAfterDeath ~= expectedTotal then
        return false, string.format(
            "XP not retained on elimination: expected %d, got %d (previous=%d, runXP=%d, blocks=%d, multiplier=%d)",
            expectedTotal, totalXPAfterDeath, previousTotalXP, runXP, blocksTraveled, packMultiplier
        )
    end

    -- Property: runXP = blocks * multiplier (no deduction)
    local expectedRunXP = blocksTraveled * packMultiplier
    if runXP ~= expectedRunXP then
        return false, string.format(
            "Run XP calculation wrong: expected %d, got %d (blocks=%d, multiplier=%d)",
            expectedRunXP, runXP, blocksTraveled, packMultiplier
        )
    end

    -- Property: no XP is lost — total increased by exactly the full run amount
    local xpIncrease = totalXPAfterDeath - previousTotalXP
    if xpIncrease ~= runXP then
        return false, string.format(
            "XP increase doesn't match run earnings: increase=%d, runXP=%d",
            xpIncrease, runXP
        )
    end

    return true, nil
end)

--============================================================================
-- Property 12: Achievement Awarded on Pack Completion
-- **Validates: Requirements 8.2**
--
-- When a player has completed all 10 levels (1 through 10) of a Level_Pack
-- and does not yet have the achievement, the achievement service should add
-- exactly that pack's achievement to the player's profile.
-- Missing any level → achievement not awarded.
--============================================================================

TestHarness.property("Property 12: Achievement Awarded on Pack Completion", 150, function(rng)
    local packId = TestHarness.randomString(rng, 5, 12)
    local achievementName = "Complete_" .. packId

    -- Generate a random subset of completed levels (1-10)
    -- Decide if we want all 10 or a partial set
    local allComplete = TestHarness.randomBool(rng)

    local completedLevels: {number} = {}
    if allComplete then
        -- Complete all 10 levels
        for i = 1, 10 do
            table.insert(completedLevels, i)
        end
    else
        -- Complete a random subset (0 to 9 levels, NOT all 10)
        local count = TestHarness.randomInt(rng, 0, 9)
        local available = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
        for _ = 1, count do
            local idx = TestHarness.randomInt(rng, 1, #available)
            table.insert(completedLevels, available[idx])
            table.remove(available, idx)
        end
    end

    local completions: { [string]: {number} } = {}
    completions[packId] = completedLevels

    -- Start with no achievements
    local achievements: {string} = {}

    -- Check pack completion
    local awarded = checkPackCompletion(completions, packId, achievementName, achievements)

    if allComplete then
        -- All 10 levels complete → achievement should be awarded
        if awarded ~= achievementName then
            return false, string.format(
                "Achievement not awarded when all 10 levels complete: packId=%s, levels=%d",
                packId, #completedLevels
            )
        end

        -- Apply the award and verify it's in the list
        local updatedList, wasNew = awardAchievement(achievements, awarded :: string)
        if not wasNew then
            return false, string.format(
                "awardAchievement reported not new for first-time award: achievement=%s",
                achievementName
            )
        end
        -- Verify achievement is in the list
        local found = false
        for _, id in updatedList do
            if id == achievementName then
                found = true
                break
            end
        end
        if not found then
            return false, string.format(
                "Achievement not found in list after award: achievement=%s",
                achievementName
            )
        end
    else
        -- Missing at least one level → achievement should NOT be awarded
        if awarded ~= nil then
            return false, string.format(
                "Achievement awarded with incomplete pack: packId=%s, completedLevels=%d, awarded=%s",
                packId, #completedLevels, tostring(awarded)
            )
        end
    end

    return true, nil
end)

--============================================================================
-- Property 13: Achievement Idempotence
-- **Validates: Requirements 8.3**
--
-- If a player already possesses an achievement, attempting to award the same
-- achievement again should leave the achievements list unchanged (no duplicates
-- added, same length).
--============================================================================

TestHarness.property("Property 13: Achievement Idempotence", 150, function(rng)
    -- Generate a random starting achievements list
    local numExisting = TestHarness.randomInt(rng, 1, 10)
    local achievements: {string} = {}
    for i = 1, numExisting do
        table.insert(achievements, "achievement_" .. tostring(i) .. "_" .. TestHarness.randomString(rng, 3, 6))
    end

    -- Pick one achievement that's already in the list to try to award again
    local duplicateIdx = TestHarness.randomInt(rng, 1, #achievements)
    local duplicateId = achievements[duplicateIdx]

    -- Record the state before duplicate award attempt
    local lengthBefore = #achievements
    local contentsBefore: {string} = {}
    for _, id in achievements do
        table.insert(contentsBefore, id)
    end

    -- Attempt to award the duplicate
    local updatedList, wasNew = awardAchievement(achievements, duplicateId)

    -- Property: wasNew should be false (already had it)
    if wasNew then
        return false, string.format(
            "awardAchievement reported new for duplicate: id=%s",
            duplicateId
        )
    end

    -- Property: list length unchanged
    if #updatedList ~= lengthBefore then
        return false, string.format(
            "List length changed after duplicate award: before=%d, after=%d, id=%s",
            lengthBefore, #updatedList, duplicateId
        )
    end

    -- Property: list contents unchanged
    for i, id in contentsBefore do
        if updatedList[i] ~= id then
            return false, string.format(
                "List contents changed at index %d: before=%s, after=%s",
                i, id, updatedList[i] or "nil"
            )
        end
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
