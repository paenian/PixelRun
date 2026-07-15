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
local RunService = game:GetService("RunService")

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

-- Ground
local GROUND_RADIUS = 50 * B -- 100 studs radius
local GROUND_COLOR = Color3.fromRGB(80, 90, 80)
local PATH_COLOR = Color3.fromRGB(140, 110, 80)
local SPAWN_PLATFORM_COLOR = Color3.fromRGB(50, 50, 65)
local SPAWN_TRIM_COLOR = Color3.fromRGB(0, 200, 255)

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
	-- Main ground (large circular feel via square with rounded appearance)
	createPart({
		name = "LobbyGround",
		size = Vector3.new(GROUND_RADIUS * 2, 1, GROUND_RADIUS * 2),
		position = Vector3.new(0, -0.5, 0),
		color = GROUND_COLOR,
		material = Enum.Material.Grass,
		parent = parent,
	})

	-- Central spawn platform (circular cylinder)
	local spawnPlat = createPart({
		name = "SpawnPlatform",
		size = Vector3.new(12 * B, 1, 12 * B),
		position = Vector3.new(0, 0.5, 0),
		color = SPAWN_PLATFORM_COLOR,
		material = Enum.Material.Marble,
		shape = Enum.PartType.Cylinder,
		parent = parent,
	})
	-- Cylinder: Size.X = length (height when rotated), Y/Z = diameter
	spawnPlat.Size = Vector3.new(1, 12 * B, 12 * B)
	spawnPlat.CFrame = CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90))

	-- Glowing trim ring around spawn
	local trimRing = createPart({
		name = "SpawnTrim",
		size = Vector3.new(1.5, 13 * B, 13 * B),
		cframe = CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color = SPAWN_TRIM_COLOR,
		material = Enum.Material.Neon,
		shape = Enum.PartType.Cylinder,
		canCollide = false,
		transparency = 0.3,
		parent = parent,
	})
	addPointLight(trimRing, SPAWN_TRIM_COLOR, 0.6, 20)

	-- SpawnLocation
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = SPAWN_POS
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

local function buildCenterpiece(parent: Model)
	local cpModel = Instance.new("Model")
	cpModel.Name = "Centerpiece"
	cpModel.Parent = parent

	-- Build a T-piece shape (large, 3x scale) that will spin
	local pieceScale = 3 * B
	local colors = { PURPLE, PURPLE, PURPLE, PURPLE }
	local offsets = { {0,0}, {1,0}, {2,0}, {1,1} } -- T-piece

	local pivotPart: Part? = nil
	for idx, off in offsets do
		local block = createPart({
			name = "CenterBlock_" .. tostring(idx),
			size = Vector3.new(pieceScale, pieceScale, pieceScale),
			position = CENTERPIECE_POS + Vector3.new(
				(off[1] - 1) * pieceScale,
				off[2] * pieceScale,
				0
			),
			color = colors[idx],
			material = Enum.Material.Neon,
			canCollide = false,
			parent = cpModel,
		})
		if idx == 1 then
			pivotPart = block
		end
	end

	-- Add a slow spinning tween on the model pivot
	if pivotPart then
		cpModel.PrimaryPart = pivotPart
		-- Use RunService to rotate the model slowly
		centerpieceModel = cpModel
	end
end

local function startCenterpieceSpin()
	if not centerpieceModel or not centerpieceModel.PrimaryPart then
		return
	end
	task.spawn(function()
		while centerpieceModel and centerpieceModel.Parent do
			local pp = centerpieceModel.PrimaryPart
			if pp then
				local cf = pp.CFrame
				local center = CENTERPIECE_POS
				-- Rotate all parts around center Y axis
				for _, child in centerpieceModel:GetChildren() do
					if child:IsA("BasePart") then
						local offset = child.Position - center
						local angle = math.rad(0.5) -- 0.5 degrees per frame
						local cos, sin = math.cos(angle), math.sin(angle)
						local newX = offset.X * cos - offset.Z * sin
						local newZ = offset.X * sin + offset.Z * cos
						child.Position = center + Vector3.new(newX, offset.Y, newZ)
					end
				end
			end
			task.wait(1/30)
		end
	end)
end

