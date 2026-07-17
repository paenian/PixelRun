--!strict
--[[
    MorassManager.luau - Server-side morass (advancing wall) management

    The morass is the core conveyor-belt enforcement mechanic. It spawns 50 blocks
    behind the player's starting position and advances forward at the level's configured
    minimum speed (conveyorSpeed). If the morass reaches the player, they are eliminated.

    The morass provides visual urgency: for the Tetris pack it appears as rolling
    Tetris blocks (neon material, colorful). Each player has their own independent
    morass instance.

    Validates: Requirements 4.1, 4.2, 4.3, 4.4, 4.5
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Types)

local MorassManager = {}

--============================================================================
-- Constants
--============================================================================

local MORASS_SPAWN_OFFSET = Types.MORASS_SPAWN_OFFSET -- 50 blocks behind start
local BLOCK_SCALE = 2     -- Must match LevelGenerator scale
local MORASS_WIDTH = 10 * BLOCK_SCALE   -- Full level width in studs
local MORASS_HEIGHT = 20 * BLOCK_SCALE  -- Tall enough to be impassable
local MORASS_DEPTH = 5 * BLOCK_SCALE    -- Thickness of the wall in studs

--============================================================================
-- Internal State
--============================================================================

--- Per-player morass state
type MorassState = {
    part: Part,               -- The physical morass Part in workspace
    positionZ: number,        -- Current Z position of the morass front face
    startZ: number,           -- The player's starting Z position
    conveyorSpeed: number,    -- Blocks per second advance rate
    morassVisual: string,     -- Visual style identifier
    levelNum: number,         -- Current level number (1-10) for intensity scaling
    active: boolean,          -- Whether the morass is currently advancing
    connection: RBXScriptConnection?, -- Heartbeat connection for updates
}

--- Map of player UserId -> MorassState
local playerMorass: {[number]: MorassState} = {}

--============================================================================
-- Internal: Visual Configuration
--============================================================================

--- Apply theme-appropriate visuals to the morass part based on morassVisual config.
--- For "rolling_tetris_blocks": colorful neon material simulating rolling blocks.
local function applyMorassVisuals(part: Part, morassVisual: string)
    if morassVisual == "rolling_tetris_blocks" then
        -- Tetris theme: vibrant multi-color neon look
        part.Color = Color3.fromRGB(200, 50, 255) -- Purple-ish, Tetris-inspired
        part.Material = Enum.Material.Neon
        part.Transparency = 0.1
    else
        -- Default fallback: dark menacing wall
        part.Color = Color3.fromRGB(50, 50, 50)
        part.Material = Enum.Material.SmoothPlastic
        part.Transparency = 0
    end
end

--============================================================================
-- Internal: Particle Intensity Scaling
--============================================================================

--- Returns particle emitter configuration based on level number.
--- Levels 1-3: gentle (low rate, muted colors)
--- Levels 4-6: moderate (standard rate)
--- Levels 7-10: intense (high rate, brighter colors)
local function getParticleConfig(levelNum: number): {rate: number, speed: number, color: Color3, lifetime: number}
    if levelNum <= 3 then
        -- Gentle: low particle rate, muted purple
        return {
            rate = 5,
            speed = 3,
            color = Color3.fromRGB(120, 60, 150),
            lifetime = 2,
        }
    elseif levelNum <= 6 then
        -- Moderate: standard particle rate
        return {
            rate = 15,
            speed = 6,
            color = Color3.fromRGB(180, 50, 220),
            lifetime = 1.5,
        }
    else
        -- Intense: high particle rate, vivid colors
        return {
            rate = 35,
            speed = 10,
            color = Color3.fromRGB(255, 40, 80),
            lifetime = 1,
        }
    end
end

--- Attach a ParticleEmitter to the morass part with intensity scaled by level.
local function applyMorassParticles(part: Part, levelNum: number)
    -- Remove any existing particle emitter
    local existing = part:FindFirstChildOfClass("ParticleEmitter")
    if existing then
        existing:Destroy()
    end

    local config = getParticleConfig(levelNum)

    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "MorassParticles"
    emitter.Rate = config.rate
    emitter.Speed = NumberRange.new(config.speed * 0.5, config.speed)
    emitter.Lifetime = NumberRange.new(config.lifetime * 0.5, config.lifetime)
    emitter.SpreadAngle = Vector2.new(30, 30)
    emitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, config.color),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 0, 30)),
    })
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.8),
        NumberSequenceKeypoint.new(1, 0.1),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.7, 0.5),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.RotSpeed = NumberRange.new(-90, 90)
    emitter.LightEmission = if levelNum >= 7 then 0.4 else 0.1
    emitter.Parent = part
end

--============================================================================
-- Public: init
--============================================================================

--- Initialize morass for a player. Creates the morass Part 50 blocks behind
--- the player's starting Z position.
---
--- @param player Player -- The player to create morass for
--- @param layout Types.LevelLayout -- The generated level layout with conveyorSpeed and morassVisual
--- @param startZ number -- The player's starting Z position (typically 0)
--- @param levelNum number? -- The level number (1-10) for visual intensity scaling (defaults to 1)
function MorassManager.init(player: Player, layout: Types.LevelLayout, startZ: number, levelNum: number?)
    -- Clean up any existing morass for this player
    MorassManager.cleanup(player)

    local currentLevel = levelNum or 1

    -- Spawn offset is in blocks, convert to studs
    local spawnZ = startZ - (MORASS_SPAWN_OFFSET * BLOCK_SCALE)

    -- Create the morass Part
    local part = Instance.new("Part")
    part.Name = "Morass_" .. tostring(player.UserId)
    part.Size = Vector3.new(MORASS_WIDTH, MORASS_HEIGHT, MORASS_DEPTH)
    part.Position = Vector3.new(MORASS_WIDTH / 2, MORASS_HEIGHT / 2, spawnZ - MORASS_DEPTH / 2)
    part.Anchored = true
    part.CanCollide = false -- Collision is detected via position check, not physics
    part.CastShadow = false
    part:SetAttribute("IsMorass", true)
    part:SetAttribute("OwnerId", player.UserId)
    part:SetAttribute("LevelNum", currentLevel)

    -- Apply theme visuals
    applyMorassVisuals(part, layout.morassVisual)

    -- Apply level-scaled particle effects
    applyMorassParticles(part, currentLevel)

    -- Parent to workspace
    part.Parent = workspace

    -- Store state (conveyorSpeed is in blocks/sec, scale to studs/sec)
    local state: MorassState = {
        part = part,
        positionZ = spawnZ,
        startZ = startZ,
        conveyorSpeed = layout.conveyorSpeed * BLOCK_SCALE,
        morassVisual = layout.morassVisual,
        levelNum = currentLevel,
        active = false,
        connection = nil,
    }

    playerMorass[player.UserId] = state
end

--============================================================================
-- Public: startMorass
--============================================================================

--- Begin advancing the morass forward at the conveyor speed.
--- Uses RunService.Heartbeat to update position each frame.
---
--- @param player Player -- The player whose morass to start
function MorassManager.startMorass(player: Player)
    local state = playerMorass[player.UserId]
    if not state then
        return
    end

    -- Don't start if already active
    if state.active then
        return
    end

    state.active = true

    -- Connect to Heartbeat for frame-by-frame advancement
    state.connection = RunService.Heartbeat:Connect(function(deltaTime: number)
        if not state.active then
            return
        end

        -- Advance morass forward at conveyor speed
        state.positionZ += state.conveyorSpeed * deltaTime

        -- Update the Part position to match
        state.part.Position = Vector3.new(
            MORASS_WIDTH / 2,
            MORASS_HEIGHT / 2,
            state.positionZ - MORASS_DEPTH / 2
        )
    end)
end

--============================================================================
-- Public: stopMorass
--============================================================================

--- Pause morass advancement. Used during level transitions.
---
--- @param player Player -- The player whose morass to stop
function MorassManager.stopMorass(player: Player)
    local state = playerMorass[player.UserId]
    if not state then
        return
    end

    state.active = false

    -- Disconnect the Heartbeat connection
    if state.connection then
        state.connection:Disconnect()
        state.connection = nil
    end
end

--============================================================================
-- Public: resetMorass
--============================================================================

--- Reset morass back to its spawn position (50 blocks behind start).
--- Called on player elimination/respawn.
---
--- @param player Player -- The player whose morass to reset
function MorassManager.resetMorass(player: Player)
    local state = playerMorass[player.UserId]
    if not state then
        return
    end

    -- Stop advancement first
    MorassManager.stopMorass(player)

    -- Reset position to spawn offset (scaled)
    state.positionZ = state.startZ - (MORASS_SPAWN_OFFSET * BLOCK_SCALE)

    -- Update the Part position
    state.part.Position = Vector3.new(
        MORASS_WIDTH / 2,
        MORASS_HEIGHT / 2,
        state.positionZ - MORASS_DEPTH / 2
    )
end

--============================================================================
-- Public: checkCollision
--============================================================================

--- Check if the morass has reached or passed the player's Z position.
--- Returns true if the player is caught (morass Z >= player Z).
---
--- @param player Player -- The player to check collision for
--- @return boolean -- True if player is caught by the morass
function MorassManager.checkCollision(player: Player): boolean
    local state = playerMorass[player.UserId]
    if not state then
        return false
    end

    -- Get the player's character and position
    local character = player.Character
    if not character then
        return false
    end

    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not humanoidRootPart then
        return false
    end

    local playerZ = humanoidRootPart.Position.Z

    -- Morass catches the player when its front face reaches the player's Z
    return state.positionZ >= playerZ
end

--============================================================================
-- Public: getMorassPosition
--============================================================================

--- Return the current morass Z position for a player.
--- Used for client visualization sync.
---
--- @param player Player -- The player whose morass position to get
--- @return Vector3? -- Current morass center position, or nil if no morass exists
function MorassManager.getMorassPosition(player: Player): Vector3?
    local state = playerMorass[player.UserId]
    if not state then
        return nil
    end

    return Vector3.new(
        MORASS_WIDTH / 2,
        MORASS_HEIGHT / 2,
        state.positionZ - MORASS_DEPTH / 2
    )
end

--============================================================================
-- Public: getConveyorSpeed
--============================================================================

--- Return the conveyor speed for a player's current level.
--- Useful for other systems that need to know the minimum speed.
---
--- @param player Player -- The player to query
--- @return number -- Conveyor speed in blocks per second, or 0 if no morass exists
function MorassManager.getConveyorSpeed(player: Player): number
    local state = playerMorass[player.UserId]
    if not state then
        return 0
    end

    return state.conveyorSpeed
end

--============================================================================
-- Public: isActive
--============================================================================

--- Check if the morass is currently active (advancing) for a player.
---
--- @param player Player -- The player to check
--- @return boolean -- True if the morass is currently advancing
function MorassManager.isActive(player: Player): boolean
    local state = playerMorass[player.UserId]
    if not state then
        return false
    end

    return state.active
end

--============================================================================
-- Public: getLevelNum
--============================================================================

--- Return the level number associated with a player's morass instance.
--- Used for client-side intensity effects (proximity warning).
---
--- @param player Player -- The player to query
--- @return number -- Level number (1-10), or 1 if no morass exists
function MorassManager.getLevelNum(player: Player): number
    local state = playerMorass[player.UserId]
    if not state then
        return 1
    end

    return state.levelNum
end

--============================================================================
-- Public: cleanup
--============================================================================

--- Clean up morass state for a player. Called when player leaves or game ends.
---
--- @param player Player -- The player to clean up for
function MorassManager.cleanup(player: Player)
    local state = playerMorass[player.UserId]
    if not state then
        return
    end

    -- Stop advancement
    if state.connection then
        state.connection:Disconnect()
        state.connection = nil
    end

    -- Remove the Part from workspace
    if state.part then
        state.part:Destroy()
    end

    -- Remove from state table
    playerMorass[player.UserId] = nil
end

--============================================================================
-- Public: cleanupAll
--============================================================================

--- Clean up all morass instances. Called on server shutdown.
function MorassManager.cleanupAll()
    for userId, state in playerMorass do
        if state.connection then
            state.connection:Disconnect()
        end
        if state.part then
            state.part:Destroy()
        end
    end

    table.clear(playerMorass)
end

return MorassManager
