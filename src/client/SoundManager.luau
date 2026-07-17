--!strict
--[[
    SoundManager.luau - Dynamic music and sound effects with crossfading

    Manages background music per level pack theme with smooth crossfade transitions,
    and one-shot sound effects for game events.

    Validates: Requirements 9.4, 9.5
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local SoundManager = {}

export type SoundManager = {
	playPackMusic: (packTheme: string) -> (),
	playLobbyMusic: () -> (),
	crossfade: (toTrack: string, duration: number) -> (),
	playSFX: (effect: string) -> (),
	setMusicVolume: (volume: number) -> (),
	setSFXVolume: (volume: number) -> (),
	getMusicVolume: () -> number,
	getSFXVolume: () -> number,
}

--============================================================================
-- Constants
--============================================================================

local MUSIC_VOLUME = 0.5
local SFX_VOLUME = 0.8
local DEFAULT_CROSSFADE_DURATION = 1.5

--- Map of pack theme identifiers to music asset IDs.
--- Using placeholder IDs (rbxassetid://0) until real assets are integrated.
local THEME_MUSIC: { [string]: string } = {
	lobby = "rbxassetid://0",
	tetris = "rbxassetid://0",
	pipeworld = "rbxassetid://0",
}

--- Map of SFX effect names to asset IDs.
--- Using placeholder IDs (rbxassetid://0) until real assets are integrated.
local SFX_SOUNDS: { [string]: string } = {
	death = "rbxassetid://0",
	levelComplete = "rbxassetid://0",
	achievement = "rbxassetid://0",
	purchase = "rbxassetid://0",
	pipeWhoosh = "rbxassetid://0",
	coinDing = "rbxassetid://0",
	chomp = "rbxassetid://0",
}

--============================================================================
-- Internal State
--============================================================================

--- The currently playing music Sound instance (nil if nothing is playing).
local currentMusic: Sound? = nil

--- The identifier of the currently playing track (theme key).
local currentTrackId: string? = nil

--- Folder to hold music Sound instances under SoundService.
local musicFolder: Folder = nil :: any

--============================================================================
-- Internal Helpers
--============================================================================

--- Ensures the music folder exists under SoundService.
local function ensureMusicFolder(): Folder
	if musicFolder then
		return musicFolder
	end
	local existing = SoundService:FindFirstChild("PixelRunMusic")
	if existing and existing:IsA("Folder") then
		musicFolder = existing :: Folder
	else
		local folder = Instance.new("Folder")
		folder.Name = "PixelRunMusic"
		folder.Parent = SoundService
		musicFolder = folder
	end
	return musicFolder
end

--- Creates a new looping music Sound for the given track identifier.
local function createMusicSound(trackId: string): Sound
	local folder = ensureMusicFolder()
	local sound = Instance.new("Sound")
	sound.Name = "Music_" .. trackId
	sound.SoundId = THEME_MUSIC[trackId] or "rbxassetid://0"
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = folder
	return sound
end

--- Creates a one-shot SFX Sound instance.
local function createSFXSound(effect: string): Sound
	local folder = ensureMusicFolder()
	local sound = Instance.new("Sound")
	sound.Name = "SFX_" .. effect
	sound.SoundId = SFX_SOUNDS[effect] or "rbxassetid://0"
	sound.Looped = false
	sound.Volume = SFX_VOLUME
	sound.PlayOnRemove = false
	sound.Parent = folder
	return sound
end

--============================================================================
-- Public API
--============================================================================

--- Play a looping background music track matched to the pack theme.
--- If music is already playing, crossfades from the current track to the new one.
--- @param packTheme string -- Theme identifier (e.g., "tetris")
function SoundManager.playPackMusic(packTheme: string): ()
	if currentTrackId == packTheme then
		return -- Already playing this track
	end

	SoundManager.crossfade(packTheme, DEFAULT_CROSSFADE_DURATION)
end

--- Play the lobby background music track (looping).
--- If pack music is currently playing, crossfades to lobby music.
function SoundManager.playLobbyMusic(): ()
	if currentTrackId == "lobby" then
		return -- Already playing lobby music
	end

	SoundManager.crossfade("lobby", DEFAULT_CROSSFADE_DURATION)
end

--- Smoothly transition from the currently playing track to the specified track
--- over `duration` seconds (1-2 seconds). Uses TweenService to fade the current
--- track volume down to 0 while fading the new track volume up to target.
--- Destroys/stops the old track after the fade completes.
--- @param toTrack string -- Theme identifier to transition to
--- @param duration number -- Duration of the crossfade in seconds (1-2)
function SoundManager.crossfade(toTrack: string, duration: number): ()
	-- Clamp duration to 1-2 seconds as specified
	duration = math.clamp(duration, 1, 2)

	local oldMusic = currentMusic
	local oldTrackId = currentTrackId

	-- Don't crossfade to the same track
	if oldTrackId == toTrack then
		return
	end

	-- Create the new music track
	local newMusic = createMusicSound(toTrack)
	newMusic.Volume = 0
	newMusic:Play()

	-- Fade in the new track
	local fadeInInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
	local fadeInTween = TweenService:Create(newMusic, fadeInInfo, { Volume = MUSIC_VOLUME })
	fadeInTween:Play()

	-- Fade out the old track (if one is playing)
	if oldMusic then
		local fadeOutInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
		local fadeOutTween = TweenService:Create(oldMusic, fadeOutInfo, { Volume = 0 })
		fadeOutTween:Play()

		-- Clean up old track after fade completes
		fadeOutTween.Completed:Connect(function()
			oldMusic:Stop()
			oldMusic:Destroy()
		end)
	end

	-- Update state
	currentMusic = newMusic
	currentTrackId = toTrack
end

--- Play a one-shot sound effect. Creates a Sound, plays it, and destroys it
--- after completion. Effects include: "death", "levelComplete", "achievement", "purchase".
--- @param effect string -- Effect identifier
function SoundManager.playSFX(effect: string): ()
	local sound = createSFXSound(effect)
	sound:Play()

	-- Destroy the sound after it finishes playing
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

--- Set the music volume (0-100 percentage). Applies immediately to the current track.
--- @param volume number -- Volume percentage (0-100)
function SoundManager.setMusicVolume(volume: number): ()
	MUSIC_VOLUME = math.clamp(volume, 0, 100) / 100
	-- Apply to currently playing music
	if currentMusic then
		currentMusic.Volume = MUSIC_VOLUME
	end
end

--- Set the SFX volume (0-100 percentage). Applies to future sound effects.
--- @param volume number -- Volume percentage (0-100)
function SoundManager.setSFXVolume(volume: number): ()
	SFX_VOLUME = math.clamp(volume, 0, 100) / 100
end

--- Get the current music volume as a percentage (0-100).
function SoundManager.getMusicVolume(): number
	return MUSIC_VOLUME * 100
end

--- Get the current SFX volume as a percentage (0-100).
function SoundManager.getSFXVolume(): number
	return SFX_VOLUME * 100
end

return SoundManager
