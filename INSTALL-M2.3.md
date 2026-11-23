# M2.3 — Runtime Selection Engine Installation

## Prerequisites

- M2.2 (Runtime Providers) must be complete and merged.
- Xcode 16+ or Swift 6.0+ toolchain.
- The `feat/m2.3-runtime-selection-engine` branch checked out.

## Files

| File | Purpose |
|------|---------|
| `Sources/MacGameBridgeCore/Runtime/RuntimeSelector.swift` | Selection engine and all models |
| `Tests/MacGameBridgeCoreTests/RuntimeSelectorTests.swift` | 42 Swift Testing tests: 36 original M2.3 tests + 6 regression tests added during independent review (automatic lower-ranked evaluation; preferred-provider no-fallback Rosetta rejection; preferred-provider fallback-allowed-but-no-eligible-candidate rejection; exact-installation missing-ID rejection; input-order independence with case/numeric IDs; locale-independent tie-break ordering) |
| `docs/M2.3-RUNTIME-SELECTION.md` | Architecture documentation |
| `INSTALL-M2.3.md` | This file |

## Verification

```bash
# Build
swift build

# Run all tests (including existing M2.1 and M2.2 tests)
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing

# Check for whitespace issues
git diff --check
```

Expected result: **72 tests pass** across the full project (RuntimeDiscoveryTests: 7, RuntimeScannerTests: 22, DiagnosticReportTests: 1, RuntimeSelectorTests: 42 — of which 66 are pre-existing M1/M2.1/M2.2/M2.3 tests and 6 are regression tests added during independent review of M2.3).

## Programmatic usage

```swift
import MacGameBridgeCore

// Discover installations
let installations = RuntimeScanner.scan(paths: .current).installations

// Build a request — Rosetta must be confirmed, never assumed.
// On Apple Silicon, use the factory method with the actual, already-verified
// Rosetta availability for this host (e.g. from a prior `sysctl.proc_translated`
// or `pgrep oahd` check) — never hardcode `true`.
let rosettaAvailable = currentHostHasRosettaInstalled() // caller-supplied verification
let request = RuntimeSelector.appleSiliconRequest(rosettaAvailable: rosettaAvailable)

// Automatic selection
let result = RuntimeSelector.select(
    from: installations,
    request: request
)
print("Selected: \(result.selected?.id ?? "none")")
print("Reason: \(result.selectionReason)")

// Preference-based selection
let prefResult = RuntimeSelector.select(
    from: installations,
    policy: .preferProvider(.crossover),
    request: request
)

// Exact installation (never falls back)
let exactResult = RuntimeSelector.select(
    from: installations,
    policy: .exactInstallation("crossover:/Applications/CrossOver.app"),
    request: request
)
if exactResult.selected == nil {
    print("Exact pin failed: \(exactResult.failure?.description ?? "unknown")")
}

// On Intel Macs
let intelResult = RuntimeSelector.select(
    from: installations,
    request: .intelRequest
)
```

## Key API changes from previous M2.3 version

| Previous | New | Reason |
|----------|-----|--------|
| `CandidateEvaluation` | `RuntimeCandidateEvaluation` | Consistent naming |
| `selectionReason` only | `failure: RuntimeSelectionRejection?` | Structured failure over string parsing |
| Hardcoded host/Rosetta | `RuntimeSelectionRequest` (required, no default) | Pure, testable architecture evaluation |
| `defaultAppleSiliconRequest` with `rosettaAvailable: true` | `appleSiliconRequest(rosettaAvailable:)` — caller provides Rosetta status | Never silently assume Rosetta is available |
| `detected` accepted | Only `validated` accepted | Safety: don't select unvalidated runtimes |
| Unconditional fallback | `allowFallback` flag | Explicit fallback control |
| Unknown host not handled | `hostArchitecture == .unknown` rejects all candidates | Safety: no positive compatibility on unknown host |

## Rollback

```bash
git checkout main
git branch -D feat/m2.3-runtime-selection-engine
```

## Changes from M2.2

| Aspect | M2.2 | M2.3 |
|--------|------|------|
| Feature | Runtime discovery & validation | Runtime selection |
| Main type | `RuntimeScanner` | `RuntimeSelector` |
| New models | `ProviderInstallation`, `RuntimeInstallationStatus` | `RuntimeSelectionPolicy`, `RuntimeSelectionRequest`, `RuntimeSelectionResult`, `RuntimeCandidateEvaluation`, `RuntimeSelectionRejection`, `ArchitectureCompatibility` |
| Dependencies | `RuntimeDiscovery`, `RuntimeValidator` | Only M2.2 types |
| CLI command | `runtimes` (scan) | None (programmatic API) |