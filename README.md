# MacGameBridge

An independent open-source engineering project for diagnosing and managing
Windows-game compatibility on Apple Silicon Macs.

**Initial target:** Apple M4, 16 GB unified memory, macOS 27.2.1.

## Current status
Early development. The Swift CLI performs read-only diagnostics and discovery,
persists *planned* game-environment metadata, and can pin an exact discovered
runtime ID through a provider adapter. Pinning saves a record only: it does not
create a prefix, run Wine, launch a game, or install software. A pinned runtime
is not evidence that any game works. MacGameBridge does not bypass DRM or
anti-cheat.

## Build
Requires Swift 6 toolchain (provided by a compatible Xcode or Command Line Tools setup).

```bash
swift build
swift run macgamebridge help
swift run macgamebridge diagnostics
swift run macgamebridge games
swift run macgamebridge environments help
swift run macgamebridge environments list
swift run macgamebridge runtimes --providers
# Copy an exact ID printed above, then pin it as metadata only:
swift run macgamebridge environments pin-runtime <environment-id> --runtime <installation-id>
swift run macgamebridge environments unpin-runtime <environment-id>
```

Environment records are stored in
`~/Library/Application Support/MacGameBridge/environments.json`. See
`docs/M3-ENVIRONMENTS.md` for environment commands and JSON shapes, and
`docs/M3.1-RUNTIME-ADAPTERS.md` for adapter support, exact pinning semantics,
and safety boundaries. Only standalone Wine has an adapter; CrossOver, Whisky,
and Sikarugir installations are discovered but cannot be pinned yet.

## Project structure
- `Sources/` — Swift CLI and core logic, including `Core/Environment` metadata
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
