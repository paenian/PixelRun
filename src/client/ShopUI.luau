--!strict
--[[
    ShopUI.luau - Client-side shop panel triggered by the Shop NPC ProximityPrompt

    Listens for the ShopProximityPrompt in the lobby's ShopBooth.
    When triggered, opens a ScreenGui panel showing:
    - Player XP at top
    - Power-up tiers with costs, current tier, and Buy buttons

    Purchase requests are sent via RemoteFunction to the server.
    Listens for XPUpdate events to keep the XP display current.

    Validates: Requirements 7.1
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

--============================================================================
-- Constants
--============================================================================

local BG_COLOR = Color3.fromRGB(15, 15, 25)
local PANEL_COLOR = Color3.fromRGB(25, 25, 40)
local ACCENT_COLOR = Color3.fromRGB(255, 215, 0) -- Gold
local TEXT_COLOR = Color3.fromRGB(220, 220, 230)
local BUY_COLOR = Color3.fromRGB(50, 180, 80)
local BUY_DISABLED_COLOR = Color3.fromRGB(60, 60, 70)
local OWNED_COLOR = Color3.fromRGB(80, 140, 255)
local XP_COLOR = Color3.fromRGB(255, 255, 100)

--============================================================================
-- Power-Up Display Data
--============================================================================

local POWER_UPS = {
	{
		id = "higherJump",
		name = "Higher Jump",
		icon = "\xF0\x9F\x94\xBA", -- triangle up
		maxTier = 3,
		costs = { 2000, 5000, 12000 },
		descriptions = { "1.25x height", "1.5x height", "2.0x height" },
	},
	{
		id = "doubleJump",
		name = "Double Jump",
		icon = "\xE2\xAC\x86", -- up arrow
		maxTier = 1,
		costs = { 8000 },
		descriptions = { "Jump again mid-air" },
	},
	{
		id = "fasterSpeed",
		name = "Faster Speed",
		icon = "\xE2\x9A\xA1", -- lightning bolt
		maxTier = 3,
		costs = { 2000, 5000, 12000 },
		descriptions = { "1.25x speed", "1.5x speed", "2.0x speed" },
	},
}

--============================================================================
-- State
--============================================================================

local ShopUI = {}

local screenGui: ScreenGui? = nil
local shopFrame: Frame? = nil
local xpLabel: TextLabel? = nil
local buyButtons: { [string]: { TextButton } } = {}
local isOpen: boolean = false
local isInitialized: boolean = false

-- Current player data (updated via events)
local currentXP: number = 0
local currentTiers: { [string]: number } = {
	higherJump = 0,
	doubleJump = 0,
	fasterSpeed = 0,
}

--============================================================================
-- UI Construction
--============================================================================

local function createShopGui(): ScreenGui
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local gui = Instance.new("ScreenGui")
	gui.Name = "ShopPanel"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10
	gui.Enabled = false
	gui.Parent = playerGui

	return gui
end

local function createBackdrop(parent: ScreenGui): Frame
	-- Semi-transparent backdrop to dim the background
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.BorderSizePixel = 0
	backdrop.Parent = parent

	return backdrop
end

local function createMainPanel(parent: ScreenGui): Frame
	local panel = Instance.new("Frame")
	panel.Name = "ShopFrame"
	panel.Size = UDim2.new(0, 420, 0, 480)
	panel.Position = UDim2.new(0.5, -210, 0.5, -240)
	panel.BackgroundColor3 = BG_COLOR
	panel.BackgroundTransparency = 0.02
	panel.BorderSizePixel = 0
	panel.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel

	-- Subtle border stroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT_COLOR
	stroke.Thickness = 2
	stroke.Transparency = 0.5
	stroke.Parent = panel

	return panel
end

local function createHeader(parent: Frame): TextLabel
	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Position = UDim2.new(0, 0, 0, 8)
	title.BackgroundTransparency = 1
	title.TextColor3 = ACCENT_COLOR
	title.TextSize = 22
	title.Font = Enum.Font.GothamBold
	title.Text = "\xE2\xAD\x90 UPGRADES SHOP"
	title.Parent = parent

	-- XP display
	local xp = Instance.new("TextLabel")
	xp.Name = "XPDisplay"
	xp.Size = UDim2.new(1, -20, 0, 28)
	xp.Position = UDim2.new(0, 10, 0, 48)
	xp.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
	xp.BackgroundTransparency = 0.3
	xp.BorderSizePixel = 0
	xp.TextColor3 = XP_COLOR
	xp.TextSize = 16
	xp.Font = Enum.Font.GothamBold
	xp.Text = "Your XP: 0"
	xp.Parent = parent

	local xpCorner = Instance.new("UICorner")
	xpCorner.CornerRadius = UDim.new(0, 6)
	xpCorner.Parent = xp

	return xp
end

local function createCloseButton(parent: Frame)
	local btn = Instance.new("TextButton")
	btn.Name = "CloseBtn"
	btn.Size = UDim2.new(0, 36, 0, 36)
	btn.Position = UDim2.new(1, -42, 0, 6)
	btn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
	btn.BackgroundTransparency = 0.3
	btn.BorderSizePixel = 0
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 18
	btn.Font = Enum.Font.GothamBold
	btn.Text = "X"
	btn.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn

	btn.MouseButton1Click:Connect(function()
		ShopUI.close()
	end)
end

local function createPowerUpRow(parent: Frame, powerUp: typeof(POWER_UPS[1]), yOffset: number)
	local row = Instance.new("Frame")
	row.Name = "Row_" .. powerUp.id
	row.Size = UDim2.new(1, -20, 0, 110)
	row.Position = UDim2.new(0, 10, 0, yOffset)
	row.BackgroundColor3 = PANEL_COLOR
	row.BackgroundTransparency = 0.1
	row.BorderSizePixel = 0
	row.Parent = parent

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 10)
	rowCorner.Parent = row

	-- Power-up name with icon
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, -10, 0, 26)
	nameLabel.Position = UDim2.new(0, 10, 0, 6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = TEXT_COLOR
	nameLabel.TextSize = 16
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = powerUp.icon .. " " .. powerUp.name
	nameLabel.Parent = row

	-- Tier buttons
	buyButtons[powerUp.id] = {}
	local tierStartX = 10
	local tierWidth = math.floor((400 - 20 - (powerUp.maxTier - 1) * 8) / powerUp.maxTier)

	for tier = 1, powerUp.maxTier do
		local tierFrame = Instance.new("Frame")
		tierFrame.Name = "Tier" .. tostring(tier)
		tierFrame.Size = UDim2.new(0, tierWidth, 0, 68)
		tierFrame.Position = UDim2.new(0, tierStartX + (tier - 1) * (tierWidth + 8), 0, 34)
		tierFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
		tierFrame.BorderSizePixel = 0
		tierFrame.Parent = row

		local tierCorner = Instance.new("UICorner")
		tierCorner.CornerRadius = UDim.new(0, 6)
		tierCorner.Parent = tierFrame

		-- Description
		local desc = Instance.new("TextLabel")
		desc.Name = "Desc"
		desc.Size = UDim2.new(1, -4, 0, 16)
		desc.Position = UDim2.new(0, 2, 0, 2)
		desc.BackgroundTransparency = 1
		desc.TextColor3 = Color3.fromRGB(160, 160, 180)
		desc.TextSize = 11
		desc.Font = Enum.Font.Gotham
		desc.Text = powerUp.descriptions[tier]
		desc.TextWrapped = true
		desc.Parent = tierFrame

		-- Cost label
		local costLabel = Instance.new("TextLabel")
		costLabel.Name = "Cost"
		costLabel.Size = UDim2.new(1, -4, 0, 14)
		costLabel.Position = UDim2.new(0, 2, 0, 18)
		costLabel.BackgroundTransparency = 1
		costLabel.TextColor3 = XP_COLOR
		costLabel.TextSize = 11
		costLabel.Font = Enum.Font.GothamBold
		costLabel.Text = tostring(powerUp.costs[tier]) .. " XP"
		costLabel.Parent = tierFrame

		-- Buy button
		local buyBtn = Instance.new("TextButton")
		buyBtn.Name = "BuyBtn_" .. powerUp.id .. "_" .. tostring(tier)
		buyBtn.Size = UDim2.new(1, -8, 0, 26)
		buyBtn.Position = UDim2.new(0, 4, 1, -30)
		buyBtn.BackgroundColor3 = BUY_COLOR
		buyBtn.BorderSizePixel = 0
		buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		buyBtn.TextSize = 12
		buyBtn.Font = Enum.Font.GothamBold
		buyBtn.Text = "BUY"
		buyBtn.Parent = tierFrame

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 5)
		btnCorner.Parent = buyBtn

		-- Wire purchase handler
		buyBtn.MouseButton1Click:Connect(function()
			ShopUI._requestPurchase(powerUp.id, tier)
		end)

		buyButtons[powerUp.id][tier] = buyBtn
	end
