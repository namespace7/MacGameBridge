import Foundation
import Testing

@testable import MacGameBridgeCore

// MARK: - Existing tests (preserved)

@Test
func discoversRuntimeBundlesAndExecutablesWithoutLaunchingThem() throws {
    try withTemporaryDirectory { root in
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let crossOver = applications.appendingPathComponent("CrossOver.app", isDirectory: true)
        let whisky = applications.appendingPathComponent("Whisky.app", isDirectory: true)
        try makeAppBundle(
            at: crossOver,
            bundleIdentifier: "com.codeweavers.CrossOver",
            version: "25.1"
        )
        try makeAppBundle(
            at: whisky,
            bundleIdentifier: "com.isaacmarovitz.Whisky",
            version: "2.3.1"
        )

        let wine = bin.appendingPathComponent("wine64")
        let gamePortingToolkit = bin.appendingPathComponent("gameportingtoolkit")
        try makeExecutable(at: wine)
        try makeExecutable(at: gamePortingToolkit)

        let paths = RuntimeDiscoveryPaths(
            applicationDirectories: [applications],
            executableDirectories: [bin]
        )
        let report = RuntimeDiscovery.discover(paths: paths)

        let crossOverFinding = try #require(report.findings.first { $0.runtime == .crossover })
        #expect(crossOverFinding.status == .detectedUnverified)
        #expect(crossOverFinding.installations.first?.version == "25.1")

        let whiskyFinding = try #require(report.findings.first { $0.runtime == .whisky })
        #expect(whiskyFinding.status == .detectedUnverified)
        #expect(whiskyFinding.installations.first?.version == "2.3.1")

        let wineFinding = try #require(report.findings.first { $0.runtime == .wine })
        #expect(wineFinding.installations.count == 1)
        #expect(wineFinding.installations.first?.path == wine.path)
        #expect(wineFinding.installations.first?.version == nil)

        let toolkitFinding = try #require(report.findings.first { $0.runtime == .gamePortingToolkit })
        #expect(toolkitFinding.status == .detectedUnverified)
        #expect(toolkitFinding.installations.contains { $0.path == gamePortingToolkit.path })
    }
}

