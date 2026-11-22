import Foundation

enum Diagnostics {
    static func run() {
        print("MacGameBridge — Host diagnostics")
        print(String(repeating: "=", count: 38))

        let architecture = run("/usr/bin/uname", ["-m"]) ?? "Unavailable"
        let productVersion = run("/usr/bin/sw_vers", ["-productVersion"]) ?? "Unavailable"
        let buildVersion = run("/usr/bin/sw_vers", ["-buildVersion"]) ?? "Unavailable"
        let chip = run("/usr/sbin/system_profiler", ["SPHardwareDataType"])?
            .components(separatedBy: "\n")
            .first(where: { $0.localizedCaseInsensitiveContains("Chip:") })?
            .trimmingCharacters(in: .whitespaces) ?? "Not detected"
        let memoryBytes = ProcessInfo.processInfo.physicalMemory
        let memoryGB = Double(memoryBytes) / 1_073_741_824
        let disk = run("/bin/df", ["-h", "/System/Volumes/Data"]) ?? "Unavailable"
        let translatedArchitecture = run("/usr/bin/arch", ["-x86_64", "/usr/bin/uname", "-m"])
        let rosettaStatus = translatedArchitecture == "x86_64" ? "Available (x86_64 test passed)" : "Not verified (x86_64 test failed)"

        print("Host architecture : \(architecture)")
        print("Chip              : \(chip)")
        print(String(format: "Physical memory   : %.1f GB", memoryGB))
        print("macOS version     : \(productVersion)")
        print("Build             : \(buildVersion)")
        print("Rosetta           : \(rosettaStatus)")
        print("\nData volume:")
        print(disk)
        print("\nNote: GPU/Metal details and exact free-space parsing will be added in a later diagnostic module.")
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
