import Foundation
import Testing

@testable import MacGameBridgeCore

// MARK: - Helpers

private func makeInstallation(
    id: String,
    provider: RuntimeProviderID = .wine,
    architecture: RuntimeArchitecture = .arm64,
    status: RuntimeInstallationStatus = .validated
) -> ProviderInstallation {
    ProviderInstallation(
        provider: provider,
        displayName: provider.rawValue.capitalized,
        wineExecutableURL: URL(fileURLWithPath: "/usr/local/bin/\(id)"),
        version: "1.0",
        architecture: architecture,
        status: status,
        evidence: ["Test fixture"]
    )
}

private func makeHost(
    architecture: RuntimeArchitecture,
    rosetta: RosettaVerificationStatus = .notVerified
) -> HostCapabilities {
    HostCapabilities(
        nativeArchitecture: architecture,
        architectureDetail: architecture.rawValue,
        rosettaStatus: rosetta,
        rosettaDetail: "Test fixture",
        translatedArchitecture: rosetta == .verified ? "x86_64" : nil
    )
}

private func makeScanReport(_ installations: [ProviderInstallation]) -> RuntimeProviderReport {
    RuntimeProviderReport(
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        installations: installations
    )
}

private struct StubDetector: HostCapabilitiesDetecting {
    let capabilities: HostCapabilities
    func detect() -> HostCapabilities { capabilities }
}

// MARK: - Selection integration

@Test
func validatedARM64RuntimeSelectedOnARM64Host() {
    let arm64 = makeInstallation(id: "arm64-wine", architecture: .arm64)
    let report = RuntimeSelectionIntegration.makeReport(
        host: makeHost(architecture: .arm64),
        scanReport: makeScanReport([arm64])
    )

    #expect(report.selection.selected?.id == arm64.id)
    #expect(report.selection.failure == nil)
    #expect(report.host.nativeArchitecture == .arm64)
}

@Test
func x8664RuntimeRejectedWhenRosettaNotVerified() {
    let x8664 = makeInstallation(id: "x8664-wine", architecture: .x8664)
    let report = RuntimeSelectionIntegration.makeReport(
        host: makeHost(architecture: .arm64, rosetta: .notVerified),
        scanReport: makeScanReport([x8664])
    )

    #expect(report.selection.selected == nil)
    // The automatic selector reports noCandidates at the top level; the
    // specific Rosetta reason is carried by the candidate evaluation.
    #expect(report.selection.failure == .noCandidates)
    #expect(report.selection.evaluations.first?.rejection == .rosettaNotAvailable)
}

@Test
func x8664RuntimeAcceptedWhenRosettaVerified() {
    let x8664 = makeInstallation(id: "x8664-wine", architecture: .x8664)
    let report = RuntimeSelectionIntegration.makeReport(
        host: makeHost(architecture: .arm64, rosetta: .verified),
        scanReport: makeScanReport([x8664])
    )

    #expect(report.selection.selected?.id == x8664.id)
    #expect(report.selection.failure == nil)
}

@Test
func unknownHostArchitectureProducesNoPositiveSelection() {
    let arm64 = makeInstallation(id: "arm64-wine", architecture: .arm64)
    let report = RuntimeSelectionIntegration.makeReport(
        host: makeHost(architecture: .unknown),
        scanReport: makeScanReport([arm64])
    )

    #expect(report.selection.selected == nil)
    #expect(report.selection.failure != nil)
    #expect(report.selection.evaluations.first?.rejection == .architectureIncompatible("Host architecture is unknown"))
}

@Test
func noInstalledRuntimesProducesClearNoCandidateResult() {
    let report = RuntimeSelectionIntegration.makeReport(
        host: makeHost(architecture: .arm64),
        scanReport: makeScanReport([])
    )

    #expect(report.selection.selected == nil)
    #expect(report.selection.failure == .noCandidates)
    #expect(report.selection.selectionReason.contains("No suitable"))
    #expect(report.selection.evaluations.isEmpty)
}

@Test
func multipleCandidatesUseExistingDeterministicRanking() {
    let wine = makeInstallation(id: "wine-arm64", provider: .wine, architecture: .arm64)
    let crossover = makeInstallation(id: "crossover-arm64", provider: .crossover, architecture: .arm64)

    let first = RuntimeSelectionIntegration.makeReport(
        host: makeHost(architecture: .arm64),
        scanReport: makeScanReport([wine, crossover])
    )
    let reversed = RuntimeSelectionIntegration.makeReport(
        host: makeHost(architecture: .arm64),
        scanReport: makeScanReport([crossover, wine])
    )

    // CrossOver outranks Wine in the existing selector; order must not matter.
    #expect(first.selection.selected?.id == crossover.id)
    #expect(reversed.selection.selected?.id == crossover.id)
}

@Test
func detectedButUnvalidatedInstallationIsNeverSelected() {
    let detected = makeInstallation(id: "detected-wine", status: .detected)
    let report = RuntimeSelectionIntegration.makeReport(
        host: makeHost(architecture: .arm64),
        scanReport: makeScanReport([detected])
    )

    #expect(report.selection.selected == nil)
    #expect(report.selection.evaluations.first?.rejection == .notValidated(.detected))
}

@Test
func collectUsesInjectedDetectorAndCurrentScannerPaths() {
    let expectedHost = makeHost(architecture: .arm64, rosetta: .verified)
    let installation = makeInstallation(id: "injected", architecture: .arm64)
    var scannedPaths: RuntimeScanner.SearchPaths?

    let report = RuntimeSelectionIntegration.collect(
        detector: StubDetector(capabilities: expectedHost),
        scanner: { paths in
            scannedPaths = paths
            return makeScanReport([installation])
        }
    )

    #expect(scannedPaths == .current)
    #expect(report.host == expectedHost)
    #expect(report.selection.selected?.id == installation.id)
}

// MARK: - Report JSON

@Test
func integrationReportEncodesAndDecodesAsJSON() throws {
    let installation = makeInstallation(id: "arm64-wine", architecture: .arm64)
    let original = RuntimeSelectionIntegration.makeReport(
        host: makeHost(architecture: .arm64, rosetta: .verified),
        scanReport: makeScanReport([installation]),
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(RuntimeSelectionIntegrationReport.self, from: data)

    #expect(decoded == original)
    #expect(decoded.host.nativeArchitecture == .arm64)
    #expect(decoded.host.rosettaStatus == .verified)
    #expect(decoded.scanReport.installations.first?.id == installation.id)
    #expect(decoded.selection.selected?.id == installation.id)
}
