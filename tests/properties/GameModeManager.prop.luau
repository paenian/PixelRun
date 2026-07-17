--!strict
--[[
    GameModeManager.prop.luau - Property-based tests for GameModeManager

    Feature: pixel-run-obby
    Task 7.5: Write property tests for GameModeManager

    **Validates: Requirements 7.1**

    Tests three properties (100 iterations each):
    1. Classic mode is always available regardless of completions state
    2. Other modes (time_attack, sprint) require pack completion in Classic (levels 1-10)
    3. Leaderboard keys are unique per mode+pack combo
]]

local TestHarness = require("../TestHarness")

--============================================================================
-- Inlined GameModeManager Logic (mirrors src/shared/GameModeManager.luau)
-- Pure functions extracted for Lune compatibility without Roblox services.
--============================================================================

local VALID_MODES = { "classic", "time_attack", "sprint" }
local MODE_SET: { [string]: boolean } = {
	classic = true,
	time_attack = true,
	sprint = true,
}

--- Determines whether a mode is unlocked for a given pack.
--- Classic mode is always unlocked.
--- Other modes require the pack to have been completed in Classic mode
--- (i.e., completions[packId] contains at least levels 1-10).
local function isModeUnlocked(modeId: string, packId: string, completions: { [string]: { number } }): boolean
	-- Classic is always unlocked
	if modeId == "classic" then
		return true
	end

	-- Unknown mode ids are not unlocked
	if MODE_SET[modeId] == nil then
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

--- Returns the OrderedDataStore key for a mode-specific leaderboard.
--- Format: "Leaderboard_{modeId}_{packId}"
local function getLeaderboardKey(modeId: string, packId: string): string
	return "Leaderboard_" .. modeId .. "_" .. packId
end

--============================================================================
-- Generators
--============================================================================

local PACK_IDS = { "tetris", "pipeworld", "space", "jungle", "ice", "fire", "candy" }

