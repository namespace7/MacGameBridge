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

## Environment metadata layer (M3)
Environments are persistent metadata records, not provisioned prefixes:
- `GameEnvironment` references a game profile, an optional discovered runtime
  installation, and an intended absolute prefix URL.
- `EnvironmentRepository` stores records in an injectable JSON file and uses
  atomic writes, stable serialization, and duplicate-ID protection.
- `EnvironmentValidator` is read-only and reports reference/path problems.
  A `planned` record is not a prefix, and directory presence is not evidence of
  Wine prefix initialization.
- The `environments` CLI creates metadata only. It never creates a prefix,
  invokes a runtime, launches a game, or changes lifecycle state to provisioned.

Existing discovery, provider scanning, and deterministic selection capabilities
remain unchanged and are reused only as read-only sources for validation.

## Runtime adapters and exact pinning (M3.1)

Runtime adapters are the boundary between provider discoveries and environment
metadata:

- `RuntimeAdapter` exposes the supported provider ID, declared capabilities,
  and read-only validation of one `ProviderInstallation` against injected
  `HostCapabilities`.
- `RuntimeAdapterRegistry` resolves an adapter by provider ID. Providers without
  an implementation return an explicit unsupported-provider error; discovery of
  a CrossOver, Whisky, or Sikarugir installation does not imply adapter support.
- `WineRuntimeAdapter` is the only M3.1 adapter. It accepts the standalone Wine
  shape produced by `RuntimeScanner` and reuses `ArchitectureCompatibility`.
- `RuntimePinningService` requires an exact match with a discovered
  `ProviderInstallation.id`, applies the existing exact-installation selection
  policy with fallback disabled, calls the registered adapter, and asks the
  repository for a conditional update. It never chooses a "better" runtime.
- `EnvironmentCLI` only parses options and renders results. Provider decisions
  stay in adapters and the pinning service, so future provisioning and launch
  operations can be added behind the same contract.

Validation and pinning remain read-only with respect to runtimes and prefixes:
no binary is executed, no prefix is created or modified, and lifecycle state is
never promoted to `provisioned`. See `docs/M3.1-RUNTIME-ADAPTERS.md`.