@Test
func doesNotCountCrossOverBundledWineAsStandaloneWine() throws {
    try withTemporaryDirectory { root in
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let crossOver = applications.appendingPathComponent("CrossOver.app", isDirectory: true)
        let bundledWine = crossOver.appendingPathComponent(
            "Contents/SharedSupport/CrossOver/bin/wine",
            isDirectory: false
        )
        try FileManager.default.createDirectory(
            at: bundledWine.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try makeExecutable(at: bundledWine)

        let pathWine = bin.appendingPathComponent("wine")
        try FileManager.default.createSymbolicLink(
            at: pathWine,
            withDestinationURL: bundledWine
        )

        let report = RuntimeDiscovery.discover(paths: RuntimeDiscoveryPaths(
            applicationDirectories: [applications],
            executableDirectories: [bin]
        ))

        let wineFinding = try #require(report.findings.first { $0.runtime == .wine })
        #expect(wineFinding.status == .notDetected)
        #expect(wineFinding.installations.isEmpty)
    }
}

@Test
func reportsNotDetectedForEmptySearchRoots() throws {
    try withTemporaryDirectory { root in
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let report = RuntimeDiscovery.discover(paths: RuntimeDiscoveryPaths(
            applicationDirectories: [applications],
            executableDirectories: [bin]
        ))

        #expect(report.findings.count == RuntimeKind.allCases.count)
        #expect(report.findings.allSatisfy { $0.status == .notDetected })
        #expect(report.findings.allSatisfy { $0.installations.isEmpty })
    }
}

// MARK: - Correction 2: CrossOver bundle identification

@Test
func detectsCrossOverAppExecutableWithoutFalsePositives() throws {
    try withTemporaryDirectory { root in
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        // Real CrossOver.app with bundled wine.
        let crossOver = applications.appendingPathComponent("CrossOver.app", isDirectory: true)
        let crossOverWine = crossOver.appendingPathComponent(
            "Contents/SharedSupport/CrossOver/bin/wine64",
            isDirectory: false
        )
        try FileManager.default.createDirectory(
            at: crossOverWine.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try makeExecutable(at: crossOverWine)

        // A similarly-named bundle that is NOT CrossOver. Note lowercase "s" in "Crossover".
        let crossoverHelper = applications.appendingPathComponent("CrossoverHelper.app", isDirectory: true)
        let helperWine = crossoverHelper.appendingPathComponent(
            "Contents/SharedSupport/bin/wine64",
            isDirectory: false
        )
        try FileManager.default.createDirectory(
            at: helperWine.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try makeExecutable(at: helperWine)

        // Standalone wine outside any bundle.
        let standaloneWine = bin.appendingPathComponent("wine64")
        try makeExecutable(at: standaloneWine)

        // Separate subdirectory for symlinks so they don't clash with the
        // standalone real file at bin/wine64.
        let symlinksDir = root.appendingPathComponent("symlinks", isDirectory: true)
        try FileManager.default.createDirectory(at: symlinksDir, withIntermediateDirectories: true)

        // CrossOver wine exposed via symlink in PATH.
        let pathCrossOverWine = symlinksDir.appendingPathComponent("wine")
        try FileManager.default.createSymbolicLink(
            at: pathCrossOverWine,
            withDestinationURL: crossOverWine
        )

        // CrossoverHelper wine exposed via symlink in PATH.
        let pathHelperWine = symlinksDir.appendingPathComponent("wine64")
        try FileManager.default.createSymbolicLink(
            at: pathHelperWine,
            withDestinationURL: helperWine
        )

        let report = RuntimeDiscovery.discover(paths: RuntimeDiscoveryPaths(
            applicationDirectories: [applications],
            executableDirectories: [bin, symlinksDir]
        ))

        let wineFinding = try #require(report.findings.first { $0.runtime == .wine })

        // CrossOver's wine must be excluded — it resolves inside CrossOver.app.
        #expect(!wineFinding.installations.contains { $0.path == pathCrossOverWine.path })

        // CrossoverHelper's wine must NOT be excluded — it is not "CrossOver".
        #expect(wineFinding.installations.contains { $0.path == pathHelperWine.path })

        // Standalone wine must be detected.
        #expect(wineFinding.installations.contains { $0.path == standaloneWine.path })

        // CrossoverHelper must be detected as an application bundle.
        let crossOverFinding = try #require(report.findings.first { $0.runtime == .crossover })
        #expect(crossOverFinding.status == .detectedUnverified)
    }
}

@Test
func resolvesSymlinksInCrossOverDetection() throws {
    try withTemporaryDirectory { root in
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        // CrossOver.app with wine binary deep inside.
        let crossOver = applications.appendingPathComponent("CrossOver.app", isDirectory: true)
        let bundledWine = crossOver.appendingPathComponent(
            "Contents/SharedSupport/CrossOver/bin/wine64",
            isDirectory: false
        )
        try FileManager.default.createDirectory(
            at: bundledWine.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try makeExecutable(at: bundledWine)

        // Create a symlink chain: bin/wine -> applications/some/link -> CrossOver.app/.../wine64
        let intermediateDir = applications.appendingPathComponent("some", isDirectory: true)
        try FileManager.default.createDirectory(at: intermediateDir, withIntermediateDirectories: true)
        let intermediateSymlink = intermediateDir.appendingPathComponent("link", isDirectory: false)
        try FileManager.default.createSymbolicLink(
            at: intermediateSymlink,
            withDestinationURL: bundledWine
        )

        // PATH points to bin, where we place another symlink to the intermediate.
        let pathSymlink = bin.appendingPathComponent("wine64")
        try FileManager.default.createSymbolicLink(
            at: pathSymlink,
            withDestinationURL: intermediateSymlink
        )

        let report = RuntimeDiscovery.discover(paths: RuntimeDiscoveryPaths(
            applicationDirectories: [applications],
            executableDirectories: [bin]
        ))

        // The symlink chain must resolve to CrossOver.app, so wine must be excluded.
        let wineFinding = try #require(report.findings.first { $0.runtime == .wine })
        #expect(wineFinding.status == .notDetected)
        #expect(wineFinding.installations.isEmpty)
    }
}

// MARK: - Correction 3: Bounded Info.plist reads

@Test
func rejectsOversizedInfoPlist() throws {
    try withTemporaryDirectory { root in
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)

        let crossOver = applications.appendingPathComponent("CrossOver.app", isDirectory: true)
        let contents = crossOver.appendingPathComponent("Contents", isDirectory: true)
        let macos = contents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)

        // Write an Info.plist larger than the read limit.
        let infoURL = contents.appendingPathComponent("Info.plist")
        // Construct a plist large enough to exceed 1 MiB + 1 byte (1,048,577).
        var oversizedPlist = Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.codeweavers.CrossOver</string><key>CFBundleShortVersionString</key><string>25.1</string><key>CFBundleExecutable</key><string>RuntimeTestStub</string>
            """.utf8
        )
        // Pad to exceed the limit — write 1,048,577 + 1 byte.
        oversizedPlist.append(Data(repeating: 32, count: 1_048_578 - oversizedPlist.count))
        try oversizedPlist.write(to: infoURL)

        try makeExecutable(at: macos.appendingPathComponent("RuntimeTestStub"))

        let report = RuntimeDiscovery.discover(paths: RuntimeDiscoveryPaths(
            applicationDirectories: [applications],
            executableDirectories: []
        ))

        let finding = try #require(report.findings.first { $0.runtime == .crossover })
        #expect(finding.status == .detectedUnverified)
        #expect(finding.installations.count == 1)

        let installation = try #require(finding.installations.first)
        #expect(installation.version == nil)
        // Evidence must mention the size limit.
        let evidence = installation.evidence.joined(separator: " ")
        #expect(evidence.localizedCaseInsensitiveContains("limit") || evidence.localizedCaseInsensitiveContains("exceeds"))
    }
}

@Test
func malformedInfoPlistDoesNotCrashDiscovery() throws {
    try withTemporaryDirectory { root in
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)

        let crossOver = applications.appendingPathComponent("CrossOver.app", isDirectory: true)
        let contents = crossOver.appendingPathComponent("Contents", isDirectory: true)
        let macos = contents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)

        // Write binary garbage as Info.plist — well within size limit but unparseable.
        let infoURL = contents.appendingPathComponent("Info.plist")
        var garbage = Data(capacity: 4096)
        for byte: UInt8 in 0..<255 {
            garbage.append(byte)
        }
        garbage.append(contentsOf: [0xFF, 0xFE, 0xFD, 0xFC])
        try garbage.write(to: infoURL)

        try makeExecutable(at: macos.appendingPathComponent("RuntimeTestStub"))

        // This must not throw.
        let report = RuntimeDiscovery.discover(paths: RuntimeDiscoveryPaths(
            applicationDirectories: [applications],
            executableDirectories: []
        ))

        let finding = try #require(report.findings.first { $0.runtime == .crossover })
        #expect(finding.status == .detectedUnverified)
        #expect(finding.installations.count == 1)

        let installation = try #require(finding.installations.first)
        #expect(installation.version == nil)
        // Evidence must mention the parse failure.
        let evidence = installation.evidence.joined(separator: " ")
        #expect(evidence.localizedCaseInsensitiveContains("parse"))
    }
}

// MARK: - Helpers

private func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacGameBridgeRuntimeDiscovery-\(UUID().uuidString)", isDirectory: true)
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