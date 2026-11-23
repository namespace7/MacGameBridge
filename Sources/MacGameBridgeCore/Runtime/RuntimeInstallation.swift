import Foundation

/// The detection or validation status of a runtime installation.
///
/// This is deliberately separate from `RuntimeDetectionStatus` in the M2.1 model
/// because M2.2 adds the `validated` state after architecture inspection.
public enum RuntimeInstallationStatus: String, Codable, Sendable {
    /// The runtime was not found in the searched locations.
    case notDetected = "not_detected"
    /// The runtime was found but not yet validated.
    case detected = "detected"
    /// The runtime was found, its executable exists, has the executable bit,
    /// and its Mach-O architecture was inspected successfully.
    case validated = "validated"
}

/// A discovered and optionally validated provider-backed runtime installation.
///
/// Distinct from the M2.1 `RuntimeInstallation` (in `RuntimeModels.swift`) which
/// is a simpler flat path-based model. This type carries provider identity,
/// discovered executable URLs, architecture, and validation status.
public struct ProviderInstallation: Codable, Equatable, Identifiable, Sendable {
    public let provider: RuntimeProviderID
    public let displayName: String

    /// The application bundle URL, if this is a wrapper-type installation.
    public let bundleURL: URL?

    /// Discovered wine executable URL, if found.
    public let wineExecutableURL: URL?

    /// Discovered wineserver executable URL, if found.
    public let wineserverExecutableURL: URL?

    /// Version string from the bundle Info.plist (wrappers) or nil (standalone).
    public let version: String?

    /// Mach-O architecture of the wine executable, if inspected.
    public let architecture: RuntimeArchitecture

    /// Current detection/validation status.
    public let status: RuntimeInstallationStatus

    /// Human-readable evidence strings.
    public let evidence: [String]

    public var id: String { "\(provider.rawValue):\(path)" }

    /// The primary path for display/identification purposes.
    public var path: String {
        bundleURL?.path ?? wineExecutableURL?.path ?? "(unknown)"
    }

    public init(
        provider: RuntimeProviderID,
        displayName: String,
        bundleURL: URL? = nil,
        wineExecutableURL: URL? = nil,
        wineserverExecutableURL: URL? = nil,
        version: String? = nil,
        architecture: RuntimeArchitecture = .unknown,
        status: RuntimeInstallationStatus,
        evidence: [String]
    ) {
        self.provider = provider
        self.displayName = displayName
        self.bundleURL = bundleURL
        self.wineExecutableURL = wineExecutableURL
        self.wineserverExecutableURL = wineserverExecutableURL
        self.version = version
        self.architecture = architecture
        self.status = status
        self.evidence = evidence
    }
}

/// The complete result of a provider scan.
public struct RuntimeProviderReport: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let generatedAt: Date
    public let installations: [ProviderInstallation]

    public init(
        schemaVersion: String = "2.0",
        generatedAt: Date = Date(),
        installations: [ProviderInstallation]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.installations = installations
    }
}