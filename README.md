# Pixel Run Obby

A near-endless running game for Roblox where players sprint through themed 10-level obstacle packs, earn XP to purchase persistent power-ups, and race against an advancing morass wall.

## Overview

Players spawn in a lobby with level pack portals, choose a pack, and run through procedurally-placed obstacles on a 10-block-wide, 1000-block-long conveyor course. The morass (a themed advancing wall) enforces a minimum speed — fall behind and you're eliminated. Earn XP per block traveled, buy power-ups (Higher Jump, Double Jump, Faster Speed), complete all 10 levels of a pack to unlock the next, and compete on global leaderboards.

## Features

- **Themed Level Packs** — Tetris-themed first pack with 7 piece-shaped obstacles across 10 difficulty-tiered levels
- **Progressive Difficulty** — Levels 1-3 (jump-over), 4-6 (gaps), 7-9 (void sections), 10 (touch-and-die)
- **Power-Up System** — 3 purchasable upgrades with tiered progression (Higher Jump 3 tiers, Double Jump, Faster Speed 3 tiers)
- **XP & Progression** — Earn XP per block × pack multiplier, 500 XP bonus per level completion, XP retained on death
- **Morass Mechanic** — Themed advancing wall (rolling Tetris blocks) enforcing minimum speed
- **Achievements** — One per pack, awarded on completing all 10 levels
- **Leaderboards** — Global real-time rankings by total XP and highest level
- **Data Persistence** — Player progress saved via DataStoreService with retry logic
- **Server-Authoritative** — All game state validated server-side, rate limiting enforced
- **Extensible Packs** — Add new level packs by dropping a single `.luau` file into `src/shared/LevelPacks/`

## Tech Stack

- **Language:** Luau (strict mode)
- **Development:** Rojo (external file sync to Roblox Studio)
- **Testing:** Lune (standalone Luau runtime for CI)
- **Architecture:** Client-server with RemoteEvents/RemoteFunctions

## Project Structure

```
PixelRun/
├── default.project.json     Rojo project mapping
├── src/
│   ├── server/              ServerScriptService (authoritative game logic)
│   ├── client/              StarterPlayerScripts (UI, input, effects)
│   └── shared/              ReplicatedStorage (types, utilities, level packs)
│       └── LevelPacks/      One module per pack (auto-discovered at start)
└── tests/
    ├── properties/          Property-based tests (min 100 iterations each)
    ├── unit/                Example-based unit tests
    └── integration/         Roblox Studio integration tests
```

## Quick Links

- [Getting started & running the game](QUICKSTART.md)
- [Development guide & adding features](DEVELOPMENT.md)
- [Publishing to Roblox](PUBLISHING.md)

## License

Private project — all rights reserved.
