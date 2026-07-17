--!strict
--[[
    ComboManager.luau - Combo system management for Pixel Run Obby

    Combo Rules:
    =============
    Trigger:
      A "near-miss" occurs when the player passes within 1 block of an obstacle
      without colliding with it. Each consecutive near-miss increments the combo streak.

    Tier Thresholds:
      - Tier 1: streak >= 5  → "Nice!"         → 1.5x XP multiplier
      - Tier 2: streak >= 10 → "Great!"        → 2.0x XP multiplier
      - Tier 3: streak >= 20 → "Amazing!"      → 3.0x XP multiplier
      - Tier 4: streak >= 50 → "Unstoppable!"  → 5.0x XP multiplier

    Reset Conditions:
      The combo resets (streak = 0, multiplier = 1.0, tierName = nil) when any of
      the following occurs:
        1. Player collides with an obstacle
        2. Player is caught by the morass
        3. Player does not register a near-miss for more than 1 second

    The combo multiplier is applied on top of the base per-block XP calculation.
    Server-authoritative: all combo state is tracked and validated server-side.

    Validates: Requirements 6.1 (XP system integration)
]]

local Types = require(script.Parent.Types)

local ComboManager = {}

--============================================================================
-- Combo Tier Definitions
--============================================================================

--- Combo tier configuration table.
--- Each tier defines the minimum streak required, display name, and XP multiplier.
--- Tiers are ordered from highest to lowest so that lookup finds the best matching tier.
export type ComboTierDefinition = {
    minStreak: number,    -- Minimum consecutive near-misses to reach this tier
    name: string,         -- Display name shown on HUD
    multiplier: number,   -- XP multiplier applied while at this tier
}

ComboManager.COMBO_TIERS: {ComboTierDefinition} = {
    { minStreak = 50, name = "Unstoppable!", multiplier = 5.0 },
    { minStreak = 20, name = "Amazing!",     multiplier = 3.0 },
    { minStreak = 10, name = "Great!",       multiplier = 2.0 },
    { minStreak = 5,  name = "Nice!",        multiplier = 1.5 },
}

--============================================================================
-- Constants
--============================================================================

--- Distance in blocks that qualifies as a "near-miss" (pass within this distance
--- of an obstacle without hitting it).
ComboManager.NEAR_MISS_DISTANCE = Types.COMBO_NEAR_MISS_DISTANCE  -- 1 block

--- Maximum time in seconds between near-misses before the combo resets.
ComboManager.TIMEOUT_SECONDS = Types.COMBO_TIMEOUT  -- 1 second

--============================================================================
-- Reset Conditions (documented enum for server-side reset triggers)
--============================================================================

--- Enumeration of events that cause a combo reset.
ComboManager.RESET_REASONS = {
    OBSTACLE_HIT = "obstacle_hit",     -- Player collided with an obstacle
    MORASS_CAUGHT = "morass_caught",    -- Player was caught by the morass
    TIMEOUT = "timeout",               -- No near-miss registered within TIMEOUT_SECONDS
}

--============================================================================
-- State Factory
--============================================================================

--- Creates a fresh ComboState with default values (no active combo).
function ComboManager.createDefaultState(): Types.ComboState
    return {
        streak = 0,
        multiplier = 1.0,
        tierName = nil,
        lastNearMissTime = 0,
    }
end

--============================================================================
-- Tier Lookup
--============================================================================

--- Returns the tier name and multiplier for a given streak count.
--- If the streak is below the minimum tier threshold (5), returns nil and 1.0.
function ComboManager.getTierForStreak(streak: number): (string?, number)
    for _, tier in ipairs(ComboManager.COMBO_TIERS) do
        if streak >= tier.minStreak then
            return tier.name, tier.multiplier
        end
    end
    return nil, 1.0
end

--============================================================================
-- Combo Operations (pure functions, immutable state pattern)
--============================================================================

--- Starts or initializes a combo with streak=1.
--- Sets the lastNearMissTime to the provided current time.
--- @param state ComboState -- Current combo state (may be default or active)
--- @param currentTime number -- Server timestamp of the near-miss event
--- @return ComboState -- New state with streak=1 and appropriate tier/multiplier
function ComboManager.startCombo(state: Types.ComboState, currentTime: number): Types.ComboState
    local tierName, multiplier = ComboManager.getTierForStreak(1)
    return {
        streak = 1,
        multiplier = multiplier,
        tierName = tierName,
        lastNearMissTime = currentTime,
    }
end

--- Increments the combo streak by 1, updates multiplier and tier.
--- Sets lastNearMissTime to the provided current time.
--- @param state ComboState -- Current active combo state
--- @param currentTime number -- Server timestamp of the near-miss event
--- @return ComboState -- New state with streak incremented
function ComboManager.incrementCombo(state: Types.ComboState, currentTime: number): Types.ComboState
    local newStreak = state.streak + 1
    local tierName, multiplier = ComboManager.getTierForStreak(newStreak)
    return {
        streak = newStreak,
        multiplier = multiplier,
        tierName = tierName,
        lastNearMissTime = currentTime,
    }
end

--- Resets combo to default state (streak=0, multiplier=1.0, tierName=nil).
--- @param state ComboState -- Current combo state (ignored, always resets to default)
--- @return ComboState -- Fresh default state
function ComboManager.resetCombo(state: Types.ComboState): Types.ComboState
    return ComboManager.createDefaultState()
end

--- Returns the current XP multiplier from the combo state.
--- @param state ComboState -- Current combo state
--- @return number -- Multiplier value (1.0 when no combo is active)
function ComboManager.getCurrentMultiplier(state: Types.ComboState): number
    return state.multiplier
end

--- Returns the current combo tier name, or nil if below minimum threshold.
--- @param state ComboState -- Current combo state
--- @return string? -- Tier display name (e.g., "Nice!", "Great!") or nil
function ComboManager.getComboTier(state: Types.ComboState): string?
    return state.tierName
end

--- Checks whether the combo has timed out based on elapsed time since last near-miss.
--- A combo times out if more than TIMEOUT_SECONDS (1 second) has elapsed.
--- @param state ComboState -- Current combo state
--- @param currentTime number -- Current server timestamp
--- @return boolean -- true if combo has timed out and should be reset
function ComboManager.shouldTimeout(state: Types.ComboState, currentTime: number): boolean
    if state.streak == 0 then
        return false
    end
    return (currentTime - state.lastNearMissTime) > ComboManager.TIMEOUT_SECONDS
end

return ComboManager
