--!strict
--[[
    TetrisPack.luau - First Level Pack Configuration for Pixel Run Obby
    
    The Tetris pack is the introductory pack with block-based obstacles using
    the 7 standard Tetris piece shapes (I, O, T, S, Z, L, J) in their
    canonical colors and 4 orientations each.
    
    Difficulty Progression:
      Levels 1-3: Jump-over only, max 3 blocks tall
      Levels 4-6: Holes/gaps up to 3 wide, obstacles up to 5 tall
      Levels 7-9: Void sections up to 5 long
      Level 10:   Touch-and-die blocks
    
    Completable without any purchased power-ups.
    
    Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5, 5.6
]]

local Types = require(script.Parent.Parent.Types)

local TetrisPack: Types.LevelPackConfig = {
    name = "Tetris",
    displayOrder = 1,
    themeId = "tetris",
    prerequisitePack = nil,
    morassVisual = "rolling_tetris_blocks",
    achievementName = "Tetris Master",
    musicTrack = "tetris_theme",

    --========================================================================
    -- Obstacle Types: 7 Tetris pieces with 4 orientations and canonical colors
    --========================================================================
    obstacleTypes = {
        -- I-piece: Cyan
        {
            shape = "I",
            orientations = {0, 90, 180, 270},
            color = Color3.fromRGB(0, 255, 255),
            maxHeight = 5,
            isTouchKill = false,
        },
        -- O-piece: Yellow
        {
            shape = "O",
            orientations = {0, 90, 180, 270},
            color = Color3.fromRGB(255, 255, 0),
            maxHeight = 5,
            isTouchKill = false,
        },
        -- T-piece: Purple
        {
            shape = "T",
            orientations = {0, 90, 180, 270},
            color = Color3.fromRGB(128, 0, 128),
            maxHeight = 5,
            isTouchKill = false,
        },
        -- S-piece: Green
        {
            shape = "S",
            orientations = {0, 90, 180, 270},
            color = Color3.fromRGB(0, 255, 0),
            maxHeight = 5,
            isTouchKill = false,
        },
        -- Z-piece: Red
        {
            shape = "Z",
            orientations = {0, 90, 180, 270},
            color = Color3.fromRGB(255, 0, 0),
            maxHeight = 5,
            isTouchKill = false,
        },
        -- L-piece: Orange
        {
            shape = "L",
            orientations = {0, 90, 180, 270},
            color = Color3.fromRGB(255, 165, 0),
            maxHeight = 5,
            isTouchKill = false,
        },
        -- J-piece: Blue
        {
            shape = "J",
            orientations = {0, 90, 180, 270},
            color = Color3.fromRGB(0, 0, 255),
            maxHeight = 5,
            isTouchKill = false,
        },

        -- Kill block: Neon Red glow, touch-and-die obstacle for level 10
        -- Shorter height (max 3) so players can still jump over or route around
        {
            shape = "Kill",
            orientations = {0, 90, 180, 270},
            color = Color3.fromRGB(255, 0, 50),
            maxHeight = 3,
            isTouchKill = true,
        },
    },

    --========================================================================
    -- Difficulty Configuration: 10 levels of progressive challenge
    -- Density is much higher than typical obbies because Tetris pieces are
    -- thin (1 block deep) and form partial walls — many pieces needed to
    -- create the look of stacked Tetris boards with navigable gaps.
    --========================================================================
    difficulty = {
        -- Levels 1-3: Jump-over only, max 3 blocks tall, no gaps or voids
        [1] = {
            obstacleDensity = 1 / 8,
            maxHeight = 3,
            gapWidth = 0,
            voidLength = 0,
            hasTouchKill = false,
            requiredPowerUps = nil,
        },
        [2] = {
            obstacleDensity = 1 / 7,
            maxHeight = 3,
            gapWidth = 0,
            voidLength = 0,
            hasTouchKill = false,
            requiredPowerUps = nil,
        },
        [3] = {
            obstacleDensity = 1 / 6,
            maxHeight = 3,
            gapWidth = 0,
            voidLength = 0,
            hasTouchKill = false,
            requiredPowerUps = nil,
        },

        -- Levels 4-6: Holes/gaps up to 3 wide, obstacles up to 5 tall
        [4] = {
            obstacleDensity = 1 / 5,
            maxHeight = 5,
            gapWidth = 3,
            voidLength = 0,
            hasTouchKill = false,
            requiredPowerUps = nil,
        },
        [5] = {
            obstacleDensity = 1 / 5,
            maxHeight = 5,
            gapWidth = 3,
            voidLength = 0,
            hasTouchKill = false,
            requiredPowerUps = nil,
        },
        [6] = {
            obstacleDensity = 1 / 4,
            maxHeight = 5,
            gapWidth = 3,
            voidLength = 0,
            hasTouchKill = false,
            requiredPowerUps = nil,
        },

        -- Levels 7-9: Void sections up to 5 long
        [7] = {
            obstacleDensity = 1 / 4,
            maxHeight = 5,
            gapWidth = 3,
            voidLength = 5,
            hasTouchKill = false,
            requiredPowerUps = nil,
        },
        [8] = {
            obstacleDensity = 1 / 3,
            maxHeight = 5,
            gapWidth = 3,
            voidLength = 5,
            hasTouchKill = false,
            requiredPowerUps = nil,
        },
        [9] = {
            obstacleDensity = 1 / 3,
            maxHeight = 5,
            gapWidth = 3,
            voidLength = 5,
            hasTouchKill = false,
            requiredPowerUps = nil,
        },

        -- Level 10: Touch-and-die blocks
        [10] = {
            obstacleDensity = 1 / 3,
            maxHeight = 5,
            gapWidth = 3,
            voidLength = 5,
            hasTouchKill = true,
            requiredPowerUps = nil,
        },
    },
}

return TetrisPack