--============================================================================
-- 1.3 Tetris Portal (with particles + progress)
--============================================================================

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
		createPart({
			name = "PillarL_" .. tostring(row),
			size = Vector3.new(frameD, B, frameD),
			position = pos + Vector3.new(-archW/2, (row + 0.5) * B, 0),
			color = c, material = Enum.Material.SmoothPlastic, parent = portal,
		})
	end

	-- Right pillar
	for row = 0, 6 do
		local c = ({ORANGE, YELLOW, CYAN, GREEN, PURPLE, BLUE, CYAN})[row + 1]
		createPart({
			name = "PillarR_" .. tostring(row),
			size = Vector3.new(frameD, B, frameD),
			position = pos + Vector3.new(archW/2, (row + 0.5) * B, 0),
			color = c, material = Enum.Material.SmoothPlastic, parent = portal,
		})
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
	addPointLight(particlePart, CYAN, 2, 25)

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

	-- "COMING SOON" sign
	local sign = createPart({
		name = "ComingSoonSign",
		size = Vector3.new(archW + 2*B, 2*B, 0.3),
		position = pos + Vector3.new(0, archH + 3.5*B, -B),
		color = SIGN_COLOR, parent = portal,
	})
	addSurfaceText(sign, "PIPE WORLD", pipeColor, 36, Enum.NormalId.Back)

	local subSign = createPart({
		name = "SubSign",
		size = Vector3.new(archW, B, 0.3),
		position = pos + Vector3.new(0, archH + 1.8*B, -B),
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

	-- Back wall
	local wall = createPart({
		name = "BackWall", size = Vector3.new(10*B, 6*B, B),
		position = pos + Vector3.new(0, 3*B, -2*B),
		color = SIGN_COLOR, parent = shop,
	})
	addSurfaceText(wall, "UPGRADES", YELLOW, 48, Enum.NormalId.Front)

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

	-- NPC (simple block character behind counter)
	local npcHead = createPart({
		name = "NPCHead", size = Vector3.new(B, B, B),
		position = pos + Vector3.new(0, 5*B, -B),
		color = Color3.fromRGB(255, 200, 150), parent = shop,
	})
	createPart({
		name = "NPCBody", size = Vector3.new(1.5*B, 2*B, B),
		position = pos + Vector3.new(0, 3.5*B, -B),
		color = Color3.fromRGB(30, 80, 160), parent = shop,
	})

	-- ProximityPrompt on counter
	local promptPart = createPart({
		name = "ShopPrompt", size = Vector3.new(8*B, 3*B, 3*B),
		position = pos + Vector3.new(0, 1.5*B, B),
		color = Color3.new(1,1,1), transparency = 1, canCollide = false, parent = shop,
	})
	addProximityPrompt(promptPart, "Upgrade Shop", "Open", 10)
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
	addProximityPrompt(screen, "Codes Terminal", "Enter Code", 8)
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
	addProximityPrompt(wheelPart, "Daily Spin", "Spin!", 10)
end

--============================================================================
-- 1.8 Leaderboard Podiums
--============================================================================

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
		createPart({
			name = group.name .. "_1st",
			size = Vector3.new(3*B, 5*B, 3*B),
			position = gPos + Vector3.new(0, 2.5*B, 0),
			color = GOLD, material = Enum.Material.SmoothPlastic, parent = podiums,
		})

		-- 2nd place (left, shorter, silver)
		createPart({
			name = group.name .. "_2nd",
			size = Vector3.new(3*B, 3.5*B, 3*B),
			position = gPos + Vector3.new(-3.5*B, 1.75*B, 0),
			color = SILVER, material = Enum.Material.SmoothPlastic, parent = podiums,
		})

		-- 3rd place (right, shortest, bronze)
		createPart({
			name = group.name .. "_3rd",
			size = Vector3.new(3*B, 2.5*B, 3*B),
			position = gPos + Vector3.new(3.5*B, 1.25*B, 0),
			color = BRONZE, material = Enum.Material.SmoothPlastic, parent = podiums,
		})

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

	-- Raised platform
	createPart({
		name = "SocialPlatform", size = Vector3.new(14*B, 0.5, 10*B),
		position = pos + Vector3.new(0, 0.25, 0),
		color = Color3.fromRGB(70, 70, 85), material = Enum.Material.Concrete, parent = social,
	})

	-- Benches (Seats so players can sit)
	local benchPositions = {
		Vector3.new(-4*B, 0, -3*B),
		Vector3.new(4*B, 0, -3*B),
		Vector3.new(-4*B, 0, 3*B),
		Vector3.new(4*B, 0, 3*B),
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
	-- Floating Tetris blocks drifting through the sky (particle emitter high up)
	local skyEmitter = createPart({
		name = "SkyParticles",
		size = Vector3.new(GROUND_RADIUS, 1, GROUND_RADIUS),
		position = Vector3.new(0, 40 * B, 0),
		color = Color3.new(1,1,1), transparency = 1, canCollide = false, parent = parent,
	})
	local driftEmitter = Instance.new("ParticleEmitter")
	driftEmitter.Name = "TetrisDrift"
	driftEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, CYAN),
		ColorSequenceKeypoint.new(0.25, YELLOW),
		ColorSequenceKeypoint.new(0.5, PURPLE),
		ColorSequenceKeypoint.new(0.75, GREEN),
		ColorSequenceKeypoint.new(1, ORANGE),
	})
	driftEmitter.Size = NumberSequence.new(1, 2)
	driftEmitter.Lifetime = NumberRange.new(8, 15)
	driftEmitter.Rate = 5
	driftEmitter.Speed = NumberRange.new(1, 3)
	driftEmitter.SpreadAngle = Vector2.new(180, 30)
	driftEmitter.Transparency = NumberSequence.new(0.4, 0.8)
	driftEmitter.RotSpeed = NumberRange.new(-30, 30)
	driftEmitter.Parent = skyEmitter

	-- Path lights (ground-level PointLights along the main path to Tetris portal)
	for i = 1, 8 do
		local t = i / 9
		local lPos = SPAWN_POS:Lerp(TETRIS_PORTAL_POS, t)
		local lightPart = createPart({
			name = "PathLight_" .. tostring(i),
			size = Vector3.new(B * 0.5, B * 0.3, B * 0.5),
			position = Vector3.new(lPos.X + 2*B, 0.3, lPos.Z),
			color = CYAN, material = Enum.Material.Neon,
			canCollide = false, parent = parent,
		})
		addPointLight(lightPart, CYAN, 0.4, 10)
	end
