--!strict
--[[
    ValidationService.luau - Server-side validation for all state-changing requests

    Validates power-up purchases, level completion claims, XP claims, and
    pack unlock status. Rejects invalid requests with descriptive error messages.

    Validates: Requirements 2.6, 7.3, 7.4, 13.3, 13.5
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Types)
local PowerUpManager = require(ReplicatedStorage.PowerUpManager)
local DataStoreManager = require(ServerScriptService.DataStoreManager)
local PackRegistry = require(ServerScriptService.PackRegistry)

local ValidationService = {}

--============================================================================
-- Constants
--============================================================================

local LEVELS_PER_PACK = 10
local LEVEL_LENGTH = Types.LEVEL_LENGTH -- 500 blocks
local MAX_XP_MULTIPLIER = 20 -- Reasonable upper bound for pack multiplier
local MAX_THEORETICAL_XP_PER_LEVEL = LEVEL_LENGTH * MAX_XP_MULTIPLIER + Types.LEVEL_COMPLETION_BONUS

--============================================================================
-- Type Export
--============================================================================

export type ValidationService = {
	validatePurchase: (player: Player, powerUpId: string, tier: number) -> (boolean, string?),
	validateLevelCompletion: (player: Player, packId: string, levelNum: number) -> (boolean, string?),
	validateXPClaim: (player: Player, amount: number) -> (boolean, string?),
	isPackUnlocked: (playerData: Types.PlayerProfile, packId: string) -> boolean,
}

--============================================================================
-- Internal Helpers
--============================================================================

--- Retrieves the player's cached profile from DataStoreManager.
--- Returns the profile or nil if no data is available.
local function getPlayerProfile(player: Player): Types.PlayerProfile?
	return DataStoreManager.getCachedData(player.UserId)
end

--============================================================================
-- Public API
--============================================================================

--- Validates whether a player can purchase a specific power-up at a given tier.
--- Delegates core logic to PowerUpManager.canPurchase after retrieving the player's
--- cached profile data.
---
--- Checks performed:
--- 1. Player profile must be available (loaded/cached)
--- 2. Power-up must exist
--- 3. Tier must be valid for the power-up
--- 4. Player must own the previous tier (sequential enforcement)
--- 5. Player must have sufficient XP
---
--- @param player Player -- The player requesting the purchase
--- @param powerUpId string -- The power-up identifier (e.g., "higherJump")
--- @param tier number -- The tier to purchase (1-based)
--- @return (boolean, string?) -- (true, nil) if valid; (false, errorMessage) if rejected
function ValidationService.validatePurchase(player: Player, powerUpId: string, tier: number): (boolean, string?)
	-- Retrieve the player's profile from cache
	local profile = getPlayerProfile(player)
	if not profile then
		return false, "ERR_NO_PROFILE: Player data not loaded"
	end

	-- Validate input types for safety
	if type(powerUpId) ~= "string" or powerUpId == "" then
		return false, "ERR_INVALID_INPUT: Power-up ID must be a non-empty string"
	end

	if type(tier) ~= "number" or tier ~= math.floor(tier) or tier < 1 then
		return false, "ERR_INVALID_INPUT: Tier must be a positive integer"
	end

	-- Delegate to PowerUpManager for comprehensive validation
	local canBuy, errorMsg = PowerUpManager.canPurchase(profile, powerUpId, tier)
	if not canBuy then
		-- Map PowerUpManager errors to descriptive error codes
		if errorMsg == "Invalid power-up ID" then
			return false, "ERR_INVALID_POWERUP: Power-up '" .. powerUpId .. "' does not exist"
		elseif errorMsg == "Invalid tier" then
			return false, "ERR_INVALID_TIER: Tier " .. tostring(tier) .. " is not valid for '" .. powerUpId .. "'"
		elseif errorMsg == "Already own this tier" then
			return false, "ERR_ALREADY_OWNED: Already own tier " .. tostring(tier) .. " of '" .. powerUpId .. "'"
		elseif errorMsg == "Must purchase previous tier first" then
			return false, "ERR_TIER_SEQUENCE: Must purchase tier " .. tostring(tier - 1) .. " before tier " .. tostring(tier)
		elseif errorMsg == "Insufficient XP" then
			local cost = PowerUpManager.getCost(powerUpId, tier)
			local shortfall = (cost or 0) - profile.xp
			return false, "ERR_INSUFFICIENT_XP: Need " .. tostring(shortfall) .. " more XP"
		else
			return false, "ERR_PURCHASE_REJECTED: " .. (errorMsg or "Unknown error")
		end
	end

	return true, nil
end

--- Validates whether a level completion claim is legitimate.
--- Checks that the player is actually in the claimed pack/level, that the
--- level number is valid (1-10), and that the player's position indicates
--- they reached the end of the level (Z >= 1000).
---
--- @param player Player -- The player claiming completion
--- @param packId string -- The pack ID being claimed
--- @param levelNum number -- The level number being claimed (1-10)
--- @return (boolean, string?) -- (true, nil) if valid; (false, errorMessage) if rejected
function ValidationService.validateLevelCompletion(player: Player, packId: string, levelNum: number): (boolean, string?)
	-- Validate input types
	if type(packId) ~= "string" or packId == "" then
		return false, "ERR_INVALID_INPUT: Pack ID must be a non-empty string"
	end

	if type(levelNum) ~= "number" or levelNum ~= math.floor(levelNum) then
		return false, "ERR_INVALID_INPUT: Level number must be an integer"
	end

	-- Validate level number range (1-10)
	if levelNum < 1 or levelNum > LEVELS_PER_PACK then
		return false, "ERR_INVALID_LEVEL: Level number must be between 1 and " .. tostring(LEVELS_PER_PACK)
	end

	-- Validate that the pack exists in the registry
	if not PackRegistry.hasPack(packId) then
		return false, "ERR_INVALID_PACK: Pack '" .. packId .. "' does not exist"
	end

	-- Validate pack is unlocked for the player
	local profile = getPlayerProfile(player)
	if profile then
		if not ValidationService.isPackUnlocked(profile, packId) then
			return false, "ERR_PACK_LOCKED: Pack '" .. packId .. "' is not unlocked"
		end
	end

	-- Validate player position (must have reached the end of the level)
	local character = player.Character
	if not character then
		return false, "ERR_NO_CHARACTER: Player character not found"
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoidRootPart then
		return false, "ERR_NO_CHARACTER: Player HumanoidRootPart not found"
	end

	local playerZ = humanoidRootPart.Position.Z
	if playerZ < LEVEL_LENGTH then
		return false, "ERR_NOT_AT_END: Player position (" .. string.format("%.1f", playerZ) .. ") has not reached the level end (" .. tostring(LEVEL_LENGTH) .. ")"
	end

	return true, nil
end

--- Validates whether an XP claim amount is reasonable.
--- Checks that the amount is positive and does not exceed the theoretical
--- maximum earnable in a single level (distance × max multiplier + completion bonus).
---
--- @param player Player -- The player claiming XP
--- @param amount number -- The XP amount being claimed
--- @return (boolean, string?) -- (true, nil) if valid; (false, errorMessage) if rejected
function ValidationService.validateXPClaim(player: Player, amount: number): (boolean, string?)
	-- Validate player profile exists
	local profile = getPlayerProfile(player)
	if not profile then
		return false, "ERR_NO_PROFILE: Player data not loaded"
	end

	-- Validate amount type
	if type(amount) ~= "number" then
		return false, "ERR_INVALID_INPUT: XP amount must be a number"
	end

	-- Amount must be positive
	if amount <= 0 then
		return false, "ERR_INVALID_AMOUNT: XP amount must be positive"
	end

	-- Amount must be a whole number (XP is always integer-based)
	if amount ~= math.floor(amount) then
		return false, "ERR_INVALID_AMOUNT: XP amount must be a whole number"
	end

	-- Amount must not exceed theoretical maximum for a single level
	-- Maximum: 1000 blocks × 20 (max pack multiplier) + 500 (completion bonus) = 20500
	if amount > MAX_THEORETICAL_XP_PER_LEVEL then
		return false, "ERR_EXCEEDS_MAX: XP amount " .. tostring(amount) .. " exceeds theoretical maximum of " .. tostring(MAX_THEORETICAL_XP_PER_LEVEL)
	end

	return true, nil
end

--- Checks if a pack is unlocked for a player based on sequential unlock logic.
--- Pack 1 (first in ordered list or with no prerequisitePack) is always unlocked.
--- Pack N requires all 10 levels of pack N-1 completed.
---
--- @param playerData PlayerProfile -- The player's profile data
--- @param packId string -- The pack ID to check
--- @return boolean -- true if the pack is unlocked for this player
function ValidationService.isPackUnlocked(playerData: Types.PlayerProfile, packId: string): boolean
	local orderedPacks = PackRegistry.getOrderedPacks()

	-- Find the index of this pack in the ordered list
	local packIndex = 0
	for i, id in orderedPacks do
		if id == packId then
			packIndex = i
			break
		end
	end

	-- If pack not found in the ordered list, check if it has no prerequisite
	if packIndex == 0 then
		local config = PackRegistry.getPackConfig(packId)
		if config and config.prerequisitePack == nil then
			return true
		end
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

return ValidationService
