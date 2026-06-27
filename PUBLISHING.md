# Publishing Guide

How to get Pixel Run Obby from your development environment into a live Roblox game that players can join.

## Overview

The publishing pipeline goes:

```
Local files → Rojo build → .rbxl file → Roblox Studio → Published Place → Live Game
```

You have two paths:
1. **Rojo serve + Studio publish** (interactive, good for first publish)
2. **Rojo build + CLI upload** (automated, good for CI/CD)

## First-Time Setup

### 1. Create the Roblox game

1. Go to [create.roblox.com](https://create.roblox.com/)
2. Click **Create New Experience**
3. Choose a template (Baseplate is fine — Rojo will overwrite it)
4. Note down the **Universe ID** and **Place ID** from the URL:
   ```
   https://create.roblox.com/dashboard/creations/experiences/UNIVERSE_ID/places/PLACE_ID
   ```

### 2. Configure game settings (web)

On the Creator Dashboard for your experience:

| Setting | Location | Value |
|---------|----------|-------|
| Access | Settings → Access | Public (when ready to launch) |
| Enable Studio API Services | Settings → Security | ON (for DataStore testing) |
| Third-Party Teleports | Settings → Security | OFF |
| Maximum player count | Settings → Places → Basic | 50 (adjust as needed) |
| Genre | Basic Info | Adventure / Action |

### 3. Configure game settings (Studio)

Open the place in Studio (after Rojo sync):

1. **Game Settings → Security:**
   - Enable Studio Access to API Services: ✓
   - Allow HTTP Requests: ✗ (not needed)

2. **Game Settings → Avatar:**
   - Avatar Type: R15 (recommended for Humanoid jump mechanics)
   - Collision: Outer Box

3. **Game Settings → Options:**
   - Experimental streaming: OFF (levels are generated per-player, not streamed)

## Publishing Methods

### Method A: Interactive (Rojo Serve + Studio)

Best for development and manual verification before going live.

```bash
# Terminal: start Rojo live sync
rojo serve
```

1. Open Roblox Studio → connect Rojo plugin
2. Playtest (F5) to verify everything works
3. **File → Publish to Roblox** (or ⌘/Ctrl+Shift+P)
4. Select your existing place or create a new one
5. Click **Publish**

The game is now live at `https://www.roblox.com/games/PLACE_ID`

### Method B: Build + Upload (CI/automated)

Best for automated deployments from Git.

```bash
# Build the .rbxl file from source
rojo build default.project.json -o PixelRunObby.rbxl
```

Then upload using one of these tools:

#### Option 1: Roblox Open Cloud API

```bash
# Install rbxcloud CLI
cargo install rbxcloud

# Upload (requires API key with "Place" scope)
rbxcloud experience upload \
  --api-key YOUR_API_KEY \
  --universe-id UNIVERSE_ID \
  --place-id PLACE_ID \
  --filename PixelRunObby.rbxl \
  --publish-mode publish
```

#### Option 2: Rojo upload (legacy)

```bash
# Requires a .ROBLOSECURITY cookie (less recommended for CI)
rojo upload default.project.json \
  --asset-id PLACE_ID \
  --cookie "YOUR_ROBLOSECURITY_COOKIE"
```

#### Option 3: GitHub Actions (recommended for CI/CD)

```yaml
# .github/workflows/deploy.yml
name: Deploy to Roblox
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Rojo
        uses: ok-nick/setup-lix@v1
        with:
          version: latest

      - name: Install Rojo
        run: cargo install rojo

      - name: Build place file
        run: rojo build default.project.json -o PixelRunObby.rbxl

      - name: Run tests
        run: lune run tests/run_tests.luau

      - name: Upload to Roblox
        run: |
          cargo install rbxcloud
          rbxcloud experience upload \
            --api-key ${{ secrets.ROBLOX_API_KEY }} \
            --universe-id ${{ secrets.UNIVERSE_ID }} \
            --place-id ${{ secrets.PLACE_ID }} \
            --filename PixelRunObby.rbxl \
            --publish-mode publish
```

Set these GitHub secrets:
- `ROBLOX_API_KEY`: Open Cloud API key (Creator Dashboard → Credentials → API Keys)
- `UNIVERSE_ID`: Your experience's universe ID
- `PLACE_ID`: Your place ID

### Getting an Open Cloud API key

1. Go to [create.roblox.com/dashboard/credentials](https://create.roblox.com/dashboard/credentials)
2. Click **Create API Key**
3. Name it (e.g., "CI Deploy")
4. Add permission: **Experience** → select your experience → **Write** access for "Place"
5. Set IP restrictions if desired (or leave open for GitHub Actions)
6. Copy the key — you won't see it again

## Pre-Launch Checklist

Before making the game public, verify these items:

### Functionality
- [ ] Player spawns in lobby, portal is visible
- [ ] Entering Tetris portal starts level 1
- [ ] Running, jumping, and strafing feel responsive
- [ ] Morass advances and eliminates slow players
- [ ] XP accumulates and displays correctly on HUD
- [ ] Level completion at 1000 blocks shows choice UI
- [ ] "Continue" restarts same level, "Next" advances, "Lobby" returns
- [ ] Power-up purchase deducts XP and applies effect
- [ ] Higher Jump, Double Jump, and Faster Speed all work
- [ ] Achievement awards on completing all 10 levels

### Persistence
- [ ] XP persists across sessions (rejoin and verify)
- [ ] Power-ups persist across sessions
- [ ] Level completions persist
- [ ] Leaderboard populates with scores

### Security
- [ ] Rate limiter drops excess calls (test with rapid clicking)
- [ ] Can't purchase power-ups without sufficient XP (check HUD error)
- [ ] Can't skip power-up tiers
- [ ] Can't enter locked packs

### Performance
- [ ] No lag spikes on level generation
- [ ] HUD updates smoothly (1/sec)
- [ ] Morass doesn't stutter
- [ ] Memory usage stable over multiple levels

## Audio Assets

Before publishing, replace placeholder audio (`rbxassetid://0`) with real assets:

1. **Upload audio** on the [Creator Dashboard → Audio](https://create.roblox.com/dashboard/creations?activeTab=Audio)
2. Wait for moderation approval (usually minutes)
3. Copy the asset ID from the approved audio
4. Update `src/client/SoundManager.luau`:
   ```luau
   local THEME_MUSIC = {
       lobby = "rbxassetid://123456789",     -- Replace with your lobby track
       tetris = "rbxassetid://987654321",    -- Replace with your Tetris theme
   }
   
   local SFX_SOUNDS = {
       death = "rbxassetid://111111111",
       levelComplete = "rbxassetid://222222222",
       achievement = "rbxassetid://333333333",
       purchase = "rbxassetid://444444444",
   }
   ```

## Game Icon & Thumbnails

1. Create a 512×512 game icon and 1920×1080 thumbnails
2. Upload via Creator Dashboard → your experience → Basic Info → Icon/Thumbnails

## Updating a Live Game

After the initial publish, updates follow the same flow:

1. Make changes in your local files
2. Test in Studio (F5)
3. Run tests: `lune run tests/run_tests.luau`
4. Publish:
   - **Manual:** File → Publish to Roblox (overwrites the live place)
   - **CI:** Push to `main` branch (triggers GitHub Actions deploy)

Players in an active server keep playing the old version. New servers spin up with the updated code. Existing players get the update when they rejoin.

## DataStore Migrations

If you change the `PlayerProfile` structure (add/remove fields), handle migration:

1. Increment `Types.CURRENT_PROFILE_VERSION`
2. In `DataStoreManager.loadPlayerData`, check the loaded profile's `version` field
3. If `version < CURRENT_PROFILE_VERSION`, run migration logic to add missing fields with defaults
4. Save the migrated profile back

This ensures existing player data doesn't break when you deploy schema changes.

## Monetization (Optional)

If you plan to add Developer Products or Game Passes:

1. **Game Passes** — Creator Dashboard → your experience → Monetization → Game Passes
2. **Developer Products** — Creator Dashboard → your experience → Monetization → Developer Products
3. Handle purchases server-side in `GameServer.server.luau` using `MarketplaceService`
4. Never trust the client for purchase verification

## Going Public

When you're ready for players:

1. Creator Dashboard → your experience → Settings → Access → **Public**
2. Add a description, tags, and social links
3. Consider creating a group for your game for community management
4. Set up a Discord or community channel for feedback
5. Monitor the Output in live servers via the Creator Dashboard → Analytics → Real-Time

Your game is now live on Roblox. Players can find it via search or direct link.
