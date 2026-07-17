--!strict
--[[
    LobbyBuilder.luau - Physical 3D lobby matching Roblox design conventions

    Builds an open spawn-island lobby with:
    - Circular spawn platform with glowing trim
    - Invisible barriers (no visible walls)
    - Brick paths radiating to zones
    - Spinning Tetris centerpiece landmark
    - Tetris portal (archway with particles + progress)
    - Pipe World locked preview portal
    - Shop NPC booth with ProximityPrompt
    - Codes terminal with ProximityPrompt
    - Daily Spin wheel with ProximityPrompt
    - Leaderboard podiums (gold/silver/bronze)
    - Social gathering space with seating
    - Ambient effects (particles, fog, path lights)
    - Lobby music trigger
]]

local TweenService = game:GetService("TweenService")

local LobbyBuilder = {}

--============================================================================
-- Constants
--============================================================================

local B = 2 -- Block scale: 1 game block = 2 studs

-- Layout positions (studs) — lobby is ~200×200 centered at origin
local SPAWN_POS = Vector3.new(0, 1, 0)
local CENTERPIECE_POS = Vector3.new(0, 12 * B, 0)
local TETRIS_PORTAL_POS = Vector3.new(0, 0, 35 * B)
local PIPEWORLD_PORTAL_POS = Vector3.new(25 * B, 0, 25 * B)
local SHOP_POS = Vector3.new(-25 * B, 0, 10 * B)
local CODES_POS = Vector3.new(-20 * B, 0, -20 * B)
local SPIN_POS = Vector3.new(20 * B, 0, -20 * B)
local PODIUM_POS = Vector3.new(0, 0, -30 * B)
local SOCIAL_POS = Vector3.new(25 * B, 0, -5 * B)
local MASCOT_DISPLAY_POS = Vector3.new(-20 * B, 0, 15 * B)

-- Ground
local GROUND_RADIUS = 50 * B -- 100 studs radius = 200×200 stud open spawn island
local GROUND_COLOR = Color3.fromRGB(75, 120, 60) -- Grass green for edges
local PATH_COLOR = Color3.fromRGB(140, 110, 80)
local SPAWN_PLATFORM_COLOR = Color3.fromRGB(45, 45, 60) -- Dark polished stone
local SPAWN_TRIM_COLOR = Color3.fromRGB(0, 200, 255) -- Glowing cyan edge

-- Tetris colors
local CYAN = Color3.fromRGB(0, 255, 255)
local YELLOW = Color3.fromRGB(255, 255, 0)
local PURPLE = Color3.fromRGB(128, 0, 128)
local GREEN = Color3.fromRGB(0, 255, 0)
local RED = Color3.fromRGB(255, 0, 0)
local ORANGE = Color3.fromRGB(255, 165, 0)
local BLUE = Color3.fromRGB(0, 0, 255)

-- UI
local SIGN_COLOR = Color3.fromRGB(20, 20, 30)
local GOLD = Color3.fromRGB(255, 215, 0)
local SILVER = Color3.fromRGB(192, 192, 192)
local BRONZE = Color3.fromRGB(205, 127, 50)

--============================================================================
-- State
--============================================================================

local lobbyModel: Model? = nil
local gateTouchPart: BasePart? = nil
local centerpieceModel: Model? = nil

--============================================================================
-- Helpers
--============================================================================

local function createPart(props: {
	name: string, size: Vector3, position: Vector3?, cframe: CFrame?,
	color: Color3, material: Enum.Material?, transparency: number?,
	canCollide: boolean?, anchored: boolean?, shape: Enum.PartType?,
	parent: Instance,
}): Part
	local p = Instance.new("Part")
	p.Name = props.name
	p.Size = props.size
	if props.cframe then
		p.CFrame = props.cframe
	elseif props.position then
		p.Position = props.position
	end
	p.Color = props.color
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.Transparency = props.transparency or 0
	p.Anchored = if props.anchored ~= nil then props.anchored else true
	p.CanCollide = if props.canCollide ~= nil then props.canCollide else true
	if props.shape then p.Shape = props.shape end
	p.Parent = props.parent
	return p
end

local function addSurfaceText(part: Part, text: string, color: Color3, size: number, face: Enum.NormalId?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = color
	label.TextSize = size
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextWrapped = true
	label.Parent = gui
end

local function addProximityPrompt(parent: Instance, text: string, action: string, distance: number?): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.ObjectText = text
	pp.ActionText = action
	pp.MaxActivationDistance = distance or 8
	pp.HoldDuration = 0
	pp.Parent = parent
	return pp
end

local function addPointLight(parent: Instance, color: Color3, brightness: number?, range: number?)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness or 1
	light.Range = range or 12
	light.Parent = parent
end

--============================================================================
-- 1.1 Ground, Spawn Platform, Invisible Barriers, Paths
--============================================================================

local function buildGround(parent: Model)
	-- Outer ground ring (grass edges — the island perimeter)
	createPart({
		name = "LobbyGround",
		size = Vector3.new(GROUND_RADIUS * 2, 1, GROUND_RADIUS * 2),
		position = Vector3.new(0, -0.5, 0),
		color = Color3.fromRGB(75, 120, 60),
		material = Enum.Material.Grass,
		parent = parent,
	})

	-- Center zone: smooth stone walkway area (60×60 studs around spawn)
	local stoneZone = createPart({
		name = "StoneCenterZone",
		size = Vector3.new(1, 30 * B, 30 * B),
		cframe = CFrame.new(0, 0.01, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(160, 160, 165),
		material = Enum.Material.Slate,
		shape = Enum.PartType.Cylinder,
		canCollide = false,
		parent = parent,
	})

	-- Central spawn platform (circular cylinder, slightly raised above ground)
	local spawnPlat = createPart({
		name = "SpawnPlatform",
		size = Vector3.new(2, 12 * B, 12 * B),
		cframe = CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color = SPAWN_PLATFORM_COLOR,
		material = Enum.Material.Marble,
		shape = Enum.PartType.Cylinder,
		parent = parent,
	})

	-- Glowing edge trim ring around spawn platform
	local trimRing = createPart({
		name = "SpawnTrim",
		size = Vector3.new(0.6, 12.5 * B, 12.5 * B),
		cframe = CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color = SPAWN_TRIM_COLOR,
		material = Enum.Material.Neon,
		shape = Enum.PartType.Cylinder,
		canCollide = false,
		transparency = 0.2,
		parent = parent,
	})
	addPointLight(trimRing, SPAWN_TRIM_COLOR, 0.8, 24)

	-- Secondary inner glow ring (pulsing effect baked into brightness)
	local innerGlow = createPart({
		name = "SpawnTrimInner",
		size = Vector3.new(0.4, 11 * B, 11 * B),
		cframe = CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color = SPAWN_TRIM_COLOR,
		material = Enum.Material.Neon,
		shape = Enum.PartType.Cylinder,
		canCollide = false,
		transparency = 0.5,
		parent = parent,
	})

	-- SpawnLocation (invisible, on top of raised platform)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = Vector3.new(0, 2.5, 0)
	spawn.Anchored = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Parent = parent
end

local function buildInvisibleBarriers(parent: Model)
	local wallH = 30 * B
	local half = GROUND_RADIUS + 5
	local sides = {
		{ name = "BarrierN", pos = Vector3.new(0, wallH/2, half), size = Vector3.new(half*2, wallH, 2) },
		{ name = "BarrierS", pos = Vector3.new(0, wallH/2, -half), size = Vector3.new(half*2, wallH, 2) },
		{ name = "BarrierE", pos = Vector3.new(half, wallH/2, 0), size = Vector3.new(2, wallH, half*2) },
		{ name = "BarrierW", pos = Vector3.new(-half, wallH/2, 0), size = Vector3.new(2, wallH, half*2) },
	}
	for _, s in sides do
		createPart({
			name = s.name,
			size = s.size,
			position = s.pos,
			color = Color3.new(1,1,1),
			transparency = 1,
			parent = parent,
		})
	end

	-- Kill plane below
	local kill = createPart({
		name = "KillPlane",
		size = Vector3.new(500, 1, 500),
		position = Vector3.new(0, -20, 0),
		color = Color3.new(0,0,0),
		transparency = 1,
		canCollide = false,
		parent = parent,
	})
	kill:SetAttribute("IsKillPart", true)
end

local function buildPaths(parent: Model)
	-- Paths from spawn to key zones (simple elongated parts on the ground)
	local paths = {
		{ to = TETRIS_PORTAL_POS, color = CYAN },
		{ to = PIPEWORLD_PORTAL_POS, color = GREEN },
		{ to = SHOP_POS, color = YELLOW },
		{ to = PODIUM_POS, color = GOLD },
		{ to = CODES_POS, color = PURPLE },
		{ to = SPIN_POS, color = ORANGE },
	}
	for i, pathDef in paths do
		local dir = pathDef.to - SPAWN_POS
		local length = dir.Magnitude
		local mid = SPAWN_POS + dir * 0.5
		local angle = math.atan2(dir.X, dir.Z)

		createPart({
			name = "Path_" .. tostring(i),
			size = Vector3.new(3 * B, 0.2, length),
			cframe = CFrame.new(mid.X, 0.1, mid.Z) * CFrame.Angles(0, angle, 0),
			color = pathDef.color,
			material = Enum.Material.Brick,
			canCollide = false,
			parent = parent,
		})
	end
end

--============================================================================
-- 1.2 Spinning Tetris Centerpiece
--============================================================================

--[[
	Large spinning sculpture made from multiple Tetris pieces arranged in a tower.
	Uses all 7 Tetris colors, Neon material with PointLights for glow, and
	TweenService for smooth continuous rotation. Visible from anywhere in the lobby.
]]

-- Tetris piece definitions: each is a list of {x, y} block offsets
local TETRIS_PIECES = {
	{ name = "T", color = PURPLE, offsets = {{0,0},{1,0},{2,0},{1,1}} },
	{ name = "I", color = CYAN, offsets = {{0,0},{1,0},{2,0},{3,0}} },
	{ name = "O", color = YELLOW, offsets = {{0,0},{1,0},{0,1},{1,1}} },
	{ name = "S", color = GREEN, offsets = {{1,0},{2,0},{0,1},{1,1}} },
	{ name = "Z", color = RED, offsets = {{0,0},{1,0},{1,1},{2,1}} },
	{ name = "L", color = ORANGE, offsets = {{0,0},{0,1},{0,2},{1,2}} },
	{ name = "J", color = BLUE, offsets = {{1,0},{1,1},{1,2},{0,2}} },
}

local function buildCenterpiece(parent: Model)
	local cpModel = Instance.new("Model")
	cpModel.Name = "Centerpiece"
	cpModel.Parent = parent

	local blockSize = 3 * B -- Each block is 6 studs — large enough to be a landmark

	-- Place pieces stacked vertically with slight rotation offsets to form a tower sculpture
	-- This creates a tall column of Tetris shapes, each placed at a different height layer
	local yOffset = 0
	local blockIndex = 0

	for pieceIdx, pieceDef in TETRIS_PIECES do
		-- Each piece is offset by a rotation angle around center for visual interest
		local pieceAngle = (pieceIdx - 1) * (math.pi * 2 / #TETRIS_PIECES)
		local cosA = math.cos(pieceAngle)
		local sinA = math.sin(pieceAngle)

		-- Center the piece's blocks around (0,0) by finding its bounding box center
		local minX, maxX = math.huge, -math.huge
		for _, off in pieceDef.offsets do
			if off[1] < minX then minX = off[1] end
			if off[1] > maxX then maxX = off[1] end
		end
		local centerX = (minX + maxX) / 2

		for _, off in pieceDef.offsets do
			blockIndex += 1
			-- Local position relative to piece center
			local localX = (off[1] - centerX) * blockSize
			local localZ = off[2] * blockSize * 0.5 -- Compress Z to keep sculpture compact

			-- Rotate around Y axis to spread pieces in a spiral
			local worldX = localX * cosA - localZ * sinA
			local worldZ = localX * sinA + localZ * cosA
			local worldY = yOffset + off[2] * blockSize

			local block = createPart({
				name = "CenterBlock_" .. tostring(blockIndex),
				size = Vector3.new(blockSize, blockSize, blockSize),
				position = CENTERPIECE_POS + Vector3.new(worldX, worldY, worldZ),
				color = pieceDef.color,
				material = Enum.Material.Neon,
				canCollide = false,
				parent = cpModel,
			})

			-- Add PointLight to every other block for strong glow without overdoing it
			if blockIndex % 2 == 1 then
				addPointLight(block, pieceDef.color, 1.5, 20)
			end
		end

		-- Stack next piece above this one (each piece occupies ~2 blocks of height)
		yOffset += blockSize * 2.2
	end

	-- Create a central invisible pivot part at the sculpture's center for TweenService rotation
	local totalHeight = yOffset
	local pivotPart = Instance.new("Part")
	pivotPart.Name = "CenterpiecePivot"
	pivotPart.Size = Vector3.new(1, 1, 1)
	pivotPart.CFrame = CFrame.new(CENTERPIECE_POS + Vector3.new(0, totalHeight / 2, 0))
	pivotPart.Anchored = true
	pivotPart.CanCollide = false
	pivotPart.Transparency = 1
	pivotPart.Parent = cpModel

	cpModel.PrimaryPart = pivotPart
	-- Set the model's WorldPivot to the center for proper rotation
	cpModel.WorldPivot = CFrame.new(CENTERPIECE_POS + Vector3.new(0, totalHeight / 2, 0))

	centerpieceModel = cpModel
end

local function startCenterpieceSpin()
	if not centerpieceModel or not centerpieceModel.PrimaryPart then
		return
	end

	-- Use TweenService for smooth continuous rotation
	-- We tween 360 degrees over 20 seconds for a slow, majestic spin
	-- Then repeat infinitely
	local pivot = centerpieceModel.PrimaryPart

	-- Tween the pivot part's CFrame to rotate 360 degrees
	local tweenInfo = TweenInfo.new(
		20, -- Duration: 20 seconds for one full rotation (slow, majestic)
		Enum.EasingStyle.Linear,
		Enum.EasingDirection.In,
		-1, -- RepeatCount: -1 = infinite
		false, -- Reverses: false
		0 -- DelayTime
	)

	-- Target: rotate 360 degrees around Y axis
	local startCF = pivot.CFrame
	local goalCF = startCF * CFrame.Angles(0, math.pi * 2, 0)

	-- Since TweenService on a single Part only rotates that part,
	-- we weld all blocks to the pivot so they rotate together
	for _, child in centerpieceModel:GetChildren() do
		if child:IsA("BasePart") and child ~= pivot then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = pivot
			weld.Part1 = child
			weld.Parent = pivot
			-- Unanchor the child so the weld drives it
			child.Anchored = false
		end
	end

	-- Now tween the pivot part
	local tween = TweenService:Create(pivot, tweenInfo, {
		CFrame = goalCF,
	})
	tween:Play()
end

--============================================================================
-- 1.3 Tetris Portal (with particles + progress)
--============================================================================

local portalLights: {PointLight} = {}

local function buildTetrisPortal(parent: Model): Part
	local portal = Instance.new("Model")
	portal.Name = "TetrisPortal"
	portal.Parent = parent

	local pos = TETRIS_PORTAL_POS
	local archW = 7 * B
	local archH = 7 * B
	local frameD = 2 * B

	-- Left pillar
	for row = 0, 6 do
		local c = ({CYAN, BLUE, PURPLE, GREEN, CYAN, YELLOW, ORANGE})[row + 1]
		local pillarBlock = createPart({
			name = "PillarL_" .. tostring(row),
			size = Vector3.new(frameD, B, frameD),
			position = pos + Vector3.new(-archW/2, (row + 0.5) * B, 0),
			color = c, material = Enum.Material.SmoothPlastic, parent = portal,
		})
		-- Add pulsing glow lights on every other frame block
		if row % 2 == 0 then
			local pl = Instance.new("PointLight")
			pl.Color = c
			pl.Brightness = 1.5
			pl.Range = 10
			pl.Parent = pillarBlock
			table.insert(portalLights, pl)
		end
	end

	-- Right pillar
	for row = 0, 6 do
		local c = ({ORANGE, YELLOW, CYAN, GREEN, PURPLE, BLUE, CYAN})[row + 1]
		local pillarBlock = createPart({
			name = "PillarR_" .. tostring(row),
			size = Vector3.new(frameD, B, frameD),
			position = pos + Vector3.new(archW/2, (row + 0.5) * B, 0),
			color = c, material = Enum.Material.SmoothPlastic, parent = portal,
		})
		-- Add pulsing glow lights on every other frame block
		if row % 2 == 0 then
			local pl = Instance.new("PointLight")
			pl.Color = c
			pl.Brightness = 1.5
			pl.Range = 10
			pl.Parent = pillarBlock
			table.insert(portalLights, pl)
		end
	end

	-- Top beam
	local beamBlocks = math.ceil(archW / B) + 2
	for col = 0, beamBlocks - 1 do
		local c = ({CYAN, GREEN, YELLOW, CYAN, PURPLE, ORANGE, CYAN, GREEN, CYAN})[col + 1] or CYAN
		createPart({
			name = "Beam_" .. tostring(col),
			size = Vector3.new(B, frameD, frameD),
			position = pos + Vector3.new(-archW/2 - B + (col + 0.5) * B, archH + B, 0),
			color = c, material = Enum.Material.SmoothPlastic, parent = portal,
		})
	end

	-- Portal particle effect (inside the opening)
	local particlePart = createPart({
		name = "PortalParticles",
		size = Vector3.new(archW - frameD, archH, 0.5),
		position = pos + Vector3.new(0, archH/2, 0),
		color = CYAN, transparency = 0.9, canCollide = false, parent = portal,
	})
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Swirl"
	emitter.Color = ColorSequence.new(CYAN, PURPLE)
	emitter.Size = NumberSequence.new(0.5, 1.5)
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Rate = 30
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Transparency = NumberSequence.new(0.3, 1)
	emitter.Parent = particlePart

	-- Pulsing glow
	local portalLight = Instance.new("PointLight")
	portalLight.Color = CYAN
	portalLight.Brightness = 2
	portalLight.Range = 25
	portalLight.Parent = particlePart
	table.insert(portalLights, portalLight)

	-- Sign: "TETRIS WORLD"
	local sign = createPart({
		name = "PortalSign",
		size = Vector3.new(archW + 2*B, 2*B, 0.3),
		position = pos + Vector3.new(0, archH + 3*B, -B),
		color = SIGN_COLOR, parent = portal,
	})
	addSurfaceText(sign, "TETRIS WORLD", CYAN, 42, Enum.NormalId.Back)

	-- Progress sign below main sign
	local progSign = createPart({
		name = "ProgressSign",
		size = Vector3.new(archW, B, 0.3),
		position = pos + Vector3.new(0, archH + 1.2*B, -B),
		color = SIGN_COLOR, transparency = 0.3, parent = portal,
	})
	addSurfaceText(progSign, "0/10 complete", Color3.fromRGB(100, 255, 100), 24, Enum.NormalId.Back)

	-- Invisible touch trigger
	local trigger = Instance.new("Part")
	trigger.Name = "GateTrigger"
	trigger.Size = Vector3.new(archW - frameD, archH, 3 * B)
	trigger.Position = pos + Vector3.new(0, archH/2, 0)
	trigger.Anchored = true
	trigger.CanCollide = false
	trigger.Transparency = 1
	trigger.Parent = portal

	return trigger
end

--============================================================================
-- 1.3b Portal Pulsing Glow Effect
--============================================================================

local function startPortalPulse()
	if #portalLights == 0 then return end

	-- Pulse each light: brightness cycles from low to high and back
	-- Stagger the start slightly per light for a wave-like effect
	for i, light in portalLights do
		local baseBrightness = light.Brightness
		local lowBrightness = baseBrightness * 0.3
		local highBrightness = baseBrightness * 1.2

		-- Start at low
		light.Brightness = lowBrightness

		-- Tween to high
		local tweenUp = TweenService:Create(light, TweenInfo.new(
			1.5, -- Duration
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1, -- Infinite repeat
			true, -- Reverses (goes back to low)
			(i - 1) * 0.15 -- Staggered delay for wave effect
		), {
			Brightness = highBrightness,
		})
		tweenUp:Play()
	end
end

--============================================================================
-- 1.4 Pipe World Locked Preview Portal
--============================================================================

local function buildPipeWorldPortal(parent: Model)
	local portal = Instance.new("Model")
	portal.Name = "PipeWorldPortal"
	portal.Parent = parent

	local pos = PIPEWORLD_PORTAL_POS
	local archW = 6 * B
	local archH = 6 * B
	local pipeColor = Color3.fromRGB(0, 180, 0)
	local brickColor = Color3.fromRGB(180, 100, 50)

	-- Left pillar (pipe green)
	createPart({
		name = "PillarL", size = Vector3.new(2*B, archH, 2*B),
		position = pos + Vector3.new(-archW/2, archH/2, 0),
		color = pipeColor, material = Enum.Material.SmoothPlastic, parent = portal,
	})

	-- Right pillar (pipe green)
	createPart({
		name = "PillarR", size = Vector3.new(2*B, archH, 2*B),
		position = pos + Vector3.new(archW/2, archH/2, 0),
		color = pipeColor, material = Enum.Material.SmoothPlastic, parent = portal,
	})

	-- Top beam (brick)
	createPart({
		name = "TopBeam", size = Vector3.new(archW + 2*B, 2*B, 2*B),
		position = pos + Vector3.new(0, archH + B, 0),
		color = brickColor, material = Enum.Material.Brick, parent = portal,
	})

	-- Translucent barrier (locked)
	local barrier = createPart({
		name = "LockBarrier",
		size = Vector3.new(archW - 2*B, archH, 0.5),
		position = pos + Vector3.new(0, archH/2, 0),
		color = pipeColor, transparency = 0.5, canCollide = true, parent = portal,
	})

	-- Lock icon
	createPart({
		name = "LockIcon",
		size = Vector3.new(2*B, 2*B, 0.3),
		position = pos + Vector3.new(0, archH/2, -0.5),
		color = YELLOW, material = Enum.Material.Neon, canCollide = false, parent = portal,
	})

	-- "PIPE WORLD" sign above portal
	local sign = createPart({
		name = "ComingSoonSign",
		size = Vector3.new(archW + 2*B, 2*B, 0.3),
		position = pos + Vector3.new(0, archH + 4.5*B, -B),
		color = SIGN_COLOR, parent = portal,
	})
	addSurfaceText(sign, "PIPE WORLD", pipeColor, 36, Enum.NormalId.Back)

	-- "COMING SOON" floating text above portal opening (above the top beam)
	local subSign = createPart({
		name = "SubSign",
		size = Vector3.new(archW, B, 0.3),
		position = pos + Vector3.new(0, archH + 2.8*B, -B),
		color = SIGN_COLOR, transparency = 0.2, parent = portal,
	})
	addSurfaceText(subSign, "COMING SOON", Color3.fromRGB(255, 180, 50), 24, Enum.NormalId.Back)
end

--============================================================================
-- 1.5 Shop NPC Booth
--============================================================================

local function buildShopBooth(parent: Model)
	local shop = Instance.new("Model")
	shop.Name = "ShopBooth"
	shop.Parent = parent

	local pos = SHOP_POS

	-- Counter
	createPart({
		name = "Counter", size = Vector3.new(8*B, 3*B, 2*B),
		position = pos + Vector3.new(0, 1.5*B, 0),
		color = Color3.fromRGB(60, 50, 40), material = Enum.Material.Wood, parent = shop,
	})

	-- Back wall with "UPGRADES" sign and XP icon
	local wall = createPart({
		name = "BackWall", size = Vector3.new(10*B, 6*B, B),
		position = pos + Vector3.new(0, 3*B, -2*B),
		color = SIGN_COLOR, parent = shop,
	})
	addSurfaceText(wall, "\xE2\xAD\x90 UPGRADES \xE2\xAD\x90", YELLOW, 44, Enum.NormalId.Front)

	-- Separate "UPGRADES" sign above the booth (visible from a distance)
	local topSign = createPart({
		name = "UpgradesSign", size = Vector3.new(8*B, 2*B, 0.3),
		position = pos + Vector3.new(0, 6.5*B, -2*B),
		color = SIGN_COLOR, parent = shop,
	})
	addSurfaceText(topSign, "\xE2\xAD\x90 UPGRADES", YELLOW, 36, Enum.NormalId.Front)
	addPointLight(topSign, YELLOW, 0.6, 14)

	-- Power-up display items on counter
	local items = {
		{ name = "Jump", color = Color3.fromRGB(100, 200, 255), x = -2.5*B },
		{ name = "DblJump", color = Color3.fromRGB(255, 200, 100), x = 0 },
		{ name = "Speed", color = Color3.fromRGB(100, 255, 150), x = 2.5*B },
	}
	for _, item in items do
		local glow = createPart({
			name = "Item_" .. item.name, size = Vector3.new(B, B, B),
			position = pos + Vector3.new(item.x, 3.5*B, 0),
			color = item.color, material = Enum.Material.Neon,
			canCollide = false, parent = shop,
		})
		addPointLight(glow, item.color, 0.5, 8)
	end

	-- NPC (simple blocky merchant character: Parts + Humanoid, no animations)
	local npcModel = Instance.new("Model")
	npcModel.Name = "ShopNPC"
	npcModel.Parent = shop

	local npcBody = createPart({
		name = "HumanoidRootPart", size = Vector3.new(1.5*B, 2*B, B),
		position = pos + Vector3.new(0, 3.5*B, -B),
		color = Color3.fromRGB(30, 80, 160), parent = npcModel,
	})

	local npcHead = createPart({
		name = "Head", size = Vector3.new(B, B, B),
		position = pos + Vector3.new(0, 5*B, -B),
		color = Color3.fromRGB(255, 200, 150), parent = npcModel,
	})

	-- NPC arms
	createPart({
		name = "LeftArm", size = Vector3.new(0.5*B, 1.8*B, B * 0.6),
		position = pos + Vector3.new(-1.2*B, 3.5*B, -B),
		color = Color3.fromRGB(30, 80, 160), parent = npcModel,
	})
	createPart({
		name = "RightArm", size = Vector3.new(0.5*B, 1.8*B, B * 0.6),
		position = pos + Vector3.new(1.2*B, 3.5*B, -B),
		color = Color3.fromRGB(30, 80, 160), parent = npcModel,
	})

	-- NPC hat (merchant flair)
	createPart({
		name = "Hat", size = Vector3.new(1.2*B, 0.4*B, 1.2*B),
		position = pos + Vector3.new(0, 5.7*B, -B),
		color = YELLOW, material = Enum.Material.SmoothPlastic, parent = npcModel,
	})

	-- Add Humanoid for NPC appearance (nameplate, health bar hidden)
	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.DisplayName = "Merchant"
	humanoid.NameDisplayDistance = 20
	humanoid.HealthDisplayDistance = 0 -- Hide health bar
	humanoid.Parent = npcModel

	npcModel.PrimaryPart = npcBody

	-- ProximityPrompt on invisible part in front of counter
	local promptPart = createPart({
		name = "ShopPrompt", size = Vector3.new(8*B, 3*B, 3*B),
		position = pos + Vector3.new(0, 1.5*B, B),
		color = Color3.new(1,1,1), transparency = 1, canCollide = false, parent = shop,
	})
	local shopPrompt = addProximityPrompt(promptPart, "Shop", "Press E to open Shop", 10)
	shopPrompt.Name = "ShopProximityPrompt"
	shopPrompt.KeyboardKeyCode = Enum.KeyCode.E
end

--============================================================================
-- 1.6 Codes Terminal
--============================================================================

local function buildCodesTerminal(parent: Model)
	local terminal = Instance.new("Model")
	terminal.Name = "CodesTerminal"
	terminal.Parent = parent

	local pos = CODES_POS

	-- Arcade machine body
	createPart({
		name = "Body", size = Vector3.new(3*B, 5*B, 2*B),
		position = pos + Vector3.new(0, 2.5*B, 0),
		color = Color3.fromRGB(40, 20, 60), material = Enum.Material.SmoothPlastic, parent = terminal,
	})

	-- Screen
	local screen = createPart({
		name = "Screen", size = Vector3.new(2.5*B, 2*B, 0.2),
		position = pos + Vector3.new(0, 4*B, B + 0.1),
		color = Color3.fromRGB(10, 10, 20), parent = terminal,
	})
	addSurfaceText(screen, "ENTER CODE", Color3.fromRGB(0, 255, 150), 30, Enum.NormalId.Front)

	-- Top sign
	local topSign = createPart({
		name = "TopSign", size = Vector3.new(3.5*B, B, 0.3),
		position = pos + Vector3.new(0, 5.5*B, B),
		color = PURPLE, material = Enum.Material.Neon, parent = terminal,
	})
	addSurfaceText(topSign, "CODES", Color3.fromRGB(255, 255, 255), 28, Enum.NormalId.Front)

	-- ProximityPrompt
	local codesPrompt = addProximityPrompt(screen, "Codes Terminal", "Press E to enter Code", 8)
	codesPrompt.Name = "CodesProximityPrompt"
	codesPrompt.KeyboardKeyCode = Enum.KeyCode.E
end

--============================================================================
-- 1.7 Daily Spin Wheel
--============================================================================

local function buildSpinWheel(parent: Model)
	local wheel = Instance.new("Model")
	wheel.Name = "DailySpinWheel"
	wheel.Parent = parent

	local pos = SPIN_POS

	-- Base stand
	createPart({
		name = "Stand", size = Vector3.new(2*B, 4*B, 2*B),
		position = pos + Vector3.new(0, 2*B, 0),
		color = Color3.fromRGB(60, 60, 80), material = Enum.Material.Metal, parent = wheel,
	})

	-- Wheel (large cylinder facing player)
	local wheelPart = createPart({
		name = "Wheel",
		size = Vector3.new(B, 8*B, 8*B),
		cframe = CFrame.new(pos + Vector3.new(0, 6*B, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(200, 50, 50),
		shape = Enum.PartType.Cylinder,
		material = Enum.Material.SmoothPlastic,
		parent = wheel,
	})

	-- Colored segment indicators (simple colored parts around the edge)
	local segColors = { RED, ORANGE, YELLOW, GREEN, CYAN, PURPLE, YELLOW, GREEN }
	for i, c in segColors do
		local angle = (i - 1) * (math.pi * 2 / #segColors)
		local radius = 3.5 * B
		local sx = math.cos(angle) * radius
		local sy = math.sin(angle) * radius
		createPart({
			name = "Seg_" .. tostring(i),
			size = Vector3.new(B, B, 0.5),
			position = pos + Vector3.new(0, 6*B + sy, sx),
			color = c, material = Enum.Material.Neon,
			canCollide = false, parent = wheel,
		})
	end

	-- Sign
	local sign = createPart({
		name = "SpinSign", size = Vector3.new(6*B, 2*B, 0.3),
		position = pos + Vector3.new(0, 10.5*B, 0),
		color = SIGN_COLOR, parent = wheel,
	})
	addSurfaceText(sign, "DAILY SPIN", ORANGE, 36, Enum.NormalId.Front)

	-- ProximityPrompt
	local spinPrompt = addProximityPrompt(wheelPart, "Daily Spin", "Spin!", 10)
	spinPrompt.Name = "SpinProximityPrompt"
	spinPrompt.KeyboardKeyCode = Enum.KeyCode.E
end

--============================================================================
-- 1.8 Leaderboard Podiums
--============================================================================

local function addBillboardGui(parent: BasePart, text: string, color: Color3, offsetY: number)
	local bbGui = Instance.new("BillboardGui")
	bbGui.Name = "NameDisplay"
	bbGui.Size = UDim2.new(0, 120, 0, 40)
	bbGui.StudsOffset = Vector3.new(0, offsetY, 0)
	bbGui.AlwaysOnTop = false
	bbGui.MaxDistance = 80
	bbGui.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "PlayerName"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.4
	label.TextSize = 18
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextScaled = false
	label.Parent = bbGui
end

local function buildPodiums(parent: Model)
	local podiums = Instance.new("Model")
	podiums.Name = "LeaderboardPodiums"
	podiums.Parent = parent

	local pos = PODIUM_POS

	-- Two podium groups side by side
	local groups = {
		{ name = "XP Champions", xOff = -12*B, color = YELLOW },
		{ name = "Level Leaders", xOff = 12*B, color = CYAN },
	}

	for _, group in groups do
		local gPos = pos + Vector3.new(group.xOff, 0, 0)

		-- 1st place podium (tall, gold)
		local first = createPart({
			name = group.name .. "_1st",
			size = Vector3.new(3*B, 5*B, 3*B),
			position = gPos + Vector3.new(0, 2.5*B, 0),
			color = GOLD, material = Enum.Material.SmoothPlastic, parent = podiums,
		})
		addBillboardGui(first, "#1 ---", GOLD, 3.5)

		-- 2nd place (left, shorter, silver)
		local second = createPart({
			name = group.name .. "_2nd",
			size = Vector3.new(3*B, 3.5*B, 3*B),
			position = gPos + Vector3.new(-3.5*B, 1.75*B, 0),
			color = SILVER, material = Enum.Material.SmoothPlastic, parent = podiums,
		})
		addBillboardGui(second, "#2 ---", SILVER, 2.75)

		-- 3rd place (right, shortest, bronze)
		local third = createPart({
			name = group.name .. "_3rd",
			size = Vector3.new(3*B, 2.5*B, 3*B),
			position = gPos + Vector3.new(3.5*B, 1.25*B, 0),
			color = BRONZE, material = Enum.Material.SmoothPlastic, parent = podiums,
		})
		addBillboardGui(third, "#3 ---", BRONZE, 2.25)

		-- Billboard behind podiums (top 10)
		local board = createPart({
			name = group.name .. "_Board",
			size = Vector3.new(12*B, 8*B, 0.5),
			position = gPos + Vector3.new(0, 6*B, -3*B),
			color = SIGN_COLOR, parent = podiums,
		})
		addSurfaceText(board, group.name .. "\n\n1. ---\n2. ---\n3. ---\n4. ---\n5. ---\n6. ---\n7. ---\n8. ---\n9. ---\n10. ---", group.color, 22, Enum.NormalId.Front)

		-- Group label
		local label = createPart({
			name = group.name .. "_Label",
			size = Vector3.new(12*B, 2*B, 0.3),
			position = gPos + Vector3.new(0, 10.5*B, -3*B),
			color = SIGN_COLOR, parent = podiums,
		})
		addSurfaceText(label, group.name, group.color, 32, Enum.NormalId.Front)
	end
end

--============================================================================
-- 1.9 Social / Gathering Space
--============================================================================

local function buildSocialSpace(parent: Model)
	local social = Instance.new("Model")
	social.Name = "SocialSpace"
	social.Parent = parent

	local pos = SOCIAL_POS

	-- Enlarged platform for 10+ players (18B × 14B = 36 × 28 studs = 1008 sq studs)
	createPart({
		name = "SocialPlatform", size = Vector3.new(18*B, 0.5, 14*B),
		position = pos + Vector3.new(0, 0.25, 0),
		color = Color3.fromRGB(70, 70, 85), material = Enum.Material.Concrete, parent = social,
	})

	-- Benches (Seats so players can sit) — spread wider on enlarged platform
	local benchPositions = {
		Vector3.new(-6*B, 0, -5*B),
		Vector3.new(6*B, 0, -5*B),
		Vector3.new(-6*B, 0, 5*B),
		Vector3.new(6*B, 0, 5*B),
	}
	for i, bPos in benchPositions do
		local benchPart = createPart({
			name = "Bench_" .. tostring(i),
			size = Vector3.new(4*B, B, 1.5*B),
			position = pos + bPos + Vector3.new(0, B * 0.75, 0),
			color = Color3.fromRGB(120, 80, 40),
			material = Enum.Material.Wood,
			parent = social,
		})
		-- Add Seat on top
		local seat = Instance.new("Seat")
		seat.Name = "Seat_" .. tostring(i)
		seat.Size = Vector3.new(4*B, 0.5, 1.5*B)
		seat.Position = pos + bPos + Vector3.new(0, B * 1.25 + 0.25, 0)
		seat.Anchored = true
		seat.Color = Color3.fromRGB(100, 60, 30)
		seat.Material = Enum.Material.Wood
		seat.Transparency = 0.1
		seat.Parent = social
	end

	-- Low decorative hedges dividing zones (visual separation, not blocking movement)
	-- These are thin, low parts that players can easily step/walk over (height < jump height)
	local hedgeColor = Color3.fromRGB(40, 100, 35)
	local hedgePositions = {
		-- North edge (between social space and spawn area)
		{ pos = Vector3.new(0, 0, -7*B), size = Vector3.new(16*B, 1.5*B, B) },
		-- South edge (between social space and portals direction)
		{ pos = Vector3.new(0, 0, 7*B), size = Vector3.new(16*B, 1.5*B, B) },
		-- Short divider between left benches and fountain
		{ pos = Vector3.new(-3*B, 0, 0), size = Vector3.new(B, 1.2*B, 6*B) },
		-- Short divider between right benches and fountain
		{ pos = Vector3.new(3*B, 0, 0), size = Vector3.new(B, 1.2*B, 6*B) },
	}
	for i, hedge in hedgePositions do
		createPart({
			name = "Hedge_" .. tostring(i),
			size = hedge.size,
			position = pos + hedge.pos + Vector3.new(0, hedge.size.Y / 2 + 0.5, 0),
			color = hedgeColor,
			material = Enum.Material.LeafyGrass,
			canCollide = false, -- Does not block movement
			parent = social,
		})
	end

	-- Small Tetris-themed fountain (center of social area)
	local fountain = createPart({
		name = "FountainBase",
		size = Vector3.new(4*B, B, 4*B),
		position = pos + Vector3.new(0, 0.75, 0),
		color = Color3.fromRGB(80, 80, 100),
		material = Enum.Material.Marble,
		shape = Enum.PartType.Cylinder,
		parent = social,
	})
	fountain.Size = Vector3.new(B, 4*B, 4*B)
	fountain.CFrame = CFrame.new(pos + Vector3.new(0, 0.75, 0)) * CFrame.Angles(0, 0, math.rad(90))

	-- Water particle effect
	local waterTop = createPart({
		name = "FountainWater",
		size = Vector3.new(2*B, 0.2, 2*B),
		position = pos + Vector3.new(0, 1.5, 0),
		color = CYAN, transparency = 0.5, canCollide = false, parent = social,
	})
	local waterEmitter = Instance.new("ParticleEmitter")
	waterEmitter.Color = ColorSequence.new(CYAN)
	waterEmitter.Size = NumberSequence.new(0.3, 0)
	waterEmitter.Lifetime = NumberRange.new(0.5, 1)
	waterEmitter.Rate = 20
	waterEmitter.Speed = NumberRange.new(3, 5)
	waterEmitter.SpreadAngle = Vector2.new(20, 20)
	waterEmitter.Transparency = NumberSequence.new(0.2, 1)
	waterEmitter.Parent = waterTop
end

--============================================================================
-- 1.10 Ambient Effects (particles, fog, path lights)
--============================================================================

local function buildAmbientEffects(parent: Model)
	-- Floating Tetris block particles drifting through the air
	-- Multiple emitter zones at different heights for depth
	local emitterPositions = {
		{ pos = Vector3.new(0, 30 * B, 0), size = Vector3.new(GROUND_RADIUS * 1.5, 1, GROUND_RADIUS * 1.5) },
		{ pos = Vector3.new(20 * B, 20 * B, 10 * B), size = Vector3.new(GROUND_RADIUS, 1, GROUND_RADIUS) },
		{ pos = Vector3.new(-15 * B, 25 * B, -10 * B), size = Vector3.new(GROUND_RADIUS, 1, GROUND_RADIUS * 0.8) },
	}

	for idx, emitterDef in emitterPositions do
		local skyEmitter = createPart({
			name = "SkyParticles_" .. tostring(idx),
			size = emitterDef.size,
			position = emitterDef.pos,
			color = Color3.new(1,1,1), transparency = 1, canCollide = false, parent = parent,
		})
		local driftEmitter = Instance.new("ParticleEmitter")
		driftEmitter.Name = "TetrisDrift"
		driftEmitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, CYAN),
			ColorSequenceKeypoint.new(0.2, YELLOW),
			ColorSequenceKeypoint.new(0.4, PURPLE),
			ColorSequenceKeypoint.new(0.6, GREEN),
			ColorSequenceKeypoint.new(0.8, ORANGE),
			ColorSequenceKeypoint.new(1, RED),
		})
		-- Larger square-ish particles to represent Tetris blocks
		driftEmitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.5),
			NumberSequenceKeypoint.new(0.5, 2.5),
			NumberSequenceKeypoint.new(1, 1.0),
		})
		driftEmitter.Lifetime = NumberRange.new(10, 20)
		driftEmitter.Rate = if idx == 1 then 4 else 2
		driftEmitter.Speed = NumberRange.new(0.5, 2)
		driftEmitter.SpreadAngle = Vector2.new(180, 40)
		driftEmitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(0.3, 0.3),
			NumberSequenceKeypoint.new(0.7, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		})
		driftEmitter.RotSpeed = NumberRange.new(-45, 45)
		driftEmitter.Rotation = NumberRange.new(0, 360)
		driftEmitter.LightEmission = 0.3
		driftEmitter.Parent = skyEmitter
	end

	-- Path lights (ground-level colored PointLights along paths)
	-- Main path to Tetris portal
	for i = 1, 8 do
		local t = i / 9
		local lPos = SPAWN_POS:Lerp(TETRIS_PORTAL_POS, t)
		local lightPart = createPart({
			name = "PathLight_Tetris_" .. tostring(i),
			size = Vector3.new(B * 0.5, B * 0.2, B * 0.5),
			position = Vector3.new(lPos.X + 2*B, 0.15, lPos.Z),
			color = CYAN, material = Enum.Material.Neon,
			canCollide = false, parent = parent,
		})
		addPointLight(lightPart, CYAN, 0.4, 10)

		-- Mirror light on other side of path
		local mirrorPart = createPart({
			name = "PathLight_Tetris_M_" .. tostring(i),
			size = Vector3.new(B * 0.5, B * 0.2, B * 0.5),
			position = Vector3.new(lPos.X - 2*B, 0.15, lPos.Z),
			color = CYAN, material = Enum.Material.Neon,
			canCollide = false, parent = parent,
		})
		addPointLight(mirrorPart, CYAN, 0.3, 8)
	end

	-- Accent lights at path intersections near spawn
	local accentPositions = {
		{ pos = Vector3.new(4 * B, 0.15, 4 * B), color = GREEN },
		{ pos = Vector3.new(-4 * B, 0.15, 4 * B), color = YELLOW },
		{ pos = Vector3.new(4 * B, 0.15, -4 * B), color = ORANGE },
		{ pos = Vector3.new(-4 * B, 0.15, -4 * B), color = PURPLE },
	}
	for i, accent in accentPositions do
		local aPart = createPart({
			name = "AccentLight_" .. tostring(i),
			size = Vector3.new(B * 0.6, B * 0.15, B * 0.6),
			position = accent.pos,
			color = accent.color, material = Enum.Material.Neon,
			canCollide = false, parent = parent,
		})
		addPointLight(aPart, accent.color, 0.5, 12)
	end
end

local function setupLighting()
	-- Configure Lighting for warm golden hour atmosphere (skybox-appropriate)
	local lighting = game:GetService("Lighting")
	lighting.Ambient = Color3.fromRGB(60, 50, 45)
	lighting.OutdoorAmbient = Color3.fromRGB(90, 80, 70)
	lighting.Brightness = 2.2
	lighting.ClockTime = 17.5 -- Late golden hour for warm orange/pink sky
	lighting.GeographicLatitude = 25
	lighting.EnvironmentDiffuseScale = 1
	lighting.EnvironmentSpecularScale = 1
	lighting.GlobalShadows = true
	lighting.ShadowSoftness = 0.3

	-- Atmosphere: soft haze for that open-air island feel
	local existingAtmo = lighting:FindFirstChildOfClass("Atmosphere")
	if existingAtmo then existingAtmo:Destroy() end
	local atmo = Instance.new("Atmosphere")
	atmo.Density = 0.25
	atmo.Offset = 0.4
	atmo.Color = Color3.fromRGB(200, 170, 150) -- Warm golden tones
	atmo.Decay = Color3.fromRGB(120, 90, 100)
	atmo.Glare = 0.4
	atmo.Haze = 2
	atmo.Parent = lighting

	-- Color correction: warm golden tint pushing the sunset feel
	local existingCC = lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if existingCC then existingCC:Destroy() end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = Color3.fromRGB(255, 240, 220) -- Warm golden tint
	cc.Brightness = 0.03
	cc.Contrast = 0.08
	cc.Saturation = 0.2
	cc.Parent = lighting

	-- Bloom for soft glow on neon elements
	local existingBloom = lighting:FindFirstChildOfClass("BloomEffect")
	if not existingBloom then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.5
		bloom.Size = 24
		bloom.Threshold = 1.5
		bloom.Parent = lighting
	end

	-- Sun rays for dramatic sky effect
	local existingSunRays = lighting:FindFirstChildOfClass("SunRaysEffect")
	if not existingSunRays then
		local sunRays = Instance.new("SunRaysEffect")
		sunRays.Intensity = 0.15
		sunRays.Spread = 0.8
		sunRays.Parent = lighting
	end
