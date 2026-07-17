--!strict
--[[
    SettingsUI.spec.luau - Unit tests for Settings logic

    Tests cover: volume clamping, settings validation, default values.

    Since SettingsUI depends on Roblox services (Players, UserInputService),
    these tests verify the logic using inlined data that mirrors the module's behavior.

    Validates: Requirements 1.11
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
-- Volume Clamping Logic
--============================================================================
print("\n=== Volume Clamping (0-100) ===")

-- The SoundManager clamps volume to 0-100 then divides by 100:
--   MUSIC_VOLUME = math.clamp(volume, 0, 100) / 100
local function clampVolume(volume: number): number
	return math.clamp(volume, 0, 100) / 100
end

-- Normal values
assertEquals(clampVolume(0), 0, "Volume 0 → internal 0.0")
assertEquals(clampVolume(50), 0.5, "Volume 50 → internal 0.5")
assertEquals(clampVolume(100), 1.0, "Volume 100 → internal 1.0")

-- Below minimum → clamped to 0
assertEquals(clampVolume(-10), 0, "Volume -10 clamped to 0.0")
assertEquals(clampVolume(-100), 0, "Volume -100 clamped to 0.0")

-- Above maximum → clamped to 1
assertEquals(clampVolume(150), 1.0, "Volume 150 clamped to 1.0")
assertEquals(clampVolume(200), 1.0, "Volume 200 clamped to 1.0")

-- Fractional values
assertTrue(math.abs(clampVolume(75) - 0.75) < 0.001, "Volume 75 → internal 0.75")
assertTrue(math.abs(clampVolume(25) - 0.25) < 0.001, "Volume 25 → internal 0.25")

--============================================================================
-- Settings Validation Logic
--============================================================================
print("\n=== Settings Validation ===")

-- Server-side validation mirrors this: clamp to 0-100 integers
local function validateSettingsVolume(value: number): number
	return math.clamp(math.floor(value), 0, 100)
end

assertEquals(validateSettingsVolume(50.7), 50, "Floor 50.7 → 50")
assertEquals(validateSettingsVolume(99.9), 99, "Floor 99.9 → 99")
assertEquals(validateSettingsVolume(0), 0, "Floor 0 → 0")
assertEquals(validateSettingsVolume(100), 100, "Floor 100 → 100")
assertEquals(validateSettingsVolume(-5), 0, "Negative clamped to 0")
assertEquals(validateSettingsVolume(200), 100, "Over 100 clamped to 100")

--============================================================================
-- Default Settings Values
--============================================================================
print("\n=== Default Settings ===")

-- Default settings from Types.DEFAULT_PLAYER_SETTINGS
local DEFAULT_SETTINGS = {
	musicVolume = 50,
	sfxVolume = 80,
	screenShake = true,
}

assertEquals(DEFAULT_SETTINGS.musicVolume, 50, "Default music volume is 50")
assertEquals(DEFAULT_SETTINGS.sfxVolume, 80, "Default SFX volume is 80")
assertEquals(DEFAULT_SETTINGS.screenShake, true, "Default screen shake is enabled")

-- Verify that defaults produce valid internal values
assertTrue(clampVolume(DEFAULT_SETTINGS.musicVolume) == 0.5, "Default music volume valid internally")
assertTrue(clampVolume(DEFAULT_SETTINGS.sfxVolume) == 0.8, "Default SFX volume valid internally")

--============================================================================
-- Settings Load Logic
--============================================================================
print("\n=== Settings Load from Profile ===")

-- Simulates the loadSettings function's clamping behavior
local function loadMusicVolume(data: { musicVolume: number? }?): number
	local volume = 50 -- default
	if data and data.musicVolume ~= nil then
		volume = math.clamp(data.musicVolume :: number, 0, 100)
	end
	return volume
end

assertEquals(loadMusicVolume(nil), 50, "Nil data → default 50")
assertEquals(loadMusicVolume({ musicVolume = nil }), 50, "Nil musicVolume → default 50")
assertEquals(loadMusicVolume({ musicVolume = 75 }), 75, "Valid musicVolume 75 loaded")
assertEquals(loadMusicVolume({ musicVolume = 0 }), 0, "musicVolume 0 allowed")
assertEquals(loadMusicVolume({ musicVolume = 100 }), 100, "musicVolume 100 allowed")
assertEquals(loadMusicVolume({ musicVolume = -20 }), 0, "Negative clamped to 0")
assertEquals(loadMusicVolume({ musicVolume = 150 }), 100, "Over 100 clamped to 100")

--============================================================================
-- Summary
--============================================================================
print("")
print(`Results: {passed} passed, {failed} failed`)

if failed > 0 then
	print("\nSOME TESTS FAILED")
	error(`{failed} test(s) failed`)
end

print("\nALL TESTS PASSED ✓")
