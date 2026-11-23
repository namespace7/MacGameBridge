import Foundation

/// A stable identifier for each supported runtime provider.
///
/// Each provider maps to a specific Windows-compatibility distribution
/// that MacGameBridge can discover, validate, and later manage.
public enum RuntimeProviderID: String, Codable, CaseIterable, Sendable {
    /// Standalone Wine installed via Homebrew, MacPorts, or direct build.
    case wine
    /// CrossOver by CodeWeavers.
    case crossover
    /// Whisky — legacy/deprecated wrapper. Discovery only.
    case whisky
    /// Sikarugir or Wineskin-style wrapper bundles.
    case sikarugir
}

/// Classification of how a runtime is distributed.
public enum RuntimeProviderKind: String, Codable, Sendable {
    /// A command-line executable installed directly into PATH
    /// (e.g., Homebrew Wine).
    case standalone
    /// An `.app` bundle that wraps a Wine engine distribution
    /// (e.g., CrossOver, Whisky, Sikarugir).
    case wrapper
}

/// Metadata for a supported runtime provider.
public struct RuntimeProvider: Codable, Equatable, Sendable {
    public let id: RuntimeProviderID
    public let displayName: String
    public let kind: RuntimeProviderKind

    public init(id: RuntimeProviderID, kind: RuntimeProviderKind) {
        self.id = id
        self.kind = kind
        switch id {
        case .wine:
            self.displayName = "Wine"
        case .crossover:
            self.displayName = "CrossOver"
        case .whisky:
            self.displayName = "Whisky"
        case .sikarugir:
            self.displayName = "Sikarugir / Wineskin"
        }
    }

    /// All known providers.
    public static let all: [RuntimeProvider] = [
        RuntimeProvider(id: .wine, kind: .standalone),
        RuntimeProvider(id: .crossover, kind: .wrapper),
        RuntimeProvider(id: .whisky, kind: .wrapper),
        RuntimeProvider(id: .sikarugir, kind: .wrapper),
    ]

    // MARK: - Internal discovery helpers

    /// App bundle name prefixes for wrapper-type providers.
    /// Used by the existing M2.1 bundle-scanning logic.
    static func bundleNamePrefixes(for id: RuntimeProviderID) -> [String] {
        switch id {
        case .crossover:
            return ["crossover"]
        case .whisky:
            return ["whisky"]
        case .sikarugir:
            return ["sikarugir", "wineskin"]
        case .wine:
            return []
        }
    }

    /// Wine executable names for PATH-based discovery (standalone Wine).
    static func wineExecutableNames(for id: RuntimeProviderID) -> [String] {
        switch id {
        case .wine:
            return ["wine", "wine64"]
        case .crossover, .whisky, .sikarugir:
            return []
        }
    }

    /// Relative paths to look for the `wine` (or `wine64`) executable
    /// inside a discovered wrapper bundle.
    static func wineExecutableRelativePaths(for id: RuntimeProviderID) -> [[String]] {
        switch id {
        case .crossover:
            return [
                ["Contents", "SharedSupport", "CrossOver", "bin", "wine64"],
                ["Contents", "SharedSupport", "CrossOver", "bin", "wine"],
            ]
        case .whisky:
            return [
                ["Contents", "SharedSupport", "wine", "bin", "wine64"],
                ["Contents", "SharedSupport", "wine", "bin", "wine"],
            ]
        case .sikarugir:
            return [
                ["Contents", "Resources", "wine", "bin", "wine64"],
                ["Contents", "Resources", "wine", "bin", "wine"],
            ]
        case .wine:
            return []
        }
    }

    /// Relative paths to look for the `wineserver` executable
    /// inside a discovered wrapper bundle.
    static func wineserverExecutableRelativePaths(for id: RuntimeProviderID) -> [[String]] {
        switch id {
        case .crossover:
            return [
                ["Contents", "SharedSupport", "CrossOver", "bin", "wineserver"],
            ]
        case .whisky:
            return [
                ["Contents", "SharedSupport", "wine", "bin", "wineserver"],
            ]
        case .sikarugir:
            return [
                ["Contents", "Resources", "wine", "bin", "wineserver"],
            ]
        case .wine:
            return []
        }
    }
}