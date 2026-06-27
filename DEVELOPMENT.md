# Development Guide

How to add features, create level packs, write tests, and maintain the codebase.

## Architecture Overview

```
Client (StarterPlayerScripts)          Server (ServerScriptService)
─────────────────────────────          ─────────────────────────────
InputController.client.luau            GameServer.server.luau
  → movement, jump, collision            → orchestrates everything
HUDManager.luau                        LevelGenerator.luau
  → XP display, choices, errors          → deterministic level layouts
EffectsManager.luau                    MorassManager.luau
  → particles, floating text             → advancing wall per player
SoundManager.luau                      DataStoreManager.luau
  → music crossfade, SFX                 → persistence + cache
LobbyUI.luau                           LeaderboardService.luau
  → portal display                       → OrderedDataStore rankings
EventWiring.client.luau                AchievementService.luau
  → connects events → effects/sound     ValidationService.luau
                                        RateLimiter.luau
                                        PackRegistry.luau

Shared (ReplicatedStorage)
─────────────────────────────
Types.luau         → all type defs + constants
LevelUtils.luau    → XP calc, density, seeds
PowerUpManager.luau → definitions, purchase logic
LevelPacks/        → one module per pack (auto-discovered)
```

**Key principle:** The server is authoritative. All state changes (XP, purchases, completions) happen server-side. The client only renders and sends requests.

## Adding a New Level Pack

This is the most common addition. No core code changes needed.

### 1. Create the pack file

Create `src/shared/LevelPacks/YourPack.luau`:

```luau
--!strict
local Types = require(script.Parent.Parent.Types)

local YourPack: Types.LevelPackConfig = {
    name = "Your Pack Name",
    displayOrder = 2,                    -- Determines portal position (ascending)
    themeId = "your_theme",              -- Unique ID, used as registry key
    prerequisitePack = "tetris",         -- themeId of pack that must be completed first (nil for none)
    morassVisual = "lava_flow",          -- Visual style for the morass wall
    achievementName = "Your Achievement",
    musicTrack = "your_music",

    obstacleTypes = {
        {
            shape = "Block",
            orientations = {0, 90, 180, 270},
            color = Color3.fromRGB(200, 100, 50),
            maxHeight = 5,
            isTouchKill = false,
        },
        -- Add more obstacle types...
        -- Include at least one isTouchKill = true type for level 10
    },

    difficulty = {
        [1]  = { obstacleDensity = 1/50, maxHeight = 3, gapWidth = 0, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil },
        [2]  = { obstacleDensity = 1/45, maxHeight = 3, gapWidth = 0, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil },
        [3]  = { obstacleDensity = 1/40, maxHeight = 3, gapWidth = 0, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil },
        [4]  = { obstacleDensity = 1/35, maxHeight = 5, gapWidth = 3, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil },
        [5]  = { obstacleDensity = 1/30, maxHeight = 5, gapWidth = 3, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil },
        [6]  = { obstacleDensity = 1/25, maxHeight = 5, gapWidth = 3, voidLength = 0, hasTouchKill = false, requiredPowerUps = nil },
        [7]  = { obstacleDensity = 1/20, maxHeight = 5, gapWidth = 3, voidLength = 5, hasTouchKill = false, requiredPowerUps = nil },
        [8]  = { obstacleDensity = 1/15, maxHeight = 5, gapWidth = 3, voidLength = 5, hasTouchKill = false, requiredPowerUps = nil },
        [9]  = { obstacleDensity = 1/12, maxHeight = 5, gapWidth = 3, voidLength = 5, hasTouchKill = false, requiredPowerUps = nil },
        [10] = { obstacleDensity = 1/10, maxHeight = 5, gapWidth = 3, voidLength = 5, hasTouchKill = true,  requiredPowerUps = nil },
    },
}

return YourPack
```

### 2. That's it

On server start, `PackRegistry` auto-discovers all modules in `LevelPacks/`, validates their schema, and registers them. The lobby portal appears automatically based on `displayOrder`. No changes to `default.project.json` or any other file are needed.

### Schema validation

PackRegistry validates the following required fields at startup:
- `name` (string)
- `displayOrder` (number)
- `themeId` (string)
- `obstacleTypes` (non-empty array)
- `difficulty` (table)
- `morassVisual` (string)
- `achievementName` (string)

If your pack fails validation, it's skipped with a warning in the Output. Check for typos in field names.

### Pack unlock sequencing

Packs unlock sequentially by `displayOrder`. A player must complete all 10 levels of pack N before pack N+1 unlocks. Set `prerequisitePack` to the `themeId` of the pack that must be completed first, or `nil` for no prerequisite.

## Adding a New Power-Up

1. Add the definition to `Types.POWER_UP_DEFINITIONS` in `src/shared/Types.luau`
2. Add a field to `PlayerProfile.powerUps` in `Types.luau`
3. Update `PowerUpManager.luau` — add cases in `getPlayerTier` and `applyPurchase`
4. Update `InputController.client.luau` — apply the effect in `applyPowerUpEffects()`
5. Update `ValidationService.luau` if needed
6. Add property tests in `tests/properties/PowerUpManager.prop.luau`

## Communication Protocol

All client-server communication goes through a single `RemoteEvents` folder in ReplicatedStorage:

| Name | Direction | Purpose |
|------|-----------|---------|
| RequestStartLevel | Client → Server | Enter a pack portal |
| LevelStarted | Server → Client | Level loaded, start gameplay |
| LevelCompleted | Server → Client | Reached 1000 blocks |
| LevelChoice | Client → Server | Continue/Next/Lobby choice |
| PlayerEliminated | Server → Client | Caught by morass |
| XPUpdate | Server → Client | Periodic XP state (1/sec) |
| PowerUpUpdate | Server → Client | After successful purchase |
| AchievementAwarded | Server → Client | Pack achievement earned |
| ShowLobby | Server → Client | Display lobby with pack data |
| ServerError | Server → Client | Validation/rate-limit error |
| PurchasePowerUp | Client → Server | RemoteFunction (request-response) |
| RequestLeaderboard | Client → Server | RemoteFunction (request-response) |

## Testing

### Test categories

| Directory | Pattern | Runner | Purpose |
|-----------|---------|--------|---------|
| `tests/unit/` | `*.spec.luau` | Lune subprocess | Example-based assertions |
| `tests/properties/` | `*.prop.luau` | Lune subprocess | Property-based (100+ iterations) |
| `tests/integration/` | `*.spec.luau` | Roblox Studio (TestEZ) | Requires Roblox services |

### Writing a property test

```luau
--!strict
local TestHarness = require("../TestHarness")

TestHarness.property("Your property name", 100, function(rng)
    -- Generate random inputs
    local value = TestHarness.randomInt(rng, 1, 1000)

    -- Exercise the code
    local result = yourFunction(value)

    -- Assert the property
    if not yourCondition(result) then
        return false, string.format("Failed for value=%d, result=%d", value, result)
    end

    return true, nil
end)

TestHarness.report()
```

### Running tests

```bash
lune run tests/run_tests.luau
```

### Reproducing a failure

If a property test fails, it prints the seed:
```
  ✗ FAIL [iteration 42/100]: Your property name
    Seed: 1234567890
    Reproduce: TestHarness.setSeed(1234567890)
```

Add `TestHarness.setSeed(1234567890)` before your property call to reproduce the exact failure.

## Code Conventions

- All files use `--!strict` mode
- Module pattern: `local Module = {} ... return Module`
- Types exported via `export type` when needed by other modules
- Server scripts end in `.server.luau`, client scripts in `.client.luau`
- Regular modules end in `.luau` (required by other scripts)
- Constants in UPPER_SNAKE_CASE, functions in camelCase
- Every module has a file header comment explaining its purpose and requirements validated

## Stubbed Modules (Future Development)

These modules export correct interfaces but are no-ops, ready for implementation:

| Module | Location | Purpose |
|--------|----------|---------|
| GameModeManager | `src/shared/` | Future game mode variations |
| ComboManager | `src/shared/` | Future combo/streak systems |
| RewardsManager | `src/shared/` | Future reward distributions |
| MascotManager | `src/shared/` | Future mascot/companion system |

## Common Tasks

### Adjusting game feel
- **Player speed:** `BASE_WALK_SPEED` in `InputController.client.luau` (default: 16)
- **Jump power:** `BASE_JUMP_POWER` in `InputController.client.luau` (default: 50)
- **Morass speed:** Conveyor speed scales from 5-12 blocks/sec (levels 1-10) in `LevelGenerator.luau`
- **Track width:** `Types.LEVEL_WIDTH` (10 blocks)
- **Level length:** `Types.LEVEL_LENGTH` (1000 blocks)

### Changing XP rates
- Per-block rate: `Types.XP_PER_BLOCK` (default: 1)
- Completion bonus: `Types.LEVEL_COMPLETION_BONUS` (default: 500)
- Pack multiplier: Equals `displayOrder` of the pack

### Changing power-up costs
Edit `Types.POWER_UP_DEFINITIONS` in `src/shared/Types.luau`. The costs/multipliers array is indexed by tier (1-based).

### Adding sounds/music
1. Upload audio to Roblox (Creator Dashboard → Audio)
2. Replace `"rbxassetid://0"` placeholders in `SoundManager.luau` with real asset IDs
3. Map pack themes to tracks in the `THEME_MUSIC` table

### Adding visual effects
Modify `EffectsManager.luau` — each function creates temporary Parts with ParticleEmitters. Adjust colors, speeds, lifetimes, and emit counts for different feels.

## Developing on macOS

The entire workflow runs natively on macOS with no Windows-specific dependencies.

### Tool installation (Homebrew)

```bash
brew install rojo lune
```

Or install via Cargo if you have the Rust toolchain:
```bash
cargo install rojo lune
```

### Editor setup

Any editor with Luau support works. Recommended options on Mac:

- **VS Code** with the [Luau LSP extension](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.luau-lsp) — type checking, autocomplete, go-to-definition
- **Zed** — fast native editor with Luau tree-sitter grammar
- **Sublime Text** with the Luau syntax package

For Luau LSP to resolve `script.Parent` paths, point it at your `default.project.json`:
```json
// .vscode/settings.json
{
  "luau-lsp.sourcemap.rojoProjectFile": "default.project.json"
}
```

Generate a sourcemap for full IntelliSense:
```bash
rojo sourcemap default.project.json -o sourcemap.json
```

### Running tests on macOS

```bash
# All tests
lune run tests/run_tests.luau

# Watch mode (re-run on file change) using fswatch
brew install fswatch
fswatch -o src/ tests/ | xargs -n1 -I{} lune run tests/run_tests.luau
```

### CI with GitHub Actions (cross-platform)

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest  # Also works on macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ok-nick/setup-lix@v1
        with:
          version: latest
      - run: lune run tests/run_tests.luau
```

### macOS-specific gotchas

- **Case sensitivity:** macOS filesystems are case-insensitive by default. Avoid having two files that differ only in casing (e.g., `Types.luau` vs `types.luau`).
- **Quarantine:** If Rojo or Lune binaries are quarantined after download, clear it: `xattr -d com.apple.quarantine /path/to/binary`
- **Studio updates:** Roblox Studio auto-updates on Mac. If the Rojo plugin breaks after an update, reinstall it from the Toolbox.
- **.DS_Store files:** Add `.DS_Store` to your `.gitignore` to avoid committing macOS metadata files.
