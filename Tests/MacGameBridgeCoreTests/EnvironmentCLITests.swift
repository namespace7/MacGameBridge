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
    #expect(output.contains("metadata only"))
}