end

--============================================================================
-- Mascot Display Case
--============================================================================

local function buildMascotDisplay(parent: Model)
	local display = Instance.new("Model")
	display.Name = "MascotDisplayCase"
	display.Parent = parent

	local pos = MASCOT_DISPLAY_POS

	-- Glass cabinet base (raised platform)
	createPart({
		name = "DisplayBase",
		size = Vector3.new(8 * B, B, 5 * B),
		position = pos + Vector3.new(0, 0.5 * B, 0),
		color = Color3.fromRGB(50, 50, 65),
		material = Enum.Material.Marble,
		parent = display,
	})

	-- Glass walls (transparent enclosure)
	-- Back wall
	createPart({
		name = "GlassBack",
		size = Vector3.new(8 * B, 4 * B, 0.3),
		position = pos + Vector3.new(0, 3 * B, -2.5 * B),
		color = Color3.fromRGB(180, 220, 255),
		material = Enum.Material.Glass,
		transparency = 0.7,
		canCollide = true,
		parent = display,
	})

	-- Left wall
	createPart({
		name = "GlassLeft",
		size = Vector3.new(0.3, 4 * B, 5 * B),
		position = pos + Vector3.new(-4 * B, 3 * B, 0),
		color = Color3.fromRGB(180, 220, 255),
		material = Enum.Material.Glass,
		transparency = 0.7,
		canCollide = true,
		parent = display,
	})

	-- Right wall
	createPart({
		name = "GlassRight",
		size = Vector3.new(0.3, 4 * B, 5 * B),
		position = pos + Vector3.new(4 * B, 3 * B, 0),
		color = Color3.fromRGB(180, 220, 255),
		material = Enum.Material.Glass,
		transparency = 0.7,
		canCollide = true,
		parent = display,
	})

	-- Preview mascot orbs inside the cabinet (colored neon spheres representing mascots)
	local mascotColors = {
		Color3.fromRGB(70, 130, 230),   -- Pixel Pup (Blue)
		Color3.fromRGB(150, 70, 200),   -- Cube Cat (Purple)
		Color3.fromRGB(50, 200, 80),    -- Pipe Frog (Green)
		Color3.fromRGB(230, 100, 30),   -- Flame Fox (Orange)
		Color3.fromRGB(80, 40, 120),    -- Shadow Owl (Dark Purple)
		Color3.fromRGB(255, 200, 50),   -- Golden Dragon (Gold)
	}

	for i, color in mascotColors do
		local col = ((i - 1) % 3)
		local row = math.floor((i - 1) / 3)
		local orbX = (col - 1) * 2.5 * B
		local orbZ = (row - 0.5) * 2 * B

		local orb = createPart({
			name = "MascotOrb_" .. tostring(i),
			size = Vector3.new(1.5 * B, 1.5 * B, 1.5 * B),
			position = pos + Vector3.new(orbX, 2.5 * B, orbZ),
			color = color,
			material = Enum.Material.Neon,
			shape = Enum.PartType.Ball,
			canCollide = false,
			parent = display,
		})
		addPointLight(orb, color, 0.6, 8)
	end

	-- Sign above case: "MASCOTS"
	local sign = createPart({
		name = "MascotSign",
		size = Vector3.new(8 * B, 2 * B, 0.3),
		position = pos + Vector3.new(0, 5.5 * B, -2.5 * B),
		color = SIGN_COLOR,
		parent = display,
	})
	addSurfaceText(sign, "MASCOTS", Color3.fromRGB(255, 150, 255), 36, Enum.NormalId.Front)

	-- ProximityPrompt trigger area (in front of the case)
	local promptPart = createPart({
		name = "MascotPrompt",
		size = Vector3.new(8 * B, 3 * B, 3 * B),
		position = pos + Vector3.new(0, 1.5 * B, 3 * B),
		color = Color3.new(1, 1, 1),
		transparency = 1,
		canCollide = false,
		parent = display,
	})
	local mascotPrompt = addProximityPrompt(promptPart, "Mascots", "Press E to view Mascots", 10)
	mascotPrompt.Name = "MascotProximityPrompt"
	mascotPrompt.KeyboardKeyCode = Enum.KeyCode.E
