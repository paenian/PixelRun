--!strict
--[[
    LeaderboardService.spec.luau - Unit tests for mode-specific leaderboard functions

    Tests cover: getLeaderboardKey, updateModeScore inversion logic, getModeTop un-inversion.

    Since LeaderboardService uses Roblox DataStoreService which doesn't work in Lune,
    we inline the pure functions here (mirroring the source exactly).

    Validates: Requirements 7.4
]]

--============================================================================
-- Inlined LeaderboardService pure functions (mirrors src/server/LeaderboardService.luau)
--============================================================================

local MAX_TIME = 999999

local LeaderboardService = {}

--- Returns the OrderedDataStore key for a mode-specific leaderboard.
function LeaderboardService.getLeaderboardKey(modeId: string, packId: string): string
	return "Leaderboard_" .. modeId .. "_" .. packId
end

--- Calculate the stored value for a mode-specific score.
--- For Time Attack: invert so lower times rank higher in ascending OrderedDataStore.
--- For Sprint: store directly (higher distance = better).
function LeaderboardService.calculateStoredValue(modeId: string, score: number): number
	if modeId == "time_attack" then
		return MAX_TIME - math.floor(score)
	else
		return math.floor(score)
	end
end

--- Un-invert a stored Time Attack value back to the actual time.
function LeaderboardService.uninvertTimeAttackValue(storedValue: number): number
	return MAX_TIME - storedValue
end

--============================================================================
-- Test Infrastructure
--============================================================================

local passed = 0
local failed = 0

local function assertEquals(actual: any, expected: any, testName: string)
	if actual == expected then
		passed += 1
		print(`  \u{2713} {testName}`)
	else
		failed += 1
		print(`  \u{2717} {testName}: expected {expected}, got {actual}`)
	end
end

local function assertTrue(condition: boolean, testName: string)
	if condition then
		passed += 1
		print(`  \u{2713} {testName}`)
	else
		failed += 1
		print(`  \u{2717} {testName}: expected true, got false`)
	end
end

--============================================================================
-- getLeaderboardKey tests
--============================================================================
print("\n=== getLeaderboardKey ===")

assertEquals(
	LeaderboardService.getLeaderboardKey("time_attack", "tetris"),
	"Leaderboard_time_attack_tetris",
	"Time Attack + tetris produces correct key"
)

assertEquals(
	LeaderboardService.getLeaderboardKey("sprint", "tetris"),
	"Leaderboard_sprint_tetris",
	"Sprint + tetris produces correct key"
)

assertEquals(
	LeaderboardService.getLeaderboardKey("time_attack", "pipeworld"),
	"Leaderboard_time_attack_pipeworld",
	"Time Attack + pipeworld produces correct key"
)

assertEquals(
	LeaderboardService.getLeaderboardKey("sprint", "pipeworld"),
	"Leaderboard_sprint_pipeworld",
	"Sprint + pipeworld produces correct key"
)

assertEquals(
	LeaderboardService.getLeaderboardKey("classic", "tetris"),
	"Leaderboard_classic_tetris",
	"Classic + tetris produces correct key"
)

-- Keys are unique per mode+pack combo
local key1 = LeaderboardService.getLeaderboardKey("time_attack", "tetris")
local key2 = LeaderboardService.getLeaderboardKey("sprint", "tetris")
local key3 = LeaderboardService.getLeaderboardKey("time_attack", "pipeworld")
assertTrue(key1 ~= key2, "Different modes produce different keys for same pack")
assertTrue(key1 ~= key3, "Same mode with different packs produce different keys")
assertTrue(key2 ~= key3, "Different mode+pack combos produce unique keys")

--============================================================================
-- Time Attack score inversion tests
--============================================================================
print("\n=== Time Attack Score Inversion ===")

-- Lower time = higher stored value (better rank in descending sort)
local stored30s = LeaderboardService.calculateStoredValue("time_attack", 30)
local stored60s = LeaderboardService.calculateStoredValue("time_attack", 60)
local stored120s = LeaderboardService.calculateStoredValue("time_attack", 120)

assertTrue(stored30s > stored60s, "30s time produces higher stored value than 60s")
assertTrue(stored60s > stored120s, "60s time produces higher stored value than 120s")

-- Verify inversion formula: stored = MAX_TIME - floor(score)
assertEquals(stored30s, MAX_TIME - 30, "30s stored value is MAX_TIME - 30")
assertEquals(stored60s, MAX_TIME - 60, "60s stored value is MAX_TIME - 60")

-- Un-inversion produces original time
local uninverted30 = LeaderboardService.uninvertTimeAttackValue(stored30s)
assertEquals(uninverted30, 30, "Un-inverting stored 30s value gives 30")

local uninverted60 = LeaderboardService.uninvertTimeAttackValue(stored60s)
assertEquals(uninverted60, 60, "Un-inverting stored 60s value gives 60")

-- Fractional times are floored before inversion
local storedFrac = LeaderboardService.calculateStoredValue("time_attack", 45.7)
assertEquals(storedFrac, MAX_TIME - 45, "Fractional time 45.7s is floored to 45 before inversion")

--============================================================================
-- Sprint score storage tests
--============================================================================
print("\n=== Sprint Score Storage ===")

-- Sprint: higher distance = higher stored value (direct storage)
local stored100 = LeaderboardService.calculateStoredValue("sprint", 100)
local stored200 = LeaderboardService.calculateStoredValue("sprint", 200)
local stored500 = LeaderboardService.calculateStoredValue("sprint", 500)

assertTrue(stored500 > stored200, "500 blocks produces higher stored value than 200")
assertTrue(stored200 > stored100, "200 blocks produces higher stored value than 100")

-- Direct storage: stored value equals the floored score
assertEquals(stored100, 100, "Sprint 100 blocks stores 100")
assertEquals(stored200, 200, "Sprint 200 blocks stores 200")
assertEquals(stored500, 500, "Sprint 500 blocks stores 500")

-- Fractional distances are floored
local storedFracSprint = LeaderboardService.calculateStoredValue("sprint", 123.9)
assertEquals(storedFracSprint, 123, "Fractional sprint distance 123.9 is floored to 123")

--============================================================================
-- Edge cases
--============================================================================
print("\n=== Edge Cases ===")

-- Zero time in Time Attack
local storedZero = LeaderboardService.calculateStoredValue("time_attack", 0)
assertEquals(storedZero, MAX_TIME, "0 seconds time attack = MAX_TIME stored")

-- Zero distance in Sprint
local storedZeroSprint = LeaderboardService.calculateStoredValue("sprint", 0)
assertEquals(storedZeroSprint, 0, "0 blocks sprint = 0 stored")

-- Very large time
local storedLarge = LeaderboardService.calculateStoredValue("time_attack", 9999)
assertEquals(storedLarge, MAX_TIME - 9999, "Large time stores correctly")
assertTrue(storedLarge > 0, "Large time stored value is still positive")

--============================================================================
-- Summary
--============================================================================
print(`\n=== Results: {passed} passed, {failed} failed ===`)

if failed > 0 then
	error(`{failed} test(s) failed`)
end
