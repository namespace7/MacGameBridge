# M3 — Isolated game environments (metadata MVP)

## Goal

Make environments a first-class, persistent concept without pretending that an
environment is ready. This milestone records *intent* only: which game, which
intended prefix, and optionally which already-discovered runtime installation.

No prefix is created, no Wine command is run, and no game is launched.

## Model

`GameEnvironment` is provider-independent:

| Field | Meaning |
|---|---|
| `id` | Stable environment identifier; generated when the record is created |
| `gameProfileID` | References `GameProfile.id` from `database/games.json` |
| `runtimeInstallationID` | Optional reference to `ProviderInstallation.id` |
| `name` | Display name |
| `prefixURL` | Absolute, intended prefix file URL; metadata only |
| `lifecycleState` | `planned` or `provisioned` |
| `createdAt`, `updatedAt` | Creation and last-update timestamps |

`planned` means metadata exists. `provisioned` is reserved for a future step
with genuine successful provisioning evidence; this MVP never creates or
promotes a record to that state. Validation explicitly rejects a `provisioned`
record because no evidence model exists yet.

## Registry

Default location:

```
~/Library/Application Support/MacGameBridge/environments.json
```

The storage URL is injectable via `EnvironmentRepository(storageURL:)`, which
allows isolated temporary-directory tests. The file shape is:

```json
{
  "environments": [
    {
      "createdAt": "2023-11-14T22:13:20Z",
      "gameProfileID": "pes-2021",
      "id": "env-...",
      "lifecycleState": "planned",
      "name": "PES 2021 offline",
      "prefixURL": "file:///Users/me/Games/prefixes/pes-2021",
      "runtimeInstallationID": null,
      "updatedAt": "2023-11-14T22:13:20Z"
    }
  ],
  "schemaVersion": "1.0"
}
```

Properties:

- JSONEncoder uses sorted keys and ISO-8601 dates for stable serialization.
- Writes use Foundation's atomic data write; readers never see a partial file.
- Duplicate IDs are rejected; a missing file is an empty registry.
- `create` requires `prefixURL` to be a local filesystem URL, then applies the
  lexical `EnvironmentPrefixPolicy` to its path, so direct API callers cannot
  persist non-file, relative, empty, malformed, root, home, traversal, or
  app-bundle prefixes. No symlinks are resolved and no directory is inspected
  or created.
- `create` also rejects a second record with the same `gameProfileID` and
  normalized `prefixURL.path`, returning `duplicateGamePrefix`. The CLI maps
  that error to the existing actionable `duplicateEnvironment` message.
- Corrupt or unsupported-schema files produce an error and are never overwritten.
- No registry operation creates, modifies, or deletes a prefix, runtime, or game file.

## Validation

`EnvironmentValidator` is read-only. It reports structured issues and never
changes lifecycle state. It checks:

- the referenced game profile exists; a successfully loaded catalogue is
  authoritative even when empty, while a load failure is reported separately as
  `gameCatalogUnavailable`;
- a pinned runtime installation can be resolved;
- that installation has status `validated` before it is eligible;
- the prefix URL is a local filesystem URL; a non-file URL is reported as
  `prefix_path_invalid` without passing its path to the policy or inspecting
  the filesystem;
- the prefix path is absolute, normalized, non-reserved, and not inside an app bundle;
- a path collision with a regular file is an error.

An existing directory at the prefix path is only informational. The report always
states `prefixInitializationStatus: "not_initialized"` and `readyToLaunch: false`.
Directory presence is not Wine prefix initialization.

## CLI

```bash
macgamebridge environments list [--json]
macgamebridge environments create --game <id> --name <name> --prefix <absolute-path> [--json]
macgamebridge environments show <id> [--json]
macgamebridge environments validate <id> [--json]
macgamebridge environments help
```

`create` validates arguments, checks the game ID, saves metadata, and returns.
It does not scan or invoke a runtime and does not create the prefix directory.

JSON shapes added by this milestone:

- `list --json`: `{ "schemaVersion": "1.0", "environments": [...] }`
- `show --json` and `create --json`: one `GameEnvironment` object
- `validate --json`: one `EnvironmentValidationReport` object

Existing `diagnostics`, `runtimes`, and `games` commands and their JSON contracts
are unchanged.

## Files

| File | Purpose |
|---|---|
| `Sources/MacGameBridgeCore/Environment/GameEnvironment.swift` | Environment model and lifecycle states |
| `Sources/MacGameBridgeCore/Environment/EnvironmentRepository.swift` | JSON persistence and duplicate protection |
| `Sources/MacGameBridgeCore/Environment/EnvironmentPrefixPolicy.swift` | Lexical prefix-path safety checks |
| `Sources/MacGameBridgeCore/Environment/GameProfileCatalog.swift` | Read-only game catalog loading |
| `Sources/MacGameBridgeCore/Environment/EnvironmentValidator.swift` | Read-only validation report |
| `Sources/MacGameBridgeCore/Environment/EnvironmentCLI.swift` | Testable CLI parser and runner |
| `Sources/MacGameBridgeCLI/main.swift` | Production command wiring |

## Tests

```bash
swift build
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
git diff --check
```

Tests use Swift Testing, injected storage URLs, fixture profiles, and fixture
runtime installations. They never depend on real runtimes being installed.

## Limitations

- No provisioning, prefix initialization, or launch support.
- No runtime pinning command; CLI-created records always have a nil runtime ID.
- No per-game logs or compatibility evidence records.
- No cross-process file locking; atomic writes prevent partial files but do not
  merge simultaneous writes from separate processes.
- Prefix path validation is lexical and deliberately does not resolve symlinks.
