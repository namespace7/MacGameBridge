import Foundation

/// Read-only scanner that discovers and validates runtime installations
/// across multiple providers.
///
/// ## Design
/// - Reuses M2.1 `RuntimeDiscovery` to find app bundles and PATH executables.
/// - Enriches M2.1 findings with provider-specific wine executable paths
///   inside wrapper bundles.
/// - Validates discovered executables using `RuntimeValidator` (no execution).
/// - Search roots are injectable for deterministic test behaviour.
///
/// ## Limitations
/// - Does not scan the entire disk. Only searches configured roots.
/// - Does not execute any runtime binary.
/// - Does not create or modify Wine prefixes or CrossOver bottles.
public enum RuntimeScanner {

    /// Search roots for scanner discovery.
    /// Extends the M2.1 `RuntimeDiscoveryPaths` with provider-specific paths.
    public struct SearchPaths: Equatable, Sendable {
        /// Directories to scan for `.app` bundles.
        public let applicationDirectories: [URL]
        /// Directories to scan for PATH executables.
        public let executableDirectories: [URL]
        /// Explicit bundle URLs to scan (for testing or custom paths).
        /// Each URL is classified against the correct provider using
        /// bundle name prefix matching — a CrossOver.app is not scanned
        /// as Whisky.
        public let explicitBundleURLs: [URL]

        public init(
            applicationDirectories: [URL],
            executableDirectories: [URL],
            explicitBundleURLs: [URL] = []
        ) {
            self.applicationDirectories = applicationDirectories.map(\.standardizedFileURL)
            self.executableDirectories = executableDirectories.map(\.standardizedFileURL)
            self.explicitBundleURLs = explicitBundleURLs
        }

        /// Construct search paths from the current host environment.
        public static var current: SearchPaths {
            let m2Paths = RuntimeDiscoveryPaths.current
            return SearchPaths(
                applicationDirectories: m2Paths.applicationDirectories,
                executableDirectories: m2Paths.executableDirectories
            )
        }
    }

    /// Scan for all supported runtime providers.
    ///
    /// - Parameters:
    ///   - paths: Search roots. Supply `SearchPaths.current` in production.
    ///   - validate: If true, discovered executables are architecture-validated
    ///     using `RuntimeValidator`. Defaults to `true`.
    ///   - fileManager: Injectable file manager.
    /// - Returns: A `RuntimeProviderReport` with all discovered installations.
    public static func scan(
        paths: SearchPaths,
        validate: Bool = true,
        fileManager: FileManager = .default
    ) -> RuntimeProviderReport {
        var installations: [ProviderInstallation] = []

        for provider in RuntimeProvider.all {
            let installationsForProvider = scanProvider(
                provider,
                paths: paths,
                validate: validate,
                fileManager: fileManager
            )
            installations.append(contentsOf: installationsForProvider)
        }

        return RuntimeProviderReport(installations: installations)
    }

    // MARK: - Provider scanning

    private static func scanProvider(
        _ provider: RuntimeProvider,
        paths: SearchPaths,
        validate: Bool,
        fileManager: FileManager
    ) -> [ProviderInstallation] {
        switch provider.kind {
        case .standalone:
            return scanStandalone(provider, paths: paths, validate: validate, fileManager: fileManager)
        case .wrapper:
            let discovered = scanWrappers(provider, paths: paths, validate: validate, fileManager: fileManager)
            let explicit = scanExplicitBundles(
                provider, paths: paths, validate: validate, fileManager: fileManager
            )
            return discovered + explicit
        }
    }

    // MARK: - Standalone (Wine)

