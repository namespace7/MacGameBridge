import Foundation

// MARK: - Rosetta verification status

/// Verification state of Rosetta 2 x86_64 translation on this host.
///
/// The raw values match the long-standing `DiagnosticReport.rosetta.status`
/// vocabulary so diagnostics output and JSON remain unchanged.
public enum RosettaVerificationStatus: String, Codable, Sendable {
    /// An x86_64 macOS process executed successfully via the translation probe.
    case verified
    /// The probe failed or returned an unexpected architecture.
    ///
    /// This is **not** proof that Rosetta is absent — only that this process
    /// could not positively verify it.
    case notVerified = "not_verified"
    /// Rosetta 2 translation is not applicable on this host.
    ///
    /// The detector emits this only when the native host is already x86_64,
    /// where Rosetta 2 is unnecessary by definition. It is never inferred from
    /// a failed or unexpected translation probe on an ARM64 host.
    case unavailable
}

extension RosettaVerificationStatus: CustomStringConvertible {
    public var description: String { rawValue }
}

// MARK: - Host capabilities

/// Read-only host facts needed to select a compatible runtime.
///
/// This type deliberately carries no selection logic. It is the boundary
/// between host probing (which may run system commands) and the pure
/// `RuntimeSelector` engine.
public struct HostCapabilities: Codable, Equatable, Sendable {
    /// Native host architecture, mapped from the raw `uname -m` string.
    public let nativeArchitecture: RuntimeArchitecture
    /// Raw architecture string reported by `uname -m` (or "unknown" on failure).
    public let architectureDetail: String
    /// Rosetta translation verification state.
    public let rosettaStatus: RosettaVerificationStatus
    /// Human-readable explanation of the Rosetta verification result.
    public let rosettaDetail: String
    /// Architecture reported by the translated probe, when it returned one.
    public let translatedArchitecture: String?

    public init(
        nativeArchitecture: RuntimeArchitecture,
        architectureDetail: String,
        rosettaStatus: RosettaVerificationStatus,
        rosettaDetail: String,
        translatedArchitecture: String?
    ) {
        self.nativeArchitecture = nativeArchitecture
        self.architectureDetail = architectureDetail
        self.rosettaStatus = rosettaStatus
        self.rosettaDetail = rosettaDetail
        self.translatedArchitecture = translatedArchitecture
    }

    /// A request for the pure selector.
    ///
    /// Only a positively `verified` Rosetta probe maps to `true`. A
    /// `not_verified` result is treated conservatively as "do not assume
    /// translation is usable", never as verified availability.
    public var selectionRequest: RuntimeSelectionRequest {
        RuntimeSelectionRequest(
            hostArchitecture: nativeArchitecture,
            rosettaAvailable: rosettaStatus == .verified,
            allowFallback: true
        )
    }

    /// The existing diagnostics Rosetta model, for schema-compatible reuse.
    public var rosettaInfo: RosettaInfo {
        RosettaInfo(
            status: rosettaStatus.rawValue,
            translatedArchitecture: translatedArchitecture,
            detail: rosettaDetail
        )
    }
}

// MARK: - Injectable system command execution

/// A minimal seam for running the read-only system probes used by host
/// detection. Tests supply a fake so they never rely on the developer's Mac.
public protocol SystemCommandExecuting: Sendable {
    /// Run a system command and return trimmed standard output, or nil when
    /// the command failed, produced no UTF-8 output, or exited nonzero.
    func execute(_ executable: String, _ arguments: [String]) -> String?
}

/// Production command runner. Only standard macOS system binaries are used;
/// no Wine, runtime, or game binary is ever executed.
public struct SystemCommandRunner: SystemCommandExecuting {
    public init() {}

    public func execute(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}

// MARK: - Detection

public protocol HostCapabilitiesDetecting: Sendable {
    func detect() -> HostCapabilities
}

/// Detects native architecture and Rosetta verification using the same
/// probes historically used by `Diagnostics`:
///
/// - Native architecture: `/usr/bin/uname -m`
/// - Rosetta (ARM64 hosts only): `/usr/bin/arch -x86_64 /usr/bin/uname -m`
///
/// The native architecture is always detected first. The translated probe is
/// only meaningful on an ARM64 host — on Intel it can succeed natively and
/// would be a false Rosetta verification, so it is never run there. Both
/// probes are read-only. The translated probe executes the standard macOS
/// `uname` binary under Rosetta; it never executes a runtime or game.
public struct HostCapabilitiesDetector: HostCapabilitiesDetecting {
    private let runner: SystemCommandExecuting

    public init(runner: SystemCommandExecuting = SystemCommandRunner()) {
        self.runner = runner
    }

    public func detect() -> HostCapabilities {
        // 1. Detect the native architecture first.
        let rawArchitecture = runner.execute("/usr/bin/uname", ["-m"])
        let architectureDetail = rawArchitecture ?? "unknown"
        let nativeArchitecture = Self.mapArchitecture(rawArchitecture)

        // 2. Only a native ARM64 host needs (and can meaningfully report)
        //    Rosetta translation verification.
        let rosetta: (status: RosettaVerificationStatus, translatedArchitecture: String?, detail: String)
        switch nativeArchitecture {
        case .arm64:
            rosetta = detectRosetta()
        case .x8664:
            // Rosetta 2 is not used on Intel. Do not even attempt the
            // translated probe: `arch -x86_64 uname -m` can succeed natively
            // here and would falsely report Rosetta as verified.
            rosetta = (
                .unavailable,
                nil,
                "Rosetta 2 is not applicable on an Intel x86_64 host."
            )
        case .unknown, .universal:
            // An unknown architecture is not evidence of Rosetta. Never run
            // the translated probe or report a positive result here.
            rosetta = (
                .notVerified,
                nil,
                "Rosetta verification was not attempted because the native host architecture is unknown."
            )
        }

        return HostCapabilities(
            nativeArchitecture: nativeArchitecture,
            architectureDetail: architectureDetail,
            rosettaStatus: rosetta.status,
            rosettaDetail: rosetta.detail,
            translatedArchitecture: rosetta.translatedArchitecture
        )
    }

    /// Maps a raw `uname -m` string onto the selector's architecture model.
    /// Unknown or unrecognised values map to `.unknown` so the selector can
    /// reject them rather than guessing.
    static func mapArchitecture(_ raw: String?) -> RuntimeArchitecture {
        guard let raw else { return .unknown }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "arm64", "aarch64":
            return .arm64
        case "x86_64", "x86-64", "amd64":
            return .x8664
        default:
            return .unknown
        }
    }

    private func detectRosetta() -> (status: RosettaVerificationStatus, translatedArchitecture: String?, detail: String) {
        guard let output = runner.execute("/usr/bin/arch", ["-x86_64", "/usr/bin/uname", "-m"]) else {
            return (
                .notVerified,
                nil,
                "The x86_64 execution probe failed."
            )
        }

        let translated = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if translated == "x86_64" {
            return (
                .verified,
                translated,
                "An x86_64 macOS process executed successfully."
            )
        }

        return (
            .notVerified,
            translated,
            "The probe returned an unexpected architecture."
        )
    }
}
