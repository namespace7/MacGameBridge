import Foundation

// MARK: - Structured report

/// A read-only, explainable report combining host capabilities, runtime
/// discovery, and the pure selector's decision.
///
/// The report contains no launch configuration and performs no execution.
public struct RuntimeSelectionIntegrationReport: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let generatedAt: Date
    public let host: HostCapabilities
    public let scanReport: RuntimeProviderReport
    public let selection: RuntimeSelectionResult

    public init(
        schemaVersion: String = "1.0",
        generatedAt: Date = Date(),
        host: HostCapabilities,
        scanReport: RuntimeProviderReport,
        selection: RuntimeSelectionResult
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.host = host
        self.scanReport = scanReport
        self.selection = selection
    }
}

// MARK: - Integration service

/// Wires host detection, read-only runtime discovery, and `RuntimeSelector`
/// together without duplicating any selection or ranking logic.
public enum RuntimeSelectionIntegration {

    /// Build a report from already-detected host facts and an existing scan.
    ///
    /// This is the pure entry point for tests and for callers that already
    /// own a scan report. It always uses `RuntimeSelectionPolicy.automatic`.
    public static func makeReport(
        host: HostCapabilities,
        scanReport: RuntimeProviderReport,
        policy: RuntimeSelectionPolicy = .automatic,
        generatedAt: Date = Date()
    ) -> RuntimeSelectionIntegrationReport {
        let result = RuntimeSelector.select(
            from: scanReport.installations,
            policy: policy,
            request: host.selectionRequest
        )
        return RuntimeSelectionIntegrationReport(
            generatedAt: generatedAt,
            host: host,
            scanReport: scanReport,
            selection: result
        )
    }

    /// Production entry point: detect the current host, scan the current
    /// search roots, and select the best eligible runtime.
    ///
    /// Both the detector and scanner are injectable so this path remains
    /// independently testable; the defaults are the real host detector and
    /// `RuntimeScanner.scan(paths: .current)`.
    public static func collect(
        policy: RuntimeSelectionPolicy = .automatic,
        detector: HostCapabilitiesDetecting = HostCapabilitiesDetector(),
        scanner: (RuntimeScanner.SearchPaths) -> RuntimeProviderReport = { RuntimeScanner.scan(paths: $0) }
    ) -> RuntimeSelectionIntegrationReport {
        let host = detector.detect()
        let scanReport = scanner(.current)
        return makeReport(host: host, scanReport: scanReport, policy: policy)
    }

    // MARK: - Human-readable presentation

    /// Print a human-readable explanation of a selection report.
    public static func printHumanReadable(_ report: RuntimeSelectionIntegrationReport) {
        print("MacGameBridge — Runtime selection")
        print(String(repeating: "=", count: 38))
        print("Mode: read-only; no runtime or game binary was launched.\n")

        print("Host architecture       : \(report.host.nativeArchitecture.rawValue) (uname: \(report.host.architectureDetail))")
        print("Rosetta verification    : \(report.host.rosettaStatus.rawValue) — \(report.host.rosettaDetail)")

        print("\nDiscovered candidates:")
        if report.scanReport.installations.isEmpty {
            print("  No runtime installations were discovered.")
        } else {
            for installation in report.scanReport.installations {
                print("  \(installation.displayName) [\(installation.provider.rawValue)]")
                print("    ID:           \(installation.id)")
                print("    Status:       \(installation.status.rawValue)")
                print("    Architecture: \(installation.architecture.displayName)")
            }
        }

        print("\nSelection result:")
        if let selected = report.selection.selected {
            print("  Selected runtime: \(selected.displayName) [\(selected.provider.rawValue)]")
            print("  Path:             \(selected.path)")
        } else {
            print("  No eligible runtime was selected.")
        }
        print("  Reason: \(report.selection.selectionReason)")

        if let failure = report.selection.failure {
            print("  Failure: \(failure.description)")
        }

        let rejections = report.selection.evaluations.filter { !$0.accepted && $0.rejection != nil }
        if rejections.isEmpty {
            print("\nCandidate rejections: none.")
        } else {
            print("\nCandidate rejections:")
            for evaluation in rejections {
                let reason = evaluation.rejection?.description ?? "unknown"
                print("  \(evaluation.installation.id) — \(reason)")
            }
        }

        print("""
\nImportant: validation inspects file metadata without running any binary.
A validated runtime is not proof that a specific game will launch or work.
MacGameBridge never installs software, modifies bottles, downloads games, or
bypasses DRM/anti-cheat.
""")
    }
}
