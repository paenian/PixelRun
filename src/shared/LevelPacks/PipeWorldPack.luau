--!strict
--[[
    PipeWorldPack.luau - Second Level Pack Configuration for Pixel Run Obby
    
    The Pipe World pack is the second pack unlocked after completing Tetris.
    Features underground/sewer-themed obstacles with earthy browns, greens,
    and golds. Slightly denser than Tetris at equivalent levels.
    
    Difficulty Progression:
      Levels 1-3: Jump-over only, max 3 blocks tall (brick blocks, warp pipes, coin blocks)
      Levels 4-6: Holes/gaps up to 3 wide, obstacles up to 5 tall, crumble bricks added
      Levels 7-9: Void sections up to 5 long
      Level 10:   Pipe plants (touch-kill)
    
    Requires completion of Tetris pack. Completable without purchased power-ups.
    
    Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5, 5.6
]]

local Types = require(script.Parent.Parent.Types)

local PipeWorldPack: Types.LevelPackConfig = {
    name = "Pipe World",
    displayOrder = 2,
    themeId = "pipeworld",
    prerequisitePack = "tetris",
    morassVisual = "sewer_flood",
    achievementName = "Pipeline Pro",
    musicTrack = "pipeworld_theme",

    --========================================================================
    -- Obstacle Types: 5 pipe/underground themed obstacles with 4 orientations
    --========================================================================
    obstacleTypes = {
        -- Brick Blocks: Brown/tan standard jump-over obstacle
        {
            shape = "Brick",
            orientations = {0, 90, 180, 270},
            color = Color3.fromRGB(139, 90, 43),
            maxHeight = 5,
            isTouchKill = false,
        },
        -- Warp Pipes: Green cylindrical obstacles
        {
            shape = "Pipe",
            orientations = {0, 90, 180, 270},
            color = Color3.fromRGB(34, 139, 34),
            maxHeight = 5,
            isTouchKill = false,
        },
        -- Coin Blocks: Yellow/gold glowing blocks
        {
            shape = "CoinBlock",
            orientations = {0, 90, 180, 270},
            color = Color3.fromRGB(255, 215, 0),
            maxHeight = 5,
            isTouchKill = false,
        },
        -- Crumble Bricks: Brown with cracks, standard obstacle
        {
            shape = "Crumble",
            orientations = {0, 90, 180, 270},
            color = Color3.fromRGB(160, 82, 45),
            maxHeight = 5,
            isTouchKill = false,
        },
        -- Pipe Plants: Green/red touch-kill obstacles
        {
            shape = "PipePlant",
            orientations = {0, 90, 180, 270},
            color = Color3.fromRGB(50, 180, 50),
            maxHeight = 3,
            isTouchKill = true,
        },
    },

    --========================================================================
    -- Difficulty Configuration: 10 levels of progressive challenge
    -- Slightly denser than Tetris at equivalent levels (e.g., Tetris 1/8 → 1/7,
    -- Tetris 1/3 → 1/2.5). Same structural progression but tighter spacing.
    --========================================================================
    difficulty = {
        -- Levels 1-3: Jump-over only, max 3 blocks tall, no gaps or voids
        [1] = {
            obstacleDensity = 1 / 7,
            maxHeight = 3,
            gapWidth = 0,
            voidLength = 0,
            hasTouchKill = false,
            requiredPowerUps = nil,
        },
        [2] = {
            obstacleDensity = 1 / 6,
            maxHeight = 3,
            gapWidth = 0,
            voidLength = 0,
            hasTouchKill = false,
            requiredPowerUps = nil,
        },
        [3] = {
            obstacleDensity = 1 / 5,
            maxHeight = 3,
            gapWidth = 0,
            voidLength = 0,
            hasTouchKill = false,
            requiredPowerUps = nil,
        },

        -- Levels 4-6: Holes/gaps up to 3 wide, obstacles up to 5 tall
        [4] = {
            obstacleDensity = 1 / 4.5,
            maxHeight = 5,
            gapWidth = 3,
            voidLength = 0,
            hasTouchKill = false,
            requiredPowerUps = nil,
        },
        [5] = {
            obstacleDensity = 1 / 4,
            maxHeight = 5,
            gapWidth = 3,
            voidLength = 0,
            hasTouchKill = false,
            requiredPowerUps = nil,
        },
        [6] = {
            obstacleDensity = 1 / 3.5,
            maxHeight = 5,
            gapWidth = 3,
            voidLength = 0,
            hasTouchKill = false,
            requiredPowerUps = nil,
        },

        -- Levels 7-9: Void sections up to 5 long
        [7] = {
            obstacleDensity = 1 / 3.5,
            maxHeight = 5,
            gapWidth = 3,
            voidLength = 5,
            hasTouchKill = false,
            requiredPowerUps = nil,
        },
        [8] = {
            obstacleDensity = 1 / 2.5,
            maxHeight = 5,
            gapWidth = 3,
            voidLength = 5,
            hasTouchKill = false,
            requiredPowerUps = nil,
        },
        [9] = {
            obstacleDensity = 1 / 2.5,
            maxHeight = 5,
            gapWidth = 3,
            voidLength = 5,
            hasTouchKill = false,
            requiredPowerUps = nil,
        },

        -- Level 10: Pipe plants (touch-kill)
        [10] = {
            obstacleDensity = 1 / 2.5,
            maxHeight = 5,
            gapWidth = 3,
            voidLength = 5,
            hasTouchKill = true,
            requiredPowerUps = nil,
        },
    },
}

return PipeWorldPack
