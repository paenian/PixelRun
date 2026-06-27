# Epoch 2: Retention & Content Expansion

## Overview

Epoch 1 delivered the playable core — run, jump, earn, progress, persist. All major systems (lobby, HUD, effects, sound, power-ups, persistence, leaderboards, achievements, validation) are fully implemented. Four modules remain as stubs: GameModeManager, ComboManager, RewardsManager, and MascotManager.

Epoch 2 makes the game **sticky**: daily reasons to return, a second pack to unlock (Pipe World — retro platformer underground theme), combo mechanics that reward skilled play, and a mascot companion system for cosmetic progression. The theme is "reasons to come back tomorrow."

## Design Priorities

1. **Combo system** — instant gameplay depth without new levels
2. **Second level pack** — the first unlock goal that drives progression
3. **Daily rewards** — login incentive loop
4. **Mascot companions** — cosmetic personalization, long-term collection goal
5. **Game modes** — replayability variants on existing content
6. **Quality of life** — settings, tutorials, and polish from playtesting feedback

## Tasks

- [ ] 1. COMBO SYSTEM (ComboManager)
  - [ ] 1.1 Design combo rules and data model
    - Define combo triggers: consecutive obstacle dodges without stopping, near-misses (pass within 1 block of obstacle), consecutive jumps landing cleanly
    - Define combo tiers: 5x streak = "Nice!", 10x = "Great!", 20x = "Amazing!", 50x = "Unstoppable!"
    - Define XP multiplier per tier: 1.5x, 2x, 3x, 5x (applied on top of pack multiplier)
    - Add ComboState type to Types.luau: { streak: number, tier: number, multiplier: number, lastTriggerTime: number }
    - Combo resets on: hit obstacle, caught by morass, stop moving for > 1 second

  - [ ] 1.2 Implement ComboManager module
    - Replace stub with full implementation in `src/shared/ComboManager.luau`
    - Functions: startCombo, incrementCombo, resetCombo, getCurrentMultiplier, getComboTier
    - Track combo state per player (server-authoritative)
    - Fire combo tier-up events for client effects

  - [ ] 1.3 Wire combo into gameplay loop
    - Server: detect near-miss events (obstacle passed within 1-block margin)
    - Server: increment combo on successful obstacle dodge
    - Server: reset combo on collision/elimination/idle
    - Server: apply combo XP multiplier to per-block XP earnings
    - Client: display combo counter and current tier on HUD
    - Client: fire EffectsManager combo visual (screen flash, floating tier text)

  - [ ] 1.4 Write property tests for ComboManager
    - Combo multiplier increases monotonically with streak count
    - Combo resets produce streak = 0, multiplier = 1.0
    - XP with combo = base_xp × pack_multiplier × combo_multiplier
    - Tier boundaries are correct (5, 10, 20, 50)

- [ ] 2. SECOND LEVEL PACK (Pipe World Pack)
  - [ ] 2.1 Design Pipe World Pack theme and obstacles
    - Theme: retro platformer underground — brick tunnels, green pipes, chomping plant hazards
    - Obstacle types: brick blocks (square, stackable), warp pipes (tall cylinders, vertical), pipe plants (chomping hazard emerging from pipes — touch-kill on level 10), floating coin blocks (? pattern, elevated platforms), crumble bricks (visually cracked, fall when touched — void/gap hazard)
    - Morass visual: rising sewer flood / brown-green water wave
    - Colors: orange-brown bricks, green pipes, red-white chompers, yellow coin blocks
    - Achievement: "Pipeline Pro" — complete all 10 pipe world levels
    - themeId = "pipeworld"

  - [ ] 2.2 Create PipeWorldPack.luau configuration
    - Create `src/shared/LevelPacks/PipeWorldPack.luau` conforming to LevelPackConfig schema
    - displayOrder = 2, prerequisitePack = "tetris", themeId = "pipeworld"
    - Define 5 obstacle types with orientations and colors:
      - Brick blocks (orange-brown, 4 orientations, max height 4)
      - Warp pipes (green, 2 orientations vertical/horizontal, max height 6)
      - Coin blocks (yellow, 1 orientation, elevated — creates gap underneath)
      - Crumble bricks (tan/cracked, 2 orientations — used for void sections levels 7-9)
      - Pipe plants (red-white, 2 orientations — isTouchKill = true, level 10 only)
    - Configure 10 levels: 1-3 brick jumps only (max 4 tall), 4-6 pipe + coin block gaps (up to 3 wide), 7-9 crumble brick voids (up to 5 long), 10 pipe plants (touch-kill chompers)
    - Slightly denser than Tetris at equivalent levels (+10% obstacle density)
    - Completable without power-ups but power-ups make it noticeably easier

  - [ ] 2.3 Add Pipe World music track and sound mappings
    - Add underground/pipe-themed music asset ID to SoundManager THEME_MUSIC table
    - Add pipe-themed SFX: pipe whoosh on near-miss, coin ding on level completion, chomp sound for plant hit

  - [ ] 2.4 Write unit tests for PipeWorldPack
    - Verify all 5 obstacle types have correct colors and orientations
    - Verify difficulty progression matches tier requirements
    - Verify prerequisitePack = "tetris" and displayOrder = 2
    - Verify pipe plants only appear on level 10 (isTouchKill)
    - Verify schema validation passes

- [ ] 3. DAILY REWARDS (RewardsManager)
  - [ ] 3.1 Design daily reward schedule and data model
    - 7-day reward cycle (resets after day 7): Day 1 = 200 XP, Day 2 = 400 XP, Day 3 = 600 XP, Day 4 = 1000 XP, Day 5 = 1500 XP, Day 6 = 2000 XP, Day 7 = 5000 XP + random mascot
    - Add to PlayerProfile: { lastLoginDate: number (os.time day), loginStreak: number, totalLogins: number }
    - Streak resets if player misses a day (gap > 24h between logins)
    - Reward claimed once per calendar day (server time)

  - [ ] 3.2 Implement RewardsManager module
    - Replace stub with full implementation in `src/shared/RewardsManager.luau`
    - Functions: checkDailyReward, claimDailyReward, getStreakDay, getRewardForDay, hasClaimedToday
    - Server-authoritative: validate claim time against last login date
    - Integrate with DataStoreManager for persistence

  - [ ] 3.3 Implement daily reward UI
    - Show reward popup on login if unclaimed reward available
    - Display 7-day calendar showing current streak position and upcoming rewards
    - "Claim" button awards XP and closes popup
    - Show streak counter on lobby HUD

  - [ ] 3.4 Wire daily rewards into GameServer
    - On player join: check if daily reward is available
    - Fire ShowDailyReward event to client if unclaimed
    - Handle claim request via RemoteFunction (validate + award + persist)
    - Add RemoteEvent: ShowDailyReward, RemoteFunction: ClaimDailyReward

  - [ ] 3.5 Write property tests for RewardsManager
    - Reward increases monotonically across the 7-day cycle
    - Streak resets correctly when a day is missed
    - Cannot claim twice in the same calendar day
    - Day 7 reward includes mascot unlock (when mascot system exists)
    - Total XP from full 7-day cycle = 10,700

- [ ] 4. MASCOT COMPANION SYSTEM (MascotManager)
  - [ ] 4.1 Design mascot types and unlock conditions
    - 6 initial mascots: Pixel Pup (default, free), Cube Cat (complete Tetris pack), Pipe Frog (complete Pipe World pack), Flame Fox (50-combo streak), Shadow Owl (login 7 days straight), Golden Dragon (reach 100,000 total XP)
    - Mascot data: { id: string, name: string, description: string, unlockCondition: string, rarity: "common" | "rare" | "epic" | "legendary" }
    - Add to PlayerProfile: { equippedMascot: string, unlockedMascots: {string} }

  - [ ] 4.2 Implement MascotManager module
    - Replace stub with full implementation in `src/shared/MascotManager.luau`
    - Functions: getMascotDefinitions, isUnlocked, unlock, equip, getEquipped, checkUnlockConditions
    - Server-authoritative: unlock conditions checked on relevant events (pack complete, combo achieved, XP milestone, login streak)
    - Persist unlocked mascots and equipped mascot in DataStoreManager

  - [ ] 4.3 Implement mascot visual (client-side follower)
    - Spawn a small floating model that follows the player during gameplay
    - Each mascot has a distinct shape/color (simple Part-based, no meshes needed initially)
    - Mascot bobs up and down with a sine wave, trails slightly behind player
    - Particle trail matching mascot color for visual flair

  - [ ] 4.4 Implement mascot selection UI
    - Add mascot collection panel accessible from Lobby (button near achievements)
    - Show all mascots with locked/unlocked/equipped states
    - Display unlock condition for locked mascots
    - "Equip" button for unlocked mascots
    - Equipped mascot shown as highlighted

  - [ ] 4.5 Wire mascot unlock triggers
    - On pack completion: check if pack-specific mascot should unlock
    - On combo milestone: check if combo-specific mascot should unlock
    - On XP update: check if XP-milestone mascot should unlock
    - On daily reward streak: check if streak-specific mascot should unlock
    - Fire MascotUnlocked event to client with notification effects

  - [ ] 4.6 Write property tests for MascotManager
    - Default mascot (Pixel Pup) is always unlocked for any player profile
    - Equipping a locked mascot is rejected
    - Unlock conditions are evaluated correctly against player state
    - Equipped mascot persists in PlayerProfile serialization round-trip
    - No duplicate mascot IDs in definition list

- [ ] 5. GAME MODES (GameModeManager)
  - [ ] 5.1 Design game mode variants
    - **Time Attack**: Reach the 1000-block mark as fast as possible; no morass, timer counts up; leaderboard by fastest time per level
    - **Sprint**: Fixed 60-second timer, get as far as possible; leaderboard by distance
    - **Classic** (existing mode): Current morass-chase gameplay, unchanged
    - Game modes available per-pack (unlocked by completing the pack in Classic mode)
    - Separate leaderboards per mode per pack

  - [ ] 5.2 Implement GameModeManager module
    - Replace stub with full implementation in `src/shared/GameModeManager.luau`
    - Functions: getAvailableModes, getModeConfig, isModeUnlocked, startMode, getLeaderboardKey
    - Mode configs: { id: string, name: string, description: string, hasMorass: boolean, hasTimer: boolean, timerDirection: "up"|"down", timerDuration: number?, scoringType: "time"|"distance"|"xp" }

  - [ ] 5.3 Update LevelGenerator for mode-specific behavior
    - Time Attack: no morass spawned, conveyor still active but slower
    - Sprint: morass spawns but much slower (players outrun it easily), 60s timer on HUD
    - Classic: existing behavior unchanged

  - [ ] 5.4 Update lobby UI with mode selection
    - After entering a pack portal (for completed packs), show mode selection overlay
    - Display available modes with descriptions and best score
    - Default to Classic for uncompleted packs (no choice shown)

  - [ ] 5.5 Add mode-specific leaderboards
    - Extend LeaderboardService with mode-aware keys: `"Leaderboard_{mode}_{packId}"`
    - Time Attack: ranked by lowest time (ascending)
    - Sprint: ranked by highest distance (descending)
    - Update HUD leaderboard panel with mode filter tabs

  - [ ] 5.6 Write property tests for GameModeManager
    - Classic mode always available for all packs
    - Time Attack / Sprint only available after completing pack in Classic
    - Mode config validation (all required fields present)
    - Leaderboard keys are unique per mode+pack combination

- [ ] 6. QUALITY OF LIFE & POLISH
  - [ ] 6.1 Add settings menu
    - Music volume slider (0-100%)
    - SFX volume slider (0-100%)
    - Toggle screen shake (on/off)
    - Toggle combo notifications (on/off)
    - Persist settings in DataStore as part of player profile

  - [ ] 6.2 Add first-time tutorial
    - Detect new player (no level completions, no XP)
    - Show brief overlay tutorial on first run: "Jump to avoid obstacles", "Don't let the morass catch you", "Earn XP to buy power-ups"
    - 3 short tips, dismiss with tap/click, don't show again after first level completion
    - Persist tutorialCompleted flag in player profile

  - [ ] 6.3 Implement "Return to Lobby" from any gameplay state
    - Add a small "Leave" button on HUD during gameplay
    - Confirm dialog: "Return to lobby? (XP earned this run will be kept)"
    - Fire LevelChoice("lobby") on confirm
    - Clean up current level state server-side

  - [ ] 6.4 Add death counter and personal best tracking
    - Track deaths per level per pack (persisted)
    - Track personal best distance per level (persisted)
    - Show personal best on level start and on death ("You made it to block 847 / PB: 923")
    - Show death count humorously on level start ("Attempt #47")

  - [ ] 6.5 Polish morass visuals with difficulty scaling
    - Morass visual intensity increases with level number
    - Levels 1-3: slow, gentle advance visual
    - Levels 7-10: faster advance, more particle effects, screen-edge warning glow
    - Add subtle camera shake when morass is within 20 blocks

## Checkpoint — Epoch 2 Complete

When all tasks above are done, the game should feel **alive**:
- Players have daily reasons to log in (rewards, streak)
- Skilled play is rewarded (combos → more XP)
- There's a second pack to work toward (Pipe World)
- Cosmetic goals exist (mascots to collect)
- Replayability is built in (game modes on completed packs)
- New players aren't lost (tutorial)
- Returning players have quality-of-life (settings, leave button, stats)

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "2.1", "3.1", "4.1", "5.1"], "note": "Design all systems in parallel" },
    { "id": 1, "tasks": ["1.2", "2.2", "3.2", "4.2", "5.2"], "note": "Implement core modules" },
    { "id": 2, "tasks": ["1.3", "2.3", "3.3", "4.3", "5.3"], "note": "Wire into game + client visuals" },
    { "id": 3, "tasks": ["1.4", "2.4", "3.4", "4.4", "5.4"], "note": "Tests + secondary UI" },
    { "id": 4, "tasks": ["3.5", "4.5", "4.6", "5.5", "5.6"], "note": "Remaining tests + features" },
    { "id": 5, "tasks": ["6.1", "6.2", "6.3", "6.4", "6.5"], "note": "QoL polish (can parallel with earlier waves)" }
  ]
}
```

## Notes

- All new types should be added to `Types.luau` to maintain the single source of truth
- New RemoteEvents/RemoteFunctions should be added to the Communication Protocol table in DEVELOPMENT.md
- Combo and daily reward systems are server-authoritative to prevent exploitation
- Mascot visuals start simple (colored Parts) — mesh/texture upgrades can come in a future epoch
- Game mode leaderboards use the same OrderedDataStore pattern but with mode-specific keys
- The Pipe World pack follows the exact same schema as TetrisPack — drop-in extensibility proving the architecture works
- "Pipe World" is intentionally generic — no Nintendo characters, names, or direct IP references. Just brick/pipe/plant aesthetics common to the platformer genre
