--!strict
--[[
    LeaderboardService.luau - Global leaderboard management via OrderedDataStore

    Manages real-time global rankings for XP and highest level completed.
    Uses OrderedDataStore for persistent ranking data with in-memory caching,
    batched score updates (within 5 seconds), and graceful failure handling
    with automatic retry every 10 seconds.

    Validates: Requirements 10.1, 10.2, 10.3, 10.5, 10.6
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Types = require(game:GetService("ReplicatedStorage").Types)

local LeaderboardService = {}

--============================================================================
-- Constants
--============================================================================

local UPDATE_BATCH_INTERVAL = 5 -- Seconds to batch score updates before writing
local RETRY_INTERVAL = 10 -- Seconds between retries on failure
local CACHE_DURATION = 10 -- Seconds to cache leaderboard results
local MAX_ENTRIES = 100 -- Maximum top entries to return

-- Time Attack inversion constant: OrderedDataStore only sorts ascending,
-- so we store (MAX_TIME - actual_time) to rank lowest times first.
local MAX_TIME = 999999 -- Maximum time value for inversion (seconds)

--============================================================================
-- State
--============================================================================

-- OrderedDataStore references (lazy-initialized)
local xpDataStore: OrderedDataStore? = nil
local levelDataStore: OrderedDataStore? = nil

-- Pending score updates waiting to be flushed (batched within 5s)
local pendingXPUpdates: { [number]: number } = {} -- userId -> totalXP
local pendingLevelUpdates: { [number]: number } = {} -- userId -> highestLevel

-- Cached leaderboard results
local cachedTopXP: { Types.LeaderboardEntry } = {}
local cachedTopLevel: { Types.LeaderboardEntry } = {}
local lastXPFetchTime: number = 0
local lastLevelFetchTime: number = 0

-- Availability tracking for graceful failure display
local xpBoardAvailable: boolean = true
local levelBoardAvailable: boolean = true

-- Mode-specific leaderboard state
-- Cached OrderedDataStore references keyed by "Leaderboard_{modeId}_{packId}"
local modeDataStores: { [string]: OrderedDataStore } = {}

-- Pending mode score updates: key -> { userId -> score }
local pendingModeUpdates: { [string]: { [number]: number } } = {}

-- Cached mode leaderboard results: key -> { entries, fetchTime }
local cachedModeBoards: { [string]: { entries: { Types.LeaderboardEntry }, fetchTime: number } } = {}

-- Whether the update loop is running
local updateLoopRunning: boolean = false

--============================================================================
-- Private Helpers
--============================================================================

--- Lazily initialize the XP OrderedDataStore.
local function getXPDataStore(): OrderedDataStore?
	if xpDataStore then
		return xpDataStore
	end
	local success, store = pcall(function()
		return DataStoreService:GetOrderedDataStore("Leaderboard_XP")
	end)
	if success then
		xpDataStore = store
		return store
	end
	warn("[LeaderboardService] Failed to get XP OrderedDataStore: " .. tostring(store))
	return nil
end

--- Lazily initialize the Level OrderedDataStore.
local function getLevelDataStore(): OrderedDataStore?
	if levelDataStore then
		return levelDataStore
	end
	local success, store = pcall(function()
		return DataStoreService:GetOrderedDataStore("Leaderboard_Level")
	end)
	if success then
		levelDataStore = store
		return store
	end
	warn("[LeaderboardService] Failed to get Level OrderedDataStore: " .. tostring(store))
	return nil
end

--- Safely get a player's display name from their userId.
--- Returns "Player_<userId>" as fallback if lookup fails.
local function getDisplayName(userId: number): string
	local success, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if success and name then
		return name
	end
	return "Player_" .. tostring(userId)
end

--- Get or create a mode-specific OrderedDataStore by key.
local function getModeDataStore(key: string): OrderedDataStore?
	if modeDataStores[key] then
		return modeDataStores[key]
	end
	local success, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(key)
	end)
	if success then
		modeDataStores[key] = store
		return store
	end
	warn("[LeaderboardService] Failed to get mode OrderedDataStore '" .. key .. "': " .. tostring(store))
	return nil
end

--- Flush pending XP updates to the OrderedDataStore.
local function flushXPUpdates()
	local store = getXPDataStore()
	if not store then
		xpBoardAvailable = false
		return
	end

	for userId, totalXP in pairs(pendingXPUpdates) do
		local success, err = pcall(function()
			store:SetAsync(tostring(userId), totalXP)
		end)
		if success then
			pendingXPUpdates[userId] = nil
		else
			warn("[LeaderboardService] Failed to update XP for userId " .. tostring(userId) .. ": " .. tostring(err))
			xpBoardAvailable = false
		end
	end
end

--- Flush pending Level updates to the OrderedDataStore.
local function flushLevelUpdates()
	local store = getLevelDataStore()
	if not store then
		levelBoardAvailable = false
		return
	end

	for userId, highestLevel in pairs(pendingLevelUpdates) do
		local success, err = pcall(function()
			store:SetAsync(tostring(userId), highestLevel)
		end)
		if success then
			pendingLevelUpdates[userId] = nil
		else
			warn("[LeaderboardService] Failed to update Level for userId " .. tostring(userId) .. ": " .. tostring(err))
			levelBoardAvailable = false
		end
	end
end

--- Flush pending mode-specific score updates to their respective OrderedDataStores.
local function flushModeUpdates()
	for key, updates in pairs(pendingModeUpdates) do
		if not next(updates) then
			continue
		end

		local store = getModeDataStore(key)
		if not store then
			continue
		end

		for userId, score in pairs(updates) do
			local success, err = pcall(function()
				store:SetAsync(tostring(userId), score)
			end)
			if success then
				updates[userId] = nil
			else
				warn("[LeaderboardService] Failed to update mode score for key '" .. key .. "' userId " .. tostring(userId) .. ": " .. tostring(err))
			end
		end

		-- Remove the key entry if all updates were flushed
		if not next(updates) then
			pendingModeUpdates[key] = nil
		end
	end
end

--- Fetch top N entries from an OrderedDataStore in descending order.
--- Returns an array of LeaderboardEntry or empty array on failure.
local function fetchTopEntries(store: OrderedDataStore?, count: number): { Types.LeaderboardEntry }
	if not store then
		return {}
	end

	local entries: { Types.LeaderboardEntry } = {}
	local success, result = pcall(function()
		return store:GetSortedAsync(false, count)
	end)

	if not success or not result then
		return {}
	end

	-- Read the first page of results
	local pageSuccess, page = pcall(function()
		return result:GetCurrentPage()
	end)

	if not pageSuccess or not page then
		return {}
	end

	for _, item in ipairs(page) do
		local userId = tonumber(item.key)
		if userId then
			local entry: Types.LeaderboardEntry = {
				userId = userId,
				displayName = getDisplayName(userId),
				value = item.value,
			}
			table.insert(entries, entry)
		end
	end

	return entries
end

--- Start the background update loop that batches writes and retries failures.
local function startUpdateLoop()
	if updateLoopRunning then
		return
	end
	updateLoopRunning = true

	task.spawn(function()
		while updateLoopRunning do
			-- Flush any pending score updates
			if next(pendingXPUpdates) then
				flushXPUpdates()
			end
			if next(pendingLevelUpdates) then
				flushLevelUpdates()
			end
			-- Flush mode-specific score updates
			if next(pendingModeUpdates) then
				flushModeUpdates()
			end

			-- If boards became unavailable, retry after RETRY_INTERVAL
			if not xpBoardAvailable then
				task.delay(RETRY_INTERVAL, function()
					-- Attempt to re-establish availability
					local store = getXPDataStore()
					if store then
						local testSuccess = pcall(function()
							store:GetSortedAsync(false, 1)
						end)
						if testSuccess then
							xpBoardAvailable = true
						end
					end
				end)
			end

			if not levelBoardAvailable then
				task.delay(RETRY_INTERVAL, function()
					local store = getLevelDataStore()
					if store then
						local testSuccess = pcall(function()
							store:GetSortedAsync(false, 1)
						end)
						if testSuccess then
							levelBoardAvailable = true
						end
					end
				end)
			end

			task.wait(UPDATE_BATCH_INTERVAL)
		end
	end)
end

--============================================================================
-- Public API
--============================================================================

export type LeaderboardService = {
	updateXPScore: (userId: number, totalXP: number) -> (),
	updateLevelScore: (userId: number, highestLevel: number) -> (),
	getTopXP: (count: number) -> { Types.LeaderboardEntry },
	getTopLevel: (count: number) -> { Types.LeaderboardEntry },
	getPlayerRank: (userId: number, board: string) -> (number?, number?),
	getLeaderboardKey: (modeId: string, packId: string) -> string,
	updateModeScore: (userId: number, modeId: string, packId: string, score: number) -> (),
	getModeTop: (modeId: string, packId: string, count: number) -> { Types.LeaderboardEntry },
}

--- Queue an XP score update for the given player.
--- Updates are batched and flushed within 5 seconds.
function LeaderboardService.updateXPScore(userId: number, totalXP: number): ()
	pendingXPUpdates[userId] = totalXP
	startUpdateLoop()
end

--- Queue a highest-level score update for the given player.
--- Updates are batched and flushed within 5 seconds.
function LeaderboardService.updateLevelScore(userId: number, highestLevel: number): ()
	pendingLevelUpdates[userId] = highestLevel
	startUpdateLoop()
end

--- Get the top players by total XP.
--- Returns up to `count` entries (max 100). Uses cached results if fresh.
--- Returns empty array on failure (leaderboard temporarily unavailable).
function LeaderboardService.getTopXP(count: number): { Types.LeaderboardEntry }
	local clampedCount = math.min(count, MAX_ENTRIES)
	local now = tick()

	-- Return cached results if still fresh
	if now - lastXPFetchTime < CACHE_DURATION and #cachedTopXP > 0 then
		-- Return up to the requested count from cache
		if clampedCount >= #cachedTopXP then
			return cachedTopXP
		end
		local subset: { Types.LeaderboardEntry } = {}
		for i = 1, clampedCount do
			table.insert(subset, cachedTopXP[i])
		end
		return subset
	end

	local store = getXPDataStore()
	local entries = fetchTopEntries(store, clampedCount)

	if #entries > 0 then
		cachedTopXP = entries
		lastXPFetchTime = now
		xpBoardAvailable = true
	else
		xpBoardAvailable = false
	end

	return entries
end

--- Get the top players by highest level completed.
--- Returns up to `count` entries (max 100). Uses cached results if fresh.
--- Returns empty array on failure (leaderboard temporarily unavailable).
function LeaderboardService.getTopLevel(count: number): { Types.LeaderboardEntry }
	local clampedCount = math.min(count, MAX_ENTRIES)
	local now = tick()

	-- Return cached results if still fresh
	if now - lastLevelFetchTime < CACHE_DURATION and #cachedTopLevel > 0 then
		if clampedCount >= #cachedTopLevel then
			return cachedTopLevel
		end
		local subset: { Types.LeaderboardEntry } = {}
		for i = 1, clampedCount do
			table.insert(subset, cachedTopLevel[i])
		end
		return subset
	end

	local store = getLevelDataStore()
	local entries = fetchTopEntries(store, clampedCount)

	if #entries > 0 then
		cachedTopLevel = entries
		lastLevelFetchTime = now
		levelBoardAvailable = true
	else
		levelBoardAvailable = false
	end

	return entries
end

--- Get the player's rank and score on the specified board.
--- @param userId The player's Roblox user ID
--- @param board Either "xp" or "level"
--- @return rank (1-based position, nil if unavailable), value (score, nil if unavailable)
function LeaderboardService.getPlayerRank(userId: number, board: string): (number?, number?)
	local store: OrderedDataStore? = nil
	if board == "xp" then
		store = getXPDataStore()
	elseif board == "level" then
		store = getLevelDataStore()
	else
		warn("[LeaderboardService] Invalid board name: " .. tostring(board) .. ". Use 'xp' or 'level'.")
		return nil, nil
	end

	if not store then
		return nil, nil
	end

	-- Get the player's score value
	local valueSuccess, playerValue = pcall(function()
		return store:GetAsync(tostring(userId))
	end)

	if not valueSuccess or playerValue == nil then
		return nil, nil
	end

	-- Determine rank by fetching sorted entries and finding player position
	-- For efficiency, we use the cached top entries first
	local cachedEntries: { Types.LeaderboardEntry }
	if board == "xp" then
		cachedEntries = cachedTopXP
	else
		cachedEntries = cachedTopLevel
	end

	-- Check if the player is in the cached top entries
	for rank, entry in ipairs(cachedEntries) do
		if entry.userId == userId then
			return rank, playerValue
		end
	end

	-- Player not in top cached entries; calculate approximate rank
	-- by counting entries with higher scores via a sorted query
	local rankSuccess, rankResult = pcall(function()
		-- Get all entries with value > playerValue (those ranked above the player)
		-- OrderedDataStore GetSortedAsync(false, ...) returns descending order
		-- We count how many entries have a higher value
		local pages = store:GetSortedAsync(false, MAX_ENTRIES)
		local page = pages:GetCurrentPage()
		local rank = 1
		for _, item in ipairs(page) do
			if item.value > playerValue then
				rank = rank + 1
			end
		end
		-- If player's value is not in the top MAX_ENTRIES but we exhausted the page,
		-- the rank is at least MAX_ENTRIES + 1
		if #page == MAX_ENTRIES then
			local lastValue = page[#page].value
			if playerValue < lastValue then
				-- Player is beyond the top 100, approximate rank
				rank = MAX_ENTRIES + 1
			end
		end
		return rank
	end)

	if rankSuccess and rankResult then
		return rankResult, playerValue
	end

	-- Fallback: return just the value without rank
	return nil, playerValue
end

--============================================================================
-- Mode-Specific Leaderboard API
--============================================================================

--- Returns the OrderedDataStore key for a mode-specific leaderboard.
--- Format: "Leaderboard_{modeId}_{packId}"
--- @param modeId string -- The game mode id (e.g., "time_attack", "sprint")
--- @param packId string -- The pack id (e.g., "tetris", "pipeworld")
--- @return string -- The formatted key
function LeaderboardService.getLeaderboardKey(modeId: string, packId: string): string
	return "Leaderboard_" .. modeId .. "_" .. packId
end

--- Queue a mode-specific score update for the given player.
--- For Time Attack: score should be time in seconds (lower = better).
---   The value is inverted (MAX_TIME - score) for ascending-sort OrderedDataStore.
--- For Sprint: score should be distance in blocks (higher = better). Stored directly.
---
--- @param userId number -- Player's Roblox user ID
--- @param modeId string -- The game mode id (e.g., "time_attack", "sprint")
--- @param packId string -- The pack id (e.g., "tetris", "pipeworld")
--- @param score number -- The raw score to store
function LeaderboardService.updateModeScore(userId: number, modeId: string, packId: string, score: number): ()
	local key = LeaderboardService.getLeaderboardKey(modeId, packId)

	-- Invert score for Time Attack (lower time = higher stored value = better rank)
	local storedValue: number
	if modeId == "time_attack" then
		storedValue = MAX_TIME - math.floor(score)
	else
		-- Sprint and any other modes: higher score = better, store directly
		storedValue = math.floor(score)
	end

	-- Queue the update
	if not pendingModeUpdates[key] then
		pendingModeUpdates[key] = {}
	end
	pendingModeUpdates[key][userId] = storedValue
	startUpdateLoop()
end

--- Get the top entries for a mode-specific leaderboard.
--- Returns entries with the raw score (un-inverted for Time Attack).
---
--- @param modeId string -- The game mode id
--- @param packId string -- The pack id
--- @param count number -- Number of top entries to fetch
--- @return {LeaderboardEntry} -- Array of leaderboard entries (value = actual score)
function LeaderboardService.getModeTop(modeId: string, packId: string, count: number): { Types.LeaderboardEntry }
	local key = LeaderboardService.getLeaderboardKey(modeId, packId)
	local clampedCount = math.min(count, MAX_ENTRIES)
	local now = tick()

	-- Check cache
	local cached = cachedModeBoards[key]
	if cached and (now - cached.fetchTime) < CACHE_DURATION and #cached.entries > 0 then
		if clampedCount >= #cached.entries then
			return cached.entries
		end
		local subset: { Types.LeaderboardEntry } = {}
		for i = 1, clampedCount do
			table.insert(subset, cached.entries[i])
		end
		return subset
	end

	-- Fetch from DataStore (descending = highest stored value first)
	local store = getModeDataStore(key)
	local rawEntries = fetchTopEntries(store, clampedCount)

	-- Un-invert scores for Time Attack mode
	local entries: { Types.LeaderboardEntry } = {}
	for _, entry in rawEntries do
		local displayValue = entry.value
		if modeId == "time_attack" then
			displayValue = MAX_TIME - entry.value
		end
		table.insert(entries, {
			userId = entry.userId,
			displayName = entry.displayName,
			value = displayValue,
		})
	end

	-- Cache the result
	if #entries > 0 then
		cachedModeBoards[key] = { entries = entries, fetchTime = now }
	end

	return entries
end

return LeaderboardService
