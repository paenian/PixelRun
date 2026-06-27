--!strict
--[[
    AchievementService.luau - Achievement tracking and awarding for Pixel Run Obby

    Manages player achievements awarded on pack completion:
    - checkPackCompletion: Checks if a player has completed all 10 levels of a pack
      and awards the pack's achievement if not already owned.
    - awardAchievement: Awards an achievement (idempotent), fires client event for
      effects display, persists via DataStoreManager with retry logic.
    - getPlayerAchievements: Returns the list of achievement IDs a player has earned.

    Architecture:
    - In-memory achievement tracking per userId (module-level table)
    - Fires "AchievementAwarded" RemoteEvent to trigger client-side EffectsManager
    - Persistence via DataStoreManager.savePlayerData (up to 3 retries)
    - DataStoreManager is still a stub in Epoch 3, so persistence calls may no-op

    Validates: Requirements 8.1, 8.2, 8.3, 8.4, 8.5, 8.6
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataStoreManager = require(ServerScriptService.DataStoreManager)

local AchievementService = {}

export type AchievementService = {
	checkPackCompletion: (player: Player, packId: string) -> (),
	awardAchievement: (player: Player, achievementId: string) -> (),
	getPlayerAchievements: (player: Player) -> { string },
}

--============================================================================
-- Constants
--============================================================================

local LEVELS_PER_PACK = 10
local MAX_SAVE_RETRIES = 3
local ACHIEVEMENT_DISPLAY_DURATION = 4 -- seconds (within 3-5s range per Req 8.4)

--============================================================================
-- In-Memory State
--============================================================================

--- Tracks achievements per userId. Each entry is a list of achievement IDs.
local playerAchievements: { [number]: { string } } = {}

--- Tracks level completions per userId per packId, for use when DataStoreManager
--- cache is unavailable (Epoch 3). GameServer can pass completion data via
--- setPlayerCompletions().
local playerCompletions: { [number]: { [string]: { number } } } = {}

--============================================================================
-- Helper Functions
--============================================================================

--- Gets or initializes the achievements list for a player.
local function getOrCreateAchievementList(userId: number): { string }
	if not playerAchievements[userId] then
		playerAchievements[userId] = {}
	end
	return playerAchievements[userId]
end

--- Checks if a player already has a specific achievement.
local function hasAchievement(userId: number, achievementId: string): boolean
	local achievements = getOrCreateAchievementList(userId)
	for _, id in achievements do
		if id == achievementId then
			return true
		end
	end
	return false
end

--- Loads the pack config for a given packId from ReplicatedStorage.LevelPacks.
--- Returns the LevelPackConfig module table or nil if not found.
local function getPackConfig(packId: string): any?
	local levelPacks = ReplicatedStorage:FindFirstChild("LevelPacks")
	if not levelPacks then
		warn("[AchievementService] LevelPacks folder not found in ReplicatedStorage")
		return nil
	end

	local packModule = levelPacks:FindFirstChild(packId)
	if not packModule then
		warn("[AchievementService] Pack module not found: " .. packId)
		return nil
	end

	local success, config = pcall(function()
		return require(packModule :: ModuleScript)
	end)

	if not success then
		warn("[AchievementService] Failed to require pack module: " .. packId .. " - " .. tostring(config))
		return nil
	end

	return config
end

--- Gets the "AchievementAwarded" RemoteEvent from ReplicatedStorage.
--- Creates it if it doesn't exist yet.
local function getAchievementRemoteEvent(): RemoteEvent?
	local eventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "RemoteEvents"
		eventsFolder.Parent = ReplicatedStorage
	end

	local event = eventsFolder:FindFirstChild("AchievementAwarded") :: RemoteEvent?
	if not event then
		local newEvent = Instance.new("RemoteEvent")
		newEvent.Name = "AchievementAwarded"
		newEvent.Parent = eventsFolder
		event = newEvent
	end

	return event
end

--- Persists player achievements via DataStoreManager with retry logic.
--- Retries up to MAX_SAVE_RETRIES times. Logs warning on failure.
local function persistAchievements(player: Player): boolean
	local userId = player.UserId
	local achievements = getOrCreateAchievementList(userId)

	-- Build a PlayerProfile-like structure for DataStoreManager
	-- First try to get cached data from DataStoreManager
	local cachedData = DataStoreManager.getCachedData(userId)

	if cachedData then
		-- Update the achievements field in the cached data
		cachedData.achievements = achievements
	else
		-- If no cached data exists, we can't reliably persist
		-- (DataStoreManager stub returns nil, which is expected in Epoch 3)
		return false
	end

	-- Attempt save with retry logic
	for attempt = 1, MAX_SAVE_RETRIES do
		local success, errorMsg = DataStoreManager.savePlayerData(userId, cachedData)
		if success then
			return true
		end

		if attempt < MAX_SAVE_RETRIES then
			-- Brief wait before retry
			task.wait(0.5)
		else
			warn(
				string.format(
					"[AchievementService] Failed to persist achievements for player %s (userId: %d) after %d retries: %s",
					player.Name,
					userId,
					MAX_SAVE_RETRIES,
					tostring(errorMsg)
				)
			)
		end
	end

	return false
end

--============================================================================
-- Public API
--============================================================================

--- Checks if a player has completed all 10 levels of a pack.
--- If so, awards the pack's achievement (if not already earned).
---
--- @param player Player - The player to check
--- @param packId string - The Level Pack ID (e.g., "TetrisPack")
function AchievementService.checkPackCompletion(player: Player, packId: string): ()
	-- Load the pack config to get the achievementName
	local packConfig = getPackConfig(packId)
	if not packConfig then
		return
	end

	local achievementName = packConfig.achievementName
	if not achievementName or achievementName == "" then
		warn("[AchievementService] Pack has no achievementName: " .. packId)
		return
	end

	-- Check if the player already has this achievement
	local userId = player.UserId
	if hasAchievement(userId, achievementName) then
		return -- Already awarded, nothing to do (idempotent)
	end

	-- Check if all 10 levels are completed for this pack
	-- Try DataStoreManager cache first, then fall back to in-memory completions
	local completions: { number }? = nil

	local cachedData = DataStoreManager.getCachedData(userId)
	if cachedData and cachedData.completions then
		completions = cachedData.completions[packId]
	end

	-- Fallback: use in-memory completions (set by GameServer via setPlayerCompletions)
	if not completions and playerCompletions[userId] then
		completions = playerCompletions[userId][packId]
	end

	-- If no completions found, the player hasn't completed the pack
	if not completions then
		return
	end

	-- Verify all 10 levels are in the completions list
	local completedCount = 0
	local completedLevels: { [number]: boolean } = {}

	for _, levelNum in completions do
		if levelNum >= 1 and levelNum <= LEVELS_PER_PACK then
			completedLevels[levelNum] = true
		end
	end

	for i = 1, LEVELS_PER_PACK do
		if completedLevels[i] then
			completedCount += 1
		end
	end

	if completedCount >= LEVELS_PER_PACK then
		-- All 10 levels completed — award the achievement
		AchievementService.awardAchievement(player, achievementName)
	end
end

--- Awards an achievement to a player.
--- Idempotent: does nothing if the player already has the achievement.
--- Fires "AchievementAwarded" RemoteEvent to the client for effects display.
--- Persists via DataStoreManager with up to 3 retries.
---
--- @param player Player - The player to award
--- @param achievementId string - The unique achievement identifier
function AchievementService.awardAchievement(player: Player, achievementId: string): ()
	local userId = player.UserId

	-- Idempotent: check if player already has this achievement
	if hasAchievement(userId, achievementId) then
		return
	end

	-- Add achievement to in-memory list
	local achievements = getOrCreateAchievementList(userId)
	table.insert(achievements, achievementId)

	-- Fire RemoteEvent to client to trigger EffectsManager.playAchievement()
	-- and HUDManager.showAchievement()
	local remoteEvent = getAchievementRemoteEvent()
	if remoteEvent then
		remoteEvent:FireClient(player, {
			name = achievementId,
			duration = ACHIEVEMENT_DISPLAY_DURATION,
		})
	end

	-- Persist via DataStoreManager with retry logic
	-- This may no-op in Epoch 3 since DataStoreManager is still a stub
	task.spawn(function()
		local saved = persistAchievements(player)
		if not saved then
			-- Achievement remains in memory — will be saved in next auto-save cycle
			-- or when DataStoreManager is fully implemented in Epoch 4
			warn(
				string.format(
					"[AchievementService] Achievement '%s' for player %s saved in memory only (persistence unavailable)",
					achievementId,
					player.Name
				)
			)
		end
	end)
end

--- Returns the list of achievement IDs earned by the player.
---
--- @param player Player - The player to query
--- @return {string} - List of achievement IDs
function AchievementService.getPlayerAchievements(player: Player): { string }
	local userId = player.UserId
	return getOrCreateAchievementList(userId)
end

--============================================================================
-- Player Cleanup
--============================================================================

--- Cleans up in-memory achievements when a player leaves.
--- Called externally (e.g., from GameServer) or via Players.PlayerRemoving.
function AchievementService.onPlayerLeave(player: Player): ()
	local userId = player.UserId
	-- Data should already be persisted by DataStoreManager on PlayerRemoving
	-- Clean up in-memory state
	playerAchievements[userId] = nil
	playerCompletions[userId] = nil
end

--- Initializes achievements for a player from stored data (if available).
--- Called when a player joins and their data is loaded.
function AchievementService.initPlayerAchievements(player: Player, achievements: { string }?): ()
	local userId = player.UserId
	if achievements then
		playerAchievements[userId] = table.clone(achievements)
	else
		playerAchievements[userId] = {}
	end
end

--- Updates the in-memory completions for a player.
--- Called by GameServer after recording a level completion so that
--- checkPackCompletion can access the data without DataStoreManager.
function AchievementService.setPlayerCompletions(player: Player, completions: { [string]: { number } }): ()
	local userId = player.UserId
	playerCompletions[userId] = completions
end

return AchievementService
