import Foundation
import Metal

public enum Diagnostics {
    private static let dataVolume = "/System/Volumes/Data"

    public static func collect() -> DiagnosticReport {
        let host = HostInfo(
            architecture: command("/usr/bin/uname", ["-m"]) ?? "unknown",
            chip: detectChip(),
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            macOSVersion: command("/usr/bin/sw_vers", ["-productVersion"]) ?? "unknown",
            buildVersion: command("/usr/bin/sw_vers", ["-buildVersion"]) ?? "unknown"
        )

        let gpu = detectGPU()
        let rosetta = detectRosetta()
        let storage = detectStorage()
        let runtimes = RuntimeDiscovery.discover(paths: .current).legacyDetections

        return DiagnosticReport(
            schemaVersion: "1.0",
            generatedAt: Date(),
            host: host,
            gpu: gpu,
            rosetta: rosetta,
            storage: storage,
            runtimes: runtimes
        )
    }

    public static func printHumanReadable(_ report: DiagnosticReport) {
        print("MacGameBridge — Host diagnostics")
        print(String(repeating: "=", count: 38))
        print("Architecture      : \(report.host.architecture)")
        print("Chip              : \(report.host.chip)")
        print(String(format: "Physical memory   : %.1f GB", gb(report.host.physicalMemoryBytes)))
        print("macOS version     : \(report.host.macOSVersion)")
        print("Build             : \(report.host.buildVersion)")
        print("Rosetta           : \(report.rosetta.status) — \(report.rosetta.detail)")

        if report.gpu.available {
            print("GPU               : \(report.gpu.name ?? "Available")")
            print("Unified memory    : \(report.gpu.hasUnifiedMemory.map(String.init) ?? "unknown")")
            if let bytes = report.gpu.recommendedMaxWorkingSetBytes {
                print(String(format: "GPU working set   : %.1f GB (recommended maximum)", gb(bytes)))
            }
        } else {
            print("GPU               : No Metal device detected")
        }

        print(String(format: "Storage total     : %@", formatBytes(report.storage.totalBytes)))
        print(String(format: "Storage available : %@", formatBytes(report.storage.availableBytes)))
        print("Storage volume    : \(report.storage.volume)")

        print("\nCompatibility runtimes (presence only; not launch-tested):")
        for runtime in report.runtimes {
            let evidence = runtime.evidence.map { " — \($0)" } ?? ""
            print("  \(runtime.name): \(runtime.status)\(evidence)")
        }
    }

    private static func detectGPU() -> GPUInfo {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return GPUInfo(
                available: false,
                name: nil,
                hasUnifiedMemory: nil,
                recommendedMaxWorkingSetBytes: nil
            )
        }

        return GPUInfo(
            available: true,
            name: device.name,
            hasUnifiedMemory: device.hasUnifiedMemory,
            recommendedMaxWorkingSetBytes: device.recommendedMaxWorkingSetSize
        )
    }

    private static func detectRosetta() -> RosettaInfo {
        guard let output = command("/usr/bin/arch", ["-x86_64", "/usr/bin/uname", "-m"]) else {
            return RosettaInfo(
                status: "not_verified",
                translatedArchitecture: nil,
                detail: "The x86_64 execution probe failed."
            )
        }

        let translated = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return RosettaInfo(
            status: translated == "x86_64" ? "verified" : "not_verified",
            translatedArchitecture: translated,
            detail: translated == "x86_64"
                ? "An x86_64 macOS process executed successfully."
                : "The probe returned an unexpected architecture."
        )
    }

    private static func detectStorage() -> StorageInfo {
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: dataVolume)
        let total = (attributes?[.systemSize] as? NSNumber)?.uint64Value
        let available = (attributes?[.systemFreeSize] as? NSNumber)?.uint64Value

        return StorageInfo(
            volume: dataVolume,
            totalBytes: total,
            availableBytes: available
        )
    }

    private static func detectChip() -> String {
        guard let output = command("/usr/sbin/system_profiler", ["SPHardwareDataType"]) else {
            return "unknown"
        }

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.localizedCaseInsensitiveContains("Chip:") {
                return trimmed
                    .replacingOccurrences(of: "Chip:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return "unknown"
    }

    private static func command(_ executable: String, _ arguments: [String]) -> String? {
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

    private static func gb(_ bytes: UInt64) -> Double {
        Double(bytes) / 1_073_741_824
    }

    private static func formatBytes(_ bytes: UInt64?) -> String {
        guard let bytes else { return "unavailable" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(clamping: bytes))
    }
}
