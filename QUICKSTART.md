# Quick Start Guide

Get Pixel Run Obby running in Roblox Studio for testing in under 5 minutes.

## Prerequisites

| Tool | Purpose |
|------|---------|
| [Roblox Studio](https://create.roblox.com/) | Game runtime & testing |
| [Rojo](https://rojo.space/) | File sync (external → Studio) |
| [Lune](https://lune-org.github.io/docs) | Test runner (optional, for CI) |

### Installing on Windows

**Roblox Studio:**
Download and install from [create.roblox.com](https://create.roblox.com/).

**Rojo & Lune:**

```powershell
# Install Aftman first: https://github.com/LPGhatguy/aftman/releases
# aftman installs from the aftman.toml file - add new tools there as needed
aftman install
```

**Verify installation:**

```powershell
rojo --version    # Should print something like "rojo 7.x.x"
lune --version    # Should print something like "lune 0.8.x"
```

### Installing on macOS

**Roblox Studio:**
Download the `.dmg` from [create.roblox.com](https://create.roblox.com/) and drag to Applications.

**Rojo and Lune via Homebrew (easiest):**

```bash
# Install Homebrew if you don't have it
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install both tools
brew install rojo
brew install lune
```

**Alternative: Aftman (same as Windows):**

```bash
# Install Aftman
curl -L https://github.com/LPGhatguy/aftman/releases/latest/download/aftman-macos-aarch64.zip -o aftman.zip
unzip aftman.zip && chmod +x aftman && mv aftman /usr/local/bin/

# Then install tools
aftman install rojo-rbx/rojo
aftman install lune-org/lune
```

**Alternative: Cargo:**

```bash
# Install Rust first (if needed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Then install via Cargo
cargo install rojo lune
```

**Verify installation:**

```bash
rojo --version
lune --version
```

> **Apple Silicon note:** Homebrew, Aftman, and Cargo all provide native arm64 binaries for M1/M2/M3 Macs. If you download a release binary manually, pick the `aarch64-apple-darwin` variant.

## Setup

### 1. Clone the repository

```bash
git clone <your-repo-url>
cd PixelRun
```

### 2. Start Rojo server

```bash
rojo serve
```

This reads `default.project.json` and starts a live-sync server on `localhost:34872`.

### 3. Connect Roblox Studio

1. Open Roblox Studio (create a new Baseplate or empty place)
2. Install the [Rojo plugin](https://www.roblox.com/library/13916111004/Rojo) if you haven't
3. In Studio, click the Rojo plugin → **Connect** → confirm the server address
4. Your file system is now synced live to Studio

### 4. Playtest

- Press **F5** (Play) in Roblox Studio
- You should spawn in the lobby with the Tetris pack portal
- Click "Enter" on the portal to start running through the first level

## Running Tests (without Roblox Studio)

Property tests and unit tests run outside Studio using Lune:

```bash
# Run all tests
lune run tests/run_tests.luau

# Run a single test file
lune run tests/properties/LevelUtils.prop.luau
lune run tests/unit/TetrisPack.spec.luau
```

Tests use mocked Roblox APIs (`tests/MockRoblox.luau`) and inlined pure logic so they don't require a Roblox runtime.

## Troubleshooting

### Rojo won't connect
- Verify `rojo serve` is running and shows "Serving on port 34872"
- Check the Rojo plugin version matches your CLI version (`rojo --version`)

### Scripts don't run in Studio
- Verify the Explorer tree shows `ServerScriptService`, `StarterPlayer > StarterPlayerScripts`, and `ReplicatedStorage` populated with scripts
- Check the Output window for require errors — if you see "attempt to index nil with X", a module path may be wrong

### Player doesn't spawn / morass doesn't move
- Check Output for `[PackRegistry]` messages — if zero packs loaded, the game can't start
- Verify `src/shared/LevelPacks/TetrisPack.luau` exists and passes schema validation

### DataStore errors in Studio testing
- DataStore only works in published places or with Studio API access enabled
- For local testing, the game falls back to default profiles (0 XP, no power-ups) — this is expected behavior

## Studio Settings for Full Testing

To test DataStore persistence and leaderboards locally:

1. **Publish the place** to Roblox (File → Publish to Roblox)
2. **Enable Studio API access**: Game Settings → Security → "Enable Studio Access to API Services" → ON
3. Now DataStoreService and OrderedDataStore will work in Studio test sessions

## macOS Notes

Roblox Studio runs natively on macOS (Apple Silicon and Intel). A few differences from the Windows workflow:

### Roblox Studio on Mac

- Studio lives in `/Applications/RobloxStudio.app`
- The Rojo plugin installs the same way (Toolbox → search "Rojo" → install)
- Playtest shortcut is **⌘+F5** (or click Play in the toolbar)
- Output window: **View → Output**

### File paths & terminal

macOS uses forward slashes. The project works as-is — Rojo handles paths cross-platform. No changes needed to `default.project.json`.

```bash
cd ~/Projects/PixelRun   # or wherever you cloned it
rojo serve               # starts live sync
lune run tests/run_tests.luau  # run tests
```

### Known macOS differences

- File watching (Rojo) uses macOS FSEvents — changes sync instantly
- If Rojo fails to connect, check that port 34872 isn't blocked by the macOS firewall (System Settings → Network → Firewall → Options → allow `rojo`)
- If a binary is quarantined after download, clear it: `xattr -d com.apple.quarantine /path/to/binary`

## Controls

| Key | Action |
|-----|--------|
| Space | Jump (double jump if power-up owned) |
| A / Left Arrow | Strafe left |
| D / Right Arrow | Strafe right |
| Movement | Automatic forward (endless runner) |
