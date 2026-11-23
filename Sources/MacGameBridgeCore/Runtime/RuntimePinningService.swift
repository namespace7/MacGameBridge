import Foundation

/// Structured failures from exact runtime pinning.
///
/// These are core-level errors. `EnvironmentCLI` translates them into
/// actionable `EnvironmentCLIError` values; no provider logic lives in the CLI.
public enum RuntimePinningError: Error, Equatable, CustomStringConvertible, Sendable {
    case environmentNotFound(String)
    case runtimeIDMissing
    case ambiguousRuntimeID(String)
    case runtimeNotFound(String)
    case unsupportedProvider(RuntimeProviderID)
    case providerMismatch(expected: RuntimeProviderID, actual: RuntimeProviderID)
    case adapterMissingCapabilities(
        provider: RuntimeProviderID,
        missing: [RuntimeAdapterRequiredCapability]
    )
    case unvalidatedRuntime(String)
    case incompatibleRuntime(String, RuntimeSelectionRejection)
    case invalidRuntimeInstallation(String, [RuntimeAdapterValidationIssue])
    case replacementRequiresReplace(currentID: String, requestedID: String)
    case runtimeNotPinned(String)
    case staleEnvironment(String)
    case duplicateEnvironmentRecord(String)
    case repository(EnvironmentRepositoryError)

    public var description: String {
        switch self {
        case .environmentNotFound(let id):
            return "No environment with ID '\(id)' is recorded."
        case .runtimeIDMissing:
            return "A runtime installation ID is required. Run `macgamebridge runtimes --providers` to copy one."
        case .ambiguousRuntimeID(let id):
            return "Runtime installation ID '\(id)' matches more than one discovered installation. No pin was changed."
        case .runtimeNotFound(let id):
            return "No discovered installation has the exact ID '\(id)'. No fallback was used and no pin was changed."
        case .unsupportedProvider(let provider):
            return "Runtime provider '\(provider.rawValue)' has no adapter in M3.1. No pin was changed."
        case .providerMismatch(let expected, let actual):
            return "Adapter \(expected.rawValue) cannot validate provider \(actual.rawValue). No pin was changed."
        case .adapterMissingCapabilities(let provider, let missing):
            let names = missing.map(\.rawValue).joined(separator: ", ")
            return "Adapter for provider '\(provider.rawValue)' does not declare required capabilities: \(names). No pin was changed."
        case .unvalidatedRuntime(let id):
            return "Runtime installation '\(id)' is not validated. No pin was changed."
        case .incompatibleRuntime(let id, let rejection):
            return "Runtime installation '\(id)' is incompatible with this host: \(rejection.description). No fallback was used and no pin was changed."
        case .invalidRuntimeInstallation(let id, let issues):
            let details = issues.map(\.message).joined(separator: " ")
            return "Runtime installation '\(id)' is not eligible: \(details) No pin was changed."
        case .replacementRequiresReplace(let currentID, let requestedID):
            return "Environment is pinned to '\(currentID)'. Pass --replace to pin '\(requestedID)' instead. No record was changed."
        case .runtimeNotPinned(let id):
            return "Environment '\(id)' has no runtime pin to remove."
        case .staleEnvironment(let id):
            return "Environment '\(id)' changed since it was read. No record was changed; re-read it and retry."
        case .duplicateEnvironmentRecord(let id):
            return "The registry contains duplicate records for environment '\(id)'. No record was changed."
        case .repository(let error):
            return error.description
        }
    }
}

/// All dependencies for exact pinning are injectable.
///
/// Tests supply fixture installations, host facts, an adapter registry, a fixed
/// clock, and a temporary-directory repository. Nothing here scans the host or
/// executes a runtime binary.
public struct RuntimePinningDependencies {
    public let repository: EnvironmentRepository
    public let installations: () -> [ProviderInstallation]
    public let hostCapabilities: () -> HostCapabilities
    public let adapterRegistry: RuntimeAdapterRegistry
    public let now: () -> Date

