import Foundation
import Testing

@testable import MacGameBridgeCore

// MARK: - Architecture detection tests

@Test
func parsesARM64Architecture() {
    let result = RuntimeValidator.parseFileOutput("Mach-O 64-bit executable arm64")
    #expect(result == .arm64)
}

@Test
func parsesX8664Architecture() {
    let result = RuntimeValidator.parseFileOutput("Mach-O 64-bit executable x86_64")
    #expect(result == .x8664)
}

@Test
func parsesUniversalArchitecture() {
    let result = RuntimeValidator.parseFileOutput("Mach-O universal binary with 2 architectures: [x86_64:arm64]")
    #expect(result == .universal)
}

@Test
func parsesUnknownArchitecture() {
    let result = RuntimeValidator.parseFileOutput("Mach-O 64-bit executable ppc")
    #expect(result == .unknown)
}

@Test
func parsesEmptyOutputAsUnknown() {
    let result = RuntimeValidator.parseFileOutput("")
    #expect(result == .unknown)
}

// MARK: - Standalone Wine discovery

@Test
func discoversStandaloneWineExecutable() throws {
    try withTemporaryDirectory { root in
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let wine = bin.appendingPathComponent("wine64")
        try makeExecutable(at: wine)

        let paths = RuntimeScanner.SearchPaths(
            applicationDirectories: [],
            executableDirectories: [bin]
        )
        let report = RuntimeScanner.scan(paths: paths, validate: false)

        let wineInstallations = report.installations.filter { $0.provider == .wine }
        #expect(wineInstallations.count == 1)
        #expect(wineInstallations.first?.status == .detected)
        #expect(wineInstallations.first?.wineExecutableURL?.path == wine.path)
    }
}

@Test
func discoversStandaloneWineWithSymlinkResolution() throws {
    try withTemporaryDirectory { root in
        let realDir = root.appendingPathComponent("real", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let realWine = realDir.appendingPathComponent("wine64")
        try makeExecutable(at: realWine)

        let symlink = bin.appendingPathComponent("wine64")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: realWine)

        let paths = RuntimeScanner.SearchPaths(
            applicationDirectories: [],
            executableDirectories: [bin]
        )
        let report = RuntimeScanner.scan(paths: paths, validate: false)

        let wineInstallations = report.installations.filter { $0.provider == .wine }
        #expect(wineInstallations.count == 1)
        // The resolved URL should point to the real file.
        #expect(wineInstallations.first?.wineExecutableURL?.path == realWine.path)
    }
}

// MARK: - Wrapper bundle discovery

@Test
func discoversCrossOverWrapperBundle() throws {
    try withTemporaryDirectory { root in
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)

        let crossOver = applications.appendingPathComponent("CrossOver.app", isDirectory: true)
        try makeAppBundle(at: crossOver, bundleIdentifier: "com.codeweavers.CrossOver", version: "25.1")

        // Add a wine executable inside the bundle.
        let wineExec = crossOver.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine64")
        try FileManager.default.createDirectory(
            at: wineExec.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try makeExecutable(at: wineExec)

        let paths = RuntimeScanner.SearchPaths(
            applicationDirectories: [applications],
            executableDirectories: []
        )
        let report = RuntimeScanner.scan(paths: paths, validate: false)

        let crossOverInstallations = report.installations.filter { $0.provider == .crossover }
        #expect(crossOverInstallations.count == 1)

        let installation = try #require(crossOverInstallations.first)
        #expect(installation.status == .detected)
        #expect(installation.bundleURL?.path == crossOver.path)
        #expect(installation.wineExecutableURL?.path == wineExec.path)
        #expect(installation.version == "25.1")
    }
}

