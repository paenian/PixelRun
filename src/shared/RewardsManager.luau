--!strict
--[[
    RewardsManager.luau - Daily spin rewards management for Pixel Run Obby

    Shared module that encapsulates daily spin logic. Usable by both:
    - Server: authoritative validation (canSpinToday, determineReward)
    - Client: display logic (getRewardSegments for wheel rendering)

    Reward wheel has 10 segments total:
      100 XP  x3 (indices 1, 2, 3)
      200 XP  x2 (indices 4, 5)
      500 XP  x2 (indices 6, 7)
      1000 XP x1 (index 8)
      2000 XP x1 (index 9)
      Bonus Spin x1 (index 10) - treated as 500 XP for now

    Server-authoritative timing: compares UTC day (math.floor(timestamp / 86400)).

    Validates: Requirements 3.1, 3.2, 3.3
]]

local RewardsManager = {}

--============================================================================
-- Constants
--============================================================================

local SECONDS_PER_DAY = 86400

--============================================================================
-- Types
--============================================================================

export type RewardSegment = {
    xpAmount: number,
    label: string,
    weight: number,
}

export type RewardResult = {
    xpAmount: number,
    segmentIndex: number,
    label: string,
}

--============================================================================
-- Reward Segment Definitions (10 segments)
--============================================================================

local REWARD_SEGMENTS: { RewardSegment } = {
    { xpAmount = 100,  label = "100 XP",     weight = 1 },  -- index 1
    { xpAmount = 100,  label = "100 XP",     weight = 1 },  -- index 2
    { xpAmount = 100,  label = "100 XP",     weight = 1 },  -- index 3
    { xpAmount = 200,  label = "200 XP",     weight = 1 },  -- index 4
    { xpAmount = 200,  label = "200 XP",     weight = 1 },  -- index 5
    { xpAmount = 500,  label = "500 XP",     weight = 1 },  -- index 6
    { xpAmount = 500,  label = "500 XP",     weight = 1 },  -- index 7
    { xpAmount = 1000, label = "1000 XP",    weight = 1 },  -- index 8
    { xpAmount = 2000, label = "2000 XP",    weight = 1 },  -- index 9
    { xpAmount = 500,  label = "Bonus Spin", weight = 1 },  -- index 10 (treated as 500 XP for now)
}

--============================================================================
-- Public API
--============================================================================

--- Returns the full reward segment definitions table.
--- Used by client for wheel rendering and by server for validation.
--- @return {{xpAmount: number, label: string, weight: number}}
function RewardsManager.getRewardSegments(): { RewardSegment }
    return REWARD_SEGMENTS
end

--- Determines whether a player can spin today based on their last spin timestamp.
--- Uses server-authoritative UTC day comparison.
---
--- @param lastSpinTimestamp number? -- The os.time() timestamp of the player's last spin (nil if never spun)
--- @param currentTime number -- The current os.time() value (server-authoritative)
--- @return boolean -- true if the player can spin (different UTC day or never spun)
function RewardsManager.canSpinToday(lastSpinTimestamp: number?, currentTime: number): boolean
    if lastSpinTimestamp == nil then
        return true
    end

    local lastDay = math.floor(lastSpinTimestamp / SECONDS_PER_DAY)
    local today = math.floor(currentTime / SECONDS_PER_DAY)

    return today > lastDay
end

--- Determines the reward for a spin based on a seed value.
--- If no seed is provided, picks a random segment index (1-10).
--- The seed is used as a direct index (modulo segment count) for deterministic testing.
---
--- @param seed number? -- Optional seed for deterministic selection (uses math.random if nil)
--- @return RewardResult -- The selected reward with xpAmount, segmentIndex, and label
function RewardsManager.determineReward(seed: number?): RewardResult
    local segmentCount = #REWARD_SEGMENTS
    local segmentIndex: number

    if seed ~= nil then
        -- Use seed to deterministically pick a segment (1-indexed)
        -- Ensure positive modulo result for any seed value
        segmentIndex = ((seed - 1) % segmentCount) + 1
    else
        -- Random selection when no seed provided
        segmentIndex = math.random(1, segmentCount)
    end

    local segment = REWARD_SEGMENTS[segmentIndex]

    return {
        xpAmount = segment.xpAmount,
        segmentIndex = segmentIndex,
        label = segment.label,
    }
end

--- Returns the UTC day number from a timestamp.
--- Utility to interpret a stored spin timestamp as a date.
---
--- @param timestamp number -- An os.time() timestamp
--- @return number -- The UTC day number (floor of timestamp / 86400)
function RewardsManager.getLastSpinDate(timestamp: number): number
    return math.floor(timestamp / SECONDS_PER_DAY)
end

return RewardsManager
