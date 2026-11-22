# MacGameBridge

An independent open-source engineering project for diagnosing and managing
Windows-game compatibility on Apple Silicon Macs.

**Initial target:** Apple M4, 16 GB unified memory, macOS 27.2.1.

## Current status
Early development. The first release is a read-only Swift CLI. It does not install
Wine, CrossOver, GPTK, games, or drivers, and it does not bypass DRM or anti-cheat.

## Build
Requires Swift 6 toolchain (provided by a compatible Xcode or Command Line Tools setup).

```bash
swift build
swift run macgamebridge help
swift run macgamebridge diagnostics
swift run macgamebridge games
```

## Project structure
- `Sources/` — Swift CLI and core logic
- `database/` — data-driven game profiles
- `docs/` — architecture, roadmap, compatibility matrix
- `AGENTS.md` — instructions for AI coding assistants

## Target games
- FIFA / EA SPORTS FC — exact editions to be confirmed
- eFootball PES 2021
- Need for Speed: Most Wanted — confirm 2005 or 2012
- GTA — GTA V Legacy is provisional; confirm edition

## Legal and safety
MacGameBridge is not affiliated with CodeWeavers, Apple, Valve, EA, Konami,
Electronic Arts, Rockstar, or any game publisher. Third-party components retain
their own licenses and trademarks. Use only games and software you are licensed
to use. No anti-cheat or DRM bypass functionality will be developed.