    public init(
        repository: EnvironmentRepository,
        installations: @escaping () -> [ProviderInstallation],
        hostCapabilities: @escaping () -> HostCapabilities,
        adapterRegistry: RuntimeAdapterRegistry = .default,
        now: @escaping () -> Date = { Date() }
    ) {
        self.repository = repository
        self.installations = installations
        self.hostCapabilities = hostCapabilities
        self.adapterRegistry = adapterRegistry
        self.now = now
    }
}

/// Provider-independent pin/unpin operations for environment metadata.
///
/// Pinning never selects a "best" runtime. It requires a literal match with an
/// already-discovered `ProviderInstallation.id`, validates that exact object via
/// its registered adapter, and then persists only the pin and `updatedAt`.
public enum RuntimePinningService {

    /// Pin an exact discovered runtime installation to an environment.
    ///
    /// - Parameter replace: Required when the environment already has a
    ///   different pin. Pinning the same ID again is not a replacement.
    public static func pin(
        environmentID: String,
        runtimeID: String,
        replace: Bool,
        using dependencies: RuntimePinningDependencies
    ) throws -> GameEnvironment {
        let trimmedID = runtimeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { throw RuntimePinningError.runtimeIDMissing }

        // Trimming is only an emptiness check. The supplied value is used
        // verbatim so leading or trailing whitespace cannot silently match a
        // different installation ID.
        let requestedID = runtimeID

        guard let environment = try readEnvironment(id: environmentID, using: dependencies) else {
            throw RuntimePinningError.environmentNotFound(environmentID)
        }

        if let currentID = environment.runtimeInstallationID,
           currentID != requestedID,
           !replace {
            throw RuntimePinningError.replacementRequiresReplace(
                currentID: currentID,
                requestedID: requestedID
            )
        }

        let candidates = dependencies.installations()
        let matches = candidates.filter { $0.id == requestedID }
        guard matches.count <= 1 else {
            throw RuntimePinningError.ambiguousRuntimeID(requestedID)
        }
        guard let installation = matches.first else {
            throw RuntimePinningError.runtimeNotFound(requestedID)
        }

        let host = dependencies.hostCapabilities()
        let request = RuntimeSelectionRequest(
            hostArchitecture: host.nativeArchitecture,
            rosettaAvailable: host.rosettaStatus == .verified,
            allowFallback: false
        )

        // Reuse the exact-installation policy from the M2.3 selector. Fallback
        // is prohibited by both the policy and the request.
        let selection = RuntimeSelector.select(
            from: candidates,
            policy: .exactInstallation(requestedID),
            request: request
        )
        guard selection.selected?.id == requestedID, selection.failure == nil else {
            throw mapSelectionFailure(selection.failure, runtimeID: requestedID)
        }

        let adapter = try resolveAdapter(for: installation.provider, registry: dependencies.adapterRegistry)
        let missingCapabilities = missingPinningCapabilities(for: adapter)
        guard missingCapabilities.isEmpty else {
            throw RuntimePinningError.adapterMissingCapabilities(
                provider: installation.provider,
                missing: missingCapabilities
            )
        }

        let validation: RuntimeAdapterValidationResult
        do {
            validation = try adapter.validate(installation, host: host)
        } catch let error as RuntimeAdapterError {
            throw mapAdapterError(error)
        }
        guard validation.installationID == requestedID,
              validation.providerID == installation.provider else {
            throw RuntimePinningError.invalidRuntimeInstallation(
                requestedID,
                [RuntimeAdapterValidationIssue(
                    code: .providerMismatch,
                    message: "The adapter returned a result for a different installation."
                )]
            )
        }
        guard validation.isEligible else {
            throw mapValidationIssues(validation.issues, runtimeID: requestedID, rejection: validation.architectureRejection)
        }

        return try persist(
            environment: environment,
            runtimeInstallationID: requestedID,
            using: dependencies
        )
    }

    /// Remove a runtime pin without changing any other environment field.
    public static func unpin(
        environmentID: String,
        using dependencies: RuntimePinningDependencies
    ) throws -> GameEnvironment {
        guard let environment = try readEnvironment(id: environmentID, using: dependencies) else {
            throw RuntimePinningError.environmentNotFound(environmentID)
        }
        guard environment.runtimeInstallationID != nil else {
            throw RuntimePinningError.runtimeNotPinned(environmentID)
        }
        return try persist(
            environment: environment,
            runtimeInstallationID: nil,
            using: dependencies
        )
    }