end

--============================================================================
-- State Updates
--============================================================================

local function updateUI()
	if not xpLabel then return end

	-- Update XP display
	xpLabel.Text = "Your XP: " .. tostring(math.floor(currentXP))

	-- Update all buy buttons
	for _, powerUp in POWER_UPS do
		local playerTier = currentTiers[powerUp.id] or 0
		local buttons = buyButtons[powerUp.id]
		if not buttons then continue end

		for tier = 1, powerUp.maxTier do
			local btn = buttons[tier]
			if not btn then continue end

			if tier <= playerTier then
				-- Already owned
				btn.Text = "OWNED"
				btn.BackgroundColor3 = OWNED_COLOR
				btn.Active = false
			elseif tier == playerTier + 1 then
				-- Next available tier
				if currentXP >= powerUp.costs[tier] then
					btn.Text = "BUY"
					btn.BackgroundColor3 = BUY_COLOR
					btn.Active = true
				else
					btn.Text = "BUY"
					btn.BackgroundColor3 = BUY_DISABLED_COLOR
					btn.Active = true -- Allow click to show error
				end
			else
				-- Locked (need previous tier)
				btn.Text = "LOCKED"
				btn.BackgroundColor3 = BUY_DISABLED_COLOR
				btn.Active = false
			end
		end
	end
