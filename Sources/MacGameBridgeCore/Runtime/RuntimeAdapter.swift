import Foundation

/// Operations an adapter is willing to perform in the current milestone.
///
/// Provisioning and launch configuration are modelled explicitly so future
/// milestones can add implementations without moving provider-specific logic
/// into `EnvironmentCLI`. Both are `false` for every M3.1 adapter: pinning a
/// runtime is metadata only and is not evidence that a game can launch.
public struct RuntimeAdapterCapabilities: Codable, Equatable, Sendable {
    /// Read-only validation of a discovered installation against host facts.
    public let readOnlyValidation: Bool
    /// Eligibility for an exact `ProviderInstallation.id` pin.
    public let exactPinning: Bool
    /// Reserved for future milestones. Always false in M3.1.
    public let provisioning: Bool
    /// Reserved for future milestones. Always false in M3.1.
    public let launchConfiguration: Bool

    public init(
        readOnlyValidation: Bool = false,
        exactPinning: Bool = false,
        provisioning: Bool = false,
        launchConfiguration: Bool = false
    ) {
        self.readOnlyValidation = readOnlyValidation
        self.exactPinning = exactPinning
        self.provisioning = provisioning
        self.launchConfiguration = launchConfiguration
    }

    /// Capabilities implemented by the M3.1 Wine adapter.
    public static let validationAndPinning = RuntimeAdapterCapabilities(
        readOnlyValidation: true,
        exactPinning: true
    )

    /// Capabilities of an adapter stub that cannot do any work.
    public static let none = RuntimeAdapterCapabilities()
}

/// Capabilities exact pinning requires before an adapter may validate an
/// installation.
public enum RuntimeAdapterRequiredCapability: String, Codable, Sendable {
    case readOnlyValidation
    case exactPinning
}

/// Structured reason an adapter considers an installation ineligible.
public enum RuntimeAdapterValidationIssueCode: String, Codable, Sendable {
    /// The installation's provider does not match the adapter's provider.
    case providerMismatch
    /// The installation shape is not supported by this provider's adapter
    /// (for example, a standalone Wine installation carrying an app bundle).
    case unsupportedInstallationShape
    /// No usable Wine executable path was discovered.
    case missingWineExecutable
    /// The installation has not passed the existing read-only scanner validation.
    case statusNotValidated
    /// The executable architecture could not be determined.
    case unknownArchitecture
    /// The architecture is incompatible with the injected host capabilities.
    case architectureIncompatible
}

/// One structured, human-explainable validation finding.
public struct RuntimeAdapterValidationIssue: Codable, Equatable, Sendable {
    public let code: RuntimeAdapterValidationIssueCode
    public let message: String

    public init(code: RuntimeAdapterValidationIssueCode, message: String) {
        self.code = code
        self.message = message
    }
}

/// The result of validating one `ProviderInstallation` against a host.
///
/// `isEligible` is true only when no blocking issues were found. Validation is
/// read-only: it never executes a runtime binary and never touches a prefix.
public struct RuntimeAdapterValidationResult: Codable, Equatable, Sendable {
    public let providerID: RuntimeProviderID
    public let installationID: String
    public let isEligible: Bool
    public let architecture: RuntimeArchitecture
    public let issues: [RuntimeAdapterValidationIssue]

    /// The structured architecture rejection from the existing selection engine,
    /// when one was produced. Nil for a compatible architecture.
    public let architectureRejection: RuntimeSelectionRejection?

    public init(
        providerID: RuntimeProviderID,
        installationID: String,
        isEligible: Bool,
        architecture: RuntimeArchitecture,
        issues: [RuntimeAdapterValidationIssue],
        architectureRejection: RuntimeSelectionRejection? = nil
    ) {
        self.providerID = providerID
        self.installationID = installationID
        self.isEligible = isEligible
        self.architecture = architecture
        self.issues = issues
        self.architectureRejection = architectureRejection
    }
}

/// Errors thrown by adapter lookup or by an adapter called with a mismatched
/// installation. Ordinary validation findings are returned in
/// `RuntimeAdapterValidationResult`.
public enum RuntimeAdapterError: Error, Equatable, CustomStringConvertible, Sendable {
    /// No adapter is registered for the requested provider.
    case unsupportedProvider(RuntimeProviderID)
    /// An adapter was given an installation from a different provider.
    case providerMismatch(expected: RuntimeProviderID, actual: RuntimeProviderID)

    public var description: String {
        switch self {
        case .unsupportedProvider(let provider):
            return "No runtime adapter is registered for provider '\(provider.rawValue)'. Only standalone Wine has an adapter in M3.1."
        case .providerMismatch(let expected, let actual):
            return "Runtime adapter for '\(expected.rawValue)' cannot validate an installation from provider '\(actual.rawValue)'."
        }
    }
}

/// Provider-independent runtime adapter contract.
///
/// The protocol deliberately exposes only read-only validation in M3.1. Future
/// provisioning and launch operations can be introduced as protocol extensions
/// with explicit unsupported defaults, keeping provider decisions in adapters
/// rather than in the CLI parser or environment commands.
public protocol RuntimeAdapter: Sendable {
    /// The provider this adapter supports.
    var providerID: RuntimeProviderID { get }
    /// What this adapter can do. M3.1 adapters never report provisioning or launch.
    var capabilities: RuntimeAdapterCapabilities { get }

    /// Validate a discovered installation against injected host capabilities.
    ///
    /// This method inspects already-discovered metadata only. It does not run
    /// `/usr/bin/file`, execute a binary, create a prefix, or modify any file.
    func validate(
        _ installation: ProviderInstallation,
        host: HostCapabilities
    ) throws -> RuntimeAdapterValidationResult
}
