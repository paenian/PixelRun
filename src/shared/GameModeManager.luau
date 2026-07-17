--!strict
--[[
    GameModeManager.luau - Game mode definitions and unlock logic

    Provides mode configurations for Classic, Time Attack, and Sprint modes.
    Handles mode availability checks based on player pack completions.

    Modes:
      - Classic: Default gameplay with morass chasing, reach 1000 blocks.
      - Time Attack: No morass, timer counts up, reach 1000 blocks as fast as possible.
      - Sprint: 60-second countdown, very slow morass, go as far as possible.

    Validates: Requirements 7.1
]]

local Types = require(script.Parent.Types)

local GameModeManager = {}

--============================================================================
-- Mode Definitions
--============================================================================

type GameModeConfig = Types.GameModeConfig

local MODES: {GameModeConfig} = {
	{
		id = "classic",
		name = "Classic",
		description = "Race to 1000 blocks. Morass is chasing you!",
		hasMorass = true,
		hasTimer = false,
		timerDirection = nil,
		timerDuration = nil,
		targetDistance = 1000,
	},
	{
		id = "time_attack",
		name = "Time Attack",
		description = "No morass! Beat the clock to 1000 blocks.",
		hasMorass = false,
		hasTimer = true,
		timerDirection = "up",
		timerDuration = nil,
		targetDistance = 1000,
	},
	{
		id = "sprint",
		name = "Sprint",
		description = "60 seconds! How far can you go?",
		hasMorass = true,
		hasTimer = true,
		timerDirection = "down",
		timerDuration = 60,
		targetDistance = nil,
	},
}

--- Lookup table for fast access by mode id.
local MODE_BY_ID: {[string]: GameModeConfig} = {}
for _, mode in MODES do
	MODE_BY_ID[mode.id] = mode
end

--============================================================================
-- Public API
--============================================================================

--- Returns all available game mode definitions.
function GameModeManager.getAvailableModes(): {GameModeConfig}
	return MODES
end

--- Returns the configuration for a specific mode, or nil if the mode id is invalid.
function GameModeManager.getModeConfig(modeId: string): GameModeConfig?
	return MODE_BY_ID[modeId]
end

--- Returns the default mode id ("classic").
function GameModeManager.getDefaultModeId(): string
	return "classic"
end

--- Determines whether a mode is unlocked for a given pack.
--- Classic mode is always unlocked.
--- Other modes require the pack to have been completed in Classic mode
--- (i.e., completions[packId] contains at least levels 1-10).
---
--- @param modeId string -- The mode to check
--- @param packId string -- The pack to check against
--- @param completions {[string]: {number}} -- Player's completions map (packId -> list of completed level numbers)
--- @return boolean -- true if the mode is unlocked for that pack
function GameModeManager.isModeUnlocked(modeId: string, packId: string, completions: {[string]: {number}}): boolean
	-- Classic is always unlocked
	if modeId == "classic" then
		return true
	end

	-- Unknown mode ids are not unlocked
	if MODE_BY_ID[modeId] == nil then
		return false
	end

	-- Other modes require pack completion in Classic (all 10 levels)
	local packCompletions = completions[packId]
	if packCompletions == nil then
		return false
	end

	-- Check that levels 1-10 are all completed
	for level = 1, 10 do
		local found = false
		for _, completedLevel in packCompletions do
			if completedLevel == level then
				found = true
				break
			end
		end
		if not found then
			return false
		end
	end

	return true
end

return GameModeManager
