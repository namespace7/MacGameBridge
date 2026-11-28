import Foundation
import Testing

@testable import MacGameBridgeCore

private let laterDate = Date(timeIntervalSince1970: 1_700_003_600)

private func dependencies(
    repository: EnvironmentRepository,
    installations: [ProviderInstallation] = [],
    host: HostCapabilities = EnvironmentTestFixtures.host(),
    adapterRegistry: RuntimeAdapterRegistry = .default,
    now: @escaping () -> Date = { laterDate }
) -> RuntimePinningDependencies {
    RuntimePinningDependencies(
        repository: repository,
        installations: { installations },
        hostCapabilities: { host },
        adapterRegistry: adapterRegistry,
        now: now
    )
}

/// Test-only adapter that records whether validation was invoked.
private final class ValidationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func mark() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private struct InjectableRuntimeAdapter: RuntimeAdapter {
    let providerID: RuntimeProviderID
    let capabilities: RuntimeAdapterCapabilities
    let counter: ValidationCounter

    func validate(
        _ installation: ProviderInstallation,
        host: HostCapabilities
    ) throws -> RuntimeAdapterValidationResult {
        counter.mark()
        return RuntimeAdapterValidationResult(
            providerID: providerID,
            installationID: installation.id,
            isEligible: true,
            architecture: installation.architecture,
            issues: []
        )
    }
}

private func assertPinningError(
    _ expected: RuntimePinningError,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () throws -> Void
) {
    do {
        try body()
        Issue.record("Expected error \(expected)", sourceLocation: sourceLocation)
    } catch let error as RuntimePinningError {
        #expect(error == expected, sourceLocation: sourceLocation)
    } catch {
        Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation)
    }
}

// MARK: - Exact selection safeguards

@Test
func pinRequiresANonEmptyRuntimeID() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(storageURL: root.appendingPathComponent("environments.json"))
        let environment = EnvironmentTestFixtures.environment()
        try repository.create(environment)
        let before = try Data(contentsOf: repository.storageURL)

        assertPinningError(.runtimeIDMissing) {
            _ = try RuntimePinningService.pin(
                environmentID: environment.id,
                runtimeID: "   ",
                replace: false,
                using: dependencies(repository: repository)
            )
        }
        let after = try Data(contentsOf: repository.storageURL)
        #expect(after == before)
    }
}

@Test
func pinDoesNotTrimTheSuppliedRuntimeID() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(storageURL: root.appendingPathComponent("environments.json"))
        let environment = EnvironmentTestFixtures.environment()
        try repository.create(environment)
        let installation = EnvironmentTestFixtures.installation()
        let suppliedID = "  \(installation.id)  "
        let before = try Data(contentsOf: repository.storageURL)

        assertPinningError(.runtimeNotFound(suppliedID)) {
            _ = try RuntimePinningService.pin(
                environmentID: environment.id,
                runtimeID: suppliedID,
                replace: false,
                using: dependencies(repository: repository, installations: [installation])
            )
        }
        let after = try Data(contentsOf: repository.storageURL)
        #expect(after == before)
        let fetched = try repository.get(id: environment.id)
        #expect(fetched?.runtimeInstallationID == nil)
    }
}

@Test
func pinRejectsMissingRuntimeWithoutSelectingAnAlternative() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(storageURL: root.appendingPathComponent("environments.json"))
        let environment = EnvironmentTestFixtures.environment()
        try repository.create(environment)
        let alternative = EnvironmentTestFixtures.installation(
            id: "wine:/opt/wine/bin/wine64",
            path: "/opt/wine/bin/wine64"
        )
        let before = try Data(contentsOf: repository.storageURL)

        assertPinningError(.runtimeNotFound("wine:/missing/wine64")) {
            _ = try RuntimePinningService.pin(
                environmentID: environment.id,
                runtimeID: "wine:/missing/wine64",
                replace: false,
                using: dependencies(repository: repository, installations: [alternative])
            )
        }
        let after = try Data(contentsOf: repository.storageURL)
        #expect(after == before)
        let fetchedAfterFailure = try repository.get(id: environment.id)
        #expect(fetchedAfterFailure?.runtimeInstallationID == nil)
    }
}

@Test
func pinRejectsAmbiguousRuntimeID() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(storageURL: root.appendingPathComponent("environments.json"))
        let environment = EnvironmentTestFixtures.environment()
        try repository.create(environment)
        // `ProviderInstallation.id` is derived from provider + path, so two
        // duplicate discoveries must share a path to share an ID.
        let duplicateID = "wine:/opt/wine/bin/wine64"
        let installations = [
            EnvironmentTestFixtures.installation(id: duplicateID, path: "/opt/wine/bin/wine64"),
            EnvironmentTestFixtures.installation(id: duplicateID, path: "/opt/wine/bin/wine64")
        ]

        assertPinningError(.ambiguousRuntimeID(duplicateID)) {
            _ = try RuntimePinningService.pin(
                environmentID: environment.id,
                runtimeID: duplicateID,
                replace: false,
                using: dependencies(repository: repository, installations: installations)
            )
        }
    }
}

@Test
func pinUsesExactInstallationEvenWhenAnotherIsBetterRanked() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(storageURL: root.appendingPathComponent("environments.json"))
        let environment = EnvironmentTestFixtures.environment()
        try repository.create(environment)

        // The exact x86_64 installation is deliberately less preferred than the
        // arm64 alternative. With Rosetta verified, both are eligible; the pin
        // must still select exactly the requested ID.
        let target = EnvironmentTestFixtures.installation(
            id: "wine:/opt/wine-x86/bin/wine",
            architecture: .x8664,
            path: "/opt/wine-x86/bin/wine"
        )
        let betterRanked = EnvironmentTestFixtures.installation(
            id: "wine:/opt/wine-arm/bin/wine64",
            architecture: .arm64,
            path: "/opt/wine-arm/bin/wine64"
        )

        let updated = try RuntimePinningService.pin(
            environmentID: environment.id,
            runtimeID: target.id,
            replace: false,
            using: dependencies(
                repository: repository,
                installations: [betterRanked, target],
                host: EnvironmentTestFixtures.host()
            )
        )
        #expect(updated.runtimeInstallationID == target.id)
        #expect(updated.runtimeInstallationID != betterRanked.id)
    }
}

// MARK: - Rejection of unsafe installations

@Test
func pinRejectsUnsupportedProvider() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(storageURL: root.appendingPathComponent("environments.json"))
        let environment = EnvironmentTestFixtures.environment()
        try repository.create(environment)
        let crossover = EnvironmentTestFixtures.installation(
            id: "crossover:/Applications/CrossOver.app",
            provider: .crossover,
            bundleURL: URL(fileURLWithPath: "/Applications/CrossOver.app")
        )
        let before = try Data(contentsOf: repository.storageURL)

        assertPinningError(.unsupportedProvider(.crossover)) {
            _ = try RuntimePinningService.pin(
                environmentID: environment.id,
                runtimeID: crossover.id,
                replace: false,
                using: dependencies(repository: repository, installations: [crossover])
            )
        }
        let after = try Data(contentsOf: repository.storageURL)
        #expect(after == before)
    }
}

@Test
func pinRejectsUnvalidatedInstallation() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(storageURL: root.appendingPathComponent("environments.json"))
        let environment = EnvironmentTestFixtures.environment()
        try repository.create(environment)
        let detected = EnvironmentTestFixtures.installation(status: .detected)
        let before = try Data(contentsOf: repository.storageURL)

        assertPinningError(.unvalidatedRuntime(detected.id)) {
            _ = try RuntimePinningService.pin(
                environmentID: environment.id,
                runtimeID: detected.id,
                replace: false,
                using: dependencies(repository: repository, installations: [detected])
            )
        }
        let after = try Data(contentsOf: repository.storageURL)
        #expect(after == before)
    }
}

@Test
func pinRejectsArchitectureIncompatibleInstallation() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(storageURL: root.appendingPathComponent("environments.json"))
        let environment = EnvironmentTestFixtures.environment()
        try repository.create(environment)
        let x8664 = EnvironmentTestFixtures.installation(
            id: "wine:/opt/wine-x86/bin/wine",
            architecture: .x8664,
            path: "/opt/wine-x86/bin/wine"
        )
        let before = try Data(contentsOf: repository.storageURL)

        assertPinningError(.incompatibleRuntime(x8664.id, .rosettaNotAvailable)) {
            _ = try RuntimePinningService.pin(
                environmentID: environment.id,
                runtimeID: x8664.id,
                replace: false,
                using: dependencies(
                    repository: repository,
                    installations: [x8664],
                    host: EnvironmentTestFixtures.host(rosetta: .notVerified)
                )
            )
        }
        let after = try Data(contentsOf: repository.storageURL)
        #expect(after == before)
    }
}

@Test
func pinRejectsUnsupportedStandaloneInstallationShape() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(storageURL: root.appendingPathComponent("environments.json"))
        let environment = EnvironmentTestFixtures.environment()
        try repository.create(environment)
        let wrapper = EnvironmentTestFixtures.installation(
            id: "wine:/Applications/WineWrap.app",
            bundleURL: URL(fileURLWithPath: "/Applications/WineWrap.app"),
            path: "/Applications/WineWrap.app/Contents/wine"
        )

        assertPinningError(.invalidRuntimeInstallation(wrapper.id, [
            RuntimeAdapterValidationIssue(
                code: .unsupportedInstallationShape,
                message: "Standalone Wine cannot be pinned from a wrapper app bundle."
            )
        ])) {
            _ = try RuntimePinningService.pin(
                environmentID: environment.id,
                runtimeID: wrapper.id,
                replace: false,
                using: dependencies(repository: repository, installations: [wrapper])
            )
        }
    }
}

@Test
func pinRejectsAdapterWithoutReadOnlyValidationCapability() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(storageURL: root.appendingPathComponent("environments.json"))
        let environment = EnvironmentTestFixtures.environment()
        try repository.create(environment)
        let installation = EnvironmentTestFixtures.installation()
        let counter = ValidationCounter()
        let adapter = InjectableRuntimeAdapter(
            providerID: .wine,
            capabilities: RuntimeAdapterCapabilities(
                readOnlyValidation: false,
                exactPinning: true
            ),
            counter: counter
        )
        let deps = dependencies(
            repository: repository,
            installations: [installation],
            adapterRegistry: RuntimeAdapterRegistry(adapters: [adapter])
        )
        let before = try Data(contentsOf: repository.storageURL)

        assertPinningError(
            .adapterMissingCapabilities(provider: .wine, missing: [.readOnlyValidation])
        ) {
            _ = try RuntimePinningService.pin(
                environmentID: environment.id,
                runtimeID: installation.id,
                replace: false,
                using: deps
            )
        }
        #expect(counter.value == 0)
        let after = try Data(contentsOf: repository.storageURL)
        #expect(after == before)
    }
}

@Test
func pinRejectsAdapterWithoutExactPinningCapability() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(storageURL: root.appendingPathComponent("environments.json"))
        let environment = EnvironmentTestFixtures.environment()
        try repository.create(environment)
        let installation = EnvironmentTestFixtures.installation()
        let counter = ValidationCounter()
        let adapter = InjectableRuntimeAdapter(
            providerID: .wine,
            capabilities: RuntimeAdapterCapabilities(
                readOnlyValidation: true,
                exactPinning: false
            ),
            counter: counter
        )
        let deps = dependencies(
            repository: repository,
            installations: [installation],
            adapterRegistry: RuntimeAdapterRegistry(adapters: [adapter])
        )
        let before = try Data(contentsOf: repository.storageURL)

        assertPinningError(
            .adapterMissingCapabilities(provider: .wine, missing: [.exactPinning])
        ) {
            _ = try RuntimePinningService.pin(
                environmentID: environment.id,
                runtimeID: installation.id,
                replace: false,
                using: deps
            )
        }
        #expect(counter.value == 0)
        let after = try Data(contentsOf: repository.storageURL)
        #expect(after == before)
    }
}

// MARK: - Persistence semantics

@Test
func pinPersistsRuntimeIDAndUpdatedAtAndPreservesOtherFields() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(storageURL: root.appendingPathComponent("environments.json"))
        let original = EnvironmentTestFixtures.environment(
            id: "env-pin",
            gameProfileID: "game-d",
            name: "Game D test",
            prefixPath: root.appendingPathComponent("prefixes/game-d").path,
            lifecycleState: .planned
        )
        try repository.create(original)
        let installation = EnvironmentTestFixtures.installation(
            id: "wine:/opt/wine/bin/wine64",
            path: "/opt/wine/bin/wine64"
        )

        let updated = try RuntimePinningService.pin(
            environmentID: original.id,
            runtimeID: installation.id,
            replace: false,
            using: dependencies(repository: repository, installations: [installation])
        )

        #expect(updated.id == original.id)
        #expect(updated.gameProfileID == original.gameProfileID)
        #expect(updated.name == original.name)
        #expect(updated.prefixURL == original.prefixURL)
        #expect(updated.lifecycleState == original.lifecycleState)
        #expect(updated.createdAt == original.createdAt)
        #expect(updated.updatedAt == laterDate)
        #expect(updated.updatedAt != original.updatedAt)
        #expect(updated.runtimeInstallationID == installation.id)

        let fetched = try repository.get(id: original.id)
        let stored = try #require(fetched)
        #expect(stored == updated)
        #expect(!FileManager.default.fileExists(atPath: original.prefixPath))
    }
}

@Test
func replacingADifferentPinRequiresExplicitReplace() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(storageURL: root.appendingPathComponent("environments.json"))
        let environment = EnvironmentTestFixtures.environment()
        try repository.create(environment)
        let first = EnvironmentTestFixtures.installation(
            id: "wine:/opt/wine-a/bin/wine64",
            path: "/opt/wine-a/bin/wine64"
        )
        let second = EnvironmentTestFixtures.installation(
            id: "wine:/opt/wine-b/bin/wine64",
            path: "/opt/wine-b/bin/wine64"
        )
        let deps = dependencies(repository: repository, installations: [first, second])

        let pinned = try RuntimePinningService.pin(
            environmentID: environment.id,
            runtimeID: first.id,
            replace: false,
            using: deps
        )
        let beforeReplacement = try Data(contentsOf: repository.storageURL)

        assertPinningError(
            .replacementRequiresReplace(currentID: first.id, requestedID: second.id)
        ) {
            _ = try RuntimePinningService.pin(
                environmentID: environment.id,
                runtimeID: second.id,
                replace: false,
                using: deps
            )
        }
        let dataAfterRejectedReplacement = try Data(contentsOf: repository.storageURL)
        #expect(dataAfterRejectedReplacement == beforeReplacement)
        let fetchedAfterRejectedReplacement = try repository.get(id: environment.id)
        #expect(fetchedAfterRejectedReplacement?.runtimeInstallationID == first.id)

        let replaced = try RuntimePinningService.pin(
            environmentID: environment.id,
            runtimeID: second.id,
            replace: true,
            using: deps
        )
        #expect(replaced.runtimeInstallationID == second.id)
        #expect(replaced.createdAt == pinned.createdAt)
    }
}

@Test
func pinningTheSameIDDoesNotRequireReplace() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(storageURL: root.appendingPathComponent("environments.json"))
        let environment = EnvironmentTestFixtures.environment()
        try repository.create(environment)
        let installation = EnvironmentTestFixtures.installation()
        let deps = dependencies(repository: repository, installations: [installation])

        _ = try RuntimePinningService.pin(
            environmentID: environment.id,
            runtimeID: installation.id,
            replace: false,
            using: deps
        )
        let repinned = try RuntimePinningService.pin(
            environmentID: environment.id,
            runtimeID: installation.id,
            replace: false,
            using: deps
        )
        #expect(repinned.runtimeInstallationID == installation.id)
        #expect(repinned.updatedAt == laterDate)
    }
}

@Test
func unpinPreservesEveryOtherEnvironmentField() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(storageURL: root.appendingPathComponent("environments.json"))
        let original = EnvironmentTestFixtures.environment(
            id: "env-unpin",
            gameProfileID: "game-b",
            name: "Game B unpin",
            prefixPath: root.appendingPathComponent("prefixes/game-b").path
        )
        try repository.create(original)
        let installation = EnvironmentTestFixtures.installation()
        let deps = dependencies(repository: repository, installations: [installation])
        let pinned = try RuntimePinningService.pin(
            environmentID: original.id,
            runtimeID: installation.id,
            replace: false,
            using: deps
        )

        let unpinned = try RuntimePinningService.unpin(
            environmentID: original.id,
            using: deps
        )
        #expect(unpinned.runtimeInstallationID == nil)
        #expect(unpinned.updatedAt == laterDate)
        #expect(unpinned.id == original.id)
        #expect(unpinned.gameProfileID == original.gameProfileID)
        #expect(unpinned.name == original.name)
        #expect(unpinned.prefixURL == original.prefixURL)
        #expect(unpinned.lifecycleState == original.lifecycleState)
        #expect(unpinned.createdAt == original.createdAt)
        #expect(pinned.runtimeInstallationID == installation.id)

        let fetched = try repository.get(id: original.id)
        let stored = try #require(fetched)
        #expect(stored == unpinned)
    }
}

@Test
func unpinRejectsEnvironmentWithoutAPin() throws {
    try EnvironmentTestFixtures.withTemporaryDirectory { root in
        let repository = EnvironmentRepository(storageURL: root.appendingPathComponent("environments.json"))
        let environment = EnvironmentTestFixtures.environment()
        try repository.create(environment)
        let before = try Data(contentsOf: repository.storageURL)

        assertPinningError(.runtimeNotPinned(environment.id)) {
            _ = try RuntimePinningService.unpin(
                environmentID: environment.id,
                using: dependencies(repository: repository)
            )
        }
        let after = try Data(contentsOf: repository.storageURL)
        #expect(after == before)
    }
}
