import Foundation
import Testing

@testable import MacGameBridgeCore

private func codes(in report: EnvironmentValidationReport) -> [EnvironmentValidationIssueCode] {
    report.issues.map(\.code)
}

private final class RecordingFileManager: FileManager {
    private(set) var fileExistsCallCount = 0

    override func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        fileExistsCallCount += 1
        return false
    }
}

@Test
func validPlannedEnvironmentPassesMetadataValidation() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let prefixPath = root.appendingPathComponent("prefix").path
        let environment = EnvironmentTestFixtures.environment(
            runtimeInstallationID: "wine:/usr/local/bin/wine64",
            prefixPath: prefixPath
        )
        let installation = EnvironmentTestFixtures.installation(
            id: "wine:/usr/local/bin/wine64",
            status: .validated,
            architecture: .arm64
        )

        let report = EnvironmentValidator.validate(
            environment,
            using: EnvironmentTestFixtures.validationDependencies(installations: [installation])
        )

        #expect(report.isValid)
        #expect(!report.issues.contains { $0.severity == .error })
        #expect(!codes(in: report).contains(.gameProfileMissing))
        #expect(!codes(in: report).contains(.runtimeInstallationUnvalidated))
        #expect(!report.prefixDirectoryExists)
        #expect(report.prefixInitializationStatus == .notInitialized)
        #expect(!report.readyToLaunch)
        #expect(!FileManager.default.fileExists(atPath: prefixPath))
    }
}

@Test
func successfullyLoadedEmptyCatalogReportsMissingGameProfile() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let environment = EnvironmentTestFixtures.environment(
            prefixPath: root.appendingPathComponent("prefix").path
        )
        let dependencies = EnvironmentValidationDependencies(
            gameProfiles: { [] },
            runtimeInstallations: { [] },
            fileManager: .default,
            validatePrefixPath: { try EnvironmentPrefixPolicy.validate($0) }
        )

        let report = EnvironmentValidator.validate(environment, using: dependencies)

        #expect(!report.isValid)
        #expect(codes(in: report).contains(.gameProfileMissing))
        #expect(!codes(in: report).contains(.gameCatalogUnavailable))
    }
}

@Test
func failedCatalogLoadingReportsUnavailableWithoutClaimingProfileMissing() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let environment = EnvironmentTestFixtures.environment(
            prefixPath: root.appendingPathComponent("prefix").path
        )
        let catalogURL = URL(fileURLWithPath: "/tmp/games-unavailable.json")
        let dependencies = EnvironmentValidationDependencies(
            gameProfiles: {
                throw GameProfileCatalogError.unavailable(catalogURL, "fixture failure")
            },
            runtimeInstallations: { [] },
            fileManager: .default,
            validatePrefixPath: { try EnvironmentPrefixPolicy.validate($0) }
        )

        let report = EnvironmentValidator.validate(environment, using: dependencies)

        #expect(!report.isValid)
        #expect(codes(in: report).contains(.gameCatalogUnavailable))
        #expect(!codes(in: report).contains(.gameProfileMissing))
    }
}

@Test
func existingGameProfileIsNotReportedMissing() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let environment = EnvironmentTestFixtures.environment(
            prefixPath: root.appendingPathComponent("prefix").path
        )
        let dependencies = EnvironmentValidationDependencies(
            gameProfiles: { [EnvironmentTestFixtures.profile(id: "pes-2021")] },
            runtimeInstallations: { [] },
            fileManager: .default,
            validatePrefixPath: { try EnvironmentPrefixPolicy.validate($0) }
        )

        let report = EnvironmentValidator.validate(environment, using: dependencies)

        #expect(!codes(in: report).contains(.gameProfileMissing))
        #expect(!codes(in: report).contains(.gameCatalogUnavailable))
    }
}

@Test
func missingGameProfileIsReported() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let environment = EnvironmentTestFixtures.environment(
            gameProfileID: "does-not-exist",
            prefixPath: root.appendingPathComponent("prefix").path
        )

        let report = EnvironmentValidator.validate(
            environment,
            using: EnvironmentTestFixtures.validationDependencies()
        )

        #expect(!report.isValid)
        #expect(codes(in: report).contains(.gameProfileMissing))
        #expect(report.issues.first { $0.code == .gameProfileMissing }?.severity == .error)
    }
}

@Test
func missingRuntimeInstallationIsReported() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let environment = EnvironmentTestFixtures.environment(
            runtimeInstallationID: "wine:/missing/wine64",
            prefixPath: root.appendingPathComponent("prefix").path
        )

        let report = EnvironmentValidator.validate(
            environment,
            using: EnvironmentTestFixtures.validationDependencies()
        )

        #expect(!report.isValid)
        #expect(codes(in: report).contains(.runtimeInstallationMissing))
    }
}

@Test
func unvalidatedRuntimeInstallationIsNotEligible() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let environment = EnvironmentTestFixtures.environment(
            runtimeInstallationID: "wine:/usr/local/bin/wine64",
            prefixPath: root.appendingPathComponent("prefix").path
        )
        let detected = EnvironmentTestFixtures.installation(
            id: "wine:/usr/local/bin/wine64",
            status: .detected
        )

        let report = EnvironmentValidator.validate(
            environment,
            using: EnvironmentTestFixtures.validationDependencies(installations: [detected])
        )

        #expect(!report.isValid)
        #expect(codes(in: report).contains(.runtimeInstallationUnvalidated))
    }
}

@Test
func validatedRuntimeWithUnknownArchitectureIsWarning() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let environment = EnvironmentTestFixtures.environment(
            runtimeInstallationID: "wine:/usr/local/bin/wine64",
            prefixPath: root.appendingPathComponent("prefix").path
        )
        let installation = EnvironmentTestFixtures.installation(
            id: "wine:/usr/local/bin/wine64",
            status: .validated,
            architecture: .unknown
        )

        let report = EnvironmentValidator.validate(
            environment,
            using: EnvironmentTestFixtures.validationDependencies(installations: [installation])
        )

        #expect(report.isValid)
        #expect(codes(in: report).contains(.runtimeArchitectureUnknown))
        #expect(report.issues.first { $0.code == .runtimeArchitectureUnknown }?.severity == .warning)
    }
}

@Test
func unpinnedRuntimeIsInformational() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let environment = EnvironmentTestFixtures.environment(
            prefixPath: root.appendingPathComponent("prefix").path
        )

        let report = EnvironmentValidator.validate(
            environment,
            using: EnvironmentTestFixtures.validationDependencies()
        )

        #expect(report.isValid)
        #expect(codes(in: report).contains(.runtimeNotPinned))
        #expect(report.issues.first { $0.code == .runtimeNotPinned }?.severity == .info)
    }
}

@Test
func invalidPrefixPathsAreRejected() throws {
    let relativeURL = try #require(URL(string: "relative/prefix"))
    let relative = GameEnvironment(
        id: "env-relative",
        gameProfileID: "pes-2021",
        name: "Relative prefix",
        prefixURL: relativeURL,
        createdAt: EnvironmentTestFixtures.fixedDate,
        updatedAt: EnvironmentTestFixtures.fixedDate
    )
    let traversable = EnvironmentTestFixtures.environment(prefixPath: "/tmp/../etc")
    let appBundle = EnvironmentTestFixtures.environment(prefixPath: "/Applications/Whisky.app/prefix")

    for environment in [relative, traversable, appBundle] {
        let report = EnvironmentValidator.validate(
            environment,
            using: EnvironmentTestFixtures.validationDependencies()
        )
        #expect(!report.isValid)
        #expect(codes(in: report).contains(.prefixPathInvalid))
    }
}

@Test
func nonFilePrefixURLIsReportedInvalidWithoutFilesystemInspection() throws {
    let nonFileURL = try #require(URL(string: "https://example.com/prefix"))
    let environment = GameEnvironment(
        id: "env-non-file",
        gameProfileID: "pes-2021",
        name: "Non-file prefix",
        prefixURL: nonFileURL,
        createdAt: EnvironmentTestFixtures.fixedDate,
        updatedAt: EnvironmentTestFixtures.fixedDate
    )
    let fileManager = RecordingFileManager()
    var prefixValidationCalls = 0
    let dependencies = EnvironmentValidationDependencies(
        gameProfiles: { [EnvironmentTestFixtures.profile()] },
        runtimeInstallations: { [] },
        fileManager: fileManager,
        validatePrefixPath: { path in
            prefixValidationCalls += 1
            return try EnvironmentPrefixPolicy.validate(path)
        }
    )

    let report = EnvironmentValidator.validate(environment, using: dependencies)

    #expect(!report.isValid)
    #expect(codes(in: report).contains(.prefixPathInvalid))
    #expect(prefixValidationCalls == 0)
    #expect(fileManager.fileExistsCallCount == 0)
    #expect(!report.prefixDirectoryExists)
    #expect(report.prefixInitializationStatus == .notInitialized)
    #expect(!report.readyToLaunch)
}

@Test
func existingPrefixDirectoryIsInformationalOnly() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let prefixURL = root.appendingPathComponent("prefix", isDirectory: true)
        try FileManager.default.createDirectory(at: prefixURL, withIntermediateDirectories: true)
        let environment = EnvironmentTestFixtures.environment(prefixPath: prefixURL.path)

        let report = EnvironmentValidator.validate(
            environment,
            using: EnvironmentTestFixtures.validationDependencies()
        )

        #expect(report.isValid)
        #expect(report.prefixDirectoryExists)
        #expect(codes(in: report).contains(.prefixDirectoryExists))
        #expect(report.issues.first { $0.code == .prefixDirectoryExists }?.severity == .info)
        #expect(report.prefixInitializationStatus == .notInitialized)
        #expect(!report.readyToLaunch)
    }
}

@Test
func regularFileAtPrefixPathIsAnError() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let prefixURL = root.appendingPathComponent("prefix-file", isDirectory: false)
        try Data("not a prefix".utf8).write(to: prefixURL)
        let environment = EnvironmentTestFixtures.environment(prefixPath: prefixURL.path)

        let report = EnvironmentValidator.validate(
            environment,
            using: EnvironmentTestFixtures.validationDependencies()
        )

        #expect(!report.isValid)
        #expect(codes(in: report).contains(.prefixPathIsFile))
        #expect(!report.prefixDirectoryExists)
    }
}

@Test
func provisionedStateWithoutEvidenceIsRejected() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let environment = EnvironmentTestFixtures.environment(
            prefixPath: root.appendingPathComponent("prefix").path,
            lifecycleState: .provisioned
        )

        let report = EnvironmentValidator.validate(
            environment,
            using: EnvironmentTestFixtures.validationDependencies()
        )

        #expect(!report.isValid)
        #expect(report.lifecycleState == .provisioned)
        #expect(codes(in: report).contains(.provisionedStateUnsupported))
        #expect(!report.readyToLaunch)
    }
}

@Test
func validationDoesNotMutateTheEnvironmentOrPrefix() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let prefixURL = root.appendingPathComponent("prefix", isDirectory: true)
        let environment = EnvironmentTestFixtures.environment(prefixPath: prefixURL.path)
        let before = try FileManager.default.contentsOfDirectory(atPath: root.path)

        let report = EnvironmentValidator.validate(
            environment,
            using: EnvironmentTestFixtures.validationDependencies()
        )

        let after = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(before == after)
        #expect(report.lifecycleState == environment.lifecycleState)
        #expect(!FileManager.default.fileExists(atPath: prefixURL.path))
    }
}