@Test
func discoversWhiskyWrapperBundle() throws {
    try withTemporaryDirectory { root in
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)

        let whisky = applications.appendingPathComponent("Whisky.app", isDirectory: true)
        try makeAppBundle(at: whisky, bundleIdentifier: "com.isaacmarovitz.Whisky", version: "2.3.1")

        // Whisky stores wine in Contents/SharedSupport/wine/bin/
        let wineExec = whisky.appendingPathComponent("Contents/SharedSupport/wine/bin/wine64")
        try FileManager.default.createDirectory(
            at: wineExec.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try makeExecutable(at: wineExec)

        let paths = RuntimeScanner.SearchPaths(
            applicationDirectories: [applications],
            executableDirectories: []
        )
        let report = RuntimeScanner.scan(paths: paths, validate: false)

        let whiskyInstallations = report.installations.filter { $0.provider == .whisky }
        #expect(whiskyInstallations.count == 1)

        let installation = try #require(whiskyInstallations.first)
        #expect(installation.bundleURL?.path == whisky.path)
        #expect(installation.wineExecutableURL?.path == wineExec.path)
        #expect(installation.version == "2.3.1")
    }
}

@Test
func discoversSikarugirWrapperBundle() throws {
    try withTemporaryDirectory { root in
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)

        // Sikarugir-app or Wineskin.app
        let sikarugir = applications.appendingPathComponent("Sikarugir.app", isDirectory: true)
        try makeAppBundle(at: sikarugir, bundleIdentifier: "com.sikarugir.Sikarugir", version: "1.0")

        // Sikarugir stores wine in Contents/Resources/wine/bin/
        let wineExec = sikarugir.appendingPathComponent("Contents/Resources/wine/bin/wine64")
        try FileManager.default.createDirectory(
            at: wineExec.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try makeExecutable(at: wineExec)

        let paths = RuntimeScanner.SearchPaths(
            applicationDirectories: [applications],
            executableDirectories: []
        )
        let report = RuntimeScanner.scan(paths: paths, validate: false)

        let sikarugirInstallations = report.installations.filter { $0.provider == .sikarugir }
        #expect(sikarugirInstallations.count == 1)

        let installation = try #require(sikarugirInstallations.first)
        #expect(installation.bundleURL?.path == sikarugir.path)
        #expect(installation.wineExecutableURL?.path == wineExec.path)
    }
}

@Test
func discoversWineskinBundleViaAlternatePrefix() throws {
    try withTemporaryDirectory { root in
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)

        // Wineskin.app should also match the sikarugir provider.
        let wineskin = applications.appendingPathComponent("Wineskin.app", isDirectory: true)
        try makeAppBundle(at: wineskin, bundleIdentifier: "com.wineskin.Wineskin", version: "2.0")

        let wineExec = wineskin.appendingPathComponent("Contents/Resources/wine/bin/wine64")
        try FileManager.default.createDirectory(
            at: wineExec.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try makeExecutable(at: wineExec)

        let paths = RuntimeScanner.SearchPaths(
            applicationDirectories: [applications],
            executableDirectories: []
        )
        let report = RuntimeScanner.scan(paths: paths, validate: false)

        let sikarugirInstallations = report.installations.filter { $0.provider == .sikarugir }
        #expect(sikarugirInstallations.count == 1)
    }
}

// MARK: - Wrapper without Wine engine

@Test
func wrapperWithoutWineExecutableIsDetectedButNotValidated() throws {
    try withTemporaryDirectory { root in
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)

        // CrossOver.app exists but has no wine inside.
        let crossOver = applications.appendingPathComponent("CrossOver.app", isDirectory: true)
        try makeAppBundle(at: crossOver, bundleIdentifier: "com.codeweavers.CrossOver", version: "25.1")

        let paths = RuntimeScanner.SearchPaths(
            applicationDirectories: [applications],
            executableDirectories: []
        )
        let report = RuntimeScanner.scan(paths: paths, validate: true)

        let crossOverInstallations = report.installations.filter { $0.provider == .crossover }
        #expect(crossOverInstallations.count == 1)

        let installation = try #require(crossOverInstallations.first)
        // The bundle exists but wine was not found.
        #expect(installation.status == .detected)
        #expect(installation.wineExecutableURL == nil)
        #expect(installation.architecture == .unknown)
        let evidence = installation.evidence.joined(separator: " ")
        #expect(evidence.localizedCaseInsensitiveContains("No Wine executable"))
    }
}

