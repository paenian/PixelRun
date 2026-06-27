# Implementation Plan: Pixel Run Obby

## Overview

This plan implements Pixel Run Obby in **5 epochs prioritized by playability**. The guiding principle is "Fun first, features second" — each epoch produces a testable, playable state. Epoch 1 delivers a running game you can tweak for feel; later epochs layer in progression, polish, persistence, and hardening.

Stubs are created in Epoch 1 for modules that won't be fully implemented until later epochs, keeping the architecture clean from day one.

## Tasks

- [x] 1. EPOCH 1: Playable Game Core
  - [x] 1.1 Create Rojo project configuration and directory structure
    - Create `default.project.json` mapping ServerScriptService, StarterPlayerScripts, and ReplicatedStorage
    - Create directory structure: `src/server/`, `src/client/`, `src/shared/`, `src/shared/LevelPacks/`, `tests/`, `tests/properties/`, `tests/unit/`, `tests/integration/`
    - _Requirements: 1.1, 1.2, 1.4, 1.6_

  - [x] 1.2 Define shared type definitions and constants
    - Create `src/shared/Types.luau` with all shared types: PlayerProfile, LevelPackConfig, ObstacleDefinition, LevelDifficulty, LevelConfig, LevelLayout, PowerUpDefinition, LeaderboardEntry
    - Define Power-Up cost/multiplier constants matching the design data model
    - _Requirements: 7.1, 12.1_

  - [x] 1.3 Implement LevelUtils module
    - Create `src/shared/LevelUtils.luau` with functions: calculateXP, calculateCompletionBonus, getObstacleDensity, getLevelSeed, getDifficultyConfig
    - XP calculation: `blocks_traveled × pack_number`, completion bonus = 500
    - Obstacle density: linear scale from 1/50 (level 1) to 1/10 (level 10)
    - Deterministic seed: derived from packId + levelNum
    - _Requirements: 3.2, 6.1, 6.2, 6.3_

  - [x] 1.4 Create TetrisPack level configuration
    - Create `src/shared/LevelPacks/TetrisPack.luau` conforming to LevelPackConfig schema
    - Define 7 Tetris piece obstacle types (I, O, T, S, Z, L, J) with 4 orientations each and correct colors (cyan, yellow, purple, green, red, orange, blue)
    - Configure 10 levels of difficulty: levels 1-3 (jump-over only, max 3 blocks tall), levels 4-6 (holes/gaps up to 3 wide, obstacles up to 5 tall), levels 7-9 (void sections up to 5 long), level 10 (touch-and-die blocks)
    - Set prerequisitePack = nil, displayOrder = 1, morassVisual = "rolling_tetris_blocks"
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_

  - [x] 1.5 Implement LevelGenerator with deterministic layout
    - Create `src/server/LevelGenerator.luau` with functions: generateLevel, buildLevel, validatePackSchema
    - Generate deterministic layouts using seeded RNG from packId + levelNum
    - Place obstacles according to density configuration respecting difficulty tiers
    - Each level is 10 blocks wide, 1000 blocks long
    - Schema validation checks all required LevelPackConfig fields
    - _Requirements: 3.1, 3.2, 3.4, 3.7, 12.1, 12.5_

  - [x] 1.6 Implement player movement, jumping, and basic collision
    - Create `src/client/InputController.client.luau` with functions: init, bindJump, bindMovement
    - Bind jump input (single jump for now; double jump wired in Epoch 2)
    - Implement forward movement with base speed
    - Implement basic obstacle collision detection (player hits obstacle → death/respawn)
    - _Requirements: 13.2_

  - [x] 1.7 Implement conveyor and morass mechanics
    - Implement conveyor ground movement at configured minimum speed (blocks per second)
    - Spawn morass 50 blocks behind player start, advance at minimum speed
    - Implement morass collision detection triggering player elimination
    - Apply theme-appropriate morass visuals from TetrisPack config (rolling Tetris blocks)
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

  - [x] 1.8 Implement basic GameServer orchestration for single-level play
    - Create `src/server/GameServer.server.luau` with init, onPlayerJoin, startLevel, eliminatePlayer
    - On player join: skip lobby (Epoch 4), immediately start Tetris pack level 1
    - Generate level layout, send to client, track player position
    - On elimination: respawn at level start, reset morass position
    - _Requirements: 3.3, 4.4, 4.6_

  - [x] 1.9 Create stub modules for systems implemented in later epochs
    - Create stubs (type interface + no-op implementations) for: PowerUpManager, GameModeManager, ComboManager, RewardsManager, MascotManager in `src/shared/`
    - Create stubs for: DataStoreManager, LeaderboardService, AchievementService, ValidationService, RateLimiter in `src/server/`
    - Create stubs for: HUDManager, EffectsManager, SoundManager, LobbyUI in `src/client/`
    - Each stub exports the correct interface so other modules can require() them without error
    - _Requirements: 1.3_

