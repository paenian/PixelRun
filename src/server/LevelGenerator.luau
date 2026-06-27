--!strict
--[[
    LevelGenerator.luau - Deterministic level layout generation

    Produces identical obstacle layouts for the same packId + levelNum combination
    using seeded random number generation. Supports schema validation for level packs
    and building Roblox Model instances from generated layouts.

    Validates: Requirements 3.1, 3.2, 3.4, 3.7, 12.1, 12.5
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Types)
local LevelUtils = require(ReplicatedStorage.LevelUtils)

local LevelGenerator = {}

--============================================================================
-- Constants
--============================================================================

local LEVEL_WIDTH = Types.LEVEL_WIDTH       -- 10 blocks wide
local LEVEL_LENGTH = Types.LEVEL_LENGTH     -- 1000 blocks long
local BLOCK_SCALE = 2                       -- 1 game block = 2 studs (Roblox characters are ~5 studs tall)

--- Required fields for LevelPackConfig schema validation.
local REQUIRED_PACK_FIELDS = {
    "name",
    "displayOrder",
    "themeId",
    "obstacleTypes",
    "difficulty",
    "morassVisual",
    "achievementName",
}

--============================================================================
-- Internal: Seeded RNG
--============================================================================

--- Create a seeded random number generator using Roblox's Random class.
--- The same seed always produces the same sequence of numbers.
local function createRNG(seed: number): Random
    return Random.new(seed)
end

--============================================================================
-- Internal: Obstacle Filtering by Difficulty Tier
--============================================================================

--- Filter obstacle types based on the level's difficulty tier.
--- Levels 1-9: exclude any obstacles with isTouchKill = true
--- Level 10: all obstacle types are available (including touchKill)
---
--- Note: obstacle maxHeight is NOT used for filtering here. The actual placed
--- height is capped at generation time via math.min(obstacle.maxHeight, difficultyConfig.maxHeight),
--- so all non-touchKill obstacles are always available regardless of their maxHeight field.
local function filterObstaclesByTier(
    obstacleTypes: { Types.ObstacleDefinition },
    levelNum: number,
    difficultyConfig: Types.LevelDifficulty
): { Types.ObstacleDefinition }
    local filtered: { Types.ObstacleDefinition } = {}

    for _, obstacle in obstacleTypes do
        local include = true

        -- Exclude touchKill obstacles unless hasTouchKill is enabled for this level
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
-- Public: generateLevel
--============================================================================

--- Generate a deterministic level layout from a pack configuration and level number.
---
--- Uses LevelUtils.getLevelSeed() for deterministic RNG initialization.
--- Walks through the 1000-block length and at each position uses obstacle density
--- to probabilistically place obstacles. Obstacle types are filtered by the
--- difficulty tier for the given level number.
---
--- @param packConfig Types.LevelPackConfig -- The level pack configuration
--- @param levelNum number -- Level number within the pack (1-10)
--- @return Types.LevelLayout -- Generated layout with obstacle positions
function LevelGenerator.generateLevel(packConfig: Types.LevelPackConfig, levelNum: number): Types.LevelLayout
    -- Clamp level number to valid range
    local level = math.clamp(levelNum, 1, 10)

    -- Get deterministic seed from pack name + level number
    local seed = LevelUtils.getLevelSeed(packConfig.name, level)
    local rng = createRNG(seed)

    -- Determine difficulty configuration for this level
    -- Use pack's own difficulty config if available, otherwise fall back to LevelUtils
    local difficultyConfig: Types.LevelDifficulty
    if packConfig.difficulty and packConfig.difficulty[level] then
        difficultyConfig = packConfig.difficulty[level]
    else
        difficultyConfig = LevelUtils.getDifficultyConfig(level)
    end

    -- Get obstacle density (probability per block)
    local density = difficultyConfig.obstacleDensity

    -- Filter available obstacle types by difficulty tier
    local availableObstacles = filterObstaclesByTier(packConfig.obstacleTypes, level, difficultyConfig)

    -- Generate obstacle placements
    local obstacles: { {
        position: Vector3,
        shape: string,
        orientation: number,
        color: Color3,
        isTouchKill: boolean,
    } } = {}

    -- Walk through the level length, deciding at each block if an obstacle spawns
    for z = 1, LEVEL_LENGTH do
        -- Use density as probability of spawning an obstacle at this position
        local roll = rng:NextNumber() -- Returns 0.0 to 1.0
        if roll < density then
            -- Select a random obstacle type from available ones
            local obstacleIndex = rng:NextInteger(1, #availableObstacles)
            local obstacleType = availableObstacles[obstacleIndex]

            -- Select a random orientation from the obstacle's available orientations
            local orientationIndex = rng:NextInteger(1, #obstacleType.orientations)
            local orientation = obstacleType.orientations[orientationIndex]

            -- Select a random X position across the level width (1 to LEVEL_WIDTH)
            local xPos = rng:NextInteger(1, LEVEL_WIDTH)

            -- Determine height (random up to the obstacle's maxHeight, capped by level config)
            local maxH = math.min(obstacleType.maxHeight, difficultyConfig.maxHeight)
            local height = rng:NextInteger(1, maxH)

            -- Create the obstacle entry with position as Vector3
            table.insert(obstacles, {
                position = Vector3.new(xPos, height, z),
                shape = obstacleType.shape,
                orientation = orientation,
                color = obstacleType.color,
                isTouchKill = obstacleType.isTouchKill,
            })
        end
    end

    -- Calculate conveyor speed: faster for higher levels
    -- Base speed 5 blocks/sec at level 1, up to 12 blocks/sec at level 10
    local baseSpeed = 5
    local maxSpeed = 12
    local t = (level - 1) / 9
    local conveyorSpeed = baseSpeed + t * (maxSpeed - baseSpeed)

    local layout: Types.LevelLayout = {
        obstacles = obstacles,
        conveyorSpeed = conveyorSpeed,
        morassVisual = packConfig.morassVisual,
    }

    return layout
end

--============================================================================
-- Public: buildLevel
--============================================================================

--- Build a Roblox Model from a generated LevelLayout.
---
--- Creates Part instances for each obstacle at their specified positions.
--- Parts are colored according to the obstacle definition and named by shape.
--- TouchKill obstacles get a special CanTouch attribute set to true.
---
--- @param layout Types.LevelLayout -- The generated level layout
--- @return Model -- A Roblox Model containing all obstacle parts
function LevelGenerator.buildLevel(layout: Types.LevelLayout): Model
    local model = Instance.new("Model")
    model.Name = "GeneratedLevel"

    local scaledWidth = LEVEL_WIDTH * BLOCK_SCALE
    local scaledLength = LEVEL_LENGTH * BLOCK_SCALE

    -- Create the ground platform (scaled)
    local ground = Instance.new("Part")
    ground.Name = "Ground"
    ground.Size = Vector3.new(scaledWidth, 1, scaledLength)
    ground.Position = Vector3.new(scaledWidth / 2, -0.5, scaledLength / 2)
    ground.Anchored = true
    ground.Color = Color3.fromRGB(100, 100, 100)
    ground.Parent = model

    -- Tetris piece block offsets (relative to origin, in block units)
    -- Each piece is defined as a list of (x, y) offsets for orientation 0
    local PIECE_SHAPES: {[string]: {{number}}} = {
        I = {{0,0}, {1,0}, {2,0}, {3,0}},
        O = {{0,0}, {1,0}, {0,1}, {1,1}},
        T = {{0,0}, {1,0}, {2,0}, {1,1}},
        S = {{0,0}, {1,0}, {1,1}, {2,1}},
        Z = {{1,0}, {2,0}, {0,1}, {1,1}},
        L = {{0,0}, {1,0}, {2,0}, {2,1}},
        J = {{0,0}, {1,0}, {2,0}, {0,1}},
        Kill = {{0,0}, {1,0}, {0,1}, {1,1}}, -- 2x2 kill block
    }

    --- Rotate a set of block offsets by the given degrees (0, 90, 180, 270)
    local function rotateOffsets(offsets: {{number}}, degrees: number): {{number}}
        if degrees == 0 then
            return offsets
        end
        local rotated: {{number}} = {}
        for _, offset in offsets do
            local x, y = offset[1], offset[2]
            if degrees == 90 then
                table.insert(rotated, {y, -x})
            elseif degrees == 180 then
                table.insert(rotated, {-x, -y})
            elseif degrees == 270 then
                table.insert(rotated, {-y, x})
            end
        end
        -- Normalize: shift so minimum x and y are 0
        local minX, minY = math.huge, math.huge
        for _, r in rotated do
            if r[1] < minX then minX = r[1] end
            if r[2] < minY then minY = r[2] end
        end
        for _, r in rotated do
            r[1] = r[1] - minX
            r[2] = r[2] - minY
        end
        return rotated
    end

    -- Create obstacles as multi-block Tetris shapes
    for i, obstacle in layout.obstacles do
        local baseOffsets = PIECE_SHAPES[obstacle.shape]
        if not baseOffsets then
            -- Fallback: single block for unknown shapes
            baseOffsets = {{0, 0}}
        end

        -- Rotate the piece
        local offsets = rotateOffsets(baseOffsets, obstacle.orientation)

        -- Base position in studs (scaled)
        local baseX = obstacle.position.X * BLOCK_SCALE
        local baseZ = obstacle.position.Z * BLOCK_SCALE
        local baseY = 0 -- On top of ground (ground top is at y=0)

        -- Create a Model for this piece
        local pieceModel = Instance.new("Model")
        pieceModel.Name = obstacle.shape .. "_" .. tostring(i)

        -- Stack the piece vertically (height = obstacle.position.Y blocks tall)
        local pieceHeight = obstacle.position.Y

        for _, offset in offsets do
            for h = 0, pieceHeight - 1 do
                local block = Instance.new("Part")
                block.Name = "Block"
                block.Size = Vector3.new(BLOCK_SCALE, BLOCK_SCALE, BLOCK_SCALE)
                block.Position = Vector3.new(
                    baseX + offset[1] * BLOCK_SCALE,
                    baseY + (h + 0.5) * BLOCK_SCALE,
                    baseZ + offset[2] * BLOCK_SCALE
                )
                block.Anchored = true
                block.Color = obstacle.color

                if obstacle.isTouchKill then
                    block:SetAttribute("IsTouchKill", true)
                    block.Material = Enum.Material.Neon
                end

                block.Parent = pieceModel
            end
        end

        pieceModel.Parent = model
    end

    return model
end

--============================================================================
-- Public: validatePackSchema
--============================================================================

--- Validate that a table conforms to the LevelPackConfig schema.
---
--- Checks that all required fields are present and non-nil.
--- Required fields: name, displayOrder, themeId, obstacleTypes, difficulty,
--- morassVisual, achievementName.
---
--- @param config any -- Table to validate
--- @return (boolean, string?) -- (true, nil) on success, or (false, error message) on failure
function LevelGenerator.validatePackSchema(config: any): (boolean, string?)
    -- Must be a table
    if typeof(config) ~= "table" then
        return false, "Config is not a table"
    end

    -- Check all required fields are present
    for _, field in REQUIRED_PACK_FIELDS do
        if (config :: any)[field] == nil then
            return false, "Missing field: " .. field
        end
    end

    -- Validate obstacleTypes is a non-empty array
    local obstacleTypes = (config :: any).obstacleTypes
    if typeof(obstacleTypes) ~= "table" or #obstacleTypes == 0 then
        return false, "obstacleTypes must be a non-empty array"
    end

    -- Validate difficulty is a table with at least one entry
    local difficulty = (config :: any).difficulty
    if typeof(difficulty) ~= "table" then
        return false, "difficulty must be a table"
    end

    -- Validate displayOrder is a number
    local displayOrder = (config :: any).displayOrder
    if typeof(displayOrder) ~= "number" then
        return false, "displayOrder must be a number"
    end

    return true, nil
end

return LevelGenerator
