--!strict
--[[
    PowerUpManager.luau - Power-up management module for Pixel Run Obby
    
    Provides functions to query power-up definitions, costs, and multipliers,
    validate purchases (XP sufficiency and sequential tier enforcement),
    and apply purchases to player profiles.
    
    Validates: Requirements 7.1, 7.2, 7.3, 7.4
]]

local Types = require(script.Parent.Types)

local PowerUpManager = {}

export type PowerUpManager = {
	getDefinitions: () -> { Types.PowerUpDefinition },
	getCost: (powerUpId: string, tier: number) -> number?,
	getMultiplier: (powerUpId: string, tier: number) -> number?,
	canPurchase: (playerData: Types.PlayerProfile, powerUpId: string, tier: number) -> (boolean, string?),
	applyPurchase: (playerData: Types.PlayerProfile, powerUpId: string, tier: number) -> Types.PlayerProfile,
}

--============================================================================
-- Internal helpers
--============================================================================

--- Find a power-up definition by its ID.
--- Returns the definition or nil if not found.
local function findDefinition(powerUpId: string): Types.PowerUpDefinition?
	for _, def in Types.POWER_UP_DEFINITIONS do
		if def.id == powerUpId then
			return def
		end
	end
	return nil
end

--- Get the current tier a player owns for a given power-up.
--- Returns 0 if the player doesn't own any tier.
local function getPlayerTier(playerData: Types.PlayerProfile, powerUpId: string): number
	if powerUpId == "higherJump" then
		return playerData.powerUps.higherJump
	elseif powerUpId == "doubleJump" then
		return playerData.powerUps.doubleJump
	elseif powerUpId == "fasterSpeed" then
		return playerData.powerUps.fasterSpeed
	end
	return 0
end

--============================================================================
-- Public API
--============================================================================

--- Returns all power-up definitions from Types.POWER_UP_DEFINITIONS.
function PowerUpManager.getDefinitions(): { Types.PowerUpDefinition }
	return Types.POWER_UP_DEFINITIONS
end

--- Returns the XP cost for a specific power-up at a specific tier.
--- Returns nil if the powerUpId or tier is invalid.
function PowerUpManager.getCost(powerUpId: string, tier: number): number?
	local def = findDefinition(powerUpId)
	if not def then
		return nil
	end

	if tier < 1 or tier > def.maxTier then
		return nil
	end

	return def.costs[tier]
end

--- Returns the effect multiplier for a specific power-up at a specific tier.
--- Returns nil if the powerUpId or tier is invalid.
function PowerUpManager.getMultiplier(powerUpId: string, tier: number): number?
	local def = findDefinition(powerUpId)
	if not def then
		return nil
	end

	if tier < 1 or tier > def.maxTier then
		return nil
	end

	return def.multipliers[tier]
end

--- Validates whether a player can purchase a specific power-up tier.
--- Returns (true, nil) if valid, or (false, errorMessage) if not.
---
--- Checks:
--- 1. Power-up ID must exist
--- 2. Tier must be valid (1 to maxTier)
--- 3. Player must not already own this tier
--- 4. Player must own tier-1 first (sequential enforcement; tier 1 has no prereq)
--- 5. Player must have enough XP (>= cost for that tier)
function PowerUpManager.canPurchase(playerData: Types.PlayerProfile, powerUpId: string, tier: number): (boolean, string?)
	-- Check 1: Power-up must exist
	local def = findDefinition(powerUpId)
	if not def then
		return false, "Invalid power-up ID"
	end

	-- Check 2: Tier must be valid
	if tier < 1 or tier > def.maxTier then
		return false, "Invalid tier"
	end

	-- Check 3: Player must not already own this tier
	local currentTier = getPlayerTier(playerData, powerUpId)
	if currentTier >= tier then
		return false, "Already own this tier"
	end

	-- Check 4: Sequential tier enforcement (must own tier-1 first)
	if tier > 1 and currentTier < tier - 1 then
		return false, "Must purchase previous tier first"
	end

	-- Check 5: XP sufficiency
	local cost = def.costs[tier]
	if playerData.xp < cost then
		return false, "Insufficient XP"
	end

	return true, nil
end

--- Applies a power-up purchase to the player profile.
--- Deducts the cost from player XP and sets the power-up tier.
--- Returns the modified PlayerData.
---
--- NOTE: Caller should validate with canPurchase first; this function assumes valid input.
function PowerUpManager.applyPurchase(playerData: Types.PlayerProfile, powerUpId: string, tier: number): Types.PlayerProfile
	local def = findDefinition(powerUpId)
	if not def then
		return playerData
	end

	if tier < 1 or tier > def.maxTier then
		return playerData
	end

	-- Deduct cost from XP
	local cost = def.costs[tier]
	playerData.xp = playerData.xp - cost

	-- Set the power-up tier
	if powerUpId == "higherJump" then
		playerData.powerUps.higherJump = tier
	elseif powerUpId == "doubleJump" then
		playerData.powerUps.doubleJump = tier
	elseif powerUpId == "fasterSpeed" then
		playerData.powerUps.fasterSpeed = tier
	end

	return playerData
end

return PowerUpManager