    private static func scanStandalone(
        _ provider: RuntimeProvider,
        paths: SearchPaths,
        validate: Bool,
        fileManager: FileManager
    ) -> [ProviderInstallation] {
        let names = RuntimeProvider.wineExecutableNames(for: provider.id)
        guard !names.isEmpty else { return [] }

        var installations: [ProviderInstallation] = []

        for directory in paths.executableDirectories {
            for name in names {
                let candidate = directory.appendingPathComponent(name, isDirectory: false)
                guard fileManager.isExecutableFile(atPath: candidate.path) else { continue }

                let resolved = candidate.resolvingSymlinksInPath()

                // Skip executables that resolve inside a CrossOver bundle
                // (they are not standalone Wine installations).
                if provider.id == .wine && isInsideCrossOverBundle(resolved) {
                    continue
                }

                var evidence: [String] = [
                    "Executable found in PATH directory: \(directory.path)"
                ]
                let resolvedPath = resolved.standardizedFileURL.path
                if resolvedPath != candidate.standardizedFileURL.path {
                    evidence.append("Resolved symlink to: \(resolvedPath)")
                }

                var arch: RuntimeArchitecture = .unknown
                if validate {
                    let result = RuntimeValidator.validateExecutable(at: resolved)
                    arch = result.architecture
                    evidence.append(contentsOf: result.messages)
                }

                let status: RuntimeInstallationStatus = validate && arch != .unknown
                    ? .validated
                    : .detected

                installations.append(ProviderInstallation(
                    provider: provider.id,
                    displayName: provider.displayName,
                    wineExecutableURL: resolved.standardizedFileURL,
                    architecture: arch,
                    status: status,
                    evidence: evidence
                ))
            }
        }

        return installations
    }

    // MARK: - Wrappers (CrossOver, Whisky, Sikarugir)

    /// Scan application directories for bundles matching this provider's name prefixes.
    private static func scanWrappers(
        _ provider: RuntimeProvider,
        paths: SearchPaths,
        validate: Bool,
        fileManager: FileManager
    ) -> [ProviderInstallation] {
        let bundleURLs = discoverWrapperBundles(provider: provider, paths: paths, fileManager: fileManager)
        return bundleURLs.compactMap { bundleURL in
            scanWrapperBundle(
                provider: provider,
                bundleURL: bundleURL,
                validate: validate,
                fileManager: fileManager
            )
        }
    }

    /// Scan explicit bundle URLs, classifying each against the correct provider
    /// using bundle name prefix matching. A CrossOver.app supplied as an explicit
    /// URL will be classified as CrossOver, not Whisky or Sikarugir.
    private static func scanExplicitBundles(
        _ provider: RuntimeProvider,
        paths: SearchPaths,
        validate: Bool,
        fileManager: FileManager
    ) -> [ProviderInstallation] {
        let prefixes = RuntimeProvider.bundleNamePrefixes(for: provider.id)
        guard !prefixes.isEmpty else { return [] }

        let matchingBundles = paths.explicitBundleURLs.filter { bundleURL in
            let bundleName = bundleURL.deletingPathExtension().lastPathComponent.lowercased()
            return prefixes.contains(where: { bundleName.hasPrefix($0) })
        }

        return matchingBundles.compactMap { bundleURL in
            scanWrapperBundle(
                provider: provider,
                bundleURL: bundleURL,
                validate: validate,
                fileManager: fileManager
            )
        }
    }

    private static func discoverWrapperBundles(
        provider: RuntimeProvider,
        paths: SearchPaths,
        fileManager: FileManager
    ) -> [URL] {
        let prefixes = RuntimeProvider.bundleNamePrefixes(for: provider.id)
        guard !prefixes.isEmpty else { return [] }

        var found: [URL] = []

        for directory in paths.applicationDirectories {
            guard let children = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children where child.pathExtension.lowercased() == "app" {
                let bundleName = child.deletingPathExtension().lastPathComponent.lowercased()
                guard prefixes.contains(where: { bundleName.hasPrefix($0) }) else { continue }
                found.append(child)
            }
        }

        return found
    }

    private static func scanWrapperBundle(
        provider: RuntimeProvider,
        bundleURL: URL,
        validate: Bool,
        fileManager: FileManager
    ) -> ProviderInstallation? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: bundleURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        var evidence: [String] = ["Application bundle found at: \(bundleURL.path)"]

        // Read Info.plist for version metadata.
        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        let info = readPropertyListSafely(at: infoURL, fileManager: fileManager)
        let version: String?
        if let info, !info.exceededSizeLimit, !info.parseFailed {
            version = (info.value as? [String: Any])?["CFBundleShortVersionString"] as? String
                ?? (info.value as? [String: Any])?["CFBundleVersion"] as? String
            if let bundleID = (info.value as? [String: Any])?["CFBundleIdentifier"] as? String {
                evidence.append("Bundle identifier: \(bundleID)")
            }
            if let v = version {
                evidence.append("Version: \(v)")
            }
        } else if let info, info.exceededSizeLimit {
            evidence.append("Info.plist exceeds size limit; version unavailable")
            version = nil
        } else {
            version = nil
        }

