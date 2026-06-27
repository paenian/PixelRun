--!strict
--[[
    PackLoader.prop.luau - Property-based tests for LevelGenerator and Pack Loading

    Tests the following correctness properties:
    - Property 3: Obstacle Types Restricted by Level Tier
    - Property 11: One Achievement Per Pack
    - Property 15: Pack Schema Validation Correctness
    - Property 16: Pack Ordering by Display Order
    - Property 17: Invalid Packs Skipped Gracefully

    Validates: Requirements 3.4, 8.1, 12.1, 12.4, 12.5

    Since LevelGenerator and PackRegistry use Roblox services, this test
    inlines/reimplements the pure logic under test and uses TestHarness
    for randomized input generation.
]]

local TestHarness = require("../TestHarness")
local MockRoblox = require("../MockRoblox")
local Color3 = MockRoblox.Color3

--============================================================================
-- Inlined Pure Logic: Obstacle Filtering by Tier (from LevelGenerator)
--============================================================================

--- Obstacle definition for test purposes (mirrors Types.ObstacleDefinition)
type ObstacleDefinition = {
    shape: string,
    orientations: {number},
    color: any,
    maxHeight: number,
    isTouchKill: boolean,
}

--- Level difficulty config (mirrors Types.LevelDifficulty)
type LevelDifficulty = {
    obstacleDensity: number,
    maxHeight: number,
    gapWidth: number,
    voidLength: number,
    hasTouchKill: boolean,
    requiredPowerUps: {string}?,
}

--- Filter obstacle types based on level difficulty tier.
--- Levels 1-9 (hasTouchKill = false): exclude isTouchKill obstacles
--- Level 10 (hasTouchKill = true): all obstacle types allowed
local function filterObstaclesByTier(
    obstacleTypes: {ObstacleDefinition},
    difficultyConfig: LevelDifficulty
): {ObstacleDefinition}
    local filtered: {ObstacleDefinition} = {}

    for _, obstacle in obstacleTypes do
        local include = true
        if obstacle.isTouchKill and not difficultyConfig.hasTouchKill then
            include = false
        end
        if include then
            table.insert(filtered, obstacle)
        end
    end

    -- Fallback: if filtering removed everything, return first non-touchkill obstacle
    if #filtered == 0 then
        for _, obstacle in obstacleTypes do
            if not obstacle.isTouchKill then
                table.insert(filtered, obstacle)
                break
            end
        end
    end

    return filtered
end

--============================================================================
-- Inlined Pure Logic: Pack Schema Validation (from LevelGenerator)
--============================================================================

local REQUIRED_PACK_FIELDS = {
    "name",
    "displayOrder",
    "themeId",
    "obstacleTypes",
    "difficulty",
    "morassVisual",
    "achievementName",
}

--- Validate that a table conforms to the LevelPackConfig schema.
local function validatePackSchema(config: any): (boolean, string?)
    if type(config) ~= "table" then
        return false, "Config is not a table"
    end

    for _, field in REQUIRED_PACK_FIELDS do
        if (config :: any)[field] == nil then
            return false, "Missing field: " .. field
        end
    end

    -- Validate obstacleTypes is a non-empty array
    local obstacleTypes = (config :: any).obstacleTypes
    if type(obstacleTypes) ~= "table" or #obstacleTypes == 0 then
        return false, "obstacleTypes must be a non-empty array"
    end

    -- Validate difficulty is a table
    local difficulty = (config :: any).difficulty
    if type(difficulty) ~= "table" then
        return false, "difficulty must be a table"
    end

    -- Validate displayOrder is a number
    local displayOrder = (config :: any).displayOrder
    if type(displayOrder) ~= "number" then
        return false, "displayOrder must be a number"
    end

    return true, nil
end

--============================================================================
-- Inlined Pure Logic: Pack Ordering (from PackRegistry)
--============================================================================

type LevelPackConfig = {
    name: string,
    displayOrder: number,
    themeId: string,
    obstacleTypes: {ObstacleDefinition},
    difficulty: {[number]: LevelDifficulty},
    morassVisual: string,
    achievementName: string,
}

--- Sort pack IDs by their displayOrder ascending.
local function sortPacksByDisplayOrder(packs: {[string]: LevelPackConfig}): {string}
    local orderedPacks: {string} = {}
    for id, _ in packs do
        table.insert(orderedPacks, id)
    end
    table.sort(orderedPacks, function(a: string, b: string): boolean
        return packs[a].displayOrder < packs[b].displayOrder
    end)
    return orderedPacks
end

--============================================================================
-- Inlined Pure Logic: Pack Registration with Validation (from PackRegistry)
--============================================================================

type RegistryResult = {
    validPacks: {[string]: LevelPackConfig},
    orderedPacks: {string},
    loadErrors: {[string]: string},
}

--- Simulate pack registry: validate configs and register valid ones.
local function registerPacks(configs: {[string]: any}): RegistryResult
    local validPacks: {[string]: LevelPackConfig} = {}
    local orderedPacks: {string} = {}
    local loadErrors: {[string]: string} = {}

    for moduleName, config in configs do
        local isValid, validationError = validatePackSchema(config)
        if not isValid then
            loadErrors[moduleName] = "Schema validation failed: " .. (validationError or "unknown error")
        else
            local packConfig = config :: LevelPackConfig
            local packId = packConfig.themeId
            validPacks[packId] = packConfig
            table.insert(orderedPacks, packId)
        end
    end

    -- Sort orderedPacks by displayOrder ascending
    table.sort(orderedPacks, function(a: string, b: string): boolean
        return validPacks[a].displayOrder < validPacks[b].displayOrder
    end)

    return {
        validPacks = validPacks,
        orderedPacks = orderedPacks,
        loadErrors = loadErrors,
    }
end

--============================================================================
-- Test Generators
--============================================================================

local SHAPES = {"I", "O", "T", "S", "Z", "L", "J", "Block", "Spike", "Wall"}

--- Generate a random obstacle definition.
local function generateObstacle(rng: any, forceTouchKill: boolean?): ObstacleDefinition
    local isTouchKill = if forceTouchKill ~= nil then forceTouchKill else TestHarness.randomBool(rng)
    return {
        shape = TestHarness.randomChoice(rng, SHAPES),
        orientations = {0, 90, 180, 270},
        color = Color3.fromRGB(
            TestHarness.randomInt(rng, 0, 255),
            TestHarness.randomInt(rng, 0, 255),
            TestHarness.randomInt(rng, 0, 255)
        ),
        maxHeight = TestHarness.randomInt(rng, 1, 10),
        isTouchKill = isTouchKill,
    }
end

--- Generate a random difficulty config for a given level number.
local function generateDifficultyConfig(rng: any, levelNum: number): LevelDifficulty
    local hasTouchKill = (levelNum == 10)
    return {
        obstacleDensity = TestHarness.randomFloat(rng, 0.02, 0.10),
        maxHeight = TestHarness.randomInt(rng, 3, 5),
        gapWidth = if levelNum >= 4 then TestHarness.randomInt(rng, 1, 3) else 0,
        voidLength = if levelNum >= 7 then TestHarness.randomInt(rng, 1, 5) else 0,
        hasTouchKill = hasTouchKill,
        requiredPowerUps = nil,
    }
end

--- Generate a valid pack config with the given themeId and displayOrder.
local function generateValidPackConfig(rng: any, themeId: string, displayOrder: number): LevelPackConfig
    local numObstacles = TestHarness.randomInt(rng, 2, 7)
    local obstacles: {ObstacleDefinition} = {}
    -- Ensure at least one non-touchKill obstacle
    table.insert(obstacles, generateObstacle(rng, false))
    -- Add remaining obstacles with random touchKill status
    for _ = 2, numObstacles do
        table.insert(obstacles, generateObstacle(rng, nil))
    end

    local difficulty: {[number]: LevelDifficulty} = {}
    for level = 1, 10 do
        difficulty[level] = generateDifficultyConfig(rng, level)
    end

    return {
        name = "Pack_" .. themeId,
        displayOrder = displayOrder,
        themeId = themeId,
        obstacleTypes = obstacles,
        difficulty = difficulty,
        morassVisual = TestHarness.randomChoice(rng, {"rolling_blocks", "lava_flow", "shadow_wall", "ice_wave"}),
        achievementName = "Achievement_" .. themeId,
    }
end

--============================================================================
-- Property 3: Obstacle Types Restricted by Level Tier
-- For levels 1-9 (hasTouchKill = false): no isTouchKill obstacles in result
-- For level 10 (hasTouchKill = true): touchKill obstacles ARE allowed
--
-- Validates: Requirements 3.4
--============================================================================

print("\n=== Property 3: Obstacle Types Restricted by Level Tier ===")

TestHarness.property("Levels 1-9 exclude isTouchKill obstacles", 100, function(rng)
    -- Generate a mix of obstacles, some with isTouchKill = true
    local numObstacles = TestHarness.randomInt(rng, 2, 10)
    local obstacles: {ObstacleDefinition} = {}
    -- Ensure we have both touchKill and non-touchKill obstacles
    table.insert(obstacles, generateObstacle(rng, false))  -- at least one non-touchKill
    table.insert(obstacles, generateObstacle(rng, true))   -- at least one touchKill
    for _ = 3, numObstacles do
        table.insert(obstacles, generateObstacle(rng, nil))
    end

    -- Pick a random level from 1-9
    local levelNum = TestHarness.randomInt(rng, 1, 9)
    local diffConfig = generateDifficultyConfig(rng, levelNum)

    -- Filter obstacles
    local filtered = filterObstaclesByTier(obstacles, diffConfig)

    -- Verify: no isTouchKill obstacles in the filtered result
    for _, obs in filtered do
        if obs.isTouchKill then
            return false, string.format(
                "Level %d (hasTouchKill=%s): found isTouchKill obstacle '%s' in filtered result",
                levelNum, tostring(diffConfig.hasTouchKill), obs.shape
            )
        end
    end

    -- Verify filtered is non-empty
    if #filtered == 0 then
        return false, string.format("Level %d: filtered result is empty", levelNum)
    end

    return true, nil
end)

TestHarness.property("Level 10 allows isTouchKill obstacles", 100, function(rng)
    -- Generate obstacles with at least one touchKill
    local numObstacles = TestHarness.randomInt(rng, 2, 10)
    local obstacles: {ObstacleDefinition} = {}
    table.insert(obstacles, generateObstacle(rng, false))
    table.insert(obstacles, generateObstacle(rng, true))
    for _ = 3, numObstacles do
        table.insert(obstacles, generateObstacle(rng, nil))
    end

    -- Level 10 difficulty config
    local diffConfig = generateDifficultyConfig(rng, 10)

    -- Filter obstacles
    local filtered = filterObstaclesByTier(obstacles, diffConfig)

    -- Verify: all original obstacles should be present (nothing excluded)
    if #filtered ~= #obstacles then
        return false, string.format(
            "Level 10: expected %d obstacles (all allowed), got %d",
            #obstacles, #filtered
        )
    end

    return true, nil
end)

--============================================================================
-- Property 11: One Achievement Per Pack
-- Each valid pack config must contain exactly one non-empty achievementName.
--
-- Validates: Requirements 8.1
--============================================================================

print("\n=== Property 11: One Achievement Per Pack ===")

TestHarness.property("Valid pack has exactly one non-empty achievementName", 100, function(rng)
    local themeId = TestHarness.randomString(rng, 4, 12)
    local displayOrder = TestHarness.randomInt(rng, 1, 100)
    local pack = generateValidPackConfig(rng, themeId, displayOrder)

    -- Validate schema passes
    local isValid, err = validatePackSchema(pack :: any)
    if not isValid then
        return false, string.format("Generated pack failed validation: %s", tostring(err))
    end

    -- Check achievementName is a non-empty string
    if type(pack.achievementName) ~= "string" then
        return false, string.format(
            "achievementName is not a string, got %s",
            type(pack.achievementName)
        )
    end

    if #pack.achievementName == 0 then
        return false, "achievementName is empty string"
    end

    return true, nil
end)

--============================================================================
-- Property 15: Pack Schema Validation Correctness
-- Valid configs pass; missing any required field fails with "Missing field: <name>"
--
-- Validates: Requirements 12.1
--============================================================================

print("\n=== Property 15: Pack Schema Validation Correctness ===")

TestHarness.property("Complete valid config passes schema validation", 100, function(rng)
    local themeId = TestHarness.randomString(rng, 4, 12)
    local displayOrder = TestHarness.randomInt(rng, 1, 100)
    local pack = generateValidPackConfig(rng, themeId, displayOrder)

    local isValid, err = validatePackSchema(pack :: any)
    if not isValid then
        return false, string.format("Valid pack failed validation: %s", tostring(err))
    end

    return true, nil
end)

TestHarness.property("Missing any required field fails with correct error", 100, function(rng)
    local themeId = TestHarness.randomString(rng, 4, 12)
    local displayOrder = TestHarness.randomInt(rng, 1, 100)
    local pack = generateValidPackConfig(rng, themeId, displayOrder)

    -- Pick a random required field to remove
    local fieldToRemove = TestHarness.randomChoice(rng, REQUIRED_PACK_FIELDS)

    -- Create a copy of the pack as a generic table and remove one field
    local incomplete: {[string]: any} = {
        name = pack.name,
        displayOrder = pack.displayOrder,
        themeId = pack.themeId,
        obstacleTypes = pack.obstacleTypes,
        difficulty = pack.difficulty,
        morassVisual = pack.morassVisual,
        achievementName = pack.achievementName,
    }
    incomplete[fieldToRemove] = nil

    local isValid, err = validatePackSchema(incomplete)

    if isValid then
        return false, string.format(
            "Config missing '%s' should have failed validation but passed",
            fieldToRemove
        )
    end

    -- Verify error message mentions the missing field
    local expectedMsg = "Missing field: " .. fieldToRemove
    if err ~= expectedMsg then
        return false, string.format(
            "Expected error '%s', got '%s'",
            expectedMsg, tostring(err)
        )
    end

    return true, nil
end)

--============================================================================
-- Property 16: Pack Ordering by Display Order
-- For any set of valid packs with distinct displayOrder, sorting by
-- displayOrder produces ascending order.
--
-- Validates: Requirements 12.4
--============================================================================

print("\n=== Property 16: Pack Ordering by Display Order ===")

TestHarness.property("orderedPacks sorted in ascending displayOrder", 100, function(rng)
    -- Generate 2-10 packs with distinct displayOrder values
    local numPacks = TestHarness.randomInt(rng, 2, 10)

    -- Generate distinct displayOrder values by using indices shuffled
    local displayOrders: {number} = {}
    for i = 1, numPacks do
        -- Use unique values spread apart to guarantee distinctness
        displayOrders[i] = i * TestHarness.randomInt(rng, 1, 10) + TestHarness.randomInt(rng, 0, 9)
    end
    -- Ensure uniqueness by adding offset
    local usedOrders: {[number]: boolean} = {}
    for i = 1, numPacks do
        while usedOrders[displayOrders[i]] do
            displayOrders[i] = displayOrders[i] + 1
        end
        usedOrders[displayOrders[i]] = true
    end

    -- Build pack map
    local packs: {[string]: LevelPackConfig} = {}
    for i = 1, numPacks do
        local themeId = "theme_" .. tostring(i) .. "_" .. TestHarness.randomString(rng, 3, 6)
        packs[themeId] = generateValidPackConfig(rng, themeId, displayOrders[i])
    end

    -- Sort them
    local ordered = sortPacksByDisplayOrder(packs)

    -- Verify ascending displayOrder
    for i = 2, #ordered do
        local prevOrder = packs[ordered[i - 1]].displayOrder
        local currOrder = packs[ordered[i]].displayOrder
        if currOrder <= prevOrder then
            return false, string.format(
                "Pack at index %d has displayOrder %d <= previous %d",
                i, currOrder, prevOrder
            )
        end
    end

    -- Verify all packs are present
    if #ordered ~= numPacks then
        return false, string.format(
            "Expected %d packs in ordered list, got %d",
            numPacks, #ordered
        )
    end

    return true, nil
end)

