--!strict
--[[
    EffectsManager.luau - Visual effects for Pixel Run Obby

    Provides particle explosions and floating text for:
    - Level completion (colorful confetti burst)
    - XP gain (floating "+N XP" text, batched to once per second)
    - Death (red/dark particle burst)
    - Achievement (gold particle explosion + persistent floating text)

    Validates: Requirements 9.1, 9.2, 9.3, 8.4
]]

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local EffectsManager = {}

export type EffectsManager = {
	playLevelComplete: (position: Vector3) -> (),
	playXPGain: (amount: number, position: Vector3) -> (),
	playDeath: (position: Vector3) -> (),
	playAchievement: (name: string, duration: number) -> (),
	startMorassProximityWarning: (levelNum: number) -> (),
	stopMorassProximityWarning: () -> (),
}

--============================================================================
-- XP Batching State
--============================================================================

local xpBatchAccumulated: number = 0
local xpBatchLastDisplayTime: number = 0
local xpBatchPosition: Vector3 = Vector3.new(0, 0, 0)
local XP_BATCH_INTERVAL: number = 1 -- seconds

--============================================================================
-- Helper Functions
--============================================================================

--- Creates a temporary anchored Part at the given position for attaching effects.
local function createEffectPart(position: Vector3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = position
	part.Parent = workspace
	return part
end

--- Creates a BillboardGui with a TextLabel for floating text effects.
local function createFloatingText(position: Vector3, text: string, textColor: Color3, duration: number): ()
	local part = createEffectPart(position)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = textColor
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.Parent = billboard

	-- Float upward and fade out
	task.spawn(function()
		local elapsed = 0
		local step = 0.03
		while elapsed < duration do
			elapsed += step
			local progress = elapsed / duration
			-- Move upward
			billboard.StudsOffset = Vector3.new(0, 2 + (progress * 3), 0)
			-- Fade out text
			label.TextTransparency = progress
			label.TextStrokeTransparency = 0.5 + (progress * 0.5)
			task.wait(step)
		end
	end)

	Debris:AddItem(part, duration + 0.5)
end

--============================================================================
-- Public API
--============================================================================

--- Plays a colorful confetti-like particle explosion at the given position.
--- Used when a player completes a level (reaches 1000-block mark).
function EffectsManager.playLevelComplete(position: Vector3): ()
	local part = createEffectPart(position)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 100, 100)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(100, 255, 100)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(100, 100, 255)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(255, 255, 100)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 255)),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Speed = NumberRange.new(15, 30)
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.Rate = 0 -- We will use Emit() for a burst
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Parent = part

	-- Emit a burst of confetti particles
	emitter:Emit(50)

	-- Clean up after particles fade
	Debris:AddItem(part, 3)
end

--- Displays floating "+N XP" text, batched to once per second maximum.
--- Accumulates XP gain calls within a 1-second window and shows a single
--- combined display.
function EffectsManager.playXPGain(amount: number, position: Vector3): ()
	xpBatchAccumulated += amount
	xpBatchPosition = position

	local currentTime = tick()
	if currentTime - xpBatchLastDisplayTime >= XP_BATCH_INTERVAL then
		-- Display the accumulated XP
		xpBatchLastDisplayTime = currentTime
		local displayAmount = xpBatchAccumulated
		xpBatchAccumulated = 0

		createFloatingText(
			xpBatchPosition,
			"+" .. tostring(displayAmount) .. " XP",
			Color3.fromRGB(100, 255, 100),
			1.5
		)
	end
end

--- Plays a red/dark death particle burst at the death position.
--- Used when a player collides with a touch-and-die obstacle.
function EffectsManager.playDeath(position: Vector3): ()
	local part = createEffectPart(position)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 0, 0)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(100, 0, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 0, 0)),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.Speed = NumberRange.new(8, 15)
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.Rate = 0
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Parent = part

	-- Emit a short burst of death particles
	emitter:Emit(30)

	-- Clean up after particles fade
	Debris:AddItem(part, 1.5)
end

--- Plays a gold/yellow particle explosion at the player's position AND
--- displays floating text with the achievement name for the given duration.
--- Duration should be between 3-5 seconds.
function EffectsManager.playAchievement(name: string, duration: number): ()
	-- Clamp duration to 3-5 seconds
	duration = math.clamp(duration, 3, 5)

	-- Get the local player's position for the particle effect
	local player = Players.LocalPlayer
	local position = Vector3.new(0, 5, 0) -- fallback
	if player and player.Character then
		local rootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			position = rootPart.Position
		end
	end

	-- Gold particle explosion
	local part = createEffectPart(position)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 215, 0)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 180, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 150, 0)),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.5, 0.4),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(1.5, 2.5)
	emitter.Speed = NumberRange.new(10, 25)
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.Rate = 0
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.LightEmission = 0.5
	emitter.Parent = part

	-- Emit gold particles
	emitter:Emit(60)

	Debris:AddItem(part, 3)

	-- Display achievement floating text that persists for the full duration
	local textPart = createEffectPart(position + Vector3.new(0, 3, 0))

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 300, 0, 60)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = textPart

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 215, 0)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(50, 50, 0)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = "🏆 " .. name
	label.Parent = billboard

	-- Fade out the achievement text at the end of its duration
	task.delay(duration - 1, function()
		local elapsed = 0
		local fadeTime = 1
		local step = 0.03
		while elapsed < fadeTime do
			elapsed += step
			local progress = elapsed / fadeTime
			label.TextTransparency = progress
			label.TextStrokeTransparency = 0.3 + (progress * 0.7)
			task.wait(step)
		end
	end)

	Debris:AddItem(textPart, duration + 0.5)
