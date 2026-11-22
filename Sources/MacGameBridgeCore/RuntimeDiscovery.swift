import Foundation

/// Read-only discovery of known compatibility runtime app bundles and PATH commands.
/// No runtime is launched, installed, updated, or modified by this type.
public enum RuntimeDiscovery {
    private static let appPrefixes: [RuntimeKind: [String]] = [
        .crossover: ["crossover"],
        .whisky: ["whisky"],
        .gamePortingToolkit: ["game porting toolkit"]
    ]

    private static let executableNames: [RuntimeKind: [String]] = [
        .wine: ["wine", "wine64"],
        .gamePortingToolkit: ["gameportingtoolkit", "gameportingtoolkit-no-hud"]
    ]

    /// Maximum bytes to read from an Info.plist file. Files larger than this
    /// are treated as unreadable and the installation version is set to nil.
    /// The 1 MiB + 1 byte boundary is enforced at the FileHandle read level.
    private static let maxPlistBytes: UInt64 = 1_048_577  // 1 MiB + 1

    /// Discover known compatibility runtimes by inspecting app bundles and
    /// executable search paths.
    ///
    /// - Parameter paths: Search roots. Production code should supply
    ///   `RuntimeDiscoveryPaths.current`. Tests must supply explicit temporary
    ///   paths to avoid depending on the developer's real PATH or installed
    ///   applications.
    ///
    /// Discovery iterates the children of each application directory and each
    /// executable directory in the configured PATH. On networks with slow mounts
    /// or very large directories this may introduce latency. No caching is
    /// performed — every call re-scans the search roots.
    public static func discover(
        paths: RuntimeDiscoveryPaths,
        fileManager: FileManager = .default
    ) -> RuntimeDiscoveryReport {
        let findings = RuntimeKind.allCases.map { runtime in
            let appInstallations = discoverAppBundles(
                for: runtime,
                in: paths.applicationDirectories,
                fileManager: fileManager
            )
            let executableInstallations = discoverExecutables(
                for: runtime,
                in: paths.executableDirectories,
                fileManager: fileManager
            )
            let installations = uniqueInstallations(appInstallations + executableInstallations)
            return RuntimeFinding(runtime: runtime, installations: installations)
        }

        return RuntimeDiscoveryReport(findings: findings)
    }

    public static func printHumanReadable(_ report: RuntimeDiscoveryReport) {
        print("MacGameBridge — Runtime discovery")
        print(String(repeating: "=", count: 38))
        print("Mode: read-only; no runtime was launched or modified.\n")

        for finding in report.findings {
            print("\(finding.runtime.displayName): \(finding.status.rawValue)")
            if finding.installations.isEmpty {
                print("  No installation found in the searched locations.")
                continue
            }

            for installation in finding.installations {
                print("  Path: \(installation.path)")
                print("  Detection: \(installation.detectionMethod.rawValue)")
                print("  Version: \(installation.version ?? "not read")")
                for item in installation.evidence {
                    print("  Evidence: \(item)")
                }
            }
        }

        print("\nImportant: detection does not prove that a runtime can launch a game.")
    }

    // MARK: - App bundle discovery

    private static func discoverAppBundles(
        for runtime: RuntimeKind,
        in directories: [URL],
        fileManager: FileManager
    ) -> [RuntimeInstallation] {
        guard let prefixes = appPrefixes[runtime] else { return [] }
        var installations: [RuntimeInstallation] = []

        for directory in directories {
            guard let children = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for child in children where child.pathExtension.lowercased() == "app" {
                let bundleName = child.deletingPathExtension().lastPathComponent.lowercased()
                guard prefixes.contains(where: { bundleName.hasPrefix($0) }) else { continue }
                guard let installation = appInstallation(
                    runtime: runtime,
                    bundleURL: child,
                    fileManager: fileManager
                ) else {
                    continue
                }
                installations.append(installation)
            }
        }

        return installations
    }

    private static func appInstallation(
        runtime: RuntimeKind,
        bundleURL: URL,
        fileManager: FileManager
    ) -> RuntimeInstallation? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: bundleURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        let info = readPropertyListSafely(at: infoURL, fileManager: fileManager)
        let version = (info?.value as? [String: Any])?["CFBundleShortVersionString"] as? String
            ?? (info?.value as? [String: Any])?["CFBundleVersion"] as? String
        let bundleIdentifier = (info?.value as? [String: Any])?["CFBundleIdentifier"] as? String
        let executableName = (info?.value as? [String: Any])?["CFBundleExecutable"] as? String

        var evidence = ["Application bundle directory exists"]
        if let bundleIdentifier {
            evidence.append("Bundle identifier: \(bundleIdentifier)")
        }

        if let plistReadInfo = info {
            if plistReadInfo.exceededSizeLimit {
                evidence.append("Info.plist exceeds \(maxPlistBytes) byte read limit")
            } else if plistReadInfo.parseFailed {
                evidence.append("Info.plist could not be parsed")
            }
        }

        if let executableName, !executableName.isEmpty {
            let executableURL = bundleURL
                .appendingPathComponent("Contents/MacOS", isDirectory: true)
                .appendingPathComponent(executableName)
            if fileManager.isExecutableFile(atPath: executableURL.path) {
                evidence.append("Bundle executable exists and is executable")
            } else {
                evidence.append("Bundle executable was not found or is not executable")
            }
        }

        return RuntimeInstallation(
            runtime: runtime,
            path: bundleURL.standardizedFileURL.path,
            version: version,
            detectionMethod: .applicationBundle,
            evidence: evidence
        )
    }

    // MARK: - Executable discovery

    private static func discoverExecutables(
        for runtime: RuntimeKind,
        in directories: [URL],
        fileManager: FileManager
    ) -> [RuntimeInstallation] {
        guard let names = executableNames[runtime] else { return [] }
        var installations: [RuntimeInstallation] = []

        for directory in directories {
            for name in names {
                let candidate = directory.appendingPathComponent(name, isDirectory: false)
                guard fileManager.isExecutableFile(atPath: candidate.path) else { continue }

                // Resolve symlinks before checking bundle ancestry.
                let resolved = candidate.resolvingSymlinksInPath()
                let resolvedPath = resolved.standardizedFileURL.path

                // CrossOver ships its own Wine components. Do not mislabel them as
                // a separately installed standalone Wine runtime when exposed in PATH.
                if runtime == .wine && isInsideCrossOverBundle(resolved) {
                    continue
                }

                installations.append(RuntimeInstallation(
                    runtime: runtime,
                    path: candidate.standardizedFileURL.path,
                    version: nil,
                    detectionMethod: .pathExecutable,
                    evidence: [
                        "Executable file found in PATH search directory",
                        "Resolved path: \(resolvedPath)"
                    ]
                ))
            }
        }

        return installations
    }

    // MARK: - CrossOver bundle detection

    /// Returns true when `url` (symlink-resolved) has a path component whose
    /// stem (case-insensitive) is exactly "CrossOver" and whose extension is ".app".
    /// This prevents false matches on similarly-named bundles such as
    /// "CrossoverHelper.app".
    private static func isInsideCrossOverBundle(_ url: URL) -> Bool {
        for component in url.pathComponents.reversed() {
            let asNSString = component as NSString
            let ext = asNSString.pathExtension.lowercased()
            guard ext == "app" else { continue }
            let stem = asNSString.deletingPathExtension
            if stem.lowercased() == "crossover" {
                return true
            }
        }
        return false
    }

    // MARK: - Bounded plist reading

    /// Result of a bounded Info.plist read.
    private struct PlistReadResult {
        /// The parsed property list dictionary, or nil if it could not be read/parsed.
        let value: Any?
        /// True when the file exceeded the size limit.
        let exceededSizeLimit: Bool
        /// True when the file was within the size limit but could not be parsed.
        let parseFailed: Bool
    }

    /// Read an Info.plist with a hard byte limit of `maxPlistBytes`.
    /// Uses FileHandle to avoid loading oversized files into memory.
    /// The installation remains valid (with nil version) when the file is
    /// too large or unparseable.
    private static func readPropertyListSafely(
        at url: URL,
        fileManager: FileManager
    ) -> PlistReadResult? {
        guard fileManager.isReadableFile(atPath: url.path) else { return nil }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            return nil
        }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: Int(maxPlistBytes)) else {
            return nil
        }

        // Determine whether the file exceeds the read limit by seeking to the end.
        let fileSize = (try? handle.seekToEnd()) ?? 0
        // Reset offset to beginning for any future reads (not used, but clean).
        try? handle.seek(toOffset: 0)
        let exceededSizeLimit = fileSize > maxPlistBytes

        if exceededSizeLimit {
            return PlistReadResult(
                value: nil,
                exceededSizeLimit: true,
                parseFailed: false
            )
        }

        guard let parsed = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            return PlistReadResult(
                value: nil,
                exceededSizeLimit: false,
                parseFailed: true
            )
        }

        return PlistReadResult(
            value: parsed,
            exceededSizeLimit: false,
            parseFailed: false
        )
    }

    // MARK: - Deduplication

    private static func uniqueInstallations(_ installations: [RuntimeInstallation]) -> [RuntimeInstallation] {
        var seen = Set<String>()
        return installations.filter { seen.insert($0.id).inserted }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}