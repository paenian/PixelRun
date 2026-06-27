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

local EffectsManager = {}

export type EffectsManager = {
	playLevelComplete: (position: Vector3) -> (),
	playXPGain: (amount: number, position: Vector3) -> (),
	playDeath: (position: Vector3) -> (),
	playAchievement: (name: string, duration: number) -> (),
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

return EffectsManager
