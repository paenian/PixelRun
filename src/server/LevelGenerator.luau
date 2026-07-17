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
local LEVEL_LENGTH = Types.LEVEL_LENGTH     -- 500 blocks long
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
-- Internal: Piece Shape Definitions (used by both generateLevel and buildLevel)
--============================================================================

--- Tetris piece block offsets: {x, y} where x = across track, y = vertical height.
--- Pieces are 1 block thick in Z, forming walls facing the player.
local PIECE_SHAPES_GEN: {[string]: {{number}}} = {
    I = {{0,0}, {1,0}, {2,0}, {3,0}},       -- Horizontal bar
    O = {{0,0}, {1,0}, {0,1}, {1,1}},       -- 2x2 square
    T = {{0,0}, {1,0}, {2,0}, {1,1}},       -- T-shape
    S = {{0,0}, {1,0}, {1,1}, {2,1}},       -- S-shape
    Z = {{1,0}, {2,0}, {0,1}, {1,1}},       -- Z-shape
    L = {{0,0}, {1,0}, {2,0}, {2,1}},       -- L-shape
    J = {{0,0}, {1,0}, {2,0}, {0,1}},       -- J-shape
    Kill = {{0,0}, {1,0}, {0,1}, {1,1}},    -- 2x2 kill block
}

--- Rotate a set of block offsets by degrees (0, 90, 180, 270) and normalize.
local function rotateOffsetsGen(offsets: {{number}}, degrees: number): {{number}}
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
--- An optional modeConfig parameter modifies conveyor speed based on game mode:
--- - Time Attack (hasMorass=false): conveyorSpeed = base * 0.7 (slower conveyor)
--- - Sprint (timerDirection="down"): conveyorSpeed = base * 0.3 (very slow morass)
--- - Classic / nil: no modification
---
--- @param packConfig Types.LevelPackConfig -- The level pack configuration
--- @param levelNum number -- Level number within the pack (1-10)
--- @param modeConfig Types.GameModeConfig? -- Optional game mode configuration
--- @return Types.LevelLayout -- Generated layout with obstacle positions
function LevelGenerator.generateLevel(packConfig: Types.LevelPackConfig, levelNum: number, modeConfig: Types.GameModeConfig?): Types.LevelLayout
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

    -- Walk through the level length, deciding at each block if an obstacle wall spawns.
    -- When a wall spawns, place multiple pieces at the same Z using an occupancy grid
    -- to prevent overlaps — just like real Tetris, no two blocks share the same cell.
    for z = 1, LEVEL_LENGTH do
        -- Use density as probability of spawning a wall at this position
        local roll = rng:NextNumber() -- Returns 0.0 to 1.0
        if roll < density then
            -- Determine how many pieces to attempt placing at this Z position (2-4)
            local pieceCount = rng:NextInteger(2, 4)

            -- Occupancy grid: tracks which (x, y) cells are filled at this Z
            -- Key: "x,y" string, Value: true if occupied
            local occupied: { [string]: boolean } = {}
            local maxH = difficultyConfig.maxHeight

            for _ = 1, pieceCount do
                -- Select a random obstacle type from available ones
                local obstacleIndex = rng:NextInteger(1, #availableObstacles)
                local obstacleType = availableObstacles[obstacleIndex]

                -- Select a random orientation
                local orientationIndex = rng:NextInteger(1, #obstacleType.orientations)
                local orientation = obstacleType.orientations[orientationIndex]

                -- Select a random X position (clamped so piece fits on track)
                local xPos = rng:NextInteger(1, math.max(1, LEVEL_WIDTH - 3))

                -- Determine base Y row for this piece
                local baseRow = 0
                local obstacleMaxH = math.min(obstacleType.maxHeight, maxH)

                local stackRoll = rng:NextNumber()
                if obstacleMaxH >= 4 and stackRoll < 0.2 then
                    -- Elevated piece with run-through gap (player can run under)
                    baseRow = rng:NextInteger(3, obstacleMaxH)
                elseif stackRoll < 0.5 then
                    -- Stacked piece (sits above ground level)
                    baseRow = rng:NextInteger(1, math.min(2, obstacleMaxH))
                end

                -- Compute the cells this piece would occupy using the shape offsets
                -- We need the rotated offsets to check occupancy correctly
                local baseOffsets = PIECE_SHAPES_GEN[obstacleType.shape]
                if not baseOffsets then
                    baseOffsets = {{0, 0}}
                end
                local offsets = rotateOffsetsGen(baseOffsets, orientation)

                -- Check if all cells for this piece are free
                local canPlace = true
                local cellKeys: {string} = {}
                for _, offset in offsets do
                    local cellX = xPos + offset[1]
                    local cellY = baseRow + offset[2]
                    local key = tostring(cellX) .. "," .. tostring(cellY)
                    if occupied[key] or cellX > LEVEL_WIDTH or cellX < 1 then
                        canPlace = false
                        break
                    end
                    table.insert(cellKeys, key)
                end

                -- Only place the piece if no cells overlap
                if canPlace then
                    -- Mark cells as occupied
                    for _, key in cellKeys do
                        occupied[key] = true
                    end

                    table.insert(obstacles, {
                        position = Vector3.new(xPos, baseRow, z),
                        shape = obstacleType.shape,
                        orientation = orientation,
                        color = obstacleType.color,
                        isTouchKill = obstacleType.isTouchKill,
                    })
                end
            end
        end
    end

    -- Calculate conveyor speed: faster for higher levels
    -- Base speed 5 blocks/sec at level 1, up to 12 blocks/sec at level 10
    local baseSpeed = 5
    local maxSpeed = 12
    local t = (level - 1) / 9
    local conveyorSpeed = baseSpeed + t * (maxSpeed - baseSpeed)

    -- Apply mode-specific speed multiplier
    if modeConfig then
        if not modeConfig.hasMorass then
            -- Time Attack: no morass, slower conveyor (0.7x)
            conveyorSpeed = conveyorSpeed * 0.7
        elseif modeConfig.timerDirection == "down" then
            -- Sprint: very slow morass (0.3x)
            conveyorSpeed = conveyorSpeed * 0.3
        end
    end

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
    -- Each piece is defined as a list of {x, y} offsets where:
    --   x = horizontal position across track width (left-right)
    --   y = vertical height (up from ground)
    -- Pieces are always 1 block thick in Z (depth along the track), forming
    -- walls that face the player like a Tetris board. The player must jump
    -- over, duck through gaps, or strafe around the shapes.
    local PIECE_SHAPES: {[string]: {{number}}} = {
        I = {{0,0}, {1,0}, {2,0}, {3,0}},       -- Horizontal bar
        O = {{0,0}, {1,0}, {0,1}, {1,1}},       -- 2x2 square
        T = {{0,0}, {1,0}, {2,0}, {1,1}},       -- T-shape
        S = {{0,0}, {1,0}, {1,1}, {2,1}},       -- S-shape
        Z = {{1,0}, {2,0}, {0,1}, {1,1}},       -- Z-shape
        L = {{0,0}, {1,0}, {2,0}, {2,1}},       -- L-shape
        J = {{0,0}, {1,0}, {2,0}, {0,1}},       -- J-shape
        Kill = {{0,0}, {1,0}, {0,1}, {1,1}},    -- 2x2 kill block
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

    -- Create obstacles as multi-block Tetris shapes (1 block thick in Z direction)
    for i, obstacle in layout.obstacles do
        local baseOffsets = PIECE_SHAPES[obstacle.shape]
        if not baseOffsets then
            -- Fallback: single block for unknown shapes
            baseOffsets = {{0, 0}}
        end

        -- Rotate the piece (rotation is in the XY plane — the wall face the player sees)
        local offsets = rotateOffsets(baseOffsets, obstacle.orientation)

        -- Base position in studs (scaled)
        -- obstacle.position.X = starting column across track width
        -- obstacle.position.Z = position along the track
        -- obstacle.position.Y = base row offset (how many blocks above ground the piece starts)
        local baseX = obstacle.position.X * BLOCK_SCALE
        local baseZ = obstacle.position.Z * BLOCK_SCALE
        local baseRow = obstacle.position.Y -- Row offset above ground

        -- Create a Model for this piece
        local pieceModel = Instance.new("Model")
        pieceModel.Name = obstacle.shape .. "_" .. tostring(i)

        -- Place each block of the piece as a flat wall (1 block deep in Z)
        -- offset[1] = X position across track, offset[2] = Y position (height within piece)
        -- Final Y = baseRow + offset[2], placing the piece shape at the correct elevation
        for _, offset in offsets do
            local block = Instance.new("Part")
            block.Name = "Block"
            block.Size = Vector3.new(BLOCK_SCALE, BLOCK_SCALE, BLOCK_SCALE)
            block.Position = Vector3.new(
                baseX + offset[1] * BLOCK_SCALE,
                (baseRow + offset[2] + 0.5) * BLOCK_SCALE,
                baseZ
            )
            block.Anchored = true
            block.Color = obstacle.color

            if obstacle.isTouchKill then
                block:SetAttribute("IsTouchKill", true)
                block.Material = Enum.Material.Neon
            end

            block.Parent = pieceModel
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
