--!strict
--[[
    DataStoreManager.luau - Player data persistence with in-memory caching
    
    Handles loading, saving, and caching player profiles using DataStoreService.
    Implements retry logic, periodic auto-save, and graceful shutdown flushing.
    
    Validates: Requirements 11.1, 11.2, 11.3, 11.4, 11.5
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Types = require(game:GetService("ReplicatedStorage").Types)

local DataStoreManager = {}

--============================================================================
-- Constants
--============================================================================

local DATA_STORE_NAME = "PixelRunPlayerData"
local KEY_PREFIX = "player_"

local LOAD_RETRIES = Types.DATA_LOAD_RETRIES        -- 3
local LOAD_RETRY_DELAY = Types.DATA_LOAD_RETRY_DELAY -- 2 seconds
local SAVE_RETRIES = Types.DATA_SAVE_RETRIES        -- 3
local AUTO_SAVE_INTERVAL = Types.AUTO_SAVE_INTERVAL  -- 60 seconds

--============================================================================
-- Module State
--============================================================================

local dataStore: DataStore? = nil
local cache: {[number]: Types.PlayerProfile} = {}

--============================================================================
-- Private Helpers
--============================================================================

--- Gets or initializes the DataStore (lazy, avoids error in unpublished places).
local function getDataStore(): DataStore?
    if dataStore then
        return dataStore
    end
    local success, store = pcall(function()
        return DataStoreService:GetDataStore(DATA_STORE_NAME)
    end)
    if success then
        dataStore = store
        return store
    else
        warn("[DataStoreManager] Could not access DataStore: " .. tostring(store))
        return nil
    end
end

--- Builds the DataStore key for a given userId.
local function getKey(userId: number): string
    return KEY_PREFIX .. tostring(userId)
end

--- Deep copies a table to avoid reference sharing between cache and callers.
local function deepCopy(original: Types.PlayerProfile): Types.PlayerProfile
    local copy: any = {}
    for key, value in pairs(original :: any) do
        if type(value) == "table" then
            copy[key] = {}
            for k2, v2 in pairs(value) do
                if type(v2) == "table" then
                    local innerCopy = {}
                    for k3, v3 in pairs(v2) do
                        innerCopy[k3] = v3
                    end
                    copy[key][k2] = innerCopy
                else
                    copy[key][k2] = v2
                end
            end
        else
            copy[key] = value
        end
    end
    return copy :: Types.PlayerProfile
end

--============================================================================
-- Public Interface
--============================================================================

export type DataStoreManager = {
    loadPlayerData: (userId: number) -> (Types.PlayerProfile?, string?),
    savePlayerData: (userId: number, data: Types.PlayerProfile) -> (boolean, string?),
    getCachedData: (userId: number) -> Types.PlayerProfile?,
    startAutoSave: () -> (),
    flushAll: () -> (),
}

--- Loads player data from DataStoreService with retry logic.
--- On success, stores the profile in the in-memory cache.
--- On failure after all retries, returns nil and the error message.
--- The caller should use Types.DEFAULT_PLAYER_PROFILE as fallback.
function DataStoreManager.loadPlayerData(userId: number): (Types.PlayerProfile?, string?)
    local key = getKey(userId)
    local lastError: string? = nil

    for attempt = 1, LOAD_RETRIES do
        local store = getDataStore()
        if not store then
            -- DataStore unavailable (unpublished place) — return default profile
            local defaultProfile = deepCopy(Types.DEFAULT_PLAYER_PROFILE)
            cache[userId] = defaultProfile
            return defaultProfile, nil
        end

        local success, result = pcall(function()
            return store:GetAsync(key)
        end)

        if success then
            if result == nil then
                -- New player: use default profile
                local defaultProfile = deepCopy(Types.DEFAULT_PLAYER_PROFILE)
                cache[userId] = defaultProfile
                return defaultProfile, nil
            else
                -- Existing player: cache and return
                local profile = result :: Types.PlayerProfile
                cache[userId] = profile
                return profile, nil
            end
        else
            lastError = tostring(result)
            warn(string.format(
                "[DataStoreManager] Load attempt %d/%d failed for userId %d: %s",
                attempt, LOAD_RETRIES, userId, lastError :: string
            ))

            if attempt < LOAD_RETRIES then
                task.wait(LOAD_RETRY_DELAY)
            end
        end
    end

    -- All retries exhausted — return nil with error.
    -- GameServer should spawn with default profile as fallback.
    warn(string.format(
        "[DataStoreManager] All load retries exhausted for userId %d. Last error: %s",
        userId, lastError or "unknown"
    ))
    return nil, lastError
end

--- Saves player data to DataStoreService with retry logic (immediate retries).
--- Returns success boolean and optional error message.
function DataStoreManager.savePlayerData(userId: number, data: Types.PlayerProfile): (boolean, string?)
    local key = getKey(userId)
    local lastError: string? = nil

    -- Update cache before saving
    cache[userId] = data

    for attempt = 1, SAVE_RETRIES do
        local store = getDataStore()
        if not store then
            -- DataStore unavailable — data stays in memory cache only
            return false, "DataStore not available (place not published)"
        end

        local success, result = pcall(function()
            store:SetAsync(key, data)
        end)

        if success then
            return true, nil
        else
            lastError = tostring(result)
            warn(string.format(
                "[DataStoreManager] Save attempt %d/%d failed for userId %d: %s",
                attempt, SAVE_RETRIES, userId, lastError :: string
            ))
            -- Immediate retries on save (no delay)
        end
    end

    warn(string.format(
        "[DataStoreManager] All save retries exhausted for userId %d. Last error: %s",
        userId, lastError or "unknown"
    ))
    return false, lastError
end

--- Returns the cached player profile for a given userId, or nil if not loaded.
function DataStoreManager.getCachedData(userId: number): Types.PlayerProfile?
    return cache[userId]
end

--- Starts the auto-save loop that persists all cached profiles every 60 seconds.
--- Should be called once during server initialization.
function DataStoreManager.startAutoSave(): ()
    task.spawn(function()
        while true do
            task.wait(AUTO_SAVE_INTERVAL)

            for userId, profileData in pairs(cache) do
                -- Only save if the player is still in the game
                local player = Players:GetPlayerByUserId(userId)
                if player then
                    local success, err = DataStoreManager.savePlayerData(userId, profileData)
                    if not success then
                        warn(string.format(
                            "[DataStoreManager] Auto-save failed for userId %d: %s",
                            userId, err or "unknown"
                        ))
                    end
                end
            end
        end
    end)
end

--- Saves all cached profiles immediately. Called on server shutdown (BindToClose).
function DataStoreManager.flushAll(): ()
    for userId, profileData in pairs(cache) do
        local success, err = DataStoreManager.savePlayerData(userId, profileData)
        if not success then
            warn(string.format(
                "[DataStoreManager] flushAll failed for userId %d: %s",
                userId, err or "unknown"
            ))
        end
    end
end

--============================================================================
-- Event Wiring
--============================================================================

--- Save and clean up cache when a player leaves.
Players.PlayerRemoving:Connect(function(player: Player)
    local userId = player.UserId
    local profileData = cache[userId]

    if profileData then
        local success, err = DataStoreManager.savePlayerData(userId, profileData)
        if not success then
            warn(string.format(
                "[DataStoreManager] Save on PlayerRemoving failed for userId %d: %s",
                userId, err or "unknown"
            ))
        end
        -- Remove from cache after save attempt
        cache[userId] = nil
    end
end)

--- Flush all cached data on server shutdown.
game:BindToClose(function()
    DataStoreManager.flushAll()
end)

return DataStoreManager
