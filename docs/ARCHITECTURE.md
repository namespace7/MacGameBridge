# MacGameBridge Architecture

## Goal
An independent open-source macOS compatibility manager for legitimate Windows games
on Apple Silicon. MacGameBridge orchestrates existing compatibility technologies;
it does not reimplement Windows, Wine, DirectX, or proprietary CrossOver components.

## Layers
1. Desktop UI (future): SwiftUI.
2. Application/core: game profiles, configuration, diagnostics, process lifecycle,
   compatibility reports, benchmark records.
3. Runtime adapters: Wine distributions, CrossOver (if user has a license),
   Apple Game Porting Toolkit components, and other explicitly supported runtimes.
4. Translation technologies: Rosetta 2 where supported by the selected runtime,
   D3DMetal, DXVK, MoltenVK, and related components subject to their own licenses.
5. Host: macOS, Metal, Apple Silicon hardware.

## Important boundaries
- Rosetta translates supported x86-64 macOS code; it is not a Windows API layer.
- Wine supplies Windows API compatibility; it is not a Windows kernel.
- Graphics translation does not solve kernel anti-cheat or unsupported DRM.
- Windows ARM virtualization is a separate execution strategy and should be evaluated
  independently rather than treated as a universal fallback.
- Online compatibility must be assessed separately from offline launch/gameplay.

## MVP
The first milestone is a read-only CLI:
- `diagnostics`: report host architecture, macOS version, memory, Rosetta test, disk info.
- `games`: display configured test profiles.
No runtime installation or system mutation is performed by the MVP.
