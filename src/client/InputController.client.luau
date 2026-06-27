--!strict
--[[
    InputController.client.luau - Client-side player input and movement controller

    Handles:
    - Automatic forward movement (endless runner style)
    - Left/right strafing within the 10-block-wide track
    - Jump input (single jump + double jump when power-up owned)
    - Power-up effects: Higher Jump, Double Jump, Faster Speed
    - Obstacle collision detection triggering death/respawn

    Validates: Requirements 7.5, 7.6, 7.7, 13.2
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PowerUpManager = require(ReplicatedStorage.PowerUpManager)

--============================================================================
-- Constants
--============================================================================

local BASE_WALK_SPEED = 16 -- Roblox default humanoid walk speed (studs/s)
local BASE_JUMP_POWER = 50 -- Roblox default humanoid jump power
local TRACK_WIDTH = 10 -- Track width in studs (blocks)
local STRAFE_SPEED = 20 -- Lateral movement speed in studs/s
local FORWARD_DIRECTION = Vector3.new(0, 0, -1) -- Forward is negative Z
local DOUBLE_JUMP_VELOCITY = 50 -- Upward velocity applied on double jump

-- Tags used by LevelGenerator to identify obstacle parts
local OBSTACLE_TAG = "Obstacle"
local TOUCHKILL_TAG = "TouchKill"

--============================================================================
-- Module
--============================================================================

local InputController = {}

-- Internal state
local localPlayer: Player = Players.LocalPlayer
local character: Model? = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local isAlive: boolean = false
local trackCenterX: number = 0 -- X position of track center (set on spawn)

-- Power-up state (received from server)
local powerUpState = {
    higherJump = 0,   -- 0-3 tier
    doubleJump = 0,   -- 0-1 tier
    fasterSpeed = 0,  -- 0-3 tier
}

-- Double jump tracking
local hasDoubleJumped: boolean = false

-- Connections to clean up on character removal
local connections: { RBXScriptConnection } = {}

--============================================================================
-- Private Functions
--============================================================================

--- Clean up all active connections (called on character removal).
local function cleanupConnections()
    for _, conn in connections do
        conn:Disconnect()
    end
    table.clear(connections)
end

--- Apply power-up effects to the humanoid (jump height and walk speed).
--- Called on character spawn and whenever power-up state is updated from server.
local function applyPowerUpEffects()
    if not humanoid then
        return
    end

    -- Apply Higher Jump multiplier
    local jumpMultiplier = 1.0
    if powerUpState.higherJump > 0 then
        local mult = PowerUpManager.getMultiplier("higherJump", powerUpState.higherJump)
        if mult then
            jumpMultiplier = mult
        end
    end
    humanoid.JumpPower = BASE_JUMP_POWER * jumpMultiplier

    -- Apply Faster Speed multiplier
    local speedMultiplier = 1.0
    if powerUpState.fasterSpeed > 0 then
        local mult = PowerUpManager.getMultiplier("fasterSpeed", powerUpState.fasterSpeed)
        if mult then
            speedMultiplier = mult
        end
    end
    humanoid.WalkSpeed = BASE_WALK_SPEED * speedMultiplier
end

--- Handle player death/respawn when hitting an obstacle.
local function onObstacleHit()
    if not isAlive then
        return
    end
    if not humanoid then
        return
    end

    isAlive = false
    -- Kill the character to trigger respawn
    humanoid.Health = 0
end

--- Connect collision detection for a single part tagged as an obstacle.
local function connectObstaclePart(part: BasePart)
    local conn = part.Touched:Connect(function(otherPart: BasePart)
        if not isAlive then
            return
        end
        if not character then
            return
        end

        -- Check if the touching part belongs to our character
        local hitModel = otherPart:FindFirstAncestorOfClass("Model")
        if hitModel == character then
            onObstacleHit()
        end
    end)
    table.insert(connections, conn)
end

--- Set up collision detection for all obstacles currently in the workspace
--- and listen for new obstacles being added.
local function setupCollisionDetection()
    -- Connect existing obstacles tagged with TouchKill (instant death)
    for _, part in CollectionService:GetTagged(TOUCHKILL_TAG) do
        if part:IsA("BasePart") then
            connectObstaclePart(part :: BasePart)
        end
    end

    -- Connect existing obstacles tagged with Obstacle (also lethal for now)
    for _, part in CollectionService:GetTagged(OBSTACLE_TAG) do
        if part:IsA("BasePart") then
            connectObstaclePart(part :: BasePart)
        end
    end

    -- Listen for new tagged obstacles being added dynamically
    local addedConn1 = CollectionService:GetInstanceAddedSignal(TOUCHKILL_TAG):Connect(function(instance)
        if instance:IsA("BasePart") then
            connectObstaclePart(instance :: BasePart)
        end
    end)
    table.insert(connections, addedConn1)

    local addedConn2 = CollectionService:GetInstanceAddedSignal(OBSTACLE_TAG):Connect(function(instance)
        if instance:IsA("BasePart") then
            connectObstaclePart(instance :: BasePart)
        end
    end)
    table.insert(connections, addedConn2)
end

--- Called when a new character is added (initial spawn or respawn).
local function onCharacterAdded(newCharacter: Model)
    cleanupConnections()

    character = newCharacter
    humanoid = newCharacter:WaitForChild("Humanoid") :: Humanoid
    rootPart = newCharacter:WaitForChild("HumanoidRootPart") :: BasePart
    isAlive = true
    hasDoubleJumped = false

    -- Record the track center X from spawn position
    if rootPart then
        trackCenterX = rootPart.Position.X
    end

    -- Apply power-up effects (sets JumpPower and WalkSpeed based on current tiers)
    applyPowerUpEffects()

    -- Listen for character death to update state
    local diedConn = humanoid.Died:Connect(function()
        isAlive = false
    end)
    table.insert(connections, diedConn)

    -- Listen for landing to reset double jump
    local floorConn = humanoid:GetPropertyChangedSignal("FloorMaterial"):Connect(function()
        if humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
            -- Player has landed, reset double jump
            hasDoubleJumped = false
        end
    end)
    table.insert(connections, floorConn)

    -- Set up obstacle collision detection
    setupCollisionDetection()
end

--============================================================================
-- Public Functions
--============================================================================

--- Update power-up state from server data and re-apply effects.
function InputController.updatePowerUps(newState: { higherJump: number, doubleJump: number, fasterSpeed: number })
    powerUpState.higherJump = newState.higherJump or 0
    powerUpState.doubleJump = newState.doubleJump or 0
    powerUpState.fasterSpeed = newState.fasterSpeed or 0
    applyPowerUpEffects()
end

--- Initialize the InputController.
--- Gets local player references, binds inputs, and sets up respawn handling.
function InputController.init()
    -- Set up character added connection for respawns
    localPlayer.CharacterAdded:Connect(onCharacterAdded)

    -- If character already exists (script loaded after spawn), set up immediately
    if localPlayer.Character then
        onCharacterAdded(localPlayer.Character)
    end

    -- Bind inputs
    InputController.bindJump()
    InputController.bindMovement()

    -- Listen for power-up state updates from server
    InputController.listenForPowerUpUpdates()
end

--- Bind jump input.
--- Uses UserInputService to detect Space/Jump button press.
--- Supports double jump when the Double Jump power-up is owned.
function InputController.bindJump()
    UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
        if gameProcessedEvent then
            return
        end

        if input.KeyCode == Enum.KeyCode.Space then
            if humanoid and isAlive then
                -- Check if grounded (FloorMaterial ~= Air means on ground)
                if humanoid.FloorMaterial ~= Enum.Material.Air then
                    humanoid.Jump = true
                elseif powerUpState.doubleJump > 0 and not hasDoubleJumped then
                    -- Double Jump: player is airborne, has the power-up, hasn't used it yet
                    hasDoubleJumped = true

                    -- Apply upward velocity for the double jump
                    if rootPart then
                        local currentVelocity = rootPart.AssemblyLinearVelocity
                        rootPart.AssemblyLinearVelocity = Vector3.new(
                            currentVelocity.X,
                            DOUBLE_JUMP_VELOCITY,
                            currentVelocity.Z
                        )
                    end
                end
            end
        end
    end)

    -- Also support mobile jump button via Humanoid.JumpRequest
    if humanoid then
        humanoid.UseJumpPower = true
    end
end

--- Bind movement controls.
--- Implements automatic forward movement and left/right strafing.
--- The player runs forward automatically (endless runner).
--- A/D or Left/Right arrows control lateral strafing within the track.
function InputController.bindMovement()
    local moveConn = RunService.Heartbeat:Connect(function(deltaTime: number)
        if not isAlive then
            return
        end
        if not humanoid then
            return
        end
        if not rootPart then
            return
        end

        -- Automatic forward movement
        -- Use Humanoid:Move() to drive the character forward continuously
        local moveDirection = FORWARD_DIRECTION

        -- Read strafe input (A/D or arrow keys)
        local strafeInput = 0
        if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
            strafeInput = -1
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
            strafeInput += 1
        end

        -- Apply strafing within track bounds
        if strafeInput ~= 0 then
            local currentX = rootPart.Position.X
            local halfTrack = TRACK_WIDTH / 2
            local minX = trackCenterX - halfTrack
            local maxX = trackCenterX + halfTrack

            -- Only allow strafe if it would keep us within bounds
            if strafeInput < 0 and currentX <= minX then
                strafeInput = 0
            elseif strafeInput > 0 and currentX >= maxX then
                strafeInput = 0
            end

            -- Combine forward and lateral movement
            local lateralDirection = Vector3.new(strafeInput, 0, 0)
            moveDirection = (FORWARD_DIRECTION + lateralDirection * (STRAFE_SPEED / BASE_WALK_SPEED)).Unit
        end

        -- Drive the humanoid in the calculated direction (relative to world)
        humanoid:Move(moveDirection, false)
    end)

    table.insert(connections, moveConn)
end

--- Listen for server power-up state updates.
--- When the server sends updated power-up tiers (e.g., after a purchase),
--- the client applies the new effects to the player character.
function InputController.listenForPowerUpUpdates()
    -- Wait for the RemoteEvents folder to be available
    local eventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
    if not eventsFolder then
        return
    end

    local powerUpEvent = eventsFolder:WaitForChild("PowerUpUpdate", 10)
    if not powerUpEvent then
        return
    end

    (powerUpEvent :: RemoteEvent).OnClientEvent:Connect(function(data: any)
        if type(data) == "table" then
            -- Server sends { powerUps = { higherJump, doubleJump, fasterSpeed } }
            local powerUps = data.powerUps or data
            if type(powerUps) == "table" then
                InputController.updatePowerUps({
                    higherJump = powerUps.higherJump or 0,
                    doubleJump = powerUps.doubleJump or 0,
                    fasterSpeed = powerUps.fasterSpeed or 0,
                })
            end
        end
    end)
end

--- Stub: Handle power-up purchase request.
--- Will be wired to RemoteFunction in Epoch 2 (task 3.5).
function InputController.onPurchaseRequest(_powerUpId: string, _tier: number)
    -- Stub: to be implemented in Epoch 2 (task 3.5)
end

--- Stub: Handle level choice selection.
--- Will be wired to RemoteEvent in Epoch 2 (task 3.3).
function InputController.onLevelChoice(_choice: string)
    -- Stub: to be implemented in Epoch 2 (task 3.3)
end

--============================================================================
-- Auto-initialize on script load (client script)
--============================================================================

InputController.init()

return InputController
