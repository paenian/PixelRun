--!strict
--[[
    MascotManager.luau - Mascot companion definitions and management
    
    Defines the 6 mascot companions, their unlock conditions, and provides
    lookup utilities. Server-authoritative unlock validation is handled
    by functions in this module.
    
    Validates: Requirements 6.1
]]

local Types = require(script.Parent.Types)

local MascotManager = {}

--============================================================================
-- Mascot Definitions
--============================================================================

--- All mascot definitions with their unlock conditions.
--- "pixel_pup" is the default free mascot available to all players.
MascotManager.MASCOT_DEFINITIONS: {Types.MascotDefinition} = {
    {
        id = "pixel_pup",
        name = "Pixel Pup",
        description = "A loyal pixelated puppy. Always by your side!",
        unlockCondition = {
            conditionType = "free",
        },
        color = Color3.fromRGB(70, 130, 230), -- Blue
    },
    {
        id = "cube_cat",
        name = "Cube Cat",
        description = "A mysterious cubic feline. Complete the Tetris pack to unlock.",
        unlockCondition = {
            conditionType = "pack_complete",
            packId = "tetris",
        },
        color = Color3.fromRGB(150, 70, 200), -- Purple
    },
    {
        id = "pipe_frog",
        name = "Pipe Frog",
        description = "A cheerful amphibian from the pipes. Complete Pipe World to unlock.",
        unlockCondition = {
            conditionType = "pack_complete",
            packId = "pipeworld",
        },
        color = Color3.fromRGB(50, 200, 80), -- Green
    },
    {
        id = "flame_fox",
        name = "Flame Fox",
        description = "A fiery fox born from combo streaks. Reach a 50-combo to unlock.",
        unlockCondition = {
            conditionType = "combo_milestone",
            comboStreak = 50,
        },
        color = Color3.fromRGB(230, 100, 30), -- Orange/Red
    },
    {
        id = "shadow_owl",
        name = "Shadow Owl",
        description = "A wise nocturnal companion. Log in 7 days in a row to unlock.",
        unlockCondition = {
            conditionType = "login_streak",
            days = 7,
        },
        color = Color3.fromRGB(80, 40, 120), -- Dark Purple
    },
    {
        id = "golden_dragon",
        name = "Golden Dragon",
        description = "A legendary dragon of pure gold. Accumulate 100,000 XP to unlock.",
        unlockCondition = {
            conditionType = "xp_threshold",
            xpRequired = 100000,
        },
        color = Color3.fromRGB(255, 200, 50), -- Gold
    },
}

--============================================================================
-- Lookup Utilities
--============================================================================

--- Returns all mascot definitions.
function MascotManager.getMascotDefinitions(): {Types.MascotDefinition}
    return MascotManager.MASCOT_DEFINITIONS
end

--- Returns a mascot definition by ID, or nil if not found.
function MascotManager.getMascotById(mascotId: string): Types.MascotDefinition?
    for _, mascot in MascotManager.MASCOT_DEFINITIONS do
        if mascot.id == mascotId then
            return mascot
        end
    end
    return nil
end

--- Returns the default (free) mascot ID.
function MascotManager.getDefaultMascotId(): string
    return "pixel_pup"
end

--============================================================================
-- Operational Functions (Pure, server-authoritative)
--============================================================================

--- Checks if a mascotId is in the player's unlocked list.
--- @param unlockedMascots {string} -- List of unlocked mascot IDs
--- @param mascotId string -- The mascot ID to check
--- @return boolean -- true if the mascot is unlocked
function MascotManager.isUnlocked(unlockedMascots: {string}, mascotId: string): boolean
    for _, id in unlockedMascots do
        if id == mascotId then
            return true
        end
    end
    return false
end

--- Adds a mascotId to the unlocked list if not already present.
--- Returns the new list (does not mutate the original).
--- @param unlockedMascots {string} -- Current list of unlocked mascot IDs
--- @param mascotId string -- The mascot ID to unlock
--- @return {string} -- New list with the mascot added (or unchanged if already unlocked)
function MascotManager.unlock(unlockedMascots: {string}, mascotId: string): {string}
    -- Check if already unlocked
    for _, id in unlockedMascots do
        if id == mascotId then
            return unlockedMascots
        end
    end
    -- Create new list with the mascot added
    local newList: {string} = {}
    for _, id in unlockedMascots do
        table.insert(newList, id)
    end
    table.insert(newList, mascotId)
    return newList
end

--- Attempts to equip a mascot. Returns the new equipped ID if valid (mascot is unlocked),
--- or nil + error message if the mascot cannot be equipped.
--- @param mascotId string -- The mascot ID to equip
--- @param unlockedMascots {string} -- Player's list of unlocked mascot IDs
--- @return (string?, string?) -- (equippedId, nil) on success; (nil, errorMessage) on failure
function MascotManager.equip(mascotId: string, unlockedMascots: {string}): (string?, string?)
    -- Validate mascot exists
    local mascotDef = MascotManager.getMascotById(mascotId)
    if not mascotDef then
        return nil, "Mascot not found"
    end
    -- Validate mascot is unlocked
    if not MascotManager.isUnlocked(unlockedMascots, mascotId) then
        return nil, "Mascot is locked"
    end
    return mascotId, nil
end

--- Returns the currently equipped mascot ID, or the default if none is equipped.
--- @param equippedMascot string? -- Current equipped mascot ID (may be nil)
--- @return string -- The equipped mascot ID (falls back to "pixel_pup")
function MascotManager.getEquipped(equippedMascot: string?): string
    if equippedMascot and equippedMascot ~= "" then
        return equippedMascot
    end
    return MascotManager.getDefaultMascotId()
end

--- Evaluates whether a player meets the unlock condition for a given mascot.
--- @param mascotId string -- The mascot ID to check conditions for
--- @param playerData { xp: number, completions: {[string]: {number}}, comboHighest: number?, loginStreak: number? }
--- @return boolean -- true if the player meets the unlock condition
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
        -- Pack is complete if all 10 levels are in the completions list
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
-- Initialization
--============================================================================

function MascotManager.init(): ()
    -- No-op; module is stateless
end

return MascotManager
