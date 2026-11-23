import Foundation
import Testing

@testable import MacGameBridgeCore

private struct ListJSONResponse: Decodable {
    let schemaVersion: String
    let environments: [GameEnvironment]
}

@Test
func parsesEnvironmentCommands() throws {
    let list = try EnvironmentCLI.parse(["list"])
    let listJSON = try EnvironmentCLI.parse(["list", "--json"])
    let create = try EnvironmentCLI.parse([
        "create", "--game", "pes-2021", "--name", "PES", "--prefix", "/tmp/p"
    ])
    let createReordered = try EnvironmentCLI.parse([
        "create", "--prefix", "/tmp/p", "--name", "PES", "--game", "pes-2021", "--json"
    ])
    let show = try EnvironmentCLI.parse(["show", "env-1"])
    let validate = try EnvironmentCLI.parse(["validate", "env-1", "--json"])
    let help = try EnvironmentCLI.parse(["help"])

    #expect(list == .list(asJSON: false))
    #expect(listJSON == .list(asJSON: true))
    #expect(create == .create(gameID: "pes-2021", name: "PES", prefixPath: "/tmp/p", asJSON: false))
    #expect(createReordered == .create(gameID: "pes-2021", name: "PES", prefixPath: "/tmp/p", asJSON: true))
    #expect(show == .show(id: "env-1", asJSON: false))
    #expect(validate == .validate(id: "env-1", asJSON: true))
    #expect(help == .help)
}

@Test
func cliArgumentValidationIsActionable() {
    assertEnvironmentCLIError(.missingSubcommand) {
        _ = try EnvironmentCLI.parse([])
    }
    assertEnvironmentCLIError(.unknownSubcommand("launch")) {
        _ = try EnvironmentCLI.parse(["launch"])
    }
    assertEnvironmentCLIError(.missingOption("--game")) {
        _ = try EnvironmentCLI.parse(["create", "--name", "PES", "--prefix", "/tmp/p"])
    }
    assertEnvironmentCLIError(.missingOption("--game")) {
        _ = try EnvironmentCLI.parse(["create", "--game", "--name", "PES", "--prefix", "/tmp/p"])
    }
    assertEnvironmentCLIError(.missingOption("--name")) {
        _ = try EnvironmentCLI.parse(["create", "--game", "pes-2021", "--prefix", "/tmp/p"])
    }
    assertEnvironmentCLIError(.missingOption("--prefix")) {
        _ = try EnvironmentCLI.parse(["create", "--game", "pes-2021", "--name", "PES"])
    }
    assertEnvironmentCLIError(.invalidOptionValue("--game", "specified more than once")) {
        _ = try EnvironmentCLI.parse([
            "create", "--game", "pes-2021", "--name", "PES", "--prefix", "/tmp/p", "--game", "gta"
        ])
    }
    assertEnvironmentCLIError(.unknownOption("--force")) {
        _ = try EnvironmentCLI.parse(["list", "--force"])
    }
    assertEnvironmentCLIError(.unexpectedArgument("env-2")) {
        _ = try EnvironmentCLI.parse(["show", "env-1", "env-2"])
    }
    assertEnvironmentCLIError(.missingOption("<id>")) {
        _ = try EnvironmentCLI.parse(["validate"])
    }

    #expect(EnvironmentCLIError.missingOption("--game").description.contains("--game"))
    #expect(EnvironmentCLIError.unknownSubcommand("launch").description.contains("Usage"))
}

@Test
func createSavesMetadataOnlyAndDoesNotTouchRuntimesOrPrefix() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(
            storageURL: root.appendingPathComponent("environments.json")
        )
        let prefixPath = root.appendingPathComponent("prefix").path
        var runtimeLookupCalls = 0
        let services = EnvironmentCLIServices(
            repository: repository,
            loadGameProfiles: { [EnvironmentTestFixtures.profile()] },
            runtimeInstallations: {
                runtimeLookupCalls += 1
                return []
            },
            now: { EnvironmentTestFixtures.fixedDate },
            makeEnvironmentID: { "env-test-1" }
        )

        let output = try EnvironmentCLI.run(
            ["create", "--game", "pes-2021", "--name", "PES", "--prefix", prefixPath],
            services: services
        )

        #expect(output.contains("Created planned environment env-test-1"))
        #expect(output.contains("no directory was created"))
        #expect(!FileManager.default.fileExists(atPath: prefixPath))
        #expect(runtimeLookupCalls == 0)

        let fetched = try repository.get(id: "env-test-1")
        let stored = try #require(fetched)
        #expect(stored.lifecycleState == .planned)
        #expect(stored.runtimeInstallationID == nil)
        #expect(stored.prefixPath == prefixPath)
        #expect(stored.createdAt == EnvironmentTestFixtures.fixedDate)
        #expect(stored.updatedAt == EnvironmentTestFixtures.fixedDate)
    }
}

