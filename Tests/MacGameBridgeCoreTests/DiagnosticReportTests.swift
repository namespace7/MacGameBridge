import Foundation
import Testing

@testable import MacGameBridgeCore

@Test
func diagnosticReportRoundTripsThroughJSON() throws {
    let original = DiagnosticReport(
        schemaVersion: "1.0",
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        host: HostInfo(
            architecture: "arm64",
            chip: "Apple M4",
            physicalMemoryBytes: 16_000_000_000,
            macOSVersion: "27.2.1",
            buildVersion: "26B131"
        ),
        gpu: GPUInfo(
            available: true,
            name: "Apple M4",
            hasUnifiedMemory: true,
            recommendedMaxWorkingSetBytes: 8_000_000_000
        ),
        rosetta: RosettaInfo(
            status: "verified",
            translatedArchitecture: "x86_64",
            detail: "Test fixture"
        ),
        storage: StorageInfo(
            volume: "/System/Volumes/Data",
            totalBytes: 460_000_000_000,
            availableBytes: 126_000_000_000
        ),
        runtimes: [
            RuntimeDetection(
                name: "Wine",
                status: "not_detected",
                evidence: nil
            )
        ]
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let decoded = try decoder.decode(DiagnosticReport.self, from: data)

    #expect(decoded.host.architecture == "arm64")
    #expect(decoded.host.chip == "Apple M4")
    #expect(decoded.rosetta.status == "verified")
    #expect(decoded.gpu.hasUnifiedMemory == true)
    #expect(decoded.runtimes.first?.name == "Wine")
}
