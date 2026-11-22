# M1 — Hardware Intelligence Engine

## Commands
```bash
swift run macgamebridge diagnostics
swift run macgamebridge diagnostics --json
swift run macgamebridge games
swift test
```

## JSON report
Save a local report without committing machine-specific data:
```bash
mkdir -p reports
swift run macgamebridge diagnostics --json > reports/host-diagnostics.json
```

## Detection semantics
- Rosetta `verified`: a real x86_64 macOS process executed successfully.
- Runtime `detected_unverified`: an app bundle or executable was found; no game launch was attempted.
- Runtime `not_detected`: no supported known location/command was found. This does not prove that no custom installation exists.
- Metal GPU information comes from `MTLCreateSystemDefaultDevice()`.
- GPU recommended working-set size is a Metal recommendation, not a guarantee of memory available to a game.

## Limitations
- GPTK installations are not standardized; command discovery is best-effort.
- Wine can be installed inside app bundles or custom prefixes and may not appear on PATH.
- CrossOver detection checks conventional application bundle locations.
- No system configuration is changed and no runtime is installed.
