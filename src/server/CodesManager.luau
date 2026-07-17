--!strict
--[[
    CodesManager.luau - Server-side code validation and redemption system

    Manages promotional codes that award XP or other rewards.
    Features:
    - Code definitions with reward type, amount, max redemptions, and expiry
    - Per-player redemption tracking (stored in player profile)
    - Validation: code exists, not expired, not already redeemed, not over max redemptions

    Validates: Requirements from Epoch 2, Task 2 (Codes System)
]]

local CodesManager = {}

--============================================================================
-- Types
--============================================================================

export type CodeReward = {
    rewardType: string,   -- "xp" | "mascot"
    amount: number?,      -- XP amount (for "xp" type)
    mascotId: string?,    -- Mascot identifier (for "mascot" type)
}

export type CodeDefinition = {
    code: string,           -- The code string (uppercase, no spaces)
    reward: CodeReward,     -- What the player receives
    maxRedemptions: number?, -- Max total redemptions across all players (nil = unlimited)
    expiresAt: number?,     -- os.time() timestamp when code expires (nil = never)
}

export type RedemptionResult = {
    success: boolean,
    message: string,
    reward: CodeReward?,
}

--============================================================================
-- State
--============================================================================

-- Registered code definitions (code string -> definition)
local codeDefinitions: { [string]: CodeDefinition } = {}

-- Global redemption counts (code string -> total times redeemed)
local globalRedemptionCounts: { [string]: number } = {}

-- Per-player redemption tracking (userId -> set of redeemed code strings)
local playerRedemptions: { [number]: { [string]: boolean } } = {}

--============================================================================
-- Private Helpers
--============================================================================

--- Normalizes a code string: uppercase, trimmed of whitespace.
local function normalizeCode(input: string): string
    return string.upper(string.gsub(input, "%s+", ""))
end

--============================================================================
-- Public API
--============================================================================

--- Register a new code definition. Called at server init to seed codes.
function CodesManager.addCode(definition: CodeDefinition)
    local normalized = normalizeCode(definition.code)
    codeDefinitions[normalized] = {
        code = normalized,
        reward = definition.reward,
        maxRedemptions = definition.maxRedemptions,
        expiresAt = definition.expiresAt,
    }
    -- Initialize global count if not present
    if not globalRedemptionCounts[normalized] then
        globalRedemptionCounts[normalized] = 0
    end
end

--- Load a player's previously redeemed codes from their profile data.
--- Called when a player joins and their profile is loaded.
function CodesManager.loadPlayerRedemptions(userId: number, redeemedCodes: { string }?)
    playerRedemptions[userId] = {}
    if redeemedCodes then
        for _, code in redeemedCodes do
            playerRedemptions[userId][normalizeCode(code)] = true
        end
    end
end

--- Clean up player data when they leave.
function CodesManager.clearPlayer(userId: number)
    playerRedemptions[userId] = nil
end

--- Check if a player has already redeemed a specific code.
function CodesManager.hasRedeemed(userId: number, code: string): boolean
    local normalized = normalizeCode(code)
    local playerCodes = playerRedemptions[userId]
    if not playerCodes then
        return false
    end
    return playerCodes[normalized] == true
end

--- Get all currently active (non-expired) code definitions.
function CodesManager.getActiveCodes(): { CodeDefinition }
    local active: { CodeDefinition } = {}
    local now = os.time()
    for _, def in codeDefinitions do
        if not def.expiresAt or def.expiresAt > now then
            table.insert(active, def)
        end
    end
    return active
end

--- Get the list of codes a player has redeemed (for persistence).
function CodesManager.getRedeemedList(userId: number): { string }
    local list: { string } = {}
    local playerCodes = playerRedemptions[userId]
    if playerCodes then
        for code, _ in playerCodes do
            table.insert(list, code)
        end
    end
    return list
end

--- Attempt to redeem a code for a player.
--- Returns a RedemptionResult with success/failure and relevant message.
--- Does NOT apply the reward — caller is responsible for awarding XP/items.
function CodesManager.redeemCode(userId: number, inputCode: string): RedemptionResult
    -- Validate input
    if type(inputCode) ~= "string" or #inputCode == 0 then
        return { success = false, message = "Please enter a code.", reward = nil }
    end

    local normalized = normalizeCode(inputCode)

    -- Check code exists
    local definition = codeDefinitions[normalized]
    if not definition then
        return { success = false, message = "Invalid code.", reward = nil }
    end

    -- Check expiry
    if definition.expiresAt and os.time() >= definition.expiresAt then
        return { success = false, message = "This code has expired.", reward = nil }
    end

    -- Check max redemptions
    if definition.maxRedemptions then
        local count = globalRedemptionCounts[normalized] or 0
        if count >= definition.maxRedemptions then
            return { success = false, message = "This code has reached its redemption limit.", reward = nil }
        end
    end

    -- Check if player already redeemed
    if CodesManager.hasRedeemed(userId, normalized) then
        return { success = false, message = "You have already redeemed this code.", reward = nil }
    end

    -- All checks passed — mark as redeemed
    if not playerRedemptions[userId] then
        playerRedemptions[userId] = {}
    end
    playerRedemptions[userId][normalized] = true

    -- Increment global count
    globalRedemptionCounts[normalized] = (globalRedemptionCounts[normalized] or 0) + 1

    -- Return success with the reward info
    local rewardMsg = ""
    if definition.reward.rewardType == "xp" then
        rewardMsg = "+" .. tostring(definition.reward.amount or 0) .. " XP"
    elseif definition.reward.rewardType == "mascot" then
        rewardMsg = "Mascot unlocked!"
    end

    return {
        success = true,
        message = "Code redeemed! " .. rewardMsg,
        reward = definition.reward,
    }
end

--============================================================================
-- Initialization: Seed Default Codes
--============================================================================

--- Seeds the initial promotional codes.
function CodesManager.init()
    -- "PIXELRUN" → 500 XP (launch code, no expiry, unlimited redemptions)
    CodesManager.addCode({
        code = "PIXELRUN",
        reward = { rewardType = "xp", amount = 500 },
        maxRedemptions = nil,
        expiresAt = nil,
    })

    -- "TETRIS" → 1000 XP (first-week code, 7 day expiry from server start)
    CodesManager.addCode({
        code = "TETRIS",
        reward = { rewardType = "xp", amount = 1000 },
        maxRedemptions = nil,
        expiresAt = os.time() + (7 * 24 * 60 * 60), -- 7 days from now
    })

    -- "FOUNDER" → 2000 XP (limited to first 100 redemptions)
    CodesManager.addCode({
        code = "FOUNDER",
        reward = { rewardType = "xp", amount = 2000 },
        maxRedemptions = 100,
        expiresAt = nil,
    })
end

return CodesManager
