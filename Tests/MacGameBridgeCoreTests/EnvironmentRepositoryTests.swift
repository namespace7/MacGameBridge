import Foundation
import Testing

@testable import MacGameBridgeCore

private func environment(prefixURL: URL, id: String) -> GameEnvironment {
    GameEnvironment(
        id: id,
        gameProfileID: "pes-2021",
        name: "Unsafe prefix fixture",
        prefixURL: prefixURL,
        createdAt: EnvironmentTestFixtures.fixedDate,
        updatedAt: EnvironmentTestFixtures.fixedDate
    )
}

@Test
func repositoryCreatesListsAndGetsEnvironments() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let storageURL = root.appendingPathComponent("environments.json")
        let repository = EnvironmentRepository(storageURL: storageURL)
        let environment = EnvironmentTestFixtures.environment(id: "env-a")

        let initiallyListed = try repository.list()
        #expect(initiallyListed.isEmpty)
        let initiallyFetched = try repository.get(id: "env-a")
        #expect(initiallyFetched == nil)

        try repository.create(environment)

        let listed = try repository.list()
        #expect(listed == [environment])
        let fetched = try repository.get(id: "env-a")
        #expect(fetched == environment)
        let missing = try repository.get(id: "missing")
        #expect(missing == nil)
        #expect(FileManager.default.fileExists(atPath: storageURL.path))

        let data = try Data(contentsOf: storageURL)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("schemaVersion"))
        #expect(text.contains("env-a"))
    }
}

@Test
func repositoryRejectsDuplicateIDs() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(
            storageURL: root.appendingPathComponent("environments.json")
        )
        let environment = EnvironmentTestFixtures.environment(id: "env-dup")
        try repository.create(environment)

        assertRepositoryError(.duplicateID("env-dup")) {
            try repository.create(environment)
        }

        let listed = try repository.list()
        #expect(listed == [environment])
    }
}

@Test
func repositoryPreservesDataAcrossInstances() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let storageURL = root.appendingPathComponent("environments.json")
        let first = EnvironmentTestFixtures.environment(id: "env-first")
        let second = EnvironmentTestFixtures.environment(
            id: "env-second",
            gameProfileID: "gta",
            name: "GTA environment",
            prefixPath: "/tmp/mgb-prefixes/gta"
        )

        try EnvironmentRepository(storageURL: storageURL).create(first)
        try EnvironmentRepository(storageURL: storageURL).create(second)

        let reloaded = try EnvironmentRepository(storageURL: storageURL).list()
        #expect(reloaded == [first, second])
    }
}

@Test
func missingRegistryFileIsAnEmptyRegistry() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let storageURL = root.appendingPathComponent("missing-environments.json")
        let repository = EnvironmentRepository(storageURL: storageURL)

        let listed = try repository.list()
        #expect(listed.isEmpty)
        let fetched = try repository.get(id: "env-1")
        #expect(fetched == nil)
        #expect(!FileManager.default.fileExists(atPath: storageURL.path))
    }
}

@Test
func corruptedRegistryThrowsAndIsNotOverwritten() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let storageURL = root.appendingPathComponent("environments.json")
        let corrupted = Data("{ this is not JSON".utf8)
        try corrupted.write(to: storageURL)
        let repository = EnvironmentRepository(storageURL: storageURL)

        do {
            _ = try repository.list()
            Issue.record("Expected corrupted registry error")
        } catch let error as EnvironmentRepositoryError {
            if case .corruptedRegistry = error {
                // Expected.
            } else {
                Issue.record("Unexpected repository error: \(error)")
            }
        }

        do {
            try repository.create(EnvironmentTestFixtures.environment(id: "not-used"))
            Issue.record("Expected create to reject a corrupted registry")
        } catch let error as EnvironmentRepositoryError {
            if case .corruptedRegistry = error {
                // Expected.
            } else {
                Issue.record("Unexpected repository error: \(error)")
            }
        }

        let after = try Data(contentsOf: storageURL)
        #expect(after == corrupted)
    }
}

@Test
func unsupportedRegistrySchemaIsRejected() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let storageURL = root.appendingPathComponent("environments.json")
        let data = Data(#"{"schemaVersion":"99.0","environments":[]}"#.utf8)
        try data.write(to: storageURL)

        let repository = EnvironmentRepository(storageURL: storageURL)
        do {
            _ = try repository.list()
            Issue.record("Expected unsupported schema error")
        } catch let error as EnvironmentRepositoryError {
            if case .corruptedRegistry = error {
                // Expected.
            } else {
                Issue.record("Unexpected repository error: \(error)")
            }
        }
    }
}

@Test
func repositoryRejectsUnsafePrefixPathsFromDirectCallers() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let storageURL = root.appendingPathComponent("environments.json")
        let repository = EnvironmentRepository(storageURL: storageURL)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let unsafePrefixURLs = [
            URL(string: "relative/prefix"),
            URL(string: "file://"),
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: home),
            URL(fileURLWithPath: "/tmp/../etc"),
            URL(fileURLWithPath: "/Applications/Whisky.app/prefix")
        ]

        for (index, prefixURL) in unsafePrefixURLs.enumerated() {
            let unsafeURL = try #require(prefixURL)
            let candidate = environment(prefixURL: unsafeURL, id: "env-unsafe-\(index)")
            do {
                try repository.create(candidate)
                Issue.record("Expected unsafe prefix rejection for \(unsafeURL.path)")
            } catch let error as EnvironmentRepositoryError {
                if case .invalidEnvironment(let reason) = error {
                    #expect(reason.contains("prefix"))
                } else {
                    Issue.record("Unexpected repository error: \(error)")
                }
            }
        }

        #expect(!FileManager.default.fileExists(atPath: storageURL.path))
    }
}

@Test
func repositoryRejectsNonFilePrefixURL() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let storageURL = root.appendingPathComponent("environments.json")
        let repository = EnvironmentRepository(storageURL: storageURL)
        let nonFileURL = try #require(URL(string: "https://example.com/prefix"))
        let candidate = environment(prefixURL: nonFileURL, id: "env-non-file")

        do {
            try repository.create(candidate)
            Issue.record("Expected non-file prefix URL rejection")
        } catch let error as EnvironmentRepositoryError {
            if case .invalidEnvironment(let reason) = error {
                #expect(reason.contains("local filesystem URL"))
            } else {
                Issue.record("Unexpected repository error: \(error)")
            }
        }

        #expect(!FileManager.default.fileExists(atPath: storageURL.path))
    }
}

@Test
func repositoryRejectsDuplicateGameAndPrefixWithDifferentIDs() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let storageURL = root.appendingPathComponent("environments.json")
        let repository = EnvironmentRepository(storageURL: storageURL)
        let prefixPath = root.appendingPathComponent("prefix").path
        let first = EnvironmentTestFixtures.environment(
            id: "env-a",
            gameProfileID: "pes-2021",
            prefixPath: prefixPath
        )
        let second = EnvironmentTestFixtures.environment(
            id: "env-b",
            gameProfileID: "pes-2021",
            name: "Second PES environment",
            prefixPath: prefixPath
        )

        try repository.create(first)
        let before = try Data(contentsOf: storageURL)

        assertRepositoryError(
            .duplicateGamePrefix(
                id: "env-a",
                gameProfileID: "pes-2021",
                prefixPath: prefixPath
            )
        ) {
            try repository.create(second)
        }

        let after = try Data(contentsOf: storageURL)
        #expect(after == before)
        let listed = try repository.list()
        #expect(listed == [first])
    }
}

@Test
func repositoryNormalizesStoredPrefixForDuplicateDetection() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let storageURL = root.appendingPathComponent("environments.json")
        let legacyPrefixPath = "/tmp/mgb-prefixes/shared/../pes"
        let normalizedPrefixPath = "/tmp/mgb-prefixes/pes"
        let legacy = environment(
            prefixURL: URL(fileURLWithPath: legacyPrefixPath),
            id: "env-legacy"
        )
        try EnvironmentTestFixtures.writeRegistry(at: storageURL, environments: [legacy])
        let originalData = try Data(contentsOf: storageURL)
        let repository = EnvironmentRepository(storageURL: storageURL)
        let candidate = EnvironmentTestFixtures.environment(
            id: "env-new",
            gameProfileID: "pes-2021",
            prefixPath: normalizedPrefixPath
        )

        assertRepositoryError(
            .duplicateGamePrefix(
                id: "env-legacy",
                gameProfileID: "pes-2021",
                prefixPath: normalizedPrefixPath
            )
        ) {
            try repository.create(candidate)
        }

        let after = try Data(contentsOf: storageURL)
        #expect(after == originalData)
    }
}

@Test
func repositoryAllowsSamePrefixForDifferentGameProfiles() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let storageURL = root.appendingPathComponent("environments.json")
        let repository = EnvironmentRepository(storageURL: storageURL)
        let prefixPath = root.appendingPathComponent("shared-prefix").path
        let pes = EnvironmentTestFixtures.environment(
            id: "env-pes",
            gameProfileID: "pes-2021",
            prefixPath: prefixPath
        )
        let gta = EnvironmentTestFixtures.environment(
            id: "env-gta",
            gameProfileID: "gta",
            name: "GTA environment",
            prefixPath: prefixPath
        )

        try repository.create(pes)
        try repository.create(gta)

        let listed = try repository.list()
        #expect(listed == [gta, pes])
    }
}

@Test
func repositoryAllowsDifferentPrefixesForSameGameProfile() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let storageURL = root.appendingPathComponent("environments.json")
        let repository = EnvironmentRepository(storageURL: storageURL)
        let offline = EnvironmentTestFixtures.environment(
            id: "env-offline",
            gameProfileID: "pes-2021",
            name: "Offline prefix",
            prefixPath: root.appendingPathComponent("offline").path
        )
        let testing = EnvironmentTestFixtures.environment(
            id: "env-testing",
            gameProfileID: "pes-2021",
            name: "Testing prefix",
            prefixPath: root.appendingPathComponent("testing").path
        )

        try repository.create(offline)
        try repository.create(testing)

        let listed = try repository.list()
        #expect(listed == [offline, testing])
    }
}
