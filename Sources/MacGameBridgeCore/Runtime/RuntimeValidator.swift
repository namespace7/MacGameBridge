import Foundation

/// Read-only validation of discovered runtime executables.
///
/// Validation inspects a file's metadata and Mach-O header without
/// executing the binary. This is the step between "detected" and
/// "launch-ready" — it proves the binary is structurally sound.
public enum RuntimeValidator {

    /// Result of validating a single executable.
    public struct ValidationResult: Equatable, Sendable {
        /// Whether the executable passes basic checks (exists, executable bit).
        public let isValid: Bool
        /// Mach-O architecture, if determinable.
        public let architecture: RuntimeArchitecture
        /// Human-readable messages.
        public let messages: [String]
    }

    /// Validate an executable at a given URL.
    ///
    /// - Parameter url: The file URL of the executable to inspect.
    /// - Returns: A `ValidationResult` describing the findings.
    ///
    /// This method never executes the binary. It uses:
    /// 1. `FileManager.isExecutableFile(atPath:)` — POSIX permission check.
    /// 2. `/usr/bin/file` — reads the Mach-O header (no execution).
    public static func validateExecutable(at url: URL) -> ValidationResult {
        let fm = FileManager.default
        var messages: [String] = []

        guard fm.isExecutableFile(atPath: url.path) else {
            return ValidationResult(
                isValid: false,
                architecture: .unknown,
                messages: ["File does not exist or is not executable"]
            )
        }
        messages.append("Executable exists and has the executable bit")

        let arch = detectArchitecture(at: url)
        messages.append("Architecture: \(arch.displayName)")

        return ValidationResult(
            isValid: arch != .unknown,
            architecture: arch,
            messages: messages
        )
    }

    // MARK: - Architecture detection

    /// Detect the Mach-O architecture of a binary using `/usr/bin/file`.
    ///
    /// The `file` command reads the Mach-O header without executing the binary.
    /// Example output:
    ///   `Mach-O 64-bit executable x86_64`
    ///   `Mach-O 64-bit executable arm64`
    ///   `Mach-O 64-bit executable x86_64 (libffi)`  (ignored trailing paren)
    ///
    /// For universal (fat) binaries the output contains both:
    ///   `Mach-O universal binary with 2 architectures: [x86_64, arm64]`
    public static func detectArchitecture(at url: URL) -> RuntimeArchitecture {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/file")
        process.arguments = ["-b", url.path]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8) else {
                return .unknown
            }

            return parseFileOutput(output)
        } catch {
            return .unknown
        }
    }

    /// Parse the output of `file -b <path>` to determine architecture.
    static func parseFileOutput(_ output: String) -> RuntimeArchitecture {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Universal / fat binary check first.
        if trimmed.localizedCaseInsensitiveContains("universal binary") {
            return .universal
        }

        // Check for individual architectures in the output line.
        let hasARM64 = trimmed.localizedCaseInsensitiveContains("arm64")
        let hasX8664 = trimmed.localizedCaseInsensitiveContains("x86_64")

        if hasARM64 && hasX8664 {
            return .universal
        }
        if hasARM64 {
            return .arm64
        }
        if hasX8664 {
            return .x8664
        }

        return .unknown
    }
}