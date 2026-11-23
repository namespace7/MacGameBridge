import Foundation
import Testing

@testable import MacGameBridgeCore

// MARK: - Injected probe

/// Records every invocation so tests can prove which probes were (or were
/// not) executed on each host architecture.
private final class FakeCommandRunner: SystemCommandExecuting, @unchecked Sendable {
    /// Result returned for `/usr/bin/uname -m`.
    let unameOutput: String?
    /// Result returned for `/usr/bin/arch -x86_64 /usr/bin/uname -m`.
    let translatedUnameOutput: String?
    private(set) var invocations: [(executable: String, arguments: [String])] = []

    init(unameOutput: String?, translatedUnameOutput: String?) {
        self.unameOutput = unameOutput
        self.translatedUnameOutput = translatedUnameOutput
    }

    func execute(_ executable: String, _ arguments: [String]) -> String? {
        invocations.append((executable, arguments))
        if executable == "/usr/bin/uname" {
            return unameOutput
        }
        if executable == "/usr/bin/arch" {
            return translatedUnameOutput
        }
        return nil
    }

    var invokedArchProbe: Bool {
        invocations.contains { $0.executable == "/usr/bin/arch" }
    }
}

private func detect(
    uname: String?,
    translated: String? = nil
) -> (host: HostCapabilities, runner: FakeCommandRunner) {
    let runner = FakeCommandRunner(
        unameOutput: uname,
        translatedUnameOutput: translated
    )
    let host = HostCapabilitiesDetector(runner: runner).detect()
    return (host, runner)
}

// MARK: - Native architecture detection

@Test
func detectsARM64NativeArchitecture() {
    let (host, _) = detect(uname: "arm64")
    #expect(host.nativeArchitecture == .arm64)
    #expect(host.architectureDetail == "arm64")
}

@Test
func detectsX8664NativeArchitecture() {
    let (host, _) = detect(uname: "x86_64")
    #expect(host.nativeArchitecture == .x8664)
    #expect(host.architectureDetail == "x86_64")
}

@Test
func detectsUnknownNativeArchitecture() {
    let (host, _) = detect(uname: "ppc")
    #expect(host.nativeArchitecture == .unknown)
    #expect(host.architectureDetail == "ppc")
}

@Test
func failedUnameProbeMapsToUnknownArchitecture() {
    let (host, _) = detect(uname: nil)
    #expect(host.nativeArchitecture == .unknown)
    #expect(host.architectureDetail == "unknown")
}

// MARK: - Rosetta verification

@Test
func successfulRosettaProbeIsVerified() {
    let (host, _) = detect(uname: "arm64", translated: "x86_64")
    #expect(host.rosettaStatus == .verified)
    #expect(host.translatedArchitecture == "x86_64")
    #expect(host.rosettaDetail == "An x86_64 macOS process executed successfully.")
    #expect(host.selectionRequest.rosettaAvailable)
    #expect(host.selectionRequest.hostArchitecture == .arm64)
}

@Test
func failedRosettaProbeIsNotVerifiedAndNotTreatedAsVerified() {
    let (host, _) = detect(uname: "arm64", translated: nil)
    #expect(host.rosettaStatus == .notVerified)
    #expect(host.translatedArchitecture == nil)
    #expect(host.rosettaDetail == "The x86_64 execution probe failed.")
    #expect(!host.selectionRequest.rosettaAvailable)
    // not_verified is not proof of absence: the status must not be .unavailable.
    #expect(host.rosettaStatus != .unavailable)
}

@Test
func unexpectedRosettaProbeOutputIsNotVerified() {
    let (host, _) = detect(uname: "arm64", translated: "arm64")
    #expect(host.rosettaStatus == .notVerified)
    #expect(host.translatedArchitecture == "arm64")
    #expect(host.rosettaDetail == "The probe returned an unexpected architecture.")
    #expect(!host.selectionRequest.rosettaAvailable)
}

@Test
func arm64HostStillPerformsRosettaProbe() {
    // Even with a failing translated probe, an ARM64 host must attempt it.
    let (_, runner) = detect(uname: "arm64", translated: nil)
    #expect(runner.invokedArchProbe)
    #expect(runner.invocations.contains { invocation in
        invocation.executable == "/usr/bin/arch"
            && invocation.arguments == ["-x86_64", "/usr/bin/uname", "-m"]
    })
}

@Test
func x8664HostDoesNotInvokeRosettaProbe() {
    // On Intel the translated probe could succeed natively and falsely report
    // Rosetta as verified, so it must never be run.
    let (_, runner) = detect(uname: "x86_64", translated: "x86_64")
    #expect(!runner.invokedArchProbe)
    #expect(runner.invocations.count == 1)
    #expect(runner.invocations.first?.executable == "/usr/bin/uname")
}

@Test
func intelHostIsNotReportedAsRosettaVerified() {
    let (host, _) = detect(uname: "x86_64", translated: "x86_64")
    #expect(host.nativeArchitecture == .x8664)
    #expect(host.rosettaStatus != .verified)
    #expect(host.rosettaStatus == .unavailable)
    #expect(host.rosettaDetail == "Rosetta 2 is not applicable on an Intel x86_64 host.")
    #expect(host.translatedArchitecture == nil)
    #expect(!host.selectionRequest.rosettaAvailable)
}

@Test
func unknownHostArchitectureDoesNotBecomeRosettaVerified() {
    let (host, runner) = detect(uname: "ppc", translated: "x86_64")
    #expect(!runner.invokedArchProbe)
    #expect(host.nativeArchitecture == .unknown)
    #expect(host.rosettaStatus != .verified)
    #expect(host.rosettaStatus == .notVerified)
    #expect(!host.selectionRequest.rosettaAvailable)

    let failedProbe = detect(uname: nil, translated: "x86_64")
    #expect(!failedProbe.runner.invokedArchProbe)
    #expect(failedProbe.host.rosettaStatus != .verified)
    #expect(failedProbe.host.rosettaStatus == .notVerified)
}

@Test
func diagnosticsRosettaInfoPreservesExistingStatusVocabulary() {
    let verified = detect(uname: "arm64", translated: "x86_64").host
    #expect(verified.rosettaInfo.status == "verified")
    #expect(verified.rosettaInfo.translatedArchitecture == "x86_64")

    let failed = detect(uname: "arm64", translated: nil).host
    #expect(failed.rosettaInfo.status == "not_verified")
    #expect(failed.rosettaInfo.translatedArchitecture == nil)

    let intel = detect(uname: "x86_64", translated: "x86_64").host
    #expect(intel.rosettaInfo.status == "unavailable")
    #expect(intel.rosettaInfo.translatedArchitecture == nil)
}