end

--============================================================================
-- Public API
--============================================================================

--- Build the entire lobby and parent to Workspace.
--- Returns the gate trigger Part for GameServer to wire touch detection.
function LobbyBuilder.init(): Part?
	-- Clean up existing lobby
	local existing = workspace:FindFirstChild("Lobby")
	if existing then existing:Destroy() end

	local model = Instance.new("Model")
	model.Name = "Lobby"

	-- Build all sections
	buildGround(model)
	buildInvisibleBarriers(model)
	buildPaths(model)
	buildCenterpiece(model)
	local trigger = buildTetrisPortal(model)
	buildPipeWorldPortal(model)
	buildShopBooth(model)
	buildCodesTerminal(model)
	buildSpinWheel(model)
	buildPodiums(model)
	buildSocialSpace(model)
	buildMascotDisplay(model)
	buildAmbientEffects(model)

	model.Parent = workspace
	lobbyModel = model
	gateTouchPart = trigger

	-- Setup lighting atmosphere
	setupLighting()

	-- Start centerpiece spin
	startCenterpieceSpin()

	-- Start portal pulsing glow
	startPortalPulse()

	return trigger
end

--- Get the gate trigger part for external wiring.
function LobbyBuilder.getGateTrigger(): Part?
	return gateTouchPart :: Part?
end

--- Get the lobby spawn position.
function LobbyBuilder.getSpawnPosition(): Vector3
	return Vector3.new(0, 3, 0) -- Above the raised spawn platform
end

--- Update the BillboardGui name display on a podium part.
local function updatePodiumName(podiums: Model, partName: string, displayName: string)
	local part = podiums:FindFirstChild(partName) :: BasePart?
	if not part then return end
	local bbGui = part:FindFirstChild("NameDisplay") :: BillboardGui?
	if not bbGui then return end
	local label = bbGui:FindFirstChild("PlayerName") :: TextLabel?
	if label then
		label.Text = displayName
	end
end

--- Update leaderboard podium boards and BillboardGui names with live data.
function LobbyBuilder.updateLeaderboards(topXP: {{displayName: string, value: number}}, topLevel: {{displayName: string, value: number}})
	if not lobbyModel then return end

	local podiums = lobbyModel:FindFirstChild("LeaderboardPodiums")
	if not podiums then return end

	-- Update XP podium BillboardGui names (top 3)
	local xpPodiumSuffixes = { "_1st", "_2nd", "_3rd" }
	for i, suffix in xpPodiumSuffixes do
		local name = if i <= #topXP then topXP[i].displayName else "---"
		updatePodiumName(podiums, "XP Champions" .. suffix, "#" .. tostring(i) .. " " .. name)
	end

	-- Update Level podium BillboardGui names (top 3)
	for i, suffix in xpPodiumSuffixes do
		local name = if i <= #topLevel then topLevel[i].displayName else "---"
		updatePodiumName(podiums, "Level Leaders" .. suffix, "#" .. tostring(i) .. " " .. name)
	end

	-- Format and update XP board (full top 10)
	local xpBoard = podiums:FindFirstChild("XP Champions_Board") :: Part?
	if xpBoard then
		local text = "XP Champions\n"
		for i = 1, math.min(10, #topXP) do
			local e = topXP[i]
			local n = if #e.displayName > 10 then string.sub(e.displayName, 1, 9) .. ".." else e.displayName
			text = text .. "\n#" .. tostring(i) .. " " .. n .. " - " .. tostring(e.value)
		end
		if #topXP == 0 then text = text .. "\n\nNo rankings yet!" end
		local gui = xpBoard:FindFirstChild("SignGui") :: SurfaceGui?
		if gui then
			local label = gui:FindFirstChild("Text") :: TextLabel?
			if label then label.Text = text end
		end
	end

	-- Format and update Level board (full top 10)
	local lvBoard = podiums:FindFirstChild("Level Leaders_Board") :: Part?
	if lvBoard then
		local text = "Level Leaders\n"
		for i = 1, math.min(10, #topLevel) do
			local e = topLevel[i]
			local n = if #e.displayName > 10 then string.sub(e.displayName, 1, 9) .. ".." else e.displayName
			text = text .. "\n#" .. tostring(i) .. " " .. n .. " - Lv" .. tostring(e.value)
		end
		if #topLevel == 0 then text = text .. "\n\nNo rankings yet!" end
		local gui = lvBoard:FindFirstChild("SignGui") :: SurfaceGui?
		if gui then
			local label = gui:FindFirstChild("Text") :: TextLabel?
			if label then label.Text = text end
		end
	end
end

--- Update the Tetris portal progress display for a specific player's completion.
--- Called when player enters the lobby.
function LobbyBuilder.updatePortalProgress(completedLevels: number)
	if not lobbyModel then return end
	local portal = lobbyModel:FindFirstChild("TetrisPortal")
	if not portal then return end
	local progSign = portal:FindFirstChild("ProgressSign") :: Part?
	if progSign then
		local gui = progSign:FindFirstChild("SignGui") :: SurfaceGui?
		if gui then
			local label = gui:FindFirstChild("Text") :: TextLabel?
			if label then
				label.Text = tostring(completedLevels) .. "/10 complete"
			end
		end
	end
end

return LobbyBuilder