--- Generate a random completions map. May or may not have the target pack fully completed.
local function randomCompletions(rng: any, packId: string, forceComplete: boolean?): { [string]: { number } }
	local completions: { [string]: { number } } = {}

	-- Decide how many packs to include
	local numPacks = TestHarness.randomInt(rng, 0, #PACK_IDS)
	for i = 1, numPacks do
		local pid = PACK_IDS[TestHarness.randomInt(rng, 1, #PACK_IDS)]
		local levels: { number } = {}
		local numLevels = TestHarness.randomInt(rng, 0, 10)
		local levelSet: { [number]: boolean } = {}
		for _ = 1, numLevels do
			local lvl = TestHarness.randomInt(rng, 1, 10)
			if not levelSet[lvl] then
				levelSet[lvl] = true
				table.insert(levels, lvl)
			end
		end
		completions[pid] = levels
	end

	-- If forceComplete, ensure the target pack has all 10 levels
	if forceComplete then
		completions[packId] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
	end

	return completions
end

--============================================================================
-- Property 1: Classic always available
-- For any packId and any completions state, isModeUnlocked("classic", packId, completions) is always true
-- **Validates: Requirements 7.1**
--============================================================================

print("\n=== Property: Classic mode is always available ===")

TestHarness.property("Classic mode is always unlocked regardless of completions", 100, function(rng)
	local packId = TestHarness.randomChoice(rng, PACK_IDS)
	local completions = randomCompletions(rng, packId)

	local result = isModeUnlocked("classic", packId, completions)

	if not result then
		return false, string.format(
			"Expected classic mode to always be unlocked. packId=%s",
			packId
		)
	end

	return true, nil
end)

-- Also test with completely empty completions
TestHarness.property("Classic mode unlocked with empty completions", 100, function(rng)
	local packId = TestHarness.randomChoice(rng, PACK_IDS)
	local completions: { [string]: { number } } = {}

	local result = isModeUnlocked("classic", packId, completions)

	if not result then
		return false, string.format(
			"Expected classic mode to be unlocked with empty completions. packId=%s",
			packId
		)
	end

	return true, nil
end)

--============================================================================
-- Property 2: Other modes require pack completion in Classic
-- For time_attack and sprint, isModeUnlocked returns true only when
-- completions[packId] contains all 10 levels (1-10)
-- **Validates: Requirements 7.1**
--============================================================================

print("\n=== Property: Other modes require pack completion in Classic ===")

TestHarness.property("time_attack/sprint unlocked only when pack fully completed", 100, function(rng)
	local modeId = TestHarness.randomChoice(rng, { "time_attack", "sprint" })
	local packId = TestHarness.randomChoice(rng, PACK_IDS)

	-- Force pack to be fully complete
	local completions = randomCompletions(rng, packId, true)

	local result = isModeUnlocked(modeId, packId, completions)

	if not result then
		return false, string.format(
			"Expected mode '%s' to be unlocked when pack '%s' is fully completed. completions[packId]=%s",
			modeId, packId, tostring(completions[packId])
		)
	end

	return true, nil
end)

TestHarness.property("time_attack/sprint locked when pack has incomplete levels", 100, function(rng)
	local modeId = TestHarness.randomChoice(rng, { "time_attack", "sprint" })
	local packId = TestHarness.randomChoice(rng, PACK_IDS)

	-- Generate completions that are definitely incomplete (missing at least one level 1-10)
	local levels: { number } = {}
	local levelSet: { [number]: boolean } = {}

	-- Pick a random subset of levels, but ensure at least one from 1-10 is missing
	local missingLevel = TestHarness.randomInt(rng, 1, 10)
	for lvl = 1, 10 do
		if lvl ~= missingLevel and TestHarness.randomBool(rng) then
			levelSet[lvl] = true
			table.insert(levels, lvl)
		end
	end

	local completions: { [string]: { number } } = {}
	completions[packId] = levels

	local result = isModeUnlocked(modeId, packId, completions)

	if result then
		return false, string.format(
			"Expected mode '%s' to be LOCKED when pack '%s' is missing level %d. levels=%s",
			modeId, packId, missingLevel, table.concat(levels, ",")
		)
	end

	return true, nil
end)

TestHarness.property("time_attack/sprint locked when pack has no completions", 100, function(rng)
	local modeId = TestHarness.randomChoice(rng, { "time_attack", "sprint" })
	local packId = TestHarness.randomChoice(rng, PACK_IDS)

	-- Empty completions — no entry for this pack at all
	local completions: { [string]: { number } } = {}

	local result = isModeUnlocked(modeId, packId, completions)

	if result then
		return false, string.format(
			"Expected mode '%s' to be LOCKED when pack '%s' has no completions entry.",
			modeId, packId
		)
	end

	return true, nil
end)

--============================================================================
-- Property 3: Leaderboard keys unique per mode+pack combo
-- For any two different (modeId, packId) pairs,
-- getLeaderboardKey(mode1, pack1) ~= getLeaderboardKey(mode2, pack2)
-- unless mode1==mode2 AND pack1==pack2
-- **Validates: Requirements 7.1**
--============================================================================

print("\n=== Property: Leaderboard keys unique per mode+pack combo ===")

TestHarness.property("Different mode+pack pairs produce different leaderboard keys", 100, function(rng)
	local mode1 = TestHarness.randomChoice(rng, VALID_MODES)
	local pack1 = TestHarness.randomChoice(rng, PACK_IDS)
	local mode2 = TestHarness.randomChoice(rng, VALID_MODES)
	local pack2 = TestHarness.randomChoice(rng, PACK_IDS)

	local key1 = getLeaderboardKey(mode1, pack1)
	local key2 = getLeaderboardKey(mode2, pack2)

	local sameInputs = (mode1 == mode2) and (pack1 == pack2)

	if sameInputs then
		-- Same inputs must produce same key
		if key1 ~= key2 then
			return false, string.format(
				"Same inputs should produce same key. mode=%s, pack=%s, key1=%s, key2=%s",
				mode1, pack1, key1, key2
			)
		end
	else
		-- Different inputs must produce different keys
		if key1 == key2 then
			return false, string.format(
				"Different inputs should produce different keys. mode1=%s, pack1=%s, mode2=%s, pack2=%s, key=%s",
				mode1, pack1, mode2, pack2, key1
			)
		end
	end

	return true, nil
end)

-- Determinism: same inputs always produce same key
TestHarness.property("Leaderboard key is deterministic for same mode+pack", 100, function(rng)
	local modeId = TestHarness.randomChoice(rng, VALID_MODES)
	local packId = TestHarness.randomChoice(rng, PACK_IDS)

	local key1 = getLeaderboardKey(modeId, packId)
	local key2 = getLeaderboardKey(modeId, packId)

	if key1 ~= key2 then
		return false, string.format(
			"Leaderboard key should be deterministic. mode=%s, pack=%s, key1=%s, key2=%s",
			modeId, packId, key1, key2
		)
	end

	return true, nil
end)

--============================================================================
-- Report Results
--============================================================================

local allPassed = TestHarness.report()

if not allPassed then
	local process = require("@lune/process")
	process.exit(1)
end