- [x] 2. Checkpoint — Epoch 1 playable
  - Ensure the game runs: player spawns, level generates, player can run and jump through Tetris obstacles, morass chases, elimination respawns at start. Ask the user to playtest feel/speed/difficulty.

- [x] 3. EPOCH 2: Progression & Feedback
  - [x] 3.1 Implement PowerUpManager module (full implementation)
    - Replace stub in `src/shared/PowerUpManager.luau` with full functions: getDefinitions, getCost, getMultiplier, canPurchase, applyPurchase
    - Define Higher Jump (3 tiers: 1.25x, 1.5x, 2.0x; costs 2000, 5000, 12000), Double Jump (1 tier, cost 8000), Faster Speed (3 tiers: 1.25x, 1.5x, 2.0x; costs 2000, 5000, 12000)
    - Enforce sequential tier purchasing and XP sufficiency checks
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

  - [x] 3.2 Wire power-up effects to player character
    - Apply Higher Jump multiplier to player jump height based on purchased tier
    - Apply Double Jump allowing second airborne jump when power-up owned
    - Apply Faster Speed multiplier to player movement speed based on purchased tier
    - Update InputController to support double jump input
    - _Requirements: 7.5, 7.6, 7.7_

  - [x] 3.3 Implement XP earning and level completion flow
    - Accumulate XP at 1 per block traveled × pack multiplier during gameplay
    - Award 500 XP completion bonus at 1000-block mark
    - On level completion: present choice to continue same level or advance to next level
    - Retain all XP on elimination (no XP loss on death)
    - Track level completions per pack (levels 1-10)
    - On completing level 10 of pack: offer return to lobby or replay any level
    - _Requirements: 6.1, 6.2, 6.3, 6.5, 3.3, 3.5, 3.6_

  - [x] 3.4 Implement basic HUD showing progression
    - Replace HUDManager stub with real implementation in `src/client/HUDManager.luau`
    - Display current XP total, XP earned this run, and XP needed for next power-up (update once per second)
    - Show level completion choices (continue, next level, lobby)
    - Display error messages from server rejections
    - _Requirements: 6.4, 13.5_

  - [x] 3.5 Implement power-up purchase flow via RemoteFunction
    - Create RemoteFunction: PurchasePowerUp
    - Client sends purchase request via InputController.onPurchaseRequest
    - Server validates XP and tier sequence, deducts XP, applies upgrade
    - Server returns {success, message, newData} to client
    - Client HUD updates on success, shows error on failure
    - _Requirements: 7.2, 7.3, 13.4_

- [x] 4. Checkpoint — Epoch 2 playable
  - Ensure the full gameplay loop works: run level → earn XP → complete level → advance → buy power-ups → use power-ups on harder levels. Ask the user if the progression feels rewarding.

- [x] 5. EPOCH 3: Content & Polish
  - [x] 5.1 Implement EffectsManager (full implementation)
    - Replace stub in `src/client/EffectsManager.luau` with full functions: playLevelComplete, playXPGain, playDeath, playAchievement
    - Level completion: particle explosion at player position
    - XP gain: floating text batched to once per second
    - Death: death particle effect on collision
    - Achievement: particle explosion + floating text for 3-5 seconds
    - _Requirements: 9.1, 9.2, 9.3, 8.4_

  - [x] 5.2 Implement SoundManager (full implementation)
    - Replace stub in `src/client/SoundManager.luau` with full functions: playPackMusic, playLobbyMusic, crossfade, playSFX
    - Play theme-appropriate background music looping per Level_Pack
    - Crossfade between lobby and level music over 1-2 seconds
    - _Requirements: 9.4, 9.5_

  - [x] 5.3 Implement AchievementService (full implementation)
    - Replace stub in `src/server/AchievementService.luau` with full functions: checkPackCompletion, awardAchievement, getPlayerAchievements
    - Award achievement when all 10 levels of a pack are completed
    - Prevent duplicate awards (idempotent)
    - Trigger EffectsManager achievement display on award (particle explosion + floating text 3-5s)
    - Persist achievements via DataStoreManager with retry logic (up to 3 retries)
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_

  - [x] 5.4 Implement achievement list UI in HUD
    - Add achievement list accessible from HUD showing all defined achievements with earned/unearned status
    - Display unique name and associated icon per Level_Pack achievement
    - _Requirements: 8.7_

  - [x] 5.5 Implement full Tetris pack difficulty tuning
    - Verify and refine obstacle placement across all 10 levels for balanced difficulty curve
    - Ensure levels 1-3 use only jump-over obstacles (max 3 blocks tall)
    - Ensure levels 4-6 introduce platform gaps up to 3 blocks wide and obstacles up to 5 blocks tall
    - Ensure levels 7-9 introduce void sections up to 5 blocks long
    - Ensure level 10 introduces glowing touch-and-die blocks
    - Ensure all 10 levels completable without power-ups
    - _Requirements: 5.3, 5.6_

- [x] 6. Checkpoint — Epoch 3 polished
  - Ensure effects, sound, and achievements fire correctly. Verify the full 10-level Tetris pack feels good from level 1 through level 10. Ask the user if the juice/polish is satisfying.

- [x] 7. EPOCH 4: Persistence & Social
  - [x] 7.1 Implement DataStoreManager (full implementation)
    - Replace stub in `src/server/DataStoreManager.luau` with full functions: loadPlayerData, savePlayerData, getCachedData, startAutoSave, flushAll
    - Implement in-memory cache keyed by userId with PlayerProfile structure
    - Auto-save every 60 seconds and on each level completion
    - Retry logic: up to 3 retries with 2s delay on load, immediate retries on save
    - Fallback: spawn with default profile (0 XP, no power-ups, no completions, no achievements) on load failure
    - Save on PlayerRemoving event, flushAll on server shutdown
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_

  - [x] 7.2 Implement LeaderboardService (full implementation)
    - Replace stub in `src/server/LeaderboardService.luau` with full functions: updateXPScore, updateLevelScore, getTopXP, getTopLevel, getPlayerRank
    - Use OrderedDataStore for XP and Level leaderboards
    - Return top 100 entries, include player's own rank
    - Update within 5 seconds of score change
    - Handle failures gracefully (display "temporarily unavailable", retry every 10s)
    - _Requirements: 10.1, 10.2, 10.3, 10.5, 10.6_

  - [x] 7.3 Wire leaderboard display into HUD
    - Add leaderboard view accessible from Lobby and during gameplay via HUD
    - Show global rankings by total XP and highest level completed (top 100)
    - Always display current player's own rank and score
    - _Requirements: 10.4, 10.5_

  - [x] 7.4 Implement LobbyUI and pack portal navigation
    - Replace stub in `src/client/LobbyUI.luau` with full lobby implementation
    - Display level pack portals radiating from center with theme, difficulty (1-10), and completion status (X/10)
    - Distinguish locked packs (reduced opacity + lock icon) from unlocked packs
    - Show unlock requirement message on interaction with locked portals
    - Handle portal entry to trigger level start via RemoteEvent
    - _Requirements: 2.2, 2.3, 2.4, 2.5_

  - [x] 7.5 Implement pack unlock sequencing and lobby spawn
    - Update GameServer.onPlayerJoin to spawn player in Lobby (replace Epoch 1 direct-to-level behavior)
    - Implement sequential pack unlocking: pack N requires all 10 levels of pack N-1 completed
    - First pack (Tetris) always unlocked
    - On entering unlocked portal: teleport to level 1 of selected pack
    - _Requirements: 2.1, 2.3, 2.6_

  - [x] 7.6 Implement pack auto-discovery and registry
    - Create auto-discovery logic that iterates `src/shared/LevelPacks/` directory children at server start
    - Build PackRegistry: load each module, validate schema, register valid packs sorted by displayOrder
    - Log errors for invalid packs, skip them, continue loading remaining packs
    - Position portals in Lobby according to pack displayOrder
    - _Requirements: 12.2, 12.4, 12.5, 12.6_

  - [x] 7.7 Wire RemoteEvent/RemoteFunction communication layer
    - Create RemoteEvents: RequestStartLevel, LevelStarted, XPUpdate, LevelCompleted, LevelChoice, PlayerEliminated
    - Wire server GameServer to validate and respond to all client requests
    - Wire client InputController to fire RemoteEvents and invoke RemoteFunctions
    - Wire server responses to client HUDManager, EffectsManager, and SoundManager
    - _Requirements: 13.4, 13.5_

- [x] 8. Checkpoint — Epoch 4 live-ready
  - Ensure data persists across sessions, leaderboards populate, lobby navigation works, and packs unlock sequentially. Ask the user to verify progress saves correctly.

- [x] 9. EPOCH 5: Hardening & Extensibility
  - [x] 9.1 Implement ValidationService (full implementation)
    - Replace stub in `src/server/ValidationService.luau` with full functions: validatePurchase, validateLevelCompletion, validateXPClaim, isPackUnlocked
    - Validate pack unlock sequentially (pack N requires all 10 levels of pack N-1 completed)
    - Validate power-up purchases (XP, tier sequence, existence)
    - Validate level completion claims against player position and state
    - Reject invalid requests with error code and descriptive message
    - _Requirements: 2.6, 7.3, 7.4, 13.3, 13.5_

  - [x] 9.2 Implement RateLimiter (full implementation)
    - Replace stub in `src/server/RateLimiter.luau` with full functions: check, reset
    - Enforce maximum 30 RemoteEvent calls per second per player
    - Track per-userId call counts with tick-based reset
    - Drop excess calls and log warnings
    - _Requirements: 13.6_

  - [x] 9.3 Wire ValidationService and RateLimiter into GameServer
    - All state-changing requests pass through ValidationService before applying changes
    - All incoming RemoteEvents pass through RateLimiter before processing
    - Server returns error codes and messages on validation failure
    - Client displays rejection messages via HUDManager.showError
    - _Requirements: 13.3, 13.5, 13.6_

  - [x] 9.4 Set up Lune-based test runner for SharedModules
    - Configure Lune as the test runtime for all `tests/` directory files
    - Create test runner script that discovers and executes `.spec.luau` and `.prop.luau` files
    - Implement property test harness with seeded random generators (minimum 100 iterations)
    - _Requirements: 1.5_

  - [x] 9.5 Write property tests for LevelUtils
    - **Property 2: Obstacle Density Within Bounds** — verify density between 20–100 obstacles for levels 1–10
    - **Property 4: Deterministic Level Generation** — verify same seed produces same output
    - **Property 6: XP Calculation Correctness** — verify XP = blocks × pack_number and bonus = 500
    - **Validates: Requirements 3.2, 3.5, 3.7, 6.1, 6.3**

  - [x] 9.6 Write property tests for PowerUpManager
    - **Property 7: Successful Purchase Updates State Correctly** — XP decreases by cost, tier increments by 1
    - **Property 8: Insufficient XP Rejects Purchase** — profile unchanged when XP < cost
    - **Property 9: Sequential Tier Enforcement** — tier N rejected without tier N-1 owned
    - **Validates: Requirements 7.2, 7.3, 7.4**

  - [x] 9.7 Write property tests for LevelGenerator and pack loading
    - **Property 3: Obstacle Types Restricted by Level Tier** — verify only permitted obstacle types appear per tier
    - **Property 11: One Achievement Per Pack** — each valid pack has exactly one non-empty achievementName
    - **Property 15: Pack Schema Validation Correctness** — valid configs pass, missing fields fail with error message
    - **Property 16: Pack Ordering by Display Order** — orderedPacks sorted in ascending displayOrder
    - **Property 17: Invalid Packs Skipped Gracefully** — only valid packs in registry, invalid ones in loadErrors
    - **Validates: Requirements 3.4, 8.1, 12.1, 12.4, 12.5**

  - [x] 9.8 Write property tests for ValidationService and RateLimiter
    - **Property 1: Pack Unlock Sequential Logic** — pack N unlocked iff pack N-1 fully complete; pack 1 always unlocked
    - **Property 10: Required Power-Ups Gate Obstacles** — players without required power-ups rejected
    - **Property 18: Server Rejects Invalid State Changes** — invalid requests leave state unchanged
    - **Property 19: Rate Limiter Enforces Cap** — first 30 calls pass, subsequent calls in same second dropped
    - **Validates: Requirements 2.6, 7.8, 13.3, 13.5, 13.6**

  - [x] 9.9 Write property tests for AchievementService and DataStore
    - **Property 5: XP Retention on Elimination** — total XP increases by full run amount after death
    - **Property 12: Achievement Awarded on Pack Completion** — achievement added when all 10 levels complete
    - **Property 13: Achievement Idempotence** — duplicate award attempt leaves list unchanged
    - **Property 14: Player Profile Serialization Round-Trip** — serialize/deserialize produces identical profile
    - **Validates: Requirements 4.6, 6.5, 8.2, 8.3, 11.1**

  - [x] 9.10 Write unit tests for TetrisPack, EffectsManager, and SoundManager
    - Verify all 7 Tetris piece types have correct colors and 4 orientations each
    - Verify difficulty progression matches requirement thresholds
    - Verify pack is completable without power-ups
    - Test XP floating text batching (no more than once per second)
    - Test crossfade duration bounds (1-2 seconds)
    - Test achievement effect duration (3-5 seconds)
    - _Requirements: 5.2, 5.3, 5.6, 9.2, 9.5, 8.4_

- [x] 10. Final checkpoint — Production ready
  - Ensure all property tests and unit tests pass. Verify validation rejects exploits, rate limiter drops excess calls, and pack schema validation catches malformed configs. Ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- **Epoch philosophy**: Each epoch produces a playable/testable state. Epoch 1 = "can I run and jump through obstacles?", Epoch 2 = "is the loop rewarding?", Epoch 3 = "does it look/sound good?", Epoch 4 = "does it persist and feel social?", Epoch 5 = "is it exploit-proof?"
- Stubs created in Epoch 1 ensure modules can be require()'d cleanly throughout development — no broken imports between epochs
- Property tests are consolidated in Epoch 5 because correctness hardening happens after gameplay feel is locked in
- All code is written in Luau using the Rojo external development workflow
- Lune is used as the standalone Luau test runtime outside Roblox Studio
- Integration tests (DataStore, physics, RemoteEvents) require Roblox Studio and are not included in automated tasks

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2"] },
    { "id": 1, "tasks": ["1.3", "1.4", "1.9"] },
    { "id": 2, "tasks": ["1.5", "1.6"] },
    { "id": 3, "tasks": ["1.7", "1.8"] },
    { "id": 4, "tasks": ["3.1", "3.3"] },
    { "id": 5, "tasks": ["3.2", "3.4", "3.5"] },
    { "id": 6, "tasks": ["5.1", "5.2", "5.5"] },
    { "id": 7, "tasks": ["5.3", "5.4"] },
    { "id": 8, "tasks": ["7.1", "7.2", "7.4"] },
    { "id": 9, "tasks": ["7.3", "7.5", "7.6"] },
    { "id": 10, "tasks": ["7.7"] },
    { "id": 11, "tasks": ["9.1", "9.2"] },
    { "id": 12, "tasks": ["9.3", "9.4"] },
    { "id": 13, "tasks": ["9.5", "9.6", "9.7"] },
    { "id": 14, "tasks": ["9.8", "9.9", "9.10"] }
  ]
}
```
