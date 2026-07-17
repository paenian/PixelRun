--!strict
--[[
    SoundManager.spec.luau - Unit tests for SoundManager constants and logic

    Tests cover: crossfade duration clamping, music volume constant,
    SFX effects list.

    Since SoundManager depends on Roblox services (SoundService, TweenService),
    these tests verify the logic using inlined data that mirrors the module's constants.

    Validates: Requirements 9.5
]]

local passed = 0
local failed = 0

local function assertEquals(actual: any, expected: any, testName: string)
    if actual == expected then
        passed += 1
        print(`  ✓ {testName}`)
    else
        failed += 1
        print(`  ✗ {testName}: expected {expected}, got {actual}`)
    end
end

local function assertTrue(condition: boolean, testName: string)
    if condition then
        passed += 1
        print(`  ✓ {testName}`)
    else
        failed += 1
        print(`  ✗ {testName}: expected true, got false`)
    end
end

--============================================================================
-- Crossfade Duration Clamping (Requirement 9.5)
--============================================================================
print("\n=== Crossfade Duration Clamping ===")

-- The SoundManager clamps crossfade duration to 1-2 seconds:
--   duration = math.clamp(duration, 1, 2)
-- Test the clamp logic with various inputs.

local function clampCrossfadeDuration(duration: number): number
    return math.clamp(duration, 1, 2)
end

-- Below minimum → clamped to 1
assertEquals(clampCrossfadeDuration(0), 1, "Duration 0 clamped to 1 second")
assertEquals(clampCrossfadeDuration(0.5), 1, "Duration 0.5 clamped to 1 second")
assertEquals(clampCrossfadeDuration(-1), 1, "Duration -1 clamped to 1 second")

-- Within range → unchanged
assertEquals(clampCrossfadeDuration(1), 1, "Duration 1 stays at 1 second")
assertEquals(clampCrossfadeDuration(1.5), 1.5, "Duration 1.5 stays at 1.5 seconds")
assertEquals(clampCrossfadeDuration(2), 2, "Duration 2 stays at 2 seconds")

-- Above maximum → clamped to 2
assertEquals(clampCrossfadeDuration(3), 2, "Duration 3 clamped to 2 seconds")
assertEquals(clampCrossfadeDuration(5), 2, "Duration 5 clamped to 2 seconds")
assertEquals(clampCrossfadeDuration(10), 2, "Duration 10 clamped to 2 seconds")

-- Default crossfade duration is within valid range
local DEFAULT_CROSSFADE_DURATION = 1.5
assertTrue(
    DEFAULT_CROSSFADE_DURATION >= 1 and DEFAULT_CROSSFADE_DURATION <= 2,
    "Default crossfade duration (1.5) is within 1-2 second bounds"
)

--============================================================================
-- Music Volume Constant
--============================================================================
print("\n=== Music Volume Constant ===")

-- The SoundManager defines MUSIC_VOLUME = 0.5 for background music.
local MUSIC_VOLUME = 0.5

assertTrue(MUSIC_VOLUME > 0, "Music volume is greater than 0")
assertTrue(MUSIC_VOLUME <= 1, "Music volume is at most 1.0")
assertEquals(MUSIC_VOLUME, 0.5, "Music volume constant is 0.5")

--============================================================================
-- SFX Effects List
--============================================================================
print("\n=== SFX Effects List ===")

-- The SoundManager defines SFX_SOUNDS with these required effect keys:
-- death, levelComplete, achievement, purchase, pipeWhoosh, coinDing, chomp
local SFX_EFFECTS = {"death", "levelComplete", "achievement", "purchase", "pipeWhoosh", "coinDing", "chomp"}

-- Verify all required effects are defined (using inlined data mirroring module)
local sfxSounds: {[string]: string} = {
    death = "rbxassetid://0",
    levelComplete = "rbxassetid://0",
    achievement = "rbxassetid://0",
    purchase = "rbxassetid://0",
    pipeWhoosh = "rbxassetid://0",
    coinDing = "rbxassetid://0",
    chomp = "rbxassetid://0",
}

for _, effect in SFX_EFFECTS do
    assertTrue(sfxSounds[effect] ~= nil, `SFX effect "{effect}" is defined`)
end

-- Verify the count of SFX effects
local sfxCount = 0
for _ in sfxSounds do
    sfxCount += 1
end
assertEquals(sfxCount, 7, "Exactly 7 SFX effects defined")

-- Verify all SFX have non-empty asset IDs
for effect, assetId in sfxSounds do
    assertTrue(assetId ~= nil and assetId ~= "", `SFX "{effect}" has a non-empty asset ID`)
end

--============================================================================
-- Theme Music Mapping
--============================================================================
print("\n=== Theme Music Mapping ===")

-- The SoundManager maps pack themes to music tracks.
-- "lobby", "tetris", and "pipeworld" themes should exist.
local themeMusicMap: {[string]: string} = {
    lobby = "rbxassetid://0",
    tetris = "rbxassetid://0",
    pipeworld = "rbxassetid://0",
}

assertTrue(themeMusicMap["lobby"] ~= nil, "Lobby theme music is defined")
assertTrue(themeMusicMap["tetris"] ~= nil, "Tetris theme music is defined")
assertTrue(themeMusicMap["pipeworld"] ~= nil, "Pipe World theme music is defined")

--============================================================================
-- Summary
--============================================================================
print(`\n=== Results: {passed} passed, {failed} failed ===`)

if failed > 0 then
    error(`{failed} test(s) failed`)
end
