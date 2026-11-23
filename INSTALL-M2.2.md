# Apply the MacGameBridge M2.2 patch

This patch adds the Runtime Provider Architecture on top of the M2.1 base.

## Prerequisites

- M2.1 (runtime discovery) already applied and committed.
- Swift 6.0+ toolchain.
- macOS 14+ (Sonoma or later).

## 1. Confirm M2.1 is present

From the repository root, these files should exist:

- `Sources/MacGameBridgeCore/RuntimeModels.swift`
- `Sources/MacGameBridgeCore/RuntimeDiscovery.swift`
- `Tests/MacGameBridgeCoreTests/RuntimeDiscoveryTests.swift`

## 2. Extract the patch

```bash
cd /Users/yashwant/Documents/projects/MacGameBridge
# Copy or extract the patch files here
```

## 3. Build and test

```bash
swift package clean
swift build
swift test \
  -Xswiftc -plugin-path \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

Expect **26 tests** passing (8 existing M1/M2.1 tests + 18 new M2.2 tests).

## 4. Exercise the new CLI commands

```bash
swift run macgamebridge runtimes --providers
swift run macgamebridge runtimes --providers --json
```

Runtime discovery remains read-only. No runtime is launched or modified.

## 5. Review and commit only after local verification

```bash
git diff --check
git status --short
git diff --stat
```

Suggested commit:

```bash
git add Sources/MacGameBridgeCore/Runtime/ \
       Sources/MacGameBridgeCLI/main.swift \
       Tests/MacGameBridgeCoreTests/RuntimeScannerTests.swift \
       docs/M2.2-RUNTIME-PROVIDERS.md \
       INSTALL-M2.2.md
git commit -m "feat: add runtime provider architecture"
```

Do not commit host-specific runtime JSON reports.