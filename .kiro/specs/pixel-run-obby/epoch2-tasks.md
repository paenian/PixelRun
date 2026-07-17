# Epoch 2: Retention & Content Expansion

## Overview

Epoch 1 delivered the playable core. All major systems are implemented. Four stub modules remain (GameModeManager, ComboManager, RewardsManager, MascotManager).

Epoch 2 focuses on: a proper lobby matching Roblox design conventions, engagement systems (codes, daily spin), gameplay depth (combos), content (Pipe World pack), and cosmetics (mascots).

## Roblox Lobby Design Language

Popular Roblox games (DOORS, Blair, Epic Minigames, Horrific Housing, Pet Simulator) share a lobby vocabulary players instantly understand:

- **Spawn island** — open, well-lit platform. Not a walled room.
- **Central landmark** — fountain, statue, or spinning feature piece for orientation.
- **Physical zone markers** — players walk TO things, not click UI buttons.
- **ProximityPrompts** — "Press E" to interact. Standard Roblox UX.
- **Portal doorways** — large physical arches with particle effects inside.
- **Shop NPC/booth** — walk up, prompt appears, GUI opens.
- **Codes terminal** — physical arcade machine or signboard.
- **Daily spin wheel** — physical prop, animated spin.
- **Leaderboard podiums** — top 3 on physical pedestals, full board behind.
- **Invisible boundaries** — no visible walls. Kill plane + invisible parts.
- **Ambient life** — music, particles, lighting atmosphere, drifting decor.
- **Settings via HUD** — gear icon top-right, opens panel.

---

## Tasks

- [x] 1. LOBBY REDESIGN

  - [x] 1.1 Redesign lobby layout and geometry
    - Replace box-with-walls with open spawn island (200x200 studs)
    - Terrain-like materials (Grass edges, smooth stone center, brick paths)
    - Invisible barriers + kill plane (no visible walls)
    - Skybox-appropriate lighting (Atmosphere, ColorCorrection, warm golden hour)
    - Central circular spawn platform (slightly raised, glowing edge trim)
    - Colored brick paths radiating from spawn to each zone
    - Ambient floating Tetris block particles drifting through the air

  - [x] 1.2 Build themed centerpiece
    - Large spinning Tetris piece sculpture above spawn (slow rotation via server Tween)
    - Built from colored blocks in Tetris theme colors
    - Neon glow on edges, serves as orientation landmark
    - Visible from anywhere in the lobby

  - [x] 1.3 Rebuild Tetris portal as proper gateway
    - Larger archway (7 wide × 7 tall, 2 blocks deep frame)
    - Swirling colored particle effects inside the opening
    - Floor path leading to portal (colored trail on ground)
    - "TETRIS WORLD" sign + progress indicator ("3/10 complete")
    - Pulsing glow effect on arch frame (PointLight cycling intensity)
    - Keep invisible touch trigger for walk-through activation

  - [x] 1.4 Build Pipe World preview portal (locked)
    - Same portal frame style but green pipe / brick materials
    - Translucent barrier across opening (green-tinted, Transparency 0.5)
    - "COMING SOON" floating text above
    - Lock icon part on the barrier
    - No touch trigger (blocked)

  - [x] 1.5 Build Shop NPC booth
    - Physical counter/booth structure with NPC character behind it
    - ProximityPrompt: "Press E to open Shop"
    - Opens ScreenGui shop panel showing power-up tiers, costs, current tier, Buy buttons
    - Player XP shown at top of shop panel
    - "UPGRADES" sign above booth with XP icon
    - NPC: simple blocky merchant character (Parts + Humanoid, no animations needed)

  - [x] 1.6 Build Codes terminal
    - Physical arcade-machine-style object near spawn
    - ProximityPrompt: "Press E to enter Code"
    - Opens TextBox GUI for code entry
    - Server validates code, awards reward, shows success/error
    - Create `src/server/CodesManager.luau`

  - [x] 1.7 Build Daily Spin wheel
    - Physical spinning wheel prop (cylinder with colored segments)
    - ProximityPrompt: "Press E to Spin" (only if unclaimed today)
    - Spin animation (TweenService rotation) landing on reward segment
    - Server-authoritative: validates timing, determines reward, persists
    - "Come back tomorrow!" text when already claimed
    - Wire into RewardsManager

  - [x] 1.8 Rebuild leaderboard displays as podiums
    - Top 3 players on physical podium blocks (gold/silver/bronze)
    - Display names via BillboardGui above each podium
    - Full top-10 on billboard behind podiums
    - Two podium sets: "XP Champions" and "Level Leaders"
    - Position behind spawn (players face portals, podiums at back)

  - [x] 1.9 Add social/gathering space
    - Open area between spawn and portals
    - Benches (Seat instances for sitting)
    - Low decorative hedges/walls dividing zones (not blocking movement)
    - Small Tetris-themed fountain or water feature
    - Room for 10+ players without crowding

  - [x] 1.10 Add lobby ambient effects
    - Lobby background music (chill chiptune/retro, separate track)
    - Floating Tetris piece particles drifting across sky
    - Atmospheric fog (Atmosphere instance, light density)
    - Colored PointLights along paths (in the floor)
    - Fixed warm lighting or slow time-of-day cycle

  - [x] 1.11 Add Settings button (HUD)
    - Gear icon top-right corner (always visible)
    - Opens Settings panel: music volume, SFX volume, screen shake toggle
    - Persist settings in player profile via DataStore
    - Wire SoundManager to respect volume settings

- [x] 2. CODES SYSTEM (CodesManager)

  - [x] 2.1 Create CodesManager module
    - `src/server/CodesManager.luau`
    - Code definition: { code, reward: {type: "xp"|"mascot", amount?, mascotId?}, maxRedemptions?, expiresAt? }
    - Functions: redeemCode, hasRedeemed, addCode, getActiveCodes
    - Per-player redemption tracking (add `redeemedCodes: {string}` to PlayerProfile)
    - Validates: exists, not expired, not already redeemed, not over max redemptions

  - [x] 2.2 Wire codes terminal to GameServer
    - Add RemoteFunction: RedeemCode
    - Server: rate limit, validate via CodesManager, award, persist
    - Client: success → particle burst + floating reward text; failure → error in GUI

  - [x] 2.3 Seed initial codes
    - "PIXELRUN" → 500 XP (launch code, no expiry)
    - "TETRIS" → 1000 XP (first-week code, 7 day expiry)
    - "FOUNDER" → 2000 XP (limited to first 100 redemptions)

  - [x] 2.4 Write property tests for CodesManager
    - Valid code + first redemption → success + XP awarded
    - Same code + same player again → rejected, unchanged
    - Expired code → rejected
    - Max redemptions reached → rejected
    - Invalid code string → rejected

- [x] 3. DAILY SPIN (RewardsManager)

  - [x] 3.1 Implement RewardsManager module
    - Replace stub in `src/shared/RewardsManager.luau`
    - Functions: canSpinToday, determineReward, applyReward, getLastSpinDate
    - Reward segments: 100 XP ×3, 200 XP ×2, 500 XP ×2, 1000 XP ×1, 2000 XP ×1, "Bonus Spin" ×1
    - Add `lastDailySpinDate: number` to PlayerProfile
    - Server-authoritative timing (os.time day comparison)

  - [x] 3.2 Wire spin to GameServer
    - Add RemoteFunction: ClaimDailySpin
    - Server validates, generates reward, returns { success, reward, segmentIndex }
    - Client plays wheel animation to correct segment, shows reward

  - [x] 3.3 Write property tests
    - Cannot spin twice same day
    - All rewards > 0
    - canSpinToday true if last spin was yesterday or earlier
    - canSpinToday false if last spin was today

- [x] 4. COMBO SYSTEM (ComboManager)

  - [x] 4.1 Design combo rules and data model
    - Triggers: consecutive near-misses (pass within 1 block of obstacle without hitting)
    - Tiers: 5x="Nice!" (1.5x XP), 10x="Great!" (2x), 20x="Amazing!" (3x), 50x="Unstoppable!" (5x)
    - Resets on: hit obstacle, caught by morass, stop moving >1 second
    - Add ComboState type to Types.luau

  - [x] 4.2 Implement ComboManager module
    - Replace stub in `src/shared/ComboManager.luau`
    - Functions: startCombo, incrementCombo, resetCombo, getCurrentMultiplier, getComboTier
    - Server-authoritative combo tracking per player

  - [x] 4.3 Wire combo into gameplay
    - Server: detect near-miss events, increment combo, reset on collision
    - Server: apply combo multiplier to per-block XP
    - Client: combo counter + tier name on HUD
    - Client: screen flash + floating text on tier-up

  - [x] 4.4 Write property tests
    - Multiplier increases monotonically with streak
    - Reset → streak=0, multiplier=1.0
    - Tier boundaries: 5, 10, 20, 50

- [x] 5. SECOND LEVEL PACK (Pipe World)

  - [x] 5.1 Create PipeWorldPack.luau
    - `src/shared/LevelPacks/PipeWorldPack.luau`
    - displayOrder=2, prerequisitePack="tetris", themeId="pipeworld"
    - 5 obstacle types: brick blocks, warp pipes, coin blocks, crumble bricks, pipe plants (touch-kill)
    - 10 levels, slightly denser than Tetris at equivalent levels
    - Achievement: "Pipeline Pro", morassVisual: "sewer_flood"

  - [x] 5.2 Add Pipe World music and SFX
    - Music asset ID in SoundManager THEME_MUSIC table
    - SFX: pipe whoosh, coin ding, chomp sound

  - [x] 5.3 Write unit tests
    - Schema validation passes
    - Correct prerequisite and displayOrder
    - Touch-kill only on level 10
    - All 5 obstacle types with correct colors and orientations

- [x] 6. MASCOT COMPANIONS (MascotManager)

  - [x] 6.1 Design mascots and unlock conditions
    - 6 mascots: Pixel Pup (free), Cube Cat (complete Tetris), Pipe Frog (complete Pipe World), Flame Fox (50-combo), Shadow Owl (7-day login streak), Golden Dragon (100k XP)
    - Add to PlayerProfile: equippedMascot, unlockedMascots

  - [x] 6.2 Implement MascotManager module
    - Replace stub, functions: getMascotDefinitions, isUnlocked, unlock, equip, getEquipped, checkUnlockConditions
    - Server-authoritative unlock validation

  - [x] 6.3 Implement mascot visual (client follower)
    - Small floating Part-based model following player
    - Sine-wave bob, trails behind, colored particle trail

  - [x] 6.4 Mascot selection UI
    - Display case in lobby with ProximityPrompt
    - Collection panel: all mascots, locked/unlocked/equipped states
    - Equip button for unlocked ones

  - [x] 6.5 Wire unlock triggers
    - Pack complete → pack-specific mascot
    - Combo milestone → Flame Fox
    - XP threshold → Golden Dragon
    - Login streak → Shadow Owl
    - Fire MascotUnlocked event with effects

  - [x] 6.6 Write property tests
    - Default mascot always unlocked
    - Can't equip locked mascot
    - Unlock conditions evaluate correctly
    - Persists in serialization round-trip

- [x] 7. GAME MODES (GameModeManager)

  - [x] 7.1 Implement GameModeManager
    - Replace stub, modes: Classic (existing), Time Attack (no morass, timer up), Sprint (60s, max distance)
    - Functions: getAvailableModes, getModeConfig, isModeUnlocked, startMode

  - [x] 7.2 Mode-specific LevelGenerator behavior
    - Time Attack: no morass, slower conveyor
    - Sprint: very slow morass, 60s HUD timer

  - [x] 7.3 Mode selection on portal interaction
    - Completed packs show mode choice via ProximityPrompt menu
    - Default to Classic for uncompleted packs

  - [x] 7.4 Mode-specific leaderboards
    - Separate OrderedDataStore keys: "Leaderboard_{mode}_{packId}"
    - Time Attack: lowest time wins; Sprint: highest distance wins

  - [x] 7.5 Write property tests
    - Classic always available
    - Other modes require pack completion in Classic
    - Leaderboard keys unique per mode+pack combo

- [x] 8. QUALITY OF LIFE

  - [x] 8.1 First-time tutorial
    - Detect new player (0 XP, no completions)
    - 3 brief tip overlays: jump, morass, XP
    - Dismiss on tap, persist tutorialCompleted flag, never show again

  - [x] 8.2 "Return to Lobby" button
    - Small "Leave" button on gameplay HUD
    - Confirm dialog: "Return to lobby? XP earned will be kept."
    - Fires LevelChoice("lobby")

  - [x] 8.3 Death counter and personal best
    - Track deaths per level, best distance per level (persisted)
    - Show on level start: "Attempt #47" / "PB: 423 blocks"

  - [x] 8.4 Morass visual intensity scaling
    - Levels 1-3: gentle, slow advance visual
    - Levels 7-10: more particles, screen-edge warning glow within 20 blocks, subtle camera shake

---

## Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "2.1", "3.1", "4.1"], "note": "Design + core modules" },
    { "id": 1, "tasks": ["1.3", "1.4", "1.5", "1.6", "1.7", "1.8", "1.9"], "note": "Lobby construction" },
    { "id": 2, "tasks": ["1.10", "1.11", "2.2", "2.3", "3.2", "4.2"], "note": "Lobby polish + wire" },
    { "id": 3, "tasks": ["2.4", "3.3", "4.3", "4.4", "5.1"], "note": "Tests + combo + Pipe World" },
    { "id": 4, "tasks": ["5.2", "5.3", "6.1", "6.2", "6.3"], "note": "Pack done + mascots" },
    { "id": 5, "tasks": ["6.4", "6.5", "6.6", "7.1", "7.2"], "note": "Mascot UI + game modes" },
    { "id": 6, "tasks": ["7.3", "7.4", "7.5", "8.1", "8.2", "8.3", "8.4"], "note": "Modes + QoL" }
  ]
}
```

## Notes

- Lobby redesign is highest priority — it's the first thing players see
- Codes are trivially cheap to implement but drive social engagement (share codes on Discord/Twitter)
- Daily spin gives a physical prop + daily login reason
- ProximityPrompts are the Roblox-standard interaction pattern
- No visible walls — use invisible barriers. Players expect open-air lobbies.
- "Pipe World" is generic — no Nintendo IP references
- All new types in Types.luau, new events documented in DEVELOPMENT.md
- The lobby should feel alive even with one player (ambient effects, spinning centerpiece, music)