// MARK: - Non-executable file

@Test
func nonExecutableFileIsNotDiscoveredAsStandalone() throws {
    try withTemporaryDirectory { root in
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let wine = bin.appendingPathComponent("wine64")
        // Write the file but do NOT set the executable bit.
        try Data("not an executable".utf8).write(to: wine)

        let paths = RuntimeScanner.SearchPaths(
            applicationDirectories: [],
            executableDirectories: [bin]
        )
        let report = RuntimeScanner.scan(paths: paths, validate: false)

        let wineInstallations = report.installations.filter { $0.provider == .wine }
        #expect(wineInstallations.isEmpty)
    }
}

// MARK: - Empty search roots

@Test
func emptySearchRootsProduceNoInstallations() throws {
    try withTemporaryDirectory { root in
        let emptyApps = root.appendingPathComponent("Applications", isDirectory: true)
        let emptyBin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyApps, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: emptyBin, withIntermediateDirectories: true)

        let paths = RuntimeScanner.SearchPaths(
            applicationDirectories: [emptyApps],
            executableDirectories: [emptyBin]
        )
        let report = RuntimeScanner.scan(paths: paths, validate: false)

        #expect(report.installations.isEmpty)
    }
}

// MARK: - Malformed bundle metadata

@Test
func malformedBundleMetadataDoesNotCrashScanner() throws {
    try withTemporaryDirectory { root in
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)

        let crossOver = applications.appendingPathComponent("CrossOver.app", isDirectory: true)
        let contents = crossOver.appendingPathComponent("Contents", isDirectory: true)
        let macos = contents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)

        // Write garbage as Info.plist
        let infoURL = contents.appendingPathComponent("Info.plist")
        let garbage = Data("this is not a valid plist at all".utf8)
        try garbage.write(to: infoURL)

        // Add wine executable (so validation can proceed).
        let wineExec = crossOver.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine64")
        try FileManager.default.createDirectory(
            at: wineExec.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try makeExecutable(at: wineExec)

        let paths = RuntimeScanner.SearchPaths(
            applicationDirectories: [applications],
            executableDirectories: []
        )

        // This must not throw.
        let report = RuntimeScanner.scan(paths: paths, validate: false)

        let crossOverInstallations = report.installations.filter { $0.provider == .crossover }
        #expect(crossOverInstallations.count == 1)
        // Version should be nil because plist could not be parsed.
        #expect(crossOverInstallations.first?.version == nil)
    }
}

// MARK: - No binary execution during scan

@Test
func scannerDoesNotExecuteAnyBinary() throws {
    try withTemporaryDirectory { root in
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        // Create a sentinel that would be written if our wine is executed.
        let sentinelURL = root.appendingPathComponent(".sentinel")
        let wine = bin.appendingPathComponent("wine64")
        // The "executable" is a script that creates the sentinel file.
        try Data("#!/bin/sh\ntouch '\(sentinelURL.path)'\n".utf8).write(to: wine)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)

        let paths = RuntimeScanner.SearchPaths(
            applicationDirectories: [],
            executableDirectories: [bin]
        )
        _ = RuntimeScanner.scan(paths: paths, validate: false)

        // The sentinel must NOT exist.
        #expect(!FileManager.default.fileExists(atPath: sentinelURL.path))
    }
}

// MARK: - Multiple providers