end

local function setupLighting()
	-- Configure Lighting for warm atmospheric feel
	local lighting = game:GetService("Lighting")
	lighting.Ambient = Color3.fromRGB(50, 45, 55)
	lighting.OutdoorAmbient = Color3.fromRGB(80, 75, 85)
	lighting.Brightness = 2
	lighting.ClockTime = 17 -- Golden hour
	lighting.GeographicLatitude = 30

	-- Atmosphere
	local existingAtmo = lighting:FindFirstChildOfClass("Atmosphere")
	if not existingAtmo then
		local atmo = Instance.new("Atmosphere")
		atmo.Density = 0.2
		atmo.Offset = 0.5
		atmo.Color = Color3.fromRGB(180, 160, 200)
		atmo.Decay = Color3.fromRGB(100, 80, 120)
		atmo.Glare = 0.3
		atmo.Haze = 1.5
		atmo.Parent = lighting
	end

	-- Color correction for warmth
	local existingCC = lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if not existingCC then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.TintColor = Color3.fromRGB(255, 245, 230)
		cc.Brightness = 0.02
		cc.Contrast = 0.05
		cc.Saturation = 0.15
		cc.Parent = lighting
	end
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
	buildAmbientEffects(model)

	model.Parent = workspace
	lobbyModel = model
	gateTouchPart = trigger

	-- Setup lighting atmosphere
	setupLighting()

	-- Start centerpiece spin
	startCenterpieceSpin()

	return trigger
end

--- Get the gate trigger part for external wiring.
function LobbyBuilder.getGateTrigger(): Part?
	return gateTouchPart :: Part?
end

--- Get the lobby spawn position.
function LobbyBuilder.getSpawnPosition(): Vector3
	return SPAWN_POS
end

--- Update leaderboard podium boards with live data.
function LobbyBuilder.updateLeaderboards(topXP: {{displayName: string, value: number}}, topLevel: {{displayName: string, value: number}})
	if not lobbyModel then return end

	local podiums = lobbyModel:FindFirstChild("LeaderboardPodiums")
	if not podiums then return end

	-- Format and update XP board
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

	-- Format and update Level board
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
