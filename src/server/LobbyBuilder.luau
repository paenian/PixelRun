--!strict
--[[
    LobbyBuilder.luau - Physical 3D lobby construction

    Builds the lobby as a walkable 3D space in Workspace containing:
    - Large flat ground platform with spawn point at center
    - Tetris-piece archway gate (portal to Tetris pack level 1)
    - Power-up upgrade shop area (pedestals with signs)
    - "Coming Soon" sign for Pipe World
    - Leaderboard display boards (physical SurfaceGui billboards)
    - Decorative boundary walls

    The Tetris gate uses a TouchPart to detect when a player walks through,
    triggering level start on the server. The gate is built from colored
    blocks arranged as Tetris I, T, and L pieces forming an arch.
]]

local LobbyBuilder = {}

--============================================================================
-- Constants
--============================================================================

local BLOCK = 2 -- 1 game block = 2 studs (matches LevelGenerator.BLOCK_SCALE)

-- Lobby dimensions (in studs)
local GROUND_SIZE = Vector3.new(60 * BLOCK, 1, 60 * BLOCK) -- 120x120 studs
local GROUND_POS = Vector3.new(0, -0.5, 0)

-- Spawn
local SPAWN_POSITION = Vector3.new(0, 3, 0)

-- Tetris Gate (centered at +Z side of lobby)
local GATE_CENTER = Vector3.new(0, 0, 40 * BLOCK) -- 80 studs forward from center
local GATE_WIDTH = 5 * BLOCK -- 10 studs wide opening
local GATE_HEIGHT = 5 * BLOCK -- 10 studs tall opening

-- Shop area (left side)
local SHOP_CENTER = Vector3.new(-20 * BLOCK, 0, 0)

-- Coming Soon sign (right side)
local COMING_SOON_CENTER = Vector3.new(20 * BLOCK, 0, 30 * BLOCK)

-- Leaderboard boards (near spawn, flanking)
local LEADERBOARD_LEFT_POS = Vector3.new(-12 * BLOCK, 4 * BLOCK, -10 * BLOCK)
local LEADERBOARD_RIGHT_POS = Vector3.new(12 * BLOCK, 4 * BLOCK, -10 * BLOCK)

-- Colors
local GROUND_COLOR = Color3.fromRGB(45, 45, 55)
local WALL_COLOR = Color3.fromRGB(30, 30, 40)
local SHOP_PEDESTAL_COLOR = Color3.fromRGB(60, 60, 80)
local SIGN_COLOR = Color3.fromRGB(20, 20, 30)

-- Tetris piece colors
local CYAN = Color3.fromRGB(0, 255, 255)
local YELLOW = Color3.fromRGB(255, 255, 0)
local PURPLE = Color3.fromRGB(128, 0, 128)
local GREEN = Color3.fromRGB(0, 255, 0)
local RED = Color3.fromRGB(255, 0, 0)
local ORANGE = Color3.fromRGB(255, 165, 0)
local BLUE = Color3.fromRGB(0, 0, 255)

--============================================================================
-- State
--============================================================================

local lobbyModel: Model? = nil
local gateTouchPart: BasePart? = nil

--============================================================================
-- Helper: Create an anchored block
--============================================================================

local function createBlock(props: {
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	material: Enum.Material?,
	transparency: number?,
	canCollide: boolean?,
	parent: Instance,
}): Part
	local part = Instance.new("Part")
	part.Name = props.name
	part.Size = props.size
	part.Position = props.position
	part.Color = props.color
	part.Material = props.material or Enum.Material.SmoothPlastic
	part.Transparency = props.transparency or 0
	part.Anchored = true
	part.CanCollide = if props.canCollide ~= nil then props.canCollide else true
	part.Parent = props.parent
	return part
end

--============================================================================
-- Helper: Create a SurfaceGui text sign on a part
--============================================================================

local function addSurfaceText(part: Part, text: string, textColor: Color3, textSize: number, face: Enum.NormalId?)
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "SignGui"
	surfaceGui.Face = face or Enum.NormalId.Front
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 30
	surfaceGui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = textColor
	label.TextSize = textSize
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextWrapped = true
	label.Parent = surfaceGui
end

--============================================================================
-- Build: Ground and Boundaries
--============================================================================

