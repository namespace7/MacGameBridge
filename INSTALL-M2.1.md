# Apply the MacGameBridge M2.1 patch

This is an overlay patch for the repository after commit `f6b5157` (`feat: add hardware intelligence diagnostics`). It does not replace the repository and does not change `Package.swift`.

## 1. Confirm the M1 checkpoint

From the repository root:

```bash
git status
```

The working tree should be clean and the latest commit should be `f6b5157`.

## 2. Extract the patch

Download `MacGameBridge-M2.1-patch.zip` into `~/Downloads`, then run:

```bash
cd /Users/yashwant/Documents/projects/MacGameBridge
unzip -o ~/Downloads/MacGameBridge-M2.1-patch.zip -d .
```

This adds the runtime discovery implementation, CLI command, tests, documentation, and a read-only OpenCode reviewer agent. It updates the existing `Diagnostics.swift` and `main.swift`.

## 3. Build and test

```bash
swift package clean
swift build
swift test \
  -Xswiftc -plugin-path \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

The explicit plugin path is currently required by this developer environment for Swift Testing macro discovery.

## 4. Exercise the new commands

```bash
swift run macgamebridge runtimes
swift run macgamebridge runtimes --json
swift run macgamebridge diagnostics
```

Runtime discovery is read-only. It inspects known app bundle directories and executable search paths. It does not run Wine, CrossOver, Game Porting Toolkit, or any game.

## 5. Review and commit only after local verification

```bash
git diff --check
git status --short
git diff --stat
```

Inspect the diff before staging. Suggested commit:

```bash
git add Sources/MacGameBridgeCore Sources/MacGameBridgeCLI Tests docs .opencode
git commit -m "feat: add runtime discovery"
```

Do not commit host-specific runtime JSON reports.
