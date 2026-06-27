--!strict
--[[
    PackRegistry.luau - Auto-discovery and registration of Level Packs

    At server start, iterates all children of ReplicatedStorage.LevelPacks,
    attempts to require() each ModuleScript, validates the schema via
    LevelGenerator.validatePackSchema, and registers valid packs sorted
    by displayOrder. Invalid packs are logged and skipped.

    Validates: Requirements 12.2, 12.4, 12.5, 12.6
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LevelGenerator = require(ServerScriptService.LevelGenerator)
local Types = require(ReplicatedStorage.Types)

local PackRegistry = {}

--============================================================================
-- State
--============================================================================

--- Registered packs keyed by themeId.
local packs: { [string]: Types.LevelPackConfig } = {}

--- Pack IDs sorted in ascending displayOrder.
local orderedPacks: { string } = {}

--- Errors encountered during pack loading (module name -> error message).
local loadErrors: { [string]: string } = {}

--- Whether discovery has already been run.
local discoveryComplete: boolean = false

--============================================================================
-- Internal: discoverPacks
--============================================================================

--- Iterate all children of ReplicatedStorage.LevelPacks, attempt to require()
--- each ModuleScript, validate schema, and register valid packs.
local function discoverPacks()
    local levelPacksFolder = ReplicatedStorage:FindFirstChild("LevelPacks")
    if not levelPacksFolder then
        warn("[PackRegistry] CRITICAL: ReplicatedStorage.LevelPacks folder not found!")
        return
    end

    local children = levelPacksFolder:GetChildren()

    for _, child in children do
        -- Only process ModuleScripts
        if not child:IsA("ModuleScript") then
            continue
        end

        local moduleName = child.Name

        -- Attempt to require the module
        local success, result = pcall(function()
            return require(child)
        end)

        if not success then
            -- Module failed to require
            local errorMsg = "Failed to require module: " .. tostring(result)
            loadErrors[moduleName] = errorMsg
            warn("[PackRegistry] " .. errorMsg .. " (module: " .. moduleName .. ")")
            continue
        end

        -- Validate the pack schema
        local isValid, validationError = LevelGenerator.validatePackSchema(result)

        if not isValid then
            -- Schema validation failed
            local errorMsg = "Schema validation failed: " .. (validationError or "unknown error")
            loadErrors[moduleName] = errorMsg
            warn("[PackRegistry] " .. errorMsg .. " (module: " .. moduleName .. ")")
            continue
        end

        -- Valid pack: register it using themeId as the key
        local config = result :: Types.LevelPackConfig
        local packId = config.themeId
        packs[packId] = config
        table.insert(orderedPacks, packId)
    end

    -- Sort orderedPacks by displayOrder ascending
    table.sort(orderedPacks, function(a: string, b: string): boolean
        return packs[a].displayOrder < packs[b].displayOrder
    end)

    -- Log summary
    local validCount = #orderedPacks
    local errorCount = 0
    for _ in loadErrors do
        errorCount += 1
    end

    if validCount == 0 then
        warn("[PackRegistry] CRITICAL: Zero valid packs loaded! Game is unplayable.")
    else
        print("[PackRegistry] Loaded " .. tostring(validCount) .. " pack(s) successfully.")
    end

    if errorCount > 0 then
        warn("[PackRegistry] " .. tostring(errorCount) .. " pack(s) failed to load. See above for details.")
    end

    discoveryComplete = true
end

--============================================================================
-- Public API
--============================================================================

--- Initialize the PackRegistry by discovering and registering all packs.
--- Should be called once at server start.
function PackRegistry.init()
    if discoveryComplete then
        return
    end
    discoverPacks()
end

--- Get the LevelPackConfig for a given pack ID (themeId).
--- @param packId string -- The themeId of the pack
--- @return Types.LevelPackConfig? -- The config, or nil if not found
function PackRegistry.getPackConfig(packId: string): Types.LevelPackConfig?
    return packs[packId]
end

--- Get the ordered list of pack IDs sorted by displayOrder ascending.
--- @return {string} -- Array of themeId strings
function PackRegistry.getOrderedPacks(): { string }
    return orderedPacks
end

--- Get the load errors table for diagnostics.
--- @return {[string]: string} -- Map of module name -> error message
function PackRegistry.getLoadErrors(): { [string]: string }
    return loadErrors
end

--- Get the total number of registered packs.
--- @return number
function PackRegistry.getPackCount(): number
    return #orderedPacks
end

--- Check if a specific pack is registered.
--- @param packId string -- The themeId of the pack
--- @return boolean
function PackRegistry.hasPack(packId: string): boolean
    return packs[packId] ~= nil
end

--- Get all registered packs as a table keyed by themeId.
--- @return {[string]: Types.LevelPackConfig}
function PackRegistry.getAllPacks(): { [string]: Types.LevelPackConfig }
    return packs
end

return PackRegistry