local function buildGround(parent: Model)
	-- Main floor
	createBlock({
		name = "LobbyGround",
		size = GROUND_SIZE,
		position = GROUND_POS,
		color = GROUND_COLOR,
		material = Enum.Material.Slate,
		parent = parent,
	})

	-- Boundary walls (4 sides, tall enough players can't jump over)
	local wallHeight = 8 * BLOCK
	local wallThickness = BLOCK
	local halfX = GROUND_SIZE.X / 2
	local halfZ = GROUND_SIZE.Z / 2

	-- Back wall (-Z)
	createBlock({
		name = "WallBack",
		size = Vector3.new(GROUND_SIZE.X, wallHeight, wallThickness),
		position = Vector3.new(0, wallHeight / 2, -halfZ),
		color = WALL_COLOR,
		parent = parent,
	})

	-- Left wall (-X)
	createBlock({
		name = "WallLeft",
		size = Vector3.new(wallThickness, wallHeight, GROUND_SIZE.Z),
		position = Vector3.new(-halfX, wallHeight / 2, 0),
		color = WALL_COLOR,
		parent = parent,
	})

	-- Right wall (+X)
	createBlock({
		name = "WallRight",
		size = Vector3.new(wallThickness, wallHeight, GROUND_SIZE.Z),
		position = Vector3.new(halfX, wallHeight / 2, 0),
		color = WALL_COLOR,
		parent = parent,
	})

	-- Front wall (+Z) with a gap for the gate
	local frontWallSegmentWidth = (GROUND_SIZE.X - GATE_WIDTH) / 2 - BLOCK
	-- Left segment
	createBlock({
		name = "WallFrontLeft",
		size = Vector3.new(frontWallSegmentWidth, wallHeight, wallThickness),
		position = Vector3.new(-(frontWallSegmentWidth / 2 + GATE_WIDTH / 2 + BLOCK / 2), wallHeight / 2, halfZ),
		color = WALL_COLOR,
		parent = parent,
	})
	-- Right segment
	createBlock({
		name = "WallFrontRight",
		size = Vector3.new(frontWallSegmentWidth, wallHeight, wallThickness),
		position = Vector3.new((frontWallSegmentWidth / 2 + GATE_WIDTH / 2 + BLOCK / 2), wallHeight / 2, halfZ),
		color = WALL_COLOR,
		parent = parent,
	})
end

--============================================================================
-- Build: Tetris Piece Gate (Archway Portal)
--============================================================================

local function buildTetrisGate(parent: Model): Part
	local gateModel = Instance.new("Model")
	gateModel.Name = "TetrisGate"
	gateModel.Parent = parent

	local gateZ = GATE_CENTER.Z
	local gateX = GATE_CENTER.X

	-- The gate is an arch made of Tetris pieces:
	-- Left pillar: stacked I-pieces (cyan) going up
	-- Right pillar: stacked J/L-pieces (blue/orange)
	-- Top beam: I-piece (cyan) spanning the opening
	-- Decorative: T, S, Z pieces around the arch

	-- Left pillar (5 blocks tall, 1 wide)
	for row = 0, 4 do
		local colors = {CYAN, PURPLE, GREEN, CYAN, YELLOW}
		createBlock({
			name = "GateLeft_" .. tostring(row),
			size = Vector3.new(BLOCK, BLOCK, BLOCK),
			position = Vector3.new(gateX - GATE_WIDTH / 2, (row + 0.5) * BLOCK, gateZ),
			color = colors[row + 1],
			material = Enum.Material.SmoothPlastic,
			parent = gateModel,
		})
	end

	-- Right pillar (5 blocks tall, 1 wide)
	for row = 0, 4 do
		local colors = {ORANGE, BLUE, RED, ORANGE, YELLOW}
		createBlock({
			name = "GateRight_" .. tostring(row),
			size = Vector3.new(BLOCK, BLOCK, BLOCK),
			position = Vector3.new(gateX + GATE_WIDTH / 2, (row + 0.5) * BLOCK, gateZ),
			color = colors[row + 1],
			material = Enum.Material.SmoothPlastic,
			parent = gateModel,
		})
	end

	-- Top beam: I-piece spanning the opening (7 blocks wide to overlap pillars)
	local beamWidth = GATE_WIDTH + 2 * BLOCK
	for col = 0, 6 do
		local colors = {PURPLE, CYAN, GREEN, CYAN, CYAN, GREEN, PURPLE}
		createBlock({
			name = "GateTop_" .. tostring(col),
			size = Vector3.new(BLOCK, BLOCK, BLOCK),
			position = Vector3.new(
				gateX - beamWidth / 2 + (col + 0.5) * BLOCK,
				(5 + 0.5) * BLOCK,
				gateZ
			),
			color = colors[col + 1],
			material = Enum.Material.SmoothPlastic,
			parent = gateModel,
		})
	end

	-- Decorative top row (T-shape crown)
	for col = 1, 5 do
		local colors = {YELLOW, RED, YELLOW, RED, YELLOW}
		createBlock({
			name = "GateCrown_" .. tostring(col),
			size = Vector3.new(BLOCK, BLOCK, BLOCK),
			position = Vector3.new(
				gateX - beamWidth / 2 + (col + 0.5) * BLOCK,
				(6 + 0.5) * BLOCK,
				gateZ
			),
			color = colors[col],
			material = Enum.Material.Neon,
			parent = gateModel,
		})
	end

	-- Sign above the gate
	local signPart = createBlock({
		name = "GateSign",
		size = Vector3.new(beamWidth, 2 * BLOCK, 0.5),
		position = Vector3.new(gateX, (7 + 1) * BLOCK, gateZ - BLOCK),
		color = SIGN_COLOR,
		parent = gateModel,
	})
	addSurfaceText(signPart, "TETRIS WORLD", Color3.fromRGB(0, 255, 255), 40, Enum.NormalId.Back)

	-- Invisible touch-detection part inside the gate opening
	-- Players walking through this triggers level start
	local touchPart = Instance.new("Part")
	touchPart.Name = "GateTrigger"
	touchPart.Size = Vector3.new(GATE_WIDTH, GATE_HEIGHT, BLOCK * 2)
	touchPart.Position = Vector3.new(gateX, GATE_HEIGHT / 2, gateZ)
	touchPart.Anchored = true
	touchPart.CanCollide = false
	touchPart.Transparency = 1
	touchPart.Parent = gateModel

	return touchPart
end

--============================================================================
-- Build: Power-Up Shop Area
--============================================================================

local function buildShopArea(parent: Model)
	local shopModel = Instance.new("Model")
	shopModel.Name = "UpgradeShop"
	shopModel.Parent = parent

	-- Shop platform (raised slightly)
	createBlock({
		name = "ShopPlatform",
		size = Vector3.new(16 * BLOCK, BLOCK, 10 * BLOCK),
		position = SHOP_CENTER + Vector3.new(0, 0.5, 0),
		color = Color3.fromRGB(50, 50, 70),
		material = Enum.Material.Marble,
		parent = shopModel,
	})

	-- Shop back wall with sign
	local shopWall = createBlock({
		name = "ShopWall",
		size = Vector3.new(16 * BLOCK, 6 * BLOCK, BLOCK),
		position = SHOP_CENTER + Vector3.new(0, 3 * BLOCK + BLOCK, -5 * BLOCK),
		color = SIGN_COLOR,
		parent = shopModel,
	})
	addSurfaceText(shopWall, "POWER-UPS", Color3.fromRGB(255, 255, 100), 48, Enum.NormalId.Front)

	-- Three upgrade pedestals
	local upgrades = {
		{ name = "Higher Jump", color = Color3.fromRGB(100, 200, 255), xOffset = -5 * BLOCK },
		{ name = "Double Jump", color = Color3.fromRGB(255, 200, 100), xOffset = 0 },
		{ name = "Faster Speed", color = Color3.fromRGB(100, 255, 150), xOffset = 5 * BLOCK },
	}

	for _, upgrade in upgrades do
		-- Pedestal
		createBlock({
			name = "Pedestal_" .. upgrade.name,
			size = Vector3.new(3 * BLOCK, 2 * BLOCK, 3 * BLOCK),
			position = SHOP_CENTER + Vector3.new(upgrade.xOffset, BLOCK + BLOCK, 0),
			color = SHOP_PEDESTAL_COLOR,
			material = Enum.Material.Marble,
			parent = shopModel,
		})

		-- Floating power-up indicator (glowing block on top)
		createBlock({
			name = "PowerUp_" .. upgrade.name,
			size = Vector3.new(BLOCK, BLOCK, BLOCK),
			position = SHOP_CENTER + Vector3.new(upgrade.xOffset, 3.5 * BLOCK + BLOCK, 0),
			color = upgrade.color,
			material = Enum.Material.Neon,
			parent = shopModel,
		})

		-- Name sign
		local namePart = createBlock({
			name = "Sign_" .. upgrade.name,
			size = Vector3.new(3 * BLOCK, BLOCK, 0.2),
			position = SHOP_CENTER + Vector3.new(upgrade.xOffset, 2 * BLOCK + BLOCK, 1.6 * BLOCK),
			color = SIGN_COLOR,
			transparency = 0.2,
			parent = shopModel,
		})
		addSurfaceText(namePart, upgrade.name, upgrade.color, 24, Enum.NormalId.Front)
	end
end

--============================================================================
-- Build: Coming Soon Sign
--============================================================================

local function buildComingSoonSign(parent: Model)
	local signModel = Instance.new("Model")
	signModel.Name = "ComingSoon_PipeWorld"
	signModel.Parent = parent

	-- Large sign board
	local board = createBlock({
		name = "SignBoard",
		size = Vector3.new(10 * BLOCK, 6 * BLOCK, BLOCK),
		position = COMING_SOON_CENTER + Vector3.new(0, 3 * BLOCK, 0),
		color = Color3.fromRGB(30, 35, 25),
		parent = signModel,
	})
	addSurfaceText(board, "PIPE WORLD\n\nCOMING SOON", Color3.fromRGB(255, 180, 50), 36, Enum.NormalId.Back)

	-- Support posts
	createBlock({
		name = "PostLeft",
		size = Vector3.new(BLOCK, 6 * BLOCK, BLOCK),
		position = COMING_SOON_CENTER + Vector3.new(-4.5 * BLOCK, 3 * BLOCK, 0),
		color = Color3.fromRGB(0, 180, 0),
		parent = signModel,
	})
	createBlock({
		name = "PostRight",
		size = Vector3.new(BLOCK, 6 * BLOCK, BLOCK),
		position = COMING_SOON_CENTER + Vector3.new(4.5 * BLOCK, 3 * BLOCK, 0),
		color = Color3.fromRGB(0, 180, 0),
		parent = signModel,
	})

	-- Decorative pipe shapes (green cylinders representing the Pipe World theme)
	local pipe = Instance.new("Part")
	pipe.Name = "DecoPipe"
	pipe.Shape = Enum.PartType.Cylinder
	pipe.Size = Vector3.new(4 * BLOCK, 2 * BLOCK, 2 * BLOCK)
	pipe.CFrame = CFrame.new(COMING_SOON_CENTER + Vector3.new(0, BLOCK, 2 * BLOCK)) * CFrame.Angles(0, 0, math.rad(90))
	pipe.Color = Color3.fromRGB(0, 200, 0)
	pipe.Material = Enum.Material.SmoothPlastic
	pipe.Anchored = true
	pipe.Parent = signModel
end

--============================================================================
-- Build: Leaderboard Display Boards
--============================================================================

local function buildLeaderboardBoards(parent: Model)
	-- XP Leaderboard (left side of spawn, facing player)
	local xpBoard = createBlock({
		name = "LeaderboardXP",
		size = Vector3.new(8 * BLOCK, 6 * BLOCK, 0.5),
		position = LEADERBOARD_LEFT_POS,
		color = SIGN_COLOR,
		parent = parent,
	})
	addSurfaceText(xpBoard, "TOP XP\n\n1. ---\n2. ---\n3. ---\n4. ---\n5. ---", Color3.fromRGB(255, 255, 100), 28, Enum.NormalId.Front)

	-- Support post
	createBlock({
		name = "LeaderboardXP_Post",
		size = Vector3.new(BLOCK, LEADERBOARD_LEFT_POS.Y + 3 * BLOCK, BLOCK),
		position = Vector3.new(LEADERBOARD_LEFT_POS.X, (LEADERBOARD_LEFT_POS.Y + 3 * BLOCK) / 2 - 3 * BLOCK, LEADERBOARD_LEFT_POS.Z),
		color = WALL_COLOR,
		parent = parent,
	})

	-- Level Leaderboard (right side of spawn, facing player)
	local levelBoard = createBlock({
		name = "LeaderboardLevel",
		size = Vector3.new(8 * BLOCK, 6 * BLOCK, 0.5),
		position = LEADERBOARD_RIGHT_POS,
		color = SIGN_COLOR,
		parent = parent,
	})
	addSurfaceText(levelBoard, "TOP LEVEL\n\n1. ---\n2. ---\n3. ---\n4. ---\n5. ---", Color3.fromRGB(100, 200, 255), 28, Enum.NormalId.Front)

	-- Support post
	createBlock({
		name = "LeaderboardLevel_Post",
		size = Vector3.new(BLOCK, LEADERBOARD_RIGHT_POS.Y + 3 * BLOCK, BLOCK),
		position = Vector3.new(LEADERBOARD_RIGHT_POS.X, (LEADERBOARD_RIGHT_POS.Y + 3 * BLOCK) / 2 - 3 * BLOCK, LEADERBOARD_RIGHT_POS.Z),
		color = WALL_COLOR,
		parent = parent,
	})
end

--============================================================================
-- Build: Spawn Point
--============================================================================

local function buildSpawnPoint(parent: Model)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(4 * BLOCK, 1, 4 * BLOCK)
	spawn.Position = Vector3.new(SPAWN_POSITION.X, 0.5, SPAWN_POSITION.Z)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Color = Color3.fromRGB(60, 60, 80)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Parent = parent
end

--============================================================================
-- Public API
--============================================================================

--- Build the entire lobby and parent it to Workspace.
--- Returns the gate trigger part for touch detection wiring.
function LobbyBuilder.init(): Part?
	-- Clean up existing lobby if present
	local existing = workspace:FindFirstChild("Lobby")
	if existing then
		existing:Destroy()
	end

	-- Create lobby model
	local model = Instance.new("Model")
	model.Name = "Lobby"

	-- Build all components
	buildGround(model)
	local touchPart = buildTetrisGate(model)
	buildShopArea(model)
	buildComingSoonSign(model)
	buildLeaderboardBoards(model)
	buildSpawnPoint(model)

	-- Parent to workspace
	model.Parent = workspace

	-- Store references
	lobbyModel = model
	gateTouchPart = touchPart

	return touchPart
end

--- Get the gate trigger part (for external wiring if needed).
function LobbyBuilder.getGateTrigger(): Part?
	return gateTouchPart :: Part?
end

--- Get the lobby spawn position.
function LobbyBuilder.getSpawnPosition(): Vector3
	return SPAWN_POSITION
end

--- Update leaderboard display text on the physical boards.
--- Called by GameServer when leaderboard data refreshes.
function LobbyBuilder.updateLeaderboards(topXP: {{displayName: string, value: number}}, topLevel: {{displayName: string, value: number}})
	if not lobbyModel then
		return
	end

	-- Format XP leaderboard text
	local xpText = "TOP XP\n"
	for i = 1, math.min(5, #topXP) do
		local entry = topXP[i]
		local name = entry.displayName
		if #name > 12 then
			name = string.sub(name, 1, 11) .. ".."
		end
		xpText = xpText .. "\n#" .. tostring(i) .. " " .. name .. " - " .. tostring(entry.value)
	end
	if #topXP == 0 then
		xpText = xpText .. "\n\nNo rankings yet!"
	end

	-- Format Level leaderboard text
	local levelText = "TOP LEVEL\n"
	for i = 1, math.min(5, #topLevel) do
		local entry = topLevel[i]
		local name = entry.displayName
		if #name > 12 then
			name = string.sub(name, 1, 11) .. ".."
		end
		levelText = levelText .. "\n#" .. tostring(i) .. " " .. name .. " - Lv" .. tostring(entry.value)
	end
	if #topLevel == 0 then
		levelText = levelText .. "\n\nNo rankings yet!"
	end

	-- Update the SurfaceGui text on the boards
	local xpBoard = lobbyModel:FindFirstChild("LeaderboardXP") :: Part?
	if xpBoard then
		local gui = xpBoard:FindFirstChild("SignGui") :: SurfaceGui?
		if gui then
			local label = gui:FindFirstChild("Text") :: TextLabel?
			if label then
				label.Text = xpText
			end
		end
	end

	local levelBoard = lobbyModel:FindFirstChild("LeaderboardLevel") :: Part?
	if levelBoard then
		local gui = levelBoard:FindFirstChild("SignGui") :: SurfaceGui?
		if gui then
			local label = gui:FindFirstChild("Text") :: TextLabel?
			if label then
				label.Text = levelText
			end
		end
	end
end

return LobbyBuilder