    // MARK: - Helpers

    private static func readEnvironment(
        id: String,
        using dependencies: RuntimePinningDependencies
    ) throws -> GameEnvironment? {
        do {
            return try dependencies.repository.get(id: id)
        } catch let error as EnvironmentRepositoryError {
            throw RuntimePinningError.repository(error)
        }
    }

    private static func persist(
        environment: GameEnvironment,
        runtimeInstallationID: String?,
        using dependencies: RuntimePinningDependencies
    ) throws -> GameEnvironment {
        do {
            return try dependencies.repository.updateRuntimeInstallationID(
                for: environment,
                runtimeInstallationID: runtimeInstallationID,
                updatedAt: dependencies.now()
            )
        } catch let error as EnvironmentRepositoryError {
            switch error {
            case .staleRecord(let id):
                throw RuntimePinningError.staleEnvironment(id)
            case .duplicateID(let id):
                throw RuntimePinningError.duplicateEnvironmentRecord(id)
            default:
                throw RuntimePinningError.repository(error)
            }
        }
    }

    private static func resolveAdapter(
        for provider: RuntimeProviderID,
        registry: RuntimeAdapterRegistry
    ) throws -> any RuntimeAdapter {
        do {
            return try registry.adapter(for: provider)
        } catch let error as RuntimeAdapterError {
            throw mapAdapterError(error)
        }
    }

    private static func missingPinningCapabilities(
        for adapter: any RuntimeAdapter
    ) -> [RuntimeAdapterRequiredCapability] {
        let capabilities = adapter.capabilities
        var missing: [RuntimeAdapterRequiredCapability] = []
        if !capabilities.readOnlyValidation {
            missing.append(.readOnlyValidation)
        }
        if !capabilities.exactPinning {
            missing.append(.exactPinning)
        }
        return missing
    }

    private static func mapAdapterError(_ error: RuntimeAdapterError) -> RuntimePinningError {
        switch error {
        case .unsupportedProvider(let provider):
            return .unsupportedProvider(provider)
        case .providerMismatch(let expected, let actual):
            return .providerMismatch(expected: expected, actual: actual)
        }
    }

    private static func mapSelectionFailure(
        _ failure: RuntimeSelectionRejection?,
        runtimeID: String
    ) -> RuntimePinningError {
        switch failure {
        case .installationNotFound:
            return .runtimeNotFound(runtimeID)
        case .notValidated:
            return .unvalidatedRuntime(runtimeID)
        case .unknownArchitecture, .rosettaNotAvailable, .architectureIncompatible:
            return .incompatibleRuntime(runtimeID, failure ?? .unknownArchitecture)
        case .noCandidates, .notExactInstallation, .notPreferredProvider, .lowerRanked:
            return .runtimeNotFound(runtimeID)
        case nil:
            return .runtimeNotFound(runtimeID)
        }
    }

    private static func mapValidationIssues(
        _ issues: [RuntimeAdapterValidationIssue],
        runtimeID: String,
        rejection: RuntimeSelectionRejection?
    ) -> RuntimePinningError {
        if let rejection, issues.contains(where: { $0.code == .architectureIncompatible }) {
            return .incompatibleRuntime(runtimeID, rejection)
        }
        if issues.contains(where: { $0.code == .architectureIncompatible || $0.code == .unknownArchitecture }) {
            return .incompatibleRuntime(runtimeID, rejection ?? .unknownArchitecture)
        }
        if issues.contains(where: { $0.code == .statusNotValidated }) {
            return .unvalidatedRuntime(runtimeID)
        }
        if issues.contains(where: {
            $0.code == .unsupportedInstallationShape || $0.code == .missingWineExecutable
        }) {
            return .invalidRuntimeInstallation(runtimeID, issues)
        }
        return .invalidRuntimeInstallation(runtimeID, issues)
    }
}