end

--============================================================================
-- Morass Proximity Warning (Levels 7-10)
--============================================================================

--- State for the morass proximity warning system
local morassWarningGui: ScreenGui? = nil
local morassWarningFrame: Frame? = nil
local morassWarningConnection: RBXScriptConnection? = nil
local morassWarningLevelNum: number = 1
local morassCameraShakeOffset: CFrame = CFrame.new()

--- Proximity distance threshold (in studs, 20 blocks * 2 scale = 40 studs)
local MORASS_PROXIMITY_THRESHOLD = 40

--- Creates the red screen-edge warning glow GUI.
local function createWarningGui(): (ScreenGui, Frame)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local gui = Instance.new("ScreenGui")
	gui.Name = "MorassWarningGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100
	gui.Parent = playerGui

	-- Full-screen frame with red gradient edges (transparent center)
	local frame = Instance.new("Frame")
	frame.Name = "WarningGlow"
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.Position = UDim2.new(0, 0, 0, 0)
	frame.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
	frame.BackgroundTransparency = 1 -- Start fully transparent
	frame.BorderSizePixel = 0
	frame.Parent = gui

	-- Use a UIGradient for the edge-to-center fade
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 30, 0)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 0, 0)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(0, 0, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
	})
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.25, 0.7),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = frame

	return gui, frame
end

--- Starts the morass proximity warning system. Monitors the distance between
--- the player and their morass part each frame. For levels 7-10, shows a red
--- screen-edge glow and subtle camera shake when the morass is within 20 blocks.
---
--- @param levelNum number -- The current level number (1-10)
function EffectsManager.startMorassProximityWarning(levelNum: number): ()
	-- Clean up any existing warning
	EffectsManager.stopMorassProximityWarning()

	morassWarningLevelNum = levelNum

	-- Only show proximity effects for levels 7-10
	if levelNum < 7 then
		return
	end

	-- Create the warning GUI
	local gui, frame = createWarningGui()
	morassWarningGui = gui
	morassWarningFrame = frame

	-- Connect to RenderStepped for per-frame proximity checking
	morassWarningConnection = RunService.RenderStepped:Connect(function(_deltaTime: number)
		local player = Players.LocalPlayer
		if not player or not player.Character then
			return
		end

		local rootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then
			return
		end

		-- Find this player's morass part in workspace
		local morassPart: Part? = nil
		for _, obj in workspace:GetChildren() do
			if obj:IsA("Part") and obj:GetAttribute("IsMorass") == true then
				local ownerId = obj:GetAttribute("OwnerId")
				if ownerId == player.UserId then
					morassPart = obj :: Part
					break
				end
			end
		end

		if not morassPart then
			-- No morass found, hide warning
			if morassWarningFrame then
				morassWarningFrame.BackgroundTransparency = 1
			end
			return
		end

		-- Calculate distance between player and morass front face (Z axis)
		local playerZ = rootPart.Position.Z
		local morassZ = morassPart.Position.Z + (morassPart.Size.Z / 2) -- front face
		local distance = playerZ - morassZ

		if distance <= MORASS_PROXIMITY_THRESHOLD and distance > 0 then
			-- Morass is close! Scale intensity by proximity (closer = more intense)
			local intensity = 1 - (distance / MORASS_PROXIMITY_THRESHOLD)
			intensity = math.clamp(intensity, 0, 1)

			-- Red glow: show the frame with transparency based on proximity
			if morassWarningFrame then
				-- Max opacity at 0.6 to avoid being too obtrusive
				morassWarningFrame.BackgroundTransparency = 1 - (intensity * 0.4)
			end

			-- Subtle camera shake (only for levels 7+, respects screenShake setting)
			local camera = workspace.CurrentCamera
			if camera then
				-- Check player's screenShake preference (default: enabled)
				local screenShakeEnabled = true
				local playerData = player:FindFirstChild("PlayerSettings")
				if playerData then
					local shakeAttr = playerData:GetAttribute("screenShake")
					if shakeAttr == false then
						screenShakeEnabled = false
					end
				end

				if screenShakeEnabled then
					local shakeIntensity = intensity * 0.15 -- Max 0.15 studs offset
					local shakeX = math.sin(tick() * 20) * shakeIntensity
					local shakeY = math.cos(tick() * 17) * shakeIntensity * 0.5
					morassCameraShakeOffset = CFrame.new(shakeX, shakeY, 0)
					camera.CFrame = camera.CFrame * morassCameraShakeOffset
				end
			end
		else
			-- Morass is far enough away, hide effects
			if morassWarningFrame then
				morassWarningFrame.BackgroundTransparency = 1
			end
		end
	end)
end

--- Stops the morass proximity warning system and cleans up resources.
function EffectsManager.stopMorassProximityWarning(): ()
	if morassWarningConnection then
		morassWarningConnection:Disconnect()
		morassWarningConnection = nil
	end

	if morassWarningGui then
		morassWarningGui:Destroy()
		morassWarningGui = nil
	end

	morassWarningFrame = nil
	morassCameraShakeOffset = CFrame.new()
end

return EffectsManager