end

--============================================================================
-- Purchase Logic
--============================================================================

function ShopUI._requestPurchase(powerUpId: string, tier: number)
	local eventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not eventsFolder then return end

	local purchaseFunc = eventsFolder:FindFirstChild("PurchasePowerUp") :: RemoteFunction?
	if not purchaseFunc then
		warn("[ShopUI] PurchasePowerUp RemoteFunction not found")
		return
	end

	-- Send purchase request to server
	local result = purchaseFunc:InvokeServer(powerUpId, tier)

	if type(result) == "table" then
		if result.success then
			-- Update local state
			currentXP = result.newXP or currentXP
			currentTiers[powerUpId] = tier
			updateUI()
		else
			-- Show error briefly (could flash the button red)
			local btn = buyButtons[powerUpId] and buyButtons[powerUpId][tier]
			if btn then
				local originalColor = btn.BackgroundColor3
				local originalText = btn.Text
				btn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
				btn.Text = result.message or "Failed"
				task.delay(1.5, function()
					if btn then
						btn.BackgroundColor3 = originalColor
						btn.Text = originalText
						updateUI()
					end
				end)
			end
		end
	end
end

--============================================================================
-- ProximityPrompt Wiring
--============================================================================

local function wireProximityPrompt()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, _player: Player)
		if prompt.Name == "ShopProximityPrompt" then
			ShopUI.open()
		end
	end)
end

--============================================================================
-- Remote Event Wiring
--============================================================================

local function wireRemoteEvents()
	local eventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if not eventsFolder then return end

	-- Listen for XP updates to keep shop current
	local xpEvent = eventsFolder:WaitForChild("XPUpdate", 5) :: RemoteEvent?
	if xpEvent then
		xpEvent.OnClientEvent:Connect(function(data: any)
			if type(data) == "table" then
				currentXP = data.currentXP or currentXP
				if isOpen then
					updateUI()
				end
			end
		end)
	end

	-- Listen for ShowLobby which includes player data
	local showLobbyEvent = eventsFolder:WaitForChild("ShowLobby", 5) :: RemoteEvent?
	if showLobbyEvent then
		showLobbyEvent.OnClientEvent:Connect(function(data: any)
			if type(data) == "table" then
				if data.leaderboard and data.leaderboard.playerValueXP then
					currentXP = data.leaderboard.playerValueXP
				end
				if data.powerUps then
					for id, tier in data.powerUps do
						currentTiers[id] = tier
					end
				end
				if isOpen then
					updateUI()
				end
			end
		end)
	end

	-- Listen for PowerUpUpdate events to sync tier state
	local powerUpEvent = eventsFolder:WaitForChild("PowerUpUpdate", 5) :: RemoteEvent?
	if powerUpEvent then
		powerUpEvent.OnClientEvent:Connect(function(data: any)
			if type(data) == "table" then
				if data.powerUpId and data.tier then
					currentTiers[data.powerUpId] = data.tier
				end
				if data.currentXP then
					currentXP = data.currentXP
				end
				if isOpen then
					updateUI()
				end
			end
		end)
	end
end

--============================================================================
-- Public API
--============================================================================

--- Initialize the ShopUI system.
function ShopUI.init()
	if isInitialized then return end
	isInitialized = true

	screenGui = createShopGui()

	local backdrop = createBackdrop(screenGui)
	backdrop.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			ShopUI.close()
		end
	end)

	shopFrame = createMainPanel(screenGui)
	xpLabel = createHeader(shopFrame)
	createCloseButton(shopFrame)

	-- Build power-up rows
	local yOffset = 86
	for _, powerUp in POWER_UPS do
		createPowerUpRow(shopFrame, powerUp, yOffset)
		yOffset += 120
	end

	wireProximityPrompt()
	wireRemoteEvents()
end

--- Open the shop panel.
function ShopUI.open()
	if not isInitialized then
		ShopUI.init()
	end
	if screenGui then
		screenGui.Enabled = true
		isOpen = true
		updateUI()
	end
end

--- Close the shop panel.
function ShopUI.close()
	if screenGui then
		screenGui.Enabled = false
		isOpen = false
	end
end

--- Check if the shop is currently open.
function ShopUI.isOpen(): boolean
	return isOpen
end

--============================================================================
-- Auto-initialize
--============================================================================

task.defer(ShopUI.init)

return ShopUI