@Test
func discoversMultipleProvidersSimultaneously() throws {
    try withTemporaryDirectory { root in
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        // CrossOver.app with wine
        let crossOver = applications.appendingPathComponent("CrossOver.app", isDirectory: true)
        try makeAppBundle(at: crossOver, bundleIdentifier: "com.codeweavers.CrossOver", version: "25.0")
        let crossWine = crossOver.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine64")
        try FileManager.default.createDirectory(
            at: crossWine.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try makeExecutable(at: crossWine)

        // Standalone wine in PATH
        let standaloneWine = bin.appendingPathComponent("wine64")
        try makeExecutable(at: standaloneWine)

        let paths = RuntimeScanner.SearchPaths(
            applicationDirectories: [applications],
            executableDirectories: [bin]
        )
        let report = RuntimeScanner.scan(paths: paths, validate: false)

        // CrossOver detected
        let crossOverInstallations = report.installations.filter { $0.provider == .crossover }
        #expect(crossOverInstallations.count == 1)

        // Standalone Wine detected but CrossOver's bundled wine excluded
        let wineInstallations = report.installations.filter { $0.provider == .wine }
        #expect(wineInstallations.count == 1)
        #expect(wineInstallations.first?.wineExecutableURL?.path == standaloneWine.path)

        // Whisky and Sikarugir not found
        let whiskyInstallations = report.installations.filter { $0.provider == .whisky }
        #expect(whiskyInstallations.isEmpty)

        let sikarugirInstallations = report.installations.filter { $0.provider == .sikarugir }
        #expect(sikarugirInstallations.isEmpty)
    }
}

// MARK: - Explicit bundle URLs

@Test
func discoversExplicitBundleURLs() throws {
    try withTemporaryDirectory { root in
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)

        // A bundle at a non-standard location.
        let custom = root.appendingPathComponent("Custom/CrossOver.app", isDirectory: true)
        try makeAppBundle(at: custom, bundleIdentifier: "com.codeweavers.CrossOver", version: "25.0")
        let wineExec = custom.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine64")
        try FileManager.default.createDirectory(
            at: wineExec.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try makeExecutable(at: wineExec)

        // Standard search directories do NOT include the Custom directory.
        let paths = RuntimeScanner.SearchPaths(
            applicationDirectories: [applications],
            executableDirectories: [],
            explicitBundleURLs: [custom]
        )
        let report = RuntimeScanner.scan(paths: paths, validate: false)

        let crossOverInstallations = report.installations.filter { $0.provider == .crossover }
        #expect(crossOverInstallations.count == 1)
        #expect(crossOverInstallations.first?.bundleURL?.path == custom.path)
    }
}

// MARK: - Explicit bundle provider classification

@Test
func explicitCrossOverBundleIsNotClassifiedAsWhiskyOrSikarugir() throws {
    try withTemporaryDirectory { root in
        // An explicit CrossOver.app at a non-standard location.
        let custom = root.appendingPathComponent("Custom/CrossOver.app", isDirectory: true)
        try makeAppBundle(at: custom, bundleIdentifier: "com.codeweavers.CrossOver", version: "25.0")
        let wineExec = custom.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine64")
        try FileManager.default.createDirectory(
            at: wineExec.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try makeExecutable(at: wineExec)

        // Only supply the CrossOver URL; no application directories overlap.
        let emptyApps = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyApps, withIntermediateDirectories: true)

        let paths = RuntimeScanner.SearchPaths(
            applicationDirectories: [emptyApps],
            executableDirectories: [],
            explicitBundleURLs: [custom]
        )
        let report = RuntimeScanner.scan(paths: paths, validate: false)

        // CrossOver must be detected.
        let crossOverInstallations = report.installations.filter { $0.provider == .crossover }
        #expect(crossOverInstallations.count == 1)
        #expect(crossOverInstallations.first?.bundleURL?.path == custom.path)

        // Whisky and Sikarugir must NOT be detected — the explicit URL was
        // classified as CrossOver only.
        let whiskyInstallations = report.installations.filter { $0.provider == .whisky }
        #expect(whiskyInstallations.isEmpty)

        let sikarugirInstallations = report.installations.filter { $0.provider == .sikarugir }
        #expect(sikarugirInstallations.isEmpty)
    }
}

@Test
func explicitBundleURLDoesNotMatchAnyProviderPrefix() throws {
    try withTemporaryDirectory { root in
        // An app bundle that does not match any known provider prefix.
        let unknown = root.appendingPathComponent("Unknown.app", isDirectory: true)
        try makeAppBundle(at: unknown, bundleIdentifier: "com.unknown.Unknown", version: "1.0")

        let emptyApps = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyApps, withIntermediateDirectories: true)

        let paths = RuntimeScanner.SearchPaths(
            applicationDirectories: [emptyApps],
            executableDirectories: [],
            explicitBundleURLs: [unknown]
        )
        let report = RuntimeScanner.scan(paths: paths, validate: false)

        // No provider should detect the unknown bundle.
        #expect(report.installations.isEmpty)
    }
}

// MARK: - Wrapper executable symlink handling

@Test
func wrapperWithSymlinkedWineExecutableResolvesAndRecordsEvidence() throws {
    try withTemporaryDirectory { root in
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)

        let crossOver = applications.appendingPathComponent("CrossOver.app", isDirectory: true)
        try makeAppBundle(at: crossOver, bundleIdentifier: "com.codeweavers.CrossOver", version: "25.1")

        // Place the real wine binary outside the bundle.
        let realWineDir = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: realWineDir, withIntermediateDirectories: true)
        let realWine = realWineDir.appendingPathComponent("wine64")
        try makeExecutable(at: realWine)

        // Create a symlink inside the bundle pointing to the real wine.
        let wineSymlink = crossOver.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine64")
        try FileManager.default.createDirectory(
            at: wineSymlink.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: wineSymlink, withDestinationURL: realWine)

        let paths = RuntimeScanner.SearchPaths(
            applicationDirectories: [applications],
            executableDirectories: []
        )
        let report = RuntimeScanner.scan(paths: paths, validate: false)

        let crossOverInstallations = report.installations.filter { $0.provider == .crossover }
        #expect(crossOverInstallations.count == 1)

        let installation = try #require(crossOverInstallations.first)
        // The wineExecutableURL should be the resolved (real) path.
        #expect(installation.wineExecutableURL?.path == realWine.path)

        let evidence = installation.evidence.joined(separator: " ")
        #expect(evidence.localizedCaseInsensitiveContains("resolved to"))
    }
}

@Test
func wrapperWithBrokenWineSymlinkHandledGracefully() throws {
    try withTemporaryDirectory { root in
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)

        let crossOver = applications.appendingPathComponent("CrossOver.app", isDirectory: true)
        try makeAppBundle(at: crossOver, bundleIdentifier: "com.codeweavers.CrossOver", version: "25.1")

        // Create a broken symlink where the wine binary should be.
        let wineSymlink = crossOver.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine64")
        try FileManager.default.createDirectory(
            at: wineSymlink.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Target does not exist.
        let missingTarget = root.appendingPathComponent("nonexistent/wine64")
        try FileManager.default.createSymbolicLink(at: wineSymlink, withDestinationURL: missingTarget)

        let paths = RuntimeScanner.SearchPaths(
            applicationDirectories: [applications],
            executableDirectories: []
        )
        let report = RuntimeScanner.scan(paths: paths, validate: false)

        let crossOverInstallations = report.installations.filter { $0.provider == .crossover }
        #expect(crossOverInstallations.count == 1)

        let installation = try #require(crossOverInstallations.first)
        // The broken symlink should not be treated as a valid wine executable.
        #expect(installation.wineExecutableURL == nil)
        #expect(installation.status == .detected)

        let evidence = installation.evidence.joined(separator: " ")
        #expect(evidence.localizedCaseInsensitiveContains("No Wine executable"))
    }
}

// MARK: - Helpers

private func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacGameBridgeRuntimeScanner-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
}

private func makeAppBundle(
    at url: URL,
    bundleIdentifier: String,
    version: String
) throws {
    let contents = url.appendingPathComponent("Contents", isDirectory: true)
    let executableDirectory = contents.appendingPathComponent("MacOS", isDirectory: true)
    try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)

    let info: [String: String] = [
        "CFBundleIdentifier": bundleIdentifier,
        "CFBundleShortVersionString": version,
        "CFBundleExecutable": "RuntimeTestStub"
    ]
    let data = try PropertyListSerialization.data(
        fromPropertyList: info,
        format: .xml,
        options: 0
    )
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    try makeExecutable(at: executableDirectory.appendingPathComponent("RuntimeTestStub"))
}

private func makeExecutable(at url: URL) throws {
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: url.path
    )
}