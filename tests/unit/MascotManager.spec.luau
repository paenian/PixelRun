--!strict
--[[
    MascotManager.spec.luau - Unit tests for MascotManager operational functions
    
    Tests cover: isUnlocked, unlock, equip, getEquipped, checkUnlockConditions
    
    Validates: Requirements 6.1, 6.2
    
    Since MascotManager uses require(script.Parent.Types) and Color3 which don't
    work in Lune, we inline the pure functions here (mirroring the source exactly).
]]

--============================================================================
-- Inlined MascotManager (mirrors src/shared/MascotManager.luau operational funcs)
--============================================================================

local MascotManager = {}

-- Minimal mascot definitions needed for testing (mirrors source)
local MASCOT_DEFINITIONS = {
    {
        id = "pixel_pup",
        name = "Pixel Pup",
        description = "A loyal pixelated puppy. Always by your side!",
        unlockCondition = { conditionType = "free" },
    },
    {
        id = "cube_cat",
        name = "Cube Cat",
        description = "Complete the Tetris pack to unlock.",
        unlockCondition = { conditionType = "pack_complete", packId = "tetris" },
    },
    {
        id = "pipe_frog",
        name = "Pipe Frog",
        description = "Complete Pipe World to unlock.",
        unlockCondition = { conditionType = "pack_complete", packId = "pipeworld" },
    },
    {
        id = "flame_fox",
        name = "Flame Fox",
        description = "Reach a 50-combo to unlock.",
        unlockCondition = { conditionType = "combo_milestone", comboStreak = 50 },
    },
    {
        id = "shadow_owl",
        name = "Shadow Owl",
        description = "Log in 7 days in a row to unlock.",
        unlockCondition = { conditionType = "login_streak", days = 7 },
    },
    {
        id = "golden_dragon",
        name = "Golden Dragon",
        description = "Accumulate 100,000 XP to unlock.",
        unlockCondition = { conditionType = "xp_threshold", xpRequired = 100000 },
    },
}

function MascotManager.getMascotById(mascotId: string)
    for _, mascot in MASCOT_DEFINITIONS do
        if mascot.id == mascotId then
            return mascot
        end
    end
    return nil
end

function MascotManager.getDefaultMascotId(): string
    return "pixel_pup"
end

function MascotManager.isUnlocked(unlockedMascots: {string}, mascotId: string): boolean
    for _, id in unlockedMascots do
        if id == mascotId then
            return true
        end
    end
    return false
end

function MascotManager.unlock(unlockedMascots: {string}, mascotId: string): {string}
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

function MascotManager.equip(mascotId: string, unlockedMascots: {string}): (string?, string?)
    local mascotDef = MascotManager.getMascotById(mascotId)
    if not mascotDef then
        return nil, "Mascot not found"
    end
    if not MascotManager.isUnlocked(unlockedMascots, mascotId) then
        return nil, "Mascot is locked"
    end
    return mascotId, nil
end

function MascotManager.getEquipped(equippedMascot: string?): string
    if equippedMascot and equippedMascot ~= "" then
        return equippedMascot
    end
    return MascotManager.getDefaultMascotId()
end

function MascotManager.checkUnlockConditions(mascotId: string, playerData: {
    xp: number,
    completions: {[string]: {number}},
    comboHighest: number?,
    loginStreak: number?,
}): boolean
    local mascotDef = MascotManager.getMascotById(mascotId)
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

local function assertFalse(condition: boolean, testName: string)
    if not condition then
        passed += 1
        print(`  ✓ {testName}`)
    else
        failed += 1
        print(`  ✗ {testName}: expected false, got true`)
    end
end

--============================================================================
-- isUnlocked tests
--============================================================================
print("\n=== isUnlocked ===")

assertTrue(MascotManager.isUnlocked({"pixel_pup"}, "pixel_pup"), "pixel_pup is in list")
assertFalse(MascotManager.isUnlocked({"pixel_pup"}, "cube_cat"), "cube_cat not in list")
assertTrue(MascotManager.isUnlocked({"pixel_pup", "cube_cat"}, "cube_cat"), "cube_cat is in multi-item list")
assertFalse(MascotManager.isUnlocked({}, "pixel_pup"), "empty list returns false")

--============================================================================
-- unlock tests
--============================================================================
print("\n=== unlock ===")

do
    local result = MascotManager.unlock({"pixel_pup"}, "cube_cat")
    assertEquals(#result, 2, "unlock adds mascot to list (length)")
    assertTrue(MascotManager.isUnlocked(result, "cube_cat"), "unlock: cube_cat is now in list")
    assertTrue(MascotManager.isUnlocked(result, "pixel_pup"), "unlock: pixel_pup still in list")
end

do
    local original = {"pixel_pup", "cube_cat"}
    local result = MascotManager.unlock(original, "cube_cat")
    assertEquals(#result, 2, "unlock already-unlocked returns same length")
end

do
    local original = {"pixel_pup"}
    local result = MascotManager.unlock(original, "flame_fox")
    -- Original should not be mutated (new list is returned)
    assertEquals(#original, 1, "unlock does not mutate original list")
    assertEquals(#result, 2, "unlock returns new list with addition")
end

--============================================================================
-- equip tests
--============================================================================
print("\n=== equip ===")

do
    local id, err = MascotManager.equip("pixel_pup", {"pixel_pup"})
    assertEquals(id, "pixel_pup", "equip unlocked mascot returns id")
    assertEquals(err, nil, "equip unlocked mascot has no error")
end

do
    local id, err = MascotManager.equip("cube_cat", {"pixel_pup"})
    assertEquals(id, nil, "equip locked mascot returns nil")
    assertEquals(err, "Mascot is locked", "equip locked mascot returns error message")
end

do
    local id, err = MascotManager.equip("nonexistent_mascot", {"pixel_pup"})
    assertEquals(id, nil, "equip nonexistent mascot returns nil")
    assertEquals(err, "Mascot not found", "equip nonexistent mascot returns error message")
end

do
    local id, err = MascotManager.equip("flame_fox", {"pixel_pup", "flame_fox"})
    assertEquals(id, "flame_fox", "equip valid unlocked non-default mascot succeeds")
    assertEquals(err, nil, "equip valid unlocked non-default mascot has no error")
end

--============================================================================
-- getEquipped tests
--============================================================================
print("\n=== getEquipped ===")

assertEquals(MascotManager.getEquipped("flame_fox"), "flame_fox", "getEquipped with valid ID returns that ID")
assertEquals(MascotManager.getEquipped(nil), "pixel_pup", "getEquipped with nil returns default")
assertEquals(MascotManager.getEquipped(""), "pixel_pup", "getEquipped with empty string returns default")
assertEquals(MascotManager.getEquipped("golden_dragon"), "golden_dragon", "getEquipped with golden_dragon returns it")

--============================================================================
-- checkUnlockConditions tests
--============================================================================
print("\n=== checkUnlockConditions ===")

-- Free mascot always unlockable
do
    local playerData = { xp = 0, completions = {}, comboHighest = 0, loginStreak = 0 }
    assertTrue(
        MascotManager.checkUnlockConditions("pixel_pup", playerData),
        "free mascot is always unlockable"
    )
end

-- Pack complete: tetris with all 10 levels
do
    local playerData = {
        xp = 5000,
        completions = { tetris = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10} },
        comboHighest = 0,
        loginStreak = 0,
    }
    assertTrue(
        MascotManager.checkUnlockConditions("cube_cat", playerData),
        "cube_cat unlockable with tetris pack complete"
    )
end

-- Pack complete: tetris with only 5 levels
do
    local playerData = {
        xp = 3000,
        completions = { tetris = {1, 2, 3, 4, 5} },
        comboHighest = 0,
        loginStreak = 0,
    }
    assertFalse(
        MascotManager.checkUnlockConditions("cube_cat", playerData),
        "cube_cat NOT unlockable with incomplete tetris pack"
    )
end

-- Pack complete: no completions at all
do
    local playerData = { xp = 0, completions = {}, comboHighest = 0, loginStreak = 0 }
    assertFalse(
        MascotManager.checkUnlockConditions("cube_cat", playerData),
        "cube_cat NOT unlockable with no completions"
    )
end

-- Combo milestone: exactly 50
do
    local playerData = { xp = 1000, completions = {}, comboHighest = 50, loginStreak = 0 }
    assertTrue(
        MascotManager.checkUnlockConditions("flame_fox", playerData),
        "flame_fox unlockable at exactly 50 combo"
    )
end

-- Combo milestone: above 50
do
    local playerData = { xp = 1000, completions = {}, comboHighest = 100, loginStreak = 0 }
    assertTrue(
        MascotManager.checkUnlockConditions("flame_fox", playerData),
        "flame_fox unlockable above 50 combo"
    )
end

-- Combo milestone: below 50
do
    local playerData = { xp = 1000, completions = {}, comboHighest = 49, loginStreak = 0 }
    assertFalse(
        MascotManager.checkUnlockConditions("flame_fox", playerData),
        "flame_fox NOT unlockable below 50 combo"
    )
end

-- Login streak: exactly 7
do
    local playerData = { xp = 0, completions = {}, comboHighest = 0, loginStreak = 7 }
    assertTrue(
        MascotManager.checkUnlockConditions("shadow_owl", playerData),
        "shadow_owl unlockable at exactly 7 days"
    )
end

-- Login streak: below 7
do
    local playerData = { xp = 0, completions = {}, comboHighest = 0, loginStreak = 6 }
    assertFalse(
        MascotManager.checkUnlockConditions("shadow_owl", playerData),
        "shadow_owl NOT unlockable below 7 days"
    )
end

-- XP threshold: exactly 100000
do
    local playerData = { xp = 100000, completions = {}, comboHighest = 0, loginStreak = 0 }
    assertTrue(
        MascotManager.checkUnlockConditions("golden_dragon", playerData),
        "golden_dragon unlockable at exactly 100k XP"
    )
end

-- XP threshold: above 100000
do
    local playerData = { xp = 200000, completions = {}, comboHighest = 0, loginStreak = 0 }
    assertTrue(
        MascotManager.checkUnlockConditions("golden_dragon", playerData),
        "golden_dragon unlockable above 100k XP"
    )
end

-- XP threshold: below 100000
do
    local playerData = { xp = 99999, completions = {}, comboHighest = 0, loginStreak = 0 }
    assertFalse(
        MascotManager.checkUnlockConditions("golden_dragon", playerData),
        "golden_dragon NOT unlockable below 100k XP"
    )
end

-- Nonexistent mascot
do
    local playerData = { xp = 999999, completions = {}, comboHighest = 999, loginStreak = 999 }
    assertFalse(
        MascotManager.checkUnlockConditions("nonexistent", playerData),
        "nonexistent mascot returns false"
    )
end

--============================================================================
-- Summary
--============================================================================
print(`\n=== Results: {passed} passed, {failed} failed ===`)

if failed > 0 then
    error(`{failed} test(s) failed`)
end
