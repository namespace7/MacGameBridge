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
- FIFA / EA SPORTS FC (exact editions pending)
- eFootball PES 2021
- Need for Speed: Most Wanted (confirm 2005 vs 2012)
- GTA (GTA V Legacy is provisional from prior planning; confirm edition)
