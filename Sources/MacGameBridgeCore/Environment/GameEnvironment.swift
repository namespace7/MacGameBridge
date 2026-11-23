import Foundation

/// Lifecycle of a recorded game environment.
///
/// `planned` means only metadata has been recorded. `provisioned` is reserved
/// for environments with genuine successful provisioning evidence; this MVP
/// never creates or promotes an environment to that state.
public enum EnvironmentLifecycleState: String, Codable, Sendable {
    case planned = "planned"
    case provisioned = "provisioned"
}

/// A provider-independent record describing an intended isolated game environment.
///
/// The record is metadata only. In particular, `prefixURL` is an intended path:
/// its presence in this model is not evidence that a directory exists, that a
/// Wine prefix was initialized, or that a game can launch.
public struct GameEnvironment: Codable, Equatable, Identifiable, Sendable {
    /// Stable environment identifier assigned when the record is created.
    public let id: String
    /// The `GameProfile.id` this environment is intended for.
    public let gameProfileID: String
    /// The optional `ProviderInstallation.id` pinned for this environment.
    public let runtimeInstallationID: String?
    /// User-facing display name.
    public let name: String
    /// Intended prefix URL. Metadata only; no directory is created by the MVP.
    public let prefixURL: URL
    /// Current lifecycle state. MVP records are always `planned`.
    public let lifecycleState: EnvironmentLifecycleState
    public let createdAt: Date
    public let updatedAt: Date

    public var prefixPath: String { prefixURL.path }

    public init(
        id: String,
        gameProfileID: String,
        runtimeInstallationID: String? = nil,
        name: String,
        prefixURL: URL,
        lifecycleState: EnvironmentLifecycleState = .planned,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.gameProfileID = gameProfileID
        self.runtimeInstallationID = runtimeInstallationID
        self.name = name
        self.prefixURL = prefixURL
        self.lifecycleState = lifecycleState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