        // Discover and resolve Wine executable inside the bundle.
        let winePaths = RuntimeProvider.wineExecutableRelativePaths(for: provider.id)
        let wineResult = findResolvedExecutable(
            in: bundleURL, relativePaths: winePaths, fileManager: fileManager
        )
        let wineURL = wineResult?.resolved

        // Discover and resolve wineserver executable inside the bundle.
        let serverPaths = RuntimeProvider.wineserverExecutableRelativePaths(for: provider.id)
        let serverResult = findResolvedExecutable(
            in: bundleURL, relativePaths: serverPaths, fileManager: fileManager
        )
        let serverURL = serverResult?.resolved

        if let result = wineResult {
            evidence.append("Wine executable: \(result.original.path)")
            if result.resolved.path != result.original.path {
                evidence.append("Wine executable resolved to: \(result.resolved.path)")
            }
        } else {
            evidence.append("No Wine executable found inside this wrapper bundle")
        }
        if let result = serverResult {
            evidence.append("Wineserver executable: \(result.original.path)")
            if result.resolved.path != result.original.path {
                evidence.append("Wineserver executable resolved to: \(result.resolved.path)")
            }
        }

        // Validate wine executable if present.
        var arch: RuntimeArchitecture = .unknown
        if validate, let wineURL {
            let result = RuntimeValidator.validateExecutable(at: wineURL)
            arch = result.architecture
            evidence.append(contentsOf: result.messages)
        }

        // Determine status.
        let hasWine = wineURL != nil
        let status: RuntimeInstallationStatus
        if !hasWine {
            status = .detected  // wrapper exists but no wine engine found
        } else if validate && arch != .unknown {
            status = .validated
        } else {
            status = .detected
        }

        return ProviderInstallation(
            provider: provider.id,
            displayName: provider.displayName,
            bundleURL: bundleURL.standardizedFileURL,
            wineExecutableURL: wineURL?.standardizedFileURL,
            wineserverExecutableURL: serverURL?.standardizedFileURL,
            version: version,
            architecture: arch,
            status: status,
            evidence: evidence
        )
    }

    // MARK: - Helpers

    /// Result of finding and resolving an executable within a bundle.
    private struct ResolvedExecutableResult {
        /// The original (unresolved) URL inside the bundle.
        let original: URL
        /// The symlink-resolved URL.
        let resolved: URL
    }

    /// Find the first executable matching a set of relative paths,
    /// resolve symlinks, and verify the resolved target is executable.
    ///
    /// Returns nil when no candidate exists or when the resolved target
    /// is not executable. Broken symlinks are handled gracefully.
    private static func findResolvedExecutable(
        in bundleURL: URL,
        relativePaths: [[String]],
        fileManager: FileManager
    ) -> ResolvedExecutableResult? {
        for components in relativePaths {
            let candidate = components.reduce(bundleURL) { $0.appendingPathComponent($1, isDirectory: false) }
            guard fileManager.fileExists(atPath: candidate.path) else { continue }

            let resolved = candidate.resolvingSymlinksInPath()

            // Verify the resolved target is executable.
            guard fileManager.isExecutableFile(atPath: resolved.path) else { continue }

            return ResolvedExecutableResult(original: candidate, resolved: resolved)
        }
        return nil
    }

    /// Returns true when the resolved URL has an exact "CrossOver.app" path component.
    private static func isInsideCrossOverBundle(_ url: URL) -> Bool {
        for component in url.pathComponents.reversed() {
            let asNSString = component as NSString
            guard asNSString.pathExtension.lowercased() == "app" else { continue }
            if asNSString.deletingPathExtension.lowercased() == "crossover" {
                return true
            }
        }
        return false
    }

    // MARK: - Bounded plist reading (ported from M2.1)

    private struct PlistReadResult {
        let value: Any?
        let exceededSizeLimit: Bool
        let parseFailed: Bool
    }

    private static let maxPlistBytes: UInt64 = 1_048_577

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

        let fileSize = (try? handle.seekToEnd()) ?? 0
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
}