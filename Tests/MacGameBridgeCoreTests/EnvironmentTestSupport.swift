import Foundation
import Testing

@testable import MacGameBridgeCore

enum EnvironmentTestFixtures {
    private struct RegistryFixture: Encodable {
        let schemaVersion: String
        let environments: [GameEnvironment]
    }

    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacGameBridgeEnvironmentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        return try body(root)
    }

    static func profile(id: String = "game-b") -> GameProfile {
        GameProfile(
            id: id,
            title: "Game B",
            editionsToInvestigate: ["Edition B (fixture)"],
            primaryRisks: ["Online service availability"],
            initialMode: "Offline exhibition"
        )
    }

    static func installation(
        id: String = "wine:/usr/local/bin/wine64",
        provider: RuntimeProviderID = .wine,
        status: RuntimeInstallationStatus = .validated,
        architecture: RuntimeArchitecture = .arm64,
        bundleURL: URL? = nil,
        path: String = "/usr/local/bin/wine64"
    ) -> ProviderInstallation {
        ProviderInstallation(
            provider: provider,
            displayName: provider == .wine ? "Wine" : provider.rawValue,
            bundleURL: bundleURL,
            wineExecutableURL: provider == .wine ? URL(fileURLWithPath: path) : nil,
            version: "1.0",
            architecture: architecture,
            status: status,
            evidence: ["Test fixture: \(id)"]
        )
    }

    /// Fixture host facts. No system probe is run by any test.
    static func host(
        architecture: RuntimeArchitecture = .arm64,
        rosetta: RosettaVerificationStatus = .verified
    ) -> HostCapabilities {
        HostCapabilities(
            nativeArchitecture: architecture,
            architectureDetail: architecture.rawValue,
            rosettaStatus: rosetta,
            rosettaDetail: "Test fixture",
            translatedArchitecture: rosetta == .verified ? "x86_64" : nil
        )
    }

    static func environment(
        id: String = "env-1",
        gameProfileID: String = "game-b",
        runtimeInstallationID: String? = nil,
        name: String = "Game B environment",
        prefixPath: String = "/tmp/mgb-prefixes/game-b",
        lifecycleState: EnvironmentLifecycleState = .planned,
        createdAt: Date = fixedDate,
        updatedAt: Date = fixedDate
    ) -> GameEnvironment {
        GameEnvironment(
            id: id,
            gameProfileID: gameProfileID,
            runtimeInstallationID: runtimeInstallationID,
            name: name,
            prefixURL: URL(fileURLWithPath: prefixPath),
            lifecycleState: lifecycleState,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Write a registry fixture directly, bypassing repository create checks.
    static func writeRegistry(at url: URL, environments: [GameEnvironment]) throws {
        let document = RegistryFixture(schemaVersion: "1.0", environments: environments)
        let data = try encoder().encode(document)
        try data.write(to: url)
    }

    static func services(
        repository: EnvironmentRepository,
        profiles: [GameProfile] = [profile()],
        installations: [ProviderInstallation] = [],
        host: HostCapabilities = EnvironmentTestFixtures.host(),
        adapterRegistry: RuntimeAdapterRegistry = .default,
        now: @escaping () -> Date = { fixedDate },
        makeEnvironmentID: @escaping () -> String = { "env-test-1" }
    ) -> EnvironmentCLIServices {
        EnvironmentCLIServices(
            repository: repository,
            loadGameProfiles: { profiles },
            runtimeInstallations: { installations },
            fileManager: .default,
            now: now,
            makeEnvironmentID: makeEnvironmentID,
            hostCapabilities: { host },
            adapterRegistry: adapterRegistry
        )
    }

    static func validationDependencies(
        profiles: [GameProfile] = [profile()],
        installations: [ProviderInstallation] = [],
        fileManager: FileManager = .default
    ) -> EnvironmentValidationDependencies {
        EnvironmentValidationDependencies(
            gameProfiles: { profiles },
            runtimeInstallations: { installations },
            fileManager: fileManager,
            validatePrefixPath: { try EnvironmentPrefixPolicy.validate($0) }
        )
    }
}

func assertEnvironmentCLIError(
    _ expected: EnvironmentCLIError,
    _ body: () throws -> Void,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    do {
        try body()
        Issue.record("Expected error \(expected)", sourceLocation: sourceLocation)
    } catch let error as EnvironmentCLIError {
        #expect(error == expected, sourceLocation: sourceLocation)
    } catch {
        Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation)
    }
}

func assertRepositoryError(
    _ expected: EnvironmentRepositoryError,
    _ body: () throws -> Void,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    do {
        try body()
        Issue.record("Expected error \(expected)", sourceLocation: sourceLocation)
    } catch let error as EnvironmentRepositoryError {
        #expect(error == expected, sourceLocation: sourceLocation)
    } catch {
        Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation)
    }
}
