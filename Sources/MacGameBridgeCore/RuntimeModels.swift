import Foundation

/// The compatibility runtimes currently recognized by MacGameBridge.
public enum RuntimeKind: String, Codable, CaseIterable, Sendable {
    case crossover
    case whisky
    case wine
    case gamePortingToolkit = "game_porting_toolkit"

    public var displayName: String {
        switch self {
        case .crossover: return "CrossOver"
        case .whisky: return "Whisky"
        case .wine: return "Wine"
        case .gamePortingToolkit: return "Game Porting Toolkit"
        }
    }
}

/// Discovery is evidence of presence only; it does not imply that a runtime launches.
public enum RuntimeDetectionStatus: String, Codable, Sendable {
    case detectedUnverified = "detected_unverified"
    case notDetected = "not_detected"
}

public enum RuntimeDetectionMethod: String, Codable, Sendable {
    case applicationBundle = "application_bundle"
    case pathExecutable = "path_executable"
}

/// One independently discovered app bundle or command-line executable.
public struct RuntimeInstallation: Codable, Equatable, Identifiable, Sendable {
    public let runtime: RuntimeKind
    public let path: String
    public let version: String?
    public let detectionMethod: RuntimeDetectionMethod
    public let evidence: [String]

    public var id: String { "\(runtime.rawValue):\(path)" }

    public init(
        runtime: RuntimeKind,
        path: String,
        version: String? = nil,
        detectionMethod: RuntimeDetectionMethod,
        evidence: [String] = []
    ) {
        self.runtime = runtime
        self.path = path
        self.version = version
        self.detectionMethod = detectionMethod
        self.evidence = evidence
    }
}

/// A finding is emitted for every supported runtime, including runtimes not found.
public struct RuntimeFinding: Codable, Equatable, Sendable {
    public let runtime: RuntimeKind
    public let status: RuntimeDetectionStatus
    public let installations: [RuntimeInstallation]

    public init(runtime: RuntimeKind, installations: [RuntimeInstallation]) {
        self.runtime = runtime
        self.installations = installations
        self.status = installations.isEmpty ? .notDetected : .detectedUnverified
    }
}

public struct RuntimeDiscoveryReport: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let generatedAt: Date
    public let findings: [RuntimeFinding]

    public init(
        schemaVersion: String = "1.0",
        generatedAt: Date = Date(),
        findings: [RuntimeFinding]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.findings = findings
    }

    /// Adapts the richer M2 inventory to the stable M1 diagnostics JSON shape.
    public var legacyDetections: [RuntimeDetection] {
        findings.map { finding in
            RuntimeDetection(
                name: finding.runtime.displayName,
                status: finding.status.rawValue,
                evidence: finding.installations.first?.path
            )
        }
    }
}

/// Search roots are injectable so discovery can be tested without relying on the host.
public struct RuntimeDiscoveryPaths: Equatable, Sendable {
    public let applicationDirectories: [URL]
    public let executableDirectories: [URL]

    public init(applicationDirectories: [URL], executableDirectories: [URL]) {
        self.applicationDirectories = applicationDirectories.map(\.standardizedFileURL)
        self.executableDirectories = executableDirectories.map(\.standardizedFileURL)
    }

    public static var current: RuntimeDiscoveryPaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let applicationDirectories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Setapp", isDirectory: true),
            home.appendingPathComponent("Applications/Setapp", isDirectory: true)
        ]

        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let executableDirectories = pathValue
            .split(separator: ":", omittingEmptySubsequences: true)
            .map { URL(fileURLWithPath: String($0), isDirectory: true) }

        return RuntimeDiscoveryPaths(
            applicationDirectories: applicationDirectories,
            executableDirectories: executableDirectories
        )
    }
}
