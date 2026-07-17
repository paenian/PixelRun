--!strict
--[[
    MascotVisual.luau - Client-side mascot companion visual

    Creates a small floating Part-based model that follows the local player.
    The mascot trails behind and above the player with a sine-wave bobbing
    animation and a colored ParticleEmitter trail.

    Uses RunService.RenderStepped for smooth per-frame following.

    Validates: Requirements 6.3
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MascotManager = require(script.Parent.Parent.shared.MascotManager)

local MascotVisual = {}

--============================================================================
-- Configuration
--============================================================================

local OFFSET_BEHIND = -3        -- Studs behind the player (negative = behind)
local OFFSET_UP = 3             -- Studs above the player
local BOB_AMPLITUDE = 0.5       -- Studs of vertical oscillation
local BOB_FREQUENCY = 2         -- Oscillations per second
local FOLLOW_SMOOTHING = 0.15   -- Lerp factor per frame (lower = smoother/laggier)
local MASCOT_SIZE = Vector3.new(2, 2, 2) -- Part size in studs

--============================================================================
-- State
--============================================================================

local currentMascotPart: Part? = nil
local currentConnection: RBXScriptConnection? = nil
local spawnedMascotId: string? = nil

--============================================================================
-- Internal Helpers
--============================================================================

--- Returns the local player's HumanoidRootPart, or nil if unavailable.
local function getPlayerRoot(): BasePart?
    local player = Players.LocalPlayer
    if not player or not player.Character then
        return nil
    end
    return player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

--- Calculates the target position for the mascot based on the player's position and look direction.
local function getTargetPosition(rootPart: BasePart, elapsed: number): Vector3
    -- "Behind" is opposite to the player's look direction
    local lookVector = rootPart.CFrame.LookVector
    local behindOffset = lookVector * OFFSET_BEHIND

    -- Base position: behind and above the player
    local basePosition = rootPart.Position + behindOffset + Vector3.new(0, OFFSET_UP, 0)

    -- Add sine-wave bob
    local bob = math.sin(elapsed * BOB_FREQUENCY * math.pi * 2) * BOB_AMPLITUDE
    return basePosition + Vector3.new(0, bob, 0)
end

--- Creates the ParticleEmitter trail for the mascot part.
local function createTrailEmitter(part: Part, color: Color3): ParticleEmitter
    local emitter = Instance.new("ParticleEmitter")
    emitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, color),
        ColorSequenceKeypoint.new(1, color),
    })
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(0.5, 0.2),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.5, 0.5),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Lifetime = NumberRange.new(0.5, 1.0)
    emitter.Speed = NumberRange.new(0, 1)
    emitter.SpreadAngle = Vector2.new(30, 30)
    emitter.Rate = 15
    emitter.RotSpeed = NumberRange.new(-45, 45)
    emitter.LightEmission = 0.3
    emitter.Parent = part
    return emitter
end

--============================================================================
-- Public API
--============================================================================

--- Creates and spawns the mascot visual for the given mascot ID.
--- If a mascot is already spawned, despawns it first.
function MascotVisual.spawn(mascotId: string): ()
    -- Despawn any existing mascot
    if currentMascotPart then
        MascotVisual.despawn()
    end

    -- Look up mascot definition for color
    local mascotDef = MascotManager.getMascotById(mascotId)
    if not mascotDef then
        warn("[MascotVisual] Unknown mascot ID: " .. mascotId)
        return
    end

    local color = mascotDef.color

    -- Create the mascot part
    local part = Instance.new("Part")
    part.Name = "MascotVisual_" .. mascotId
    part.Size = MASCOT_SIZE
    part.Shape = Enum.PartType.Ball
    part.Material = Enum.Material.Neon
    part.Color = color
    part.Anchored = true
    part.CanCollide = false
    part.CastShadow = false
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent = workspace

    -- Add the trail particle emitter
    createTrailEmitter(part, color)

    -- Position initially at player if available
    local rootPart = getPlayerRoot()
    if rootPart then
        part.Position = rootPart.Position + Vector3.new(0, OFFSET_UP, 0)
    end

    currentMascotPart = part
    spawnedMascotId = mascotId

    -- Connect to RenderStepped for smooth following
    local startTime = tick()
    currentConnection = RunService.RenderStepped:Connect(function(_dt: number)
        local root = getPlayerRoot()
        if not root then
            return
        end

        local mascot = currentMascotPart
        if not mascot then
            return
        end

        local elapsed = tick() - startTime
        local targetPos = getTargetPosition(root, elapsed)

        -- Smooth lerp toward target position
        local currentPos = mascot.Position
        mascot.Position = currentPos:Lerp(targetPos, FOLLOW_SMOOTHING)
    end)
end

--- Removes the current mascot visual and disconnects the update loop.
function MascotVisual.despawn(): ()
    if currentConnection then
        currentConnection:Disconnect()
        currentConnection = nil
    end

    if currentMascotPart then
        currentMascotPart:Destroy()
        currentMascotPart = nil
    end

    spawnedMascotId = nil
end

--- Returns true if a mascot visual is currently spawned and visible.
function MascotVisual.isSpawned(): boolean
    return currentMascotPart ~= nil
end

return MascotVisual
