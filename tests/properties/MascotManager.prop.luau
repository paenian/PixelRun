--!strict
--[[
    MascotManager.prop.luau - Property-based tests for MascotManager

    Feature: pixel-run-obby
    Task 6.6: Write property tests for MascotManager

    **Validates: Requirements 6.1**

    Tests the pure logic of MascotManager: unlock checking, equip validation,
    unlock condition evaluation, and serialization round-trip via unlock/isUnlocked.
    Inlines the pure logic for Lune compatibility (no Roblox services required).
]]

local TestHarness = require("../TestHarness")

--============================================================================
-- Inlined MascotManager Logic (mirrors src/shared/MascotManager.luau)
-- Pure functions that don't depend on Roblox services.
--============================================================================

type UnlockCondition = {
    conditionType: string,
    packId: string?,
    comboStreak: number?,
    days: number?,
    xpRequired: number?,
}

type MascotDefinition = {
    id: string,
    name: string,
    description: string,
    unlockCondition: UnlockCondition,
}

local MASCOT_DEFINITIONS: {MascotDefinition} = {
    {
        id = "pixel_pup",
        name = "Pixel Pup",
        description = "A loyal pixelated puppy. Always by your side!",
        unlockCondition = { conditionType = "free" },
    },
    {
        id = "cube_cat",
        name = "Cube Cat",
        description = "A mysterious cubic feline. Complete the Tetris pack to unlock.",
        unlockCondition = { conditionType = "pack_complete", packId = "tetris" },
    },
    {
        id = "pipe_frog",
        name = "Pipe Frog",
        description = "A cheerful amphibian from the pipes. Complete Pipe World to unlock.",
        unlockCondition = { conditionType = "pack_complete", packId = "pipeworld" },
    },
    {
        id = "flame_fox",
        name = "Flame Fox",
        description = "A fiery fox born from combo streaks. Reach a 50-combo to unlock.",
        unlockCondition = { conditionType = "combo_milestone", comboStreak = 50 },
    },
    {
        id = "shadow_owl",
        name = "Shadow Owl",
        description = "A wise nocturnal companion. Log in 7 days in a row to unlock.",
        unlockCondition = { conditionType = "login_streak", days = 7 },
    },
    {
        id = "golden_dragon",
        name = "Golden Dragon",
        description = "A legendary dragon of pure gold. Accumulate 100,000 XP to unlock.",
        unlockCondition = { conditionType = "xp_threshold", xpRequired = 100000 },
    },
}

--- Returns a mascot definition by ID, or nil if not found.
local function getMascotById(mascotId: string): MascotDefinition?
    for _, mascot in MASCOT_DEFINITIONS do
        if mascot.id == mascotId then
            return mascot
        end
    end
    return nil
end

--- Checks if a mascotId is in the player's unlocked list.
local function isUnlocked(unlockedMascots: {string}, mascotId: string): boolean
    for _, id in unlockedMascots do
        if id == mascotId then
            return true
        end
    end
    return false
end

--- Adds a mascotId to the unlocked list if not already present.
--- Returns the new list (does not mutate the original).
local function unlock(unlockedMascots: {string}, mascotId: string): {string}
    for _, id in unlockedMascots do
        if id == mascotId then
            return unlockedMascots
        end
    end
    local newList: {string} = {}
    for _, id in unlockedMascots do
        table.insert(newList, id)
    end
    table.insert(newList, mascotId)
    return newList
end

--- Attempts to equip a mascot. Returns the new equipped ID if valid,
--- or nil + error message if the mascot cannot be equipped.
local function equip(mascotId: string, unlockedMascots: {string}): (string?, string?)
    local mascotDef = getMascotById(mascotId)
    if not mascotDef then
        return nil, "Mascot not found"
    end
    if not isUnlocked(unlockedMascots, mascotId) then
        return nil, "Mascot is locked"
    end
    return mascotId, nil
end

--- Returns the currently equipped mascot ID, or the default if none is equipped.
local function getEquipped(equippedMascot: string?): string
    if equippedMascot and equippedMascot ~= "" then
        return equippedMascot
    end
    return "pixel_pup"
end

type PlayerData = {
    xp: number,
    completions: {[string]: {number}},
    comboHighest: number?,
    loginStreak: number?,
}

--- Evaluates whether a player meets the unlock condition for a given mascot.
local function checkUnlockConditions(mascotId: string, playerData: PlayerData): boolean
    local mascotDef = getMascotById(mascotId)
    if not mascotDef then
        return false
    end

    local condition = mascotDef.unlockCondition

    if condition.conditionType == "free" then
        return true
    elseif condition.conditionType == "pack_complete" then
        local packId = condition.packId
        if not packId then
            return false
        end
        local packCompletions = playerData.completions[packId]
        if not packCompletions then
            return false
        end
        return #packCompletions >= 10
    elseif condition.conditionType == "combo_milestone" then
        local required = condition.comboStreak
        if not required then
            return false
        end
        local highest = playerData.comboHighest or 0
        return highest >= required
    elseif condition.conditionType == "login_streak" then
        local requiredDays = condition.days
        if not requiredDays then
            return false
        end
        local streak = playerData.loginStreak or 0
        return streak >= requiredDays
    elseif condition.conditionType == "xp_threshold" then
        local requiredXP = condition.xpRequired
        if not requiredXP then
            return false
        end
        return playerData.xp >= requiredXP
    end

    return false
end

--============================================================================
-- Generators
--============================================================================

local ALL_MASCOT_IDS = { "pixel_pup", "cube_cat", "pipe_frog", "flame_fox", "shadow_owl", "golden_dragon" }
local NON_DEFAULT_IDS = { "cube_cat", "pipe_frog", "flame_fox", "shadow_owl", "golden_dragon" }

--- Generate a random unlocked list (subset of mascot IDs).
local function randomUnlockedList(rng: any): {string}
    local list: {string} = {}
    for _, id in ALL_MASCOT_IDS do
        if TestHarness.randomBool(rng) then
            table.insert(list, id)
        end
    end
    return list
end

--- Generate random player data.
local function randomPlayerData(rng: any): PlayerData
    local xp = TestHarness.randomInt(rng, 0, 200000)
    local comboHighest = TestHarness.randomInt(rng, 0, 100)
    local loginStreak = TestHarness.randomInt(rng, 0, 30)

    local completions: {[string]: {number}} = {}
    -- Randomly fill pack completions
    local packs = { "tetris", "pipeworld" }
    for _, packId in packs do
        if TestHarness.randomBool(rng) then
            local count = TestHarness.randomInt(rng, 0, 10)
            local levels: {number} = {}
            for i = 1, count do
                table.insert(levels, i)
            end
            completions[packId] = levels
        end
    end

    return {
        xp = xp,
        completions = completions,
        comboHighest = comboHighest,
        loginStreak = loginStreak,
    }
end

--============================================================================
-- Property 1: Default mascot always unlocked
-- For any player data, checkUnlockConditions("pixel_pup", data) is always true
-- **Validates: Requirements 6.1**
--============================================================================

print("\n=== Property: Default mascot always unlocked ===")

TestHarness.property("pixel_pup unlock condition is always met for any player data", 100, function(rng)
    local playerData = randomPlayerData(rng)

    local result = checkUnlockConditions("pixel_pup", playerData)

    if not result then
        return false, string.format(
            "Expected pixel_pup to always be unlocked. Got false for xp=%d, comboHighest=%s, loginStreak=%s",
            playerData.xp,
            tostring(playerData.comboHighest),
            tostring(playerData.loginStreak)
        )
    end

    return true, nil
end)

--============================================================================
-- Property 2: Can't equip locked mascot
-- For any mascotId NOT in unlockedList, equip returns nil + error
-- **Validates: Requirements 6.1**
--============================================================================

print("\n=== Property: Can't equip locked mascot ===")

TestHarness.property("Equipping a mascot not in unlocked list returns nil + error", 100, function(rng)
    -- Generate an unlocked list that does NOT include all mascots
    local unlockedList = randomUnlockedList(rng)

    -- Pick a mascot that is NOT in the unlocked list
    local lockedMascots: {string} = {}
    for _, id in ALL_MASCOT_IDS do
        if not isUnlocked(unlockedList, id) then
            table.insert(lockedMascots, id)
        end
    end

    -- If all mascots happen to be unlocked, force one to be locked
    if #lockedMascots == 0 then
        -- Remove the last element from the unlocked list
        local targetId = TestHarness.randomChoice(rng, NON_DEFAULT_IDS)
        local filteredList: {string} = {}
        for _, id in unlockedList do
            if id ~= targetId then
                table.insert(filteredList, id)
            end
        end
        unlockedList = filteredList
        lockedMascots = { targetId }
    end

    local mascotToEquip = TestHarness.randomChoice(rng, lockedMascots)

    local equipped, err = equip(mascotToEquip, unlockedList)

    if equipped ~= nil then
        return false, string.format(
            "Expected nil when equipping locked mascot '%s'. Got '%s'. UnlockedList has %d items.",
            mascotToEquip, tostring(equipped), #unlockedList
        )
    end

    if err == nil then
        return false, string.format(
            "Expected error message when equipping locked mascot '%s'. Got nil error.",
            mascotToEquip
        )
    end

    return true, nil
end)

--============================================================================
-- Property 3: Unlock conditions evaluate correctly
-- For random playerData, checkUnlockConditions returns consistent results.
-- Specifically: if xp >= 100000, golden_dragon condition is met.
-- **Validates: Requirements 6.1**
--============================================================================

print("\n=== Property: Unlock conditions evaluate correctly ===")

TestHarness.property("golden_dragon unlocks iff xp >= 100000", 100, function(rng)
    local playerData = randomPlayerData(rng)

    local result = checkUnlockConditions("golden_dragon", playerData)
    local expected = playerData.xp >= 100000

    if result ~= expected then
        return false, string.format(
            "golden_dragon condition mismatch. xp=%d, expected=%s, got=%s",
            playerData.xp, tostring(expected), tostring(result)
        )
    end

    return true, nil
end)

TestHarness.property("flame_fox unlocks iff comboHighest >= 50", 100, function(rng)
    local playerData = randomPlayerData(rng)

    local result = checkUnlockConditions("flame_fox", playerData)
    local expected = (playerData.comboHighest or 0) >= 50

    if result ~= expected then
        return false, string.format(
            "flame_fox condition mismatch. comboHighest=%s, expected=%s, got=%s",
            tostring(playerData.comboHighest), tostring(expected), tostring(result)
        )
    end

    return true, nil
end)

TestHarness.property("shadow_owl unlocks iff loginStreak >= 7", 100, function(rng)
    local playerData = randomPlayerData(rng)

    local result = checkUnlockConditions("shadow_owl", playerData)
    local expected = (playerData.loginStreak or 0) >= 7

    if result ~= expected then
        return false, string.format(
            "shadow_owl condition mismatch. loginStreak=%s, expected=%s, got=%s",
            tostring(playerData.loginStreak), tostring(expected), tostring(result)
        )
    end

    return true, nil
end)

TestHarness.property("cube_cat unlocks iff tetris pack has >= 10 completions", 100, function(rng)
    local playerData = randomPlayerData(rng)

    local result = checkUnlockConditions("cube_cat", playerData)
    local tetrisCompletions = playerData.completions["tetris"]
    local expected = tetrisCompletions ~= nil and #tetrisCompletions >= 10

    if result ~= expected then
        local completionCount = tetrisCompletions and #tetrisCompletions or 0
        return false, string.format(
            "cube_cat condition mismatch. tetris completions=%d, expected=%s, got=%s",
            completionCount, tostring(expected), tostring(result)
        )
    end

    return true, nil
end)

TestHarness.property("pipe_frog unlocks iff pipeworld pack has >= 10 completions", 100, function(rng)
    local playerData = randomPlayerData(rng)

    local result = checkUnlockConditions("pipe_frog", playerData)
    local pipeworldCompletions = playerData.completions["pipeworld"]
    local expected = pipeworldCompletions ~= nil and #pipeworldCompletions >= 10

    if result ~= expected then
        local completionCount = pipeworldCompletions and #pipeworldCompletions or 0
        return false, string.format(
            "pipe_frog condition mismatch. pipeworld completions=%d, expected=%s, got=%s",
            completionCount, tostring(expected), tostring(result)
        )
    end

    return true, nil
end)

--============================================================================
-- Property 4: Serialization round-trip
-- unlock() produces a list that contains the new item (verifiable via isUnlocked)
-- **Validates: Requirements 6.1**
--============================================================================

print("\n=== Property: Serialization round-trip (unlock then isUnlocked) ===")

TestHarness.property("unlock() produces a list where isUnlocked returns true for the added mascot", 100, function(rng)
    -- Start with a random unlocked list
    local unlockedList = randomUnlockedList(rng)

    -- Pick a random mascot to unlock
    local mascotToUnlock = TestHarness.randomChoice(rng, ALL_MASCOT_IDS)

    -- Unlock it
    local newList = unlock(unlockedList, mascotToUnlock)

    -- Verify the mascot is now in the list
    if not isUnlocked(newList, mascotToUnlock) then
        return false, string.format(
            "After unlock('%s'), isUnlocked should return true. Original list had %d items, new list has %d items.",
            mascotToUnlock, #unlockedList, #newList
        )
    end

    -- Verify all previously unlocked mascots are still unlocked
    for _, id in unlockedList do
        if not isUnlocked(newList, id) then
            return false, string.format(
                "Previously unlocked mascot '%s' is no longer in the list after unlocking '%s'.",
                id, mascotToUnlock
            )
        end
    end

    -- Verify no duplicates: if mascot was already unlocked, list length shouldn't change
    local wasAlreadyUnlocked = isUnlocked(unlockedList, mascotToUnlock)
    if wasAlreadyUnlocked then
        if #newList ~= #unlockedList then
            return false, string.format(
                "Unlocking already-unlocked mascot '%s' changed list length from %d to %d.",
                mascotToUnlock, #unlockedList, #newList
            )
        end
    else
        if #newList ~= #unlockedList + 1 then
            return false, string.format(
                "Unlocking new mascot '%s' should add exactly 1 item. Was %d, now %d.",
                mascotToUnlock, #unlockedList, #newList
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
