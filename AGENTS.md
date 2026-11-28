# MacGameBridge — AI Engineering Instructions

## Mission
Build an independent, open-source macOS application that manages and diagnoses
legitimate Windows-game compatibility environments on Apple Silicon.

## Non-negotiable rules
- Do not copy proprietary CrossOver source, branding, assets, or private implementation.
- Integrate third-party projects only in accordance with their licenses.
- Never bypass DRM, anti-cheat, licensing, or publisher security controls.
- Do not claim a game works without a reproducible test and recorded environment.
- Separate offline/story-mode results from online/multiplayer results.
- Never install software, modify system settings, or delete user data without explicit approval.
- Do not download game executables or copyrighted game assets.
- Prefer small, testable changes and explain commands before running them.

## Architecture
- Native macOS-facing application: Swift / SwiftUI (UI comes later).
- Initial milestone: Swift command-line host diagnostics and game catalog.
- Compatibility runtimes remain external and independently versioned.
- Keep game profiles as data, not hard-coded conditionals.
- Record macOS build, hardware, runtime versions, graphics backend, game edition,
  launch result, offline result, online result, and evidence for every test.

## Engineering workflow
1. Inspect the existing repository before changing it.
2. Explain the intended change and files affected.
3. Implement the smallest useful increment.
4. Build and run relevant tests.
5. Report exact commands, results, limitations, and next steps.
6. Do not invent benchmark numbers or compatibility claims.

## Current scope
- Game A (exact editions pending)
- Game B
- Game C (confirm intended edition and release year)
- Game D (edition provisional from prior planning; confirm edition)

## Current implementation guidance
- M1 hardware intelligence is committed; preserve the `DiagnosticReport` M1 JSON shape unless a deliberate schema-version change is documented.
- M2.1 runtime discovery is read-only. It may inspect known `.app` bundle directories, `Info.plist`, executable permissions, PATH directories, and symlink destinations.
- Do not execute Wine, CrossOver, Game Porting Toolkit, or game binaries during discovery.
- Do not recursively scan the entire disk. Keep search roots explicit and injectable for tests.
- A detected runtime is `detected_unverified`; never describe it as launch-tested or game-compatible.
- Test discovery using temporary directories and fixture app bundles. Do not depend on a developer machine having CrossOver, Whisky, Wine, or Game Porting Toolkit installed.
- On the current developer Mac, run tests with the Testing macro plugin explicitly supplied:
  `swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`
- OpenCode should use the repository's `AGENTS.md`, propose bounded changes, ask before shell commands, and never commit or push without explicit human approval.