--============================================================================
-- Property 17: Invalid Packs Skipped Gracefully
-- Given a mix of valid and invalid configs, only valid ones end up
-- registered. Invalid ones produce loadErrors entries.
--
-- Validates: Requirements 12.5
--============================================================================

print("\n=== Property 17: Invalid Packs Skipped Gracefully ===")

TestHarness.property("Only valid packs registered, invalid in loadErrors", 100, function(rng)
    local numValid = TestHarness.randomInt(rng, 1, 5)
    local numInvalid = TestHarness.randomInt(rng, 1, 5)
    local totalPacks = numValid + numInvalid

    local configs: {[string]: any} = {}
    local expectedValid: {[string]: boolean} = {}
    local expectedInvalid: {[string]: boolean} = {}

    -- Create valid packs
    for i = 1, numValid do
        local moduleName = "ValidModule_" .. tostring(i)
        local themeId = "valid_" .. tostring(i) .. "_" .. TestHarness.randomString(rng, 3, 5)
        local pack = generateValidPackConfig(rng, themeId, i * 10)
        configs[moduleName] = pack
        expectedValid[themeId] = true
    end

    -- Create invalid packs (remove a random required field from each)
    for i = 1, numInvalid do
        local moduleName = "InvalidModule_" .. tostring(i)
        local themeId = "invalid_" .. tostring(i) .. "_" .. TestHarness.randomString(rng, 3, 5)
        local pack = generateValidPackConfig(rng, themeId, (numValid + i) * 10)

        -- Convert to table and remove a required field
        local broken: {[string]: any} = {
            name = pack.name,
            displayOrder = pack.displayOrder,
            themeId = pack.themeId,
            obstacleTypes = pack.obstacleTypes,
            difficulty = pack.difficulty,
            morassVisual = pack.morassVisual,
            achievementName = pack.achievementName,
        }
        local fieldToRemove = TestHarness.randomChoice(rng, REQUIRED_PACK_FIELDS)
        broken[fieldToRemove] = nil

        configs[moduleName] = broken
        expectedInvalid[moduleName] = true
    end

    -- Run registration
    local result = registerPacks(configs)

    -- Verify: all valid packs are registered
    local validCount = 0
    for _ in result.validPacks do
        validCount += 1
    end
    if validCount ~= numValid then
        return false, string.format(
            "Expected %d valid packs, got %d",
            numValid, validCount
        )
    end

    -- Verify: all expected valid themeIds are present
    for themeId, _ in expectedValid do
        if result.validPacks[themeId] == nil then
            return false, string.format("Valid pack '%s' not found in registry", themeId)
        end
    end

    -- Verify: all invalid modules have loadErrors entries
    local errorCount = 0
    for _ in result.loadErrors do
        errorCount += 1
    end
    if errorCount ~= numInvalid then
        return false, string.format(
            "Expected %d load errors, got %d",
            numInvalid, errorCount
        )
    end

    -- Verify: invalid modules are in loadErrors
    for moduleName, _ in expectedInvalid do
        if result.loadErrors[moduleName] == nil then
            return false, string.format(
                "Invalid module '%s' not found in loadErrors",
                moduleName
            )
        end
    end

    -- Verify: no invalid packs leaked into validPacks
    for themeId, _ in result.validPacks do
        if string.find(themeId, "^invalid_") then
            -- Double-check it was actually valid (shouldn't happen since we broke it)
            return false, string.format(
                "Invalid pack '%s' leaked into validPacks",
                themeId
            )
        end
    end

    return true, nil
end)

--============================================================================
-- Report Results
--============================================================================

local allPassed = TestHarness.report()

if not allPassed then
    error("One or more property tests failed")
end
