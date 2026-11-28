import Foundation

/// Read-only adapter for standalone Wine (provider ID `.wine`).
///
/// CrossOver, Whisky, and Sikarugir deliberately have no adapter in M3.1. This
/// adapter only accepts the standalone shape produced by `RuntimeScanner`:
/// a discovered `wine`/`wine64` executable, already validated by metadata
/// inspection, with no wrapper app bundle.
public struct WineRuntimeAdapter: RuntimeAdapter {
    public let providerID: RuntimeProviderID = .wine
    public let capabilities: RuntimeAdapterCapabilities = .validationAndPinning

    public init() {}

    public func validate(
        _ installation: ProviderInstallation,
        host: HostCapabilities
    ) throws -> RuntimeAdapterValidationResult {
        guard installation.provider == providerID else {
            throw RuntimeAdapterError.providerMismatch(
                expected: providerID,
                actual: installation.provider
            )
        }

        var issues: [RuntimeAdapterValidationIssue] = []

        if installation.bundleURL != nil {
            issues.append(
                RuntimeAdapterValidationIssue(
                    code: .unsupportedInstallationShape,
                    message: "Standalone Wine cannot be pinned from a wrapper app bundle."
                )
            )
        }

        if let wineURL = installation.wineExecutableURL {
            if !wineURL.isFileURL || wineURL.path.isEmpty || !wineURL.path.hasPrefix("/") {
                issues.append(
                    RuntimeAdapterValidationIssue(
                        code: .missingWineExecutable,
                        message: "The discovered Wine executable is not an absolute local file URL."
                    )
                )
            }
        } else {
            issues.append(
                RuntimeAdapterValidationIssue(
                    code: .missingWineExecutable,
                    message: "No Wine executable was discovered for this installation."
                )
            )
        }

        if installation.status != .validated {
            issues.append(
                RuntimeAdapterValidationIssue(
                    code: .statusNotValidated,
                    message: "Installation status is '\(installation.status.rawValue)'; only validated installations are eligible."
                )
            )
        }

        if installation.architecture == .unknown {
            issues.append(
                RuntimeAdapterValidationIssue(
                    code: .unknownArchitecture,
                    message: "The Wine executable architecture could not be determined."
                )
            )
        }

        // Reuse the existing compatibility engine with the injected host facts.
        // Rosetta is never assumed: only a positively verified host reports it.
        let rejection = ArchitectureCompatibility.evaluate(
            runtimeArchitecture: installation.architecture,
            hostArchitecture: host.nativeArchitecture,
            rosettaAvailable: host.rosettaStatus == .verified
        )
        var architectureRejection: RuntimeSelectionRejection?
        if let rejection {
            architectureRejection = rejection
            issues.append(
                RuntimeAdapterValidationIssue(
                    code: .architectureIncompatible,
                    message: rejection.description
                )
            )
        }

        return RuntimeAdapterValidationResult(
            providerID: providerID,
            installationID: installation.id,
            isEligible: issues.isEmpty,
            architecture: installation.architecture,
            issues: issues,
            architectureRejection: architectureRejection
        )
    }
}