@Test
func createRejectsUnknownGameIDWithKnownIDs() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(
            storageURL: root.appendingPathComponent("environments.json")
        )
        let services = EnvironmentTestFixtures.services(repository: repository)

        assertEnvironmentCLIError(.invalidGameID("nope", ["pes-2021"])) {
            _ = try EnvironmentCLI.run(
                ["create", "--game", "nope", "--name", "PES", "--prefix", "\(root.path)/prefix"],
                services: services
            )
        }
        #expect(!FileManager.default.fileExists(atPath: repository.storageURL.path))
    }
}

@Test
func createRejectsUnsafePrefixPath() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(
            storageURL: root.appendingPathComponent("environments.json")
        )
        let services = EnvironmentTestFixtures.services(repository: repository)

        do {
            _ = try EnvironmentCLI.run(
                ["create", "--game", "pes-2021", "--name", "PES", "--prefix", "relative/prefix"],
                services: services
            )
            Issue.record("Expected invalid prefix error")
        } catch let error as EnvironmentCLIError {
            if case .invalidPrefix = error {
                #expect(error.description.contains("not absolute"))
                #expect(error.description.contains("No directory was created"))
            } else {
                Issue.record("Unexpected CLI error: \(error)")
            }
        }
        #expect(!FileManager.default.fileExists(atPath: repository.storageURL.path))
    }
}

@Test
func createRejectsDuplicateEnvironmentWithExistingID() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(
            storageURL: root.appendingPathComponent("environments.json")
        )
        let services = EnvironmentTestFixtures.services(repository: repository)
        let prefixPath = root.appendingPathComponent("prefix").path
        let arguments = ["create", "--game", "pes-2021", "--name", "PES", "--prefix", prefixPath]

        _ = try EnvironmentCLI.run(arguments, services: services)

        assertEnvironmentCLIError(
            .duplicateEnvironment(
                id: "env-test-1",
                gameProfileID: "pes-2021",
                prefixPath: prefixPath
            )
        ) {
            _ = try EnvironmentCLI.run(arguments, services: services)
        }

        let listed = try repository.list()
        #expect(listed.count == 1)
    }
}

@Test
func repositoryDuplicateGamePrefixMapsToActionableCLIError() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let storageURL = root.appendingPathComponent("environments.json")
        let normalizedPrefixPath = "/tmp/mgb-prefixes/pes"
        let legacy = GameEnvironment(
            id: "env-legacy",
            gameProfileID: "pes-2021",
            name: "Legacy prefix record",
            prefixURL: URL(fileURLWithPath: "/tmp/mgb-prefixes/shared/../pes"),
            createdAt: EnvironmentTestFixtures.fixedDate,
            updatedAt: EnvironmentTestFixtures.fixedDate
        )
        try EnvironmentTestFixtures.writeRegistry(at: storageURL, environments: [legacy])
        let originalData = try Data(contentsOf: storageURL)
        let services = EnvironmentTestFixtures.services(
            repository: EnvironmentRepository(storageURL: storageURL)
        )

        assertEnvironmentCLIError(
            .duplicateEnvironment(
                id: "env-legacy",
                gameProfileID: "pes-2021",
                prefixPath: normalizedPrefixPath
            )
        ) {
            _ = try EnvironmentCLI.run(
                [
                    "create", "--game", "pes-2021", "--name", "New PES",
                    "--prefix", normalizedPrefixPath
                ],
                services: services
            )
        }

        let after = try Data(contentsOf: storageURL)
        #expect(after == originalData)
    }
}

@Test
func listAndShowSupportJSONAndMissingRecords() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(
            storageURL: root.appendingPathComponent("environments.json")
        )
        let environment = EnvironmentTestFixtures.environment(
            id: "env-json",
            prefixPath: root.appendingPathComponent("prefix").path
        )
        try repository.create(environment)
        let services = EnvironmentTestFixtures.services(repository: repository)

        let emptyOutput = try EnvironmentCLI.run(
            ["list", "--json"],
            services: EnvironmentTestFixtures.services(
                repository: EnvironmentRepository(
                    storageURL: root.appendingPathComponent("empty.json")
                )
            )
        )
        let empty = try EnvironmentTestFixtures.decoder().decode(ListJSONResponse.self, from: Data(emptyOutput.utf8))
        #expect(empty.schemaVersion == "1.0")
        #expect(empty.environments.isEmpty)

        let listOutput = try EnvironmentCLI.run(["list", "--json"], services: services)
        let list = try EnvironmentTestFixtures.decoder().decode(ListJSONResponse.self, from: Data(listOutput.utf8))
        #expect(list.environments == [environment])

        let showOutput = try EnvironmentCLI.run(["show", "env-json", "--json"], services: services)
        let shown = try EnvironmentTestFixtures.decoder().decode(
            GameEnvironment.self, from: Data(showOutput.utf8)
        )
        #expect(shown == environment)

        assertEnvironmentCLIError(.environmentNotFound("missing")) {
            _ = try EnvironmentCLI.run(["show", "missing"], services: services)
        }
        #expect(EnvironmentCLIError.environmentNotFound("missing").description.contains("environments list"))
    }
}

@Test
func validateCommandReportsUnvalidatedRuntimeAndNeverPromotesState() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(
            storageURL: root.appendingPathComponent("environments.json")
        )
        let prefixPath = root.appendingPathComponent("prefix").path
        let environment = EnvironmentTestFixtures.environment(
            id: "env-validate",
            runtimeInstallationID: "wine:/usr/local/bin/wine64",
            prefixPath: prefixPath
        )
        try repository.create(environment)

        let detected = EnvironmentTestFixtures.installation(
            id: "wine:/usr/local/bin/wine64",
            status: .detected
        )
        let services = EnvironmentTestFixtures.services(
            repository: repository,
            installations: [detected]
        )

        let output = try EnvironmentCLI.run(["validate", "env-validate"], services: services)
        #expect(output.contains("Metadata valid: no"))
        #expect(output.contains("runtime_installation_unvalidated"))
        #expect(output.contains("not_initialized"))
        #expect(output.contains("Ready to launch: no"))

        let jsonOutput = try EnvironmentCLI.run(["validate", "env-validate", "--json"], services: services)
        let report = try EnvironmentTestFixtures.decoder().decode(
            EnvironmentValidationReport.self, from: Data(jsonOutput.utf8)
        )
        #expect(!report.isValid)
        #expect(report.environmentID == "env-validate")
        #expect(report.prefixInitializationStatus == .notInitialized)

        let fetched = try repository.get(id: "env-validate")
        let stored = try #require(fetched)
        #expect(stored == environment)
        #expect(!FileManager.default.fileExists(atPath: prefixPath))
    }
}

@Test
func helpDescribesMetadataOnlyCommands() throws {
    let output = try EnvironmentCLI.run(["help"], services: .production)
    #expect(output.contains("environments list"))
    #expect(output.contains("environments create"))
    #expect(output.contains("environments validate"))
    #expect(output.contains("environments pin-runtime"))
    #expect(output.contains("environments unpin-runtime"))
    #expect(output.contains("metadata only"))
}

// MARK: - Exact runtime pinning CLI (M3.1)

@Test
func parsesPinAndUnpinCommands() throws {
    let pin = try EnvironmentCLI.parse([
        "pin-runtime", "env-1", "--runtime", "wine:/opt/wine/bin/wine64", "--json"
    ])
    let pinWithReplace = try EnvironmentCLI.parse([
        "pin-runtime", "--replace", "--runtime", "wine:/opt/wine/bin/wine64", "env-1"
    ])
    let unpin = try EnvironmentCLI.parse(["unpin-runtime", "env-1", "--json"])

    #expect(
        pin == .pinRuntime(
            id: "env-1",
            runtimeID: "wine:/opt/wine/bin/wine64",
            replace: false,
            asJSON: true
        )
    )
    #expect(
        pinWithReplace == .pinRuntime(
            id: "env-1",
            runtimeID: "wine:/opt/wine/bin/wine64",
            replace: true,
            asJSON: false
        )
    )
    #expect(unpin == .unpinRuntime(id: "env-1", asJSON: true))
}

@Test
func pinAndUnpinArgumentValidationIsActionable() {
    assertEnvironmentCLIError(.missingOption("--runtime")) {
        _ = try EnvironmentCLI.parse(["pin-runtime", "env-1"])
    }
    assertEnvironmentCLIError(.missingOption("<id>")) {
        _ = try EnvironmentCLI.parse(["pin-runtime", "--runtime", "wine:/wine"])
    }
    assertEnvironmentCLIError(.invalidOptionValue("--runtime", "specified more than once")) {
        _ = try EnvironmentCLI.parse([
            "pin-runtime", "env-1", "--runtime", "wine:/a", "--runtime", "wine:/b"
        ])
    }
    assertEnvironmentCLIError(.unknownOption("--force")) {
        _ = try EnvironmentCLI.parse([
            "pin-runtime", "env-1", "--runtime", "wine:/a", "--force"
        ])
    }
    assertEnvironmentCLIError(.unknownOption("--replace")) {
        _ = try EnvironmentCLI.parse(["unpin-runtime", "env-1", "--replace"])
    }
    #expect(EnvironmentCLIError.runtimeNotFound("wine:/x").description.contains("No substitute"))
    #expect(EnvironmentCLIError.unsupportedRuntimeProvider("crossover").description.contains("M3.1"))
}

@Test
func pinRuntimeCommandSupportsJSONAndHumanReadableOutput() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(
            storageURL: root.appendingPathComponent("environments.json")
        )
        let original = EnvironmentTestFixtures.environment(
            id: "env-pin-cli",
            prefixPath: root.appendingPathComponent("prefix").path
        )
        try repository.create(original)
        let installation = EnvironmentTestFixtures.installation(
            id: "wine:/opt/wine/bin/wine64",
            path: "/opt/wine/bin/wine64"
        )
        let services = EnvironmentTestFixtures.services(
            repository: repository,
            installations: [installation],
            now: { Date(timeIntervalSince1970: 1_700_003_600) }
        )

        let jsonOutput = try EnvironmentCLI.run(
            ["pin-runtime", original.id, "--runtime", installation.id, "--json"],
            services: services
        )
        let pinned = try EnvironmentTestFixtures.decoder().decode(
            GameEnvironment.self, from: Data(jsonOutput.utf8)
        )
        #expect(pinned.runtimeInstallationID == installation.id)
        #expect(pinned.updatedAt == Date(timeIntervalSince1970: 1_700_003_600))
        #expect(pinned.createdAt == original.createdAt)

        let humanOutput = try EnvironmentCLI.execute(
            .pinRuntime(id: original.id, runtimeID: installation.id, replace: true, asJSON: false),
            services: services
        )
        #expect(humanOutput.contains("Pinned exact runtime \(installation.id)"))
        #expect(humanOutput.contains("metadata only"))
        #expect(humanOutput.contains("no directory was created"))
        #expect(!FileManager.default.fileExists(atPath: original.prefixPath))
    }
}

@Test
func unpinRuntimeCommandSupportsJSONAndHumanReadableOutput() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(
            storageURL: root.appendingPathComponent("environments.json")
        )
        let jsonEnvironment = EnvironmentTestFixtures.environment(
            id: "env-unpin-cli-json",
            runtimeInstallationID: "wine:/opt/wine/bin/wine64",
            prefixPath: root.appendingPathComponent("prefix-json").path
        )
        let humanEnvironment = EnvironmentTestFixtures.environment(
            id: "env-unpin-cli-human",
            runtimeInstallationID: "wine:/opt/wine/bin/wine64",
            prefixPath: root.appendingPathComponent("prefix-human").path
        )
        try repository.create(jsonEnvironment)
        try repository.create(humanEnvironment)
        let original = jsonEnvironment
        let services = EnvironmentTestFixtures.services(
            repository: repository,
            now: { Date(timeIntervalSince1970: 1_700_003_600) }
        )

        let jsonOutput = try EnvironmentCLI.run(
            ["unpin-runtime", original.id, "--json"],
            services: services
        )
        let unpinned = try EnvironmentTestFixtures.decoder().decode(
            GameEnvironment.self, from: Data(jsonOutput.utf8)
        )
        #expect(unpinned.runtimeInstallationID == nil)
        #expect(unpinned.id == original.id)
        #expect(unpinned.gameProfileID == original.gameProfileID)
        #expect(unpinned.prefixURL == original.prefixURL)
        #expect(unpinned.createdAt == original.createdAt)
        #expect(unpinned.lifecycleState == original.lifecycleState)
        #expect(unpinned.updatedAt == Date(timeIntervalSince1970: 1_700_003_600))

        let humanOutput = try EnvironmentCLI.run(["unpin-runtime", humanEnvironment.id], services: services)
        #expect(humanOutput.contains("Removed the runtime pin"))
        #expect(humanOutput.contains("Runtime: not pinned"))
        #expect(humanOutput.contains("No runtime or prefix was modified"))
    }
}

@Test
func pinRuntimeCLIRequiresReplaceForDifferentPin() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(
            storageURL: root.appendingPathComponent("environments.json")
        )
        let original = EnvironmentTestFixtures.environment(
            id: "env-replace-cli",
            prefixPath: root.appendingPathComponent("prefix").path
        )
        try repository.create(original)
        let first = EnvironmentTestFixtures.installation(
            id: "wine:/opt/wine-a/bin/wine64",
            path: "/opt/wine-a/bin/wine64"
        )
        let second = EnvironmentTestFixtures.installation(
            id: "wine:/opt/wine-b/bin/wine64",
            path: "/opt/wine-b/bin/wine64"
        )
        let services = EnvironmentTestFixtures.services(
            repository: repository,
            installations: [first, second]
        )

        _ = try EnvironmentCLI.run(
            ["pin-runtime", original.id, "--runtime", first.id],
            services: services
        )
        let before = try Data(contentsOf: repository.storageURL)

        assertEnvironmentCLIError(
            .replacementRequiresReplace(currentID: first.id, requestedID: second.id)
        ) {
            _ = try EnvironmentCLI.run(
                ["pin-runtime", original.id, "--runtime", second.id],
                services: services
            )
        }
        let afterRejected = try Data(contentsOf: repository.storageURL)
        #expect(afterRejected == before)

        let replaced = try EnvironmentCLI.run(
            ["pin-runtime", original.id, "--runtime", second.id, "--replace"],
            services: services
        )
        #expect(replaced.contains(second.id))
        let stored = try repository.get(id: original.id)
        #expect(stored?.runtimeInstallationID == second.id)
    }
}

@Test
func pinRuntimeCLIMapsUnsafeInstallationsToActionableErrors() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(
            storageURL: root.appendingPathComponent("environments.json")
        )
        let original = EnvironmentTestFixtures.environment(
            id: "env-errors-cli",
            prefixPath: root.appendingPathComponent("prefix").path
        )
        try repository.create(original)
        let valid = EnvironmentTestFixtures.installation(
            id: "wine:/opt/wine/bin/wine64",
            path: "/opt/wine/bin/wine64"
        )
        let detected = EnvironmentTestFixtures.installation(
            id: "wine:/opt/wine-detected/bin/wine64",
            status: .detected,
            path: "/opt/wine-detected/bin/wine64"
        )
        let x8664 = EnvironmentTestFixtures.installation(
            id: "wine:/opt/wine-x86/bin/wine",
            architecture: .x8664,
            path: "/opt/wine-x86/bin/wine"
        )
        let crossover = EnvironmentTestFixtures.installation(
            id: "crossover:/Applications/CrossOver.app",
            provider: .crossover,
            bundleURL: URL(fileURLWithPath: "/Applications/CrossOver.app")
        )
        let installations = [valid, detected, x8664, crossover]
        let noRosetta = EnvironmentTestFixtures.host(rosetta: .notVerified)
        let services = EnvironmentTestFixtures.services(
            repository: repository,
            installations: installations,
            host: noRosetta
        )
        let before = try Data(contentsOf: repository.storageURL)

        assertEnvironmentCLIError(.runtimeNotFound("wine:/missing")) {
            _ = try EnvironmentCLI.run(
                ["pin-runtime", original.id, "--runtime", "wine:/missing"],
                services: services
            )
        }
        assertEnvironmentCLIError(.unvalidatedRuntime(detected.id)) {
            _ = try EnvironmentCLI.run(
                ["pin-runtime", original.id, "--runtime", detected.id],
                services: services
            )
        }
        assertEnvironmentCLIError(.incompatibleRuntime(x8664.id, "x86_64 runtime requires Rosetta 2, which is not available")) {
            _ = try EnvironmentCLI.run(
                ["pin-runtime", original.id, "--runtime", x8664.id],
                services: services
            )
        }
        assertEnvironmentCLIError(.unsupportedRuntimeProvider("crossover")) {
            _ = try EnvironmentCLI.run(
                ["pin-runtime", original.id, "--runtime", crossover.id],
                services: services
            )
        }

        let after = try Data(contentsOf: repository.storageURL)
        #expect(after == before)
    }
}
