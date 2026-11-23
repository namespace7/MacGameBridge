import Foundation

// MARK: - Selection Policy

/// Defines how the runtime selector should choose among available installations.
///
/// - `automatic`: The engine ranks candidates by status, architecture, and
///   provider stability, then picks the best.
/// - `preferProvider`: The engine first looks for candidates from the specified
///   provider. If none are valid, fallback is permitted only when the request
///   explicitly allows it.
/// - `exactInstallation`: The engine looks for the exact `ProviderInstallation.id`.
///   If that installation is not available or not validated, it returns a failure
///   **without** falling back to another installation. This prevents silently
///   substituting a runtime the user did not explicitly choose.
public enum RuntimeSelectionPolicy: Codable, Equatable, Sendable {
    case automatic
    case preferProvider(RuntimeProviderID)
    case exactInstallation(String)
}

// MARK: - Selection Request

/// Contextual information for runtime selection.
///
/// This model carries host-environment details that influence architecture
/// compatibility evaluation while keeping the selector pure and testable.
public struct RuntimeSelectionRequest: Codable, Equatable, Sendable {
    /// The host machine's native architecture.
    ///
    /// This is typically `arm64` on Apple Silicon or `x86_64` on Intel Macs.
    public let hostArchitecture: RuntimeArchitecture

    /// Whether Rosetta 2 translation is available on this host.
    ///
    /// On Apple Silicon, Rosetta enables x86_64 binaries to run.
    /// On Intel Macs, this should be `false`.
    public let rosettaAvailable: Bool

    /// Whether the selector may fall back to a different installation when the
    /// preferred or exact policy cannot be satisfied.
    ///
    /// - When `true`, `preferProvider` may select a different provider.
    ///   `exactInstallation` never falls back regardless of this flag.
    /// - When `false`, selection returns a failure if the preferred provider
    ///   has no valid candidates.
    public let allowFallback: Bool

    public init(
        hostArchitecture: RuntimeArchitecture,
        rosettaAvailable: Bool,
        allowFallback: Bool = true
    ) {
        self.hostArchitecture = hostArchitecture
        self.rosettaAvailable = rosettaAvailable
        self.allowFallback = allowFallback
    }
}

// MARK: - Structured Rejection Reason

/// A structured, non-ambiguous reason why a candidate was rejected during
/// runtime selection.
public enum RuntimeSelectionRejection: Codable, Equatable, Sendable {
    /// Installation status is not `validated`.
    case notValidated(RuntimeInstallationStatus)
    /// Architecture could not be determined.
    case unknownArchitecture
    /// x86_64 runtime on Apple Silicon without Rosetta available.
    case rosettaNotAvailable
    /// Architecture is incompatible with the host.
    case architectureIncompatible(String)
    /// Candidate is not from the preferred provider.
    case notPreferredProvider(RuntimeProviderID)
    /// Candidate was lower-ranked than the selected installation.
    case lowerRanked(selectedID: String)
    /// Candidate was not the exact requested installation.
    case notExactInstallation
    /// The exact requested installation ID was not found among any candidates.
    case installationNotFound(String)
    /// No candidates were available for evaluation.
    case noCandidates
}

extension RuntimeSelectionRejection: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notValidated(let status):
            return "Installation status is \(status.rawValue), not validated"
        case .unknownArchitecture:
            return "Architecture is unknown"
        case .rosettaNotAvailable:
            return "x86_64 runtime requires Rosetta 2, which is not available"
        case .architectureIncompatible(let detail):
            return "Architecture incompatible: \(detail)"
        case .notPreferredProvider(let providerID):
            return "Not from preferred provider \(providerID.rawValue)"
        case .lowerRanked(let selectedID):
            return "Lower-ranked than selected installation \(selectedID)"
        case .notExactInstallation:
            return "Not the requested exact installation"
        case .installationNotFound(let id):
            return "Requested exact installation '\(id)' was not found among any candidates"
        case .noCandidates:
            return "No candidates available for evaluation"
        }
    }
}

// MARK: - Candidate Evaluation

/// The result of evaluating a single candidate against the selection policy
/// and the host environment.
public struct RuntimeCandidateEvaluation: Codable, Equatable, Sendable {
    /// The evaluated installation.
    public let installation: ProviderInstallation
    /// Whether this candidate was accepted.
    public let accepted: Bool
    /// If rejected, a structured reason.
    public let rejection: RuntimeSelectionRejection?

    public init(installation: ProviderInstallation, accepted: Bool, rejection: RuntimeSelectionRejection?) {
        self.installation = installation
        self.accepted = accepted
        self.rejection = rejection
    }
}

// MARK: - Selection Result

/// The complete, explainable result of a runtime selection operation.
///
/// Prefer inspecting the structured `failure` property over parsing the
/// human-readable `selectionReason` string.
public struct RuntimeSelectionResult: Codable, Equatable, Sendable {
    /// The selected installation, or nil when no suitable candidate was found.
    public let selected: ProviderInstallation?
    /// A human-readable explanation of why this installation was selected (or
    /// why none was selected).
    public let selectionReason: String
    /// Evaluation results for every candidate considered.
    public let evaluations: [RuntimeCandidateEvaluation]
    /// The structured failure reason, if selection did not succeed. Nil when a
    /// candidate was selected.
    public let failure: RuntimeSelectionRejection?
    /// True when the selected installation is not the one the policy requested
    /// directly.
    public let usedFallback: Bool

    public init(
        selected: ProviderInstallation?,
        selectionReason: String,
        evaluations: [RuntimeCandidateEvaluation],
        failure: RuntimeSelectionRejection?,
        usedFallback: Bool
    ) {
        self.selected = selected
        self.selectionReason = selectionReason
        self.evaluations = evaluations
        self.failure = failure
        self.usedFallback = usedFallback
    }
}

// MARK: - Architecture Compatibility

/// Evaluates architecture compatibility between a runtime executable and
/// the host machine.
public enum ArchitectureCompatibility {
    /// Evaluate whether a runtime with the given architecture is compatible
    /// with the host, considering Rosetta availability.
    ///
    /// - Parameters:
    ///   - runtimeArchitecture: The architecture of the runtime executable.
    ///   - hostArchitecture: The host's native architecture.
    ///   - rosettaAvailable: Whether Rosetta 2 is available on Apple Silicon.
    /// - Returns: A `RuntimeSelectionRejection` describing the incompatibility,
    ///   or `nil` if the architecture is compatible.
    public static func evaluate(
        runtimeArchitecture: RuntimeArchitecture,
        hostArchitecture: RuntimeArchitecture,
        rosettaAvailable: Bool
    ) -> RuntimeSelectionRejection? {
        // When the host architecture is unknown, no runtime can be positively
        // established as compatible.
        guard hostArchitecture != .unknown else {
            return .architectureIncompatible("Host architecture is unknown")
        }

        switch runtimeArchitecture {
        case .unknown:
            return .unknownArchitecture
        case .arm64:
            // ARM64 runtime: compatible on Apple Silicon (arm64 host).
            // On x86_64 host, ARM64 is not natively executable.
            guard hostArchitecture == .arm64 else {
                return .architectureIncompatible("ARM64 runtime requires an ARM64 host")
            }
            return nil
        case .x8664:
            // x86_64 runtime: compatible on Intel (x86_64 host) natively.
            // On Apple Silicon (arm64 host), requires Rosetta.
            if hostArchitecture == .x8664 {
                return nil
            }
            guard rosettaAvailable else {
                return .rosettaNotAvailable
            }
            return nil
        case .universal:
            // Universal binary: compatible if either arm64 runs natively or
            // x86_64 runs natively or via Rosetta.
            if hostArchitecture == .arm64 {
                // arm64 slice runs natively; x86_64 slice needs Rosetta but
                // universal always has an arm64 slice.
                return nil
            }
            if hostArchitecture == .x8664 {
                // x86_64 slice runs natively.
                return nil
            }
            return .architectureIncompatible("Universal binary has no slice compatible with host")
        }
    }
}

// MARK: - Selector

/// Deterministic, provider-independent runtime selection engine.
///
/// The selector consumes discovered and validated installations from
/// `RuntimeScanner` and applies a `RuntimeSelectionPolicy` to pick the
/// best candidate. Selection is **read-only** — it does not launch,
/// install, modify, or execute any runtime.
///
/// ## Selection Rules (in order)
///
/// 1. An exact installation pin takes precedence over every other preference.
/// 2. If the pinned installation is missing or invalid, return a failure.
///    Never silently substitute another installation.
/// 3. A preferred provider should rank ahead of other providers.
/// 4. If provider preference cannot be satisfied, fallback is permitted only
///    when the request explicitly allows it.
/// 5. Never select an installation whose status is not `validated`.
/// 6. Reject unknown architecture.
/// 7. Evaluate architecture compatibility against host capabilities:
///    - ARM64 runtime on ARM64 host: compatible.
///    - x86_64 runtime on Apple Silicon: compatible only when Rosetta is available.
///    - Universal runtime: compatible if it contains a usable host or translated
///      architecture slice.
/// 8. Never assume Rosetta is available. Use the value supplied in the request.
/// 9. Return a clear explanation for every rejected candidate.
/// 10. Deterministic tie-breaking must not depend on filesystem enumeration order.
///
/// ## Safety
///
/// - An `exactInstallation` policy **never** falls back, regardless of
///   `allowFallback` in the request.
/// - A `preferProvider` policy only falls back when `allowFallback` is `true`
///   and the preferred provider has zero valid candidates.
/// - The `usedFallback` flag is `true` when the selected installation is not
///   the one the policy asked for directly.
public enum RuntimeSelector {

    /// Select a runtime installation from a set of candidates.
    ///
    /// - Parameters:
    ///   - installations: All discovered and validated installations.
    ///   - policy: The selection policy to apply. Defaults to `automatic`.
    ///   - request: Contextual host information for architecture evaluation.
    ///     The caller is responsible for supplying accurate host architecture
    ///     and Rosetta availability. There is no default — Rosetta must be
    ///     explicitly reported rather than silently assumed.
    /// - Returns: A `RuntimeSelectionResult` explaining the selection.
    public static func select(
        from installations: [ProviderInstallation],
        policy: RuntimeSelectionPolicy = .automatic,
        request: RuntimeSelectionRequest
    ) -> RuntimeSelectionResult {
        switch policy {
        case .automatic:
            return selectAutomatic(from: installations, request: request)
        case .preferProvider(let providerID):
            return selectPreferredProvider(from: installations, preferred: providerID, request: request)
        case .exactInstallation(let installationID):
            return selectExactInstallation(from: installations, installationID: installationID, request: request)
        }
    }

    /// A request template for an Apple Silicon host with known Rosetta availability.
    ///
    /// The caller **must** confirm Rosetta availability by inspecting the host
    /// before setting this to `true`. Never assume Rosetta is installed without
    /// verification.
    /// - Parameter rosettaAvailable: Whether Rosetta 2 has been confirmed available.
    /// - Returns: A `RuntimeSelectionRequest` for Apple Silicon with fallback allowed.
    public static func appleSiliconRequest(rosettaAvailable: Bool) -> RuntimeSelectionRequest {
        RuntimeSelectionRequest(
            hostArchitecture: .arm64,
            rosettaAvailable: rosettaAvailable,
            allowFallback: true
        )
    }

    /// A request template for an Intel Mac host.
    /// Intel Macs can run x86_64 binaries natively; Rosetta does not apply.
    public static let intelRequest = RuntimeSelectionRequest(
        hostArchitecture: .x8664,
        rosettaAvailable: false,
        allowFallback: true
    )

    // MARK: - Automatic

    private static func selectAutomatic(
        from installations: [ProviderInstallation],
        request: RuntimeSelectionRequest
    ) -> RuntimeSelectionResult {
        let ranked = rankCandidates(installations)

        let evaluations: [RuntimeCandidateEvaluation] = ranked.map { installation in
            // Rule 5: Only select validated installations.
            guard installation.status == .validated else {
                return RuntimeCandidateEvaluation(
                    installation: installation,
                    accepted: false,
                    rejection: .notValidated(installation.status)
                )
            }
            // Rule 6+7: Architecture compatibility.
            if let rejection = ArchitectureCompatibility.evaluate(
                runtimeArchitecture: installation.architecture,
                hostArchitecture: request.hostArchitecture,
                rosettaAvailable: request.rosettaAvailable
            ) {
                return RuntimeCandidateEvaluation(
                    installation: installation,
                    accepted: false,
                    rejection: rejection
                )
            }
            return RuntimeCandidateEvaluation(
                installation: installation,
                accepted: false,
                rejection: nil  // accepted = true set after picking the best
            )
        }

        guard let selected = ranked.first(where: { installation in
            installation.status == .validated
                && ArchitectureCompatibility.evaluate(
                    runtimeArchitecture: installation.architecture,
                    hostArchitecture: request.hostArchitecture,
                    rosettaAvailable: request.rosettaAvailable
                ) == nil
        }) else {
            return RuntimeSelectionResult(
                selected: nil,
                selectionReason: "No suitable validated runtime installation found.",
                evaluations: evaluations,
                failure: .noCandidates,
                usedFallback: false
            )
        }

        // Mark the selected candidate as accepted. Every other candidate that
        // passed validation and architecture checks (rejection == nil so far)
        // was simply outranked by the selected candidate.
        let finalEvaluations: [RuntimeCandidateEvaluation] = evaluations.map { eval in
            if eval.installation.id == selected.id {
                return RuntimeCandidateEvaluation(
                    installation: eval.installation,
                    accepted: true,
                    rejection: nil
                )
            }
            guard eval.rejection == nil else { return eval }
            return RuntimeCandidateEvaluation(
                installation: eval.installation,
                accepted: false,
                rejection: .lowerRanked(selectedID: selected.id)
            )
        }

        return RuntimeSelectionResult(
            selected: selected,
            selectionReason: "Selected best-ranked validated installation: \(selected.id)",
            evaluations: finalEvaluations,
            failure: nil,
            usedFallback: false
        )
    }

    // MARK: - Preferred Provider

    private static func selectPreferredProvider(
        from installations: [ProviderInstallation],
        preferred: RuntimeProviderID,
        request: RuntimeSelectionRequest
    ) -> RuntimeSelectionResult {
        let preferredCandidates = installations.filter { $0.provider == preferred }

        // Try to pick from the preferred provider.
        if let selected = findBestValidCandidate(
            from: preferredCandidates,
            request: request
        ) {
            let evaluations = buildEvaluations(
                installations: installations,
                selected: selected,
                preferred: preferred,
                request: request,
                isFallback: false
            )
            return RuntimeSelectionResult(
                selected: selected,
                selectionReason: "Selected preferred provider installation: \(selected.id)",
                evaluations: evaluations,
                failure: nil,
                usedFallback: false
            )
        }

        // Preferred provider has no valid candidates.
        guard request.allowFallback else {
            // Fallback prohibited: return failure with the actual rejection
            // reason for each preferred-provider candidate (validation status
            // or architecture incompatibility), not a blanket "not validated".
            let evaluations = installations.map { installation -> RuntimeCandidateEvaluation in
                guard installation.provider == preferred else {
                    return RuntimeCandidateEvaluation(
                        installation: installation,
                        accepted: false,
                        rejection: .notPreferredProvider(preferred)
                    )
                }
                return RuntimeCandidateEvaluation(
                    installation: installation,
                    accepted: false,
                    rejection: candidateRejectionReason(installation, request: request)
                )
            }
            // The top-level failure should reflect why the preferred provider
            // was rejected: if a preferred-provider candidate exists, surface
            // its specific reason (e.g. Rosetta unavailable); otherwise, no
            // candidate from that provider existed at all.
            let topLevelFailure: RuntimeSelectionRejection = evaluations
                .first { $0.installation.provider == preferred }?
                .rejection ?? .notPreferredProvider(preferred)
            return RuntimeSelectionResult(
                selected: nil,
                selectionReason: "Preferred provider \(preferred.rawValue) has no valid candidates and fallback is not allowed.",
                evaluations: evaluations,
                failure: topLevelFailure,
                usedFallback: false
            )
        }

        // Fall back to automatic ranking across all installations.
        guard let fallbackSelected = findBestValidCandidate(
            from: installations,
            request: request
        ) else {
            // No eligible candidate exists anywhere (preferred provider or
            // otherwise). Preserve each candidate's actual rejection reason
            // (validation status or architecture incompatibility) instead of
            // reporting a blanket "not validated" for candidates that may in
            // fact be validated but architecture-incompatible.
            let evaluations = installations.map { installation in
                RuntimeCandidateEvaluation(
                    installation: installation,
                    accepted: false,
                    rejection: candidateRejectionReason(installation, request: request)
                )
            }
            return RuntimeSelectionResult(
                selected: nil,
                selectionReason: "No suitable runtime installation found (preferred provider: \(preferred.rawValue) had no valid candidates, and no fallback candidates exist).",
                evaluations: evaluations,
                failure: .noCandidates,
                usedFallback: true
            )
        }

        let evaluations = buildEvaluations(
            installations: installations,
            selected: fallbackSelected,
            preferred: preferred,
            request: request,
            isFallback: true
        )
        return RuntimeSelectionResult(
            selected: fallbackSelected,
            selectionReason: "Preferred provider \(preferred.rawValue) had no valid candidates; fell back to \(fallbackSelected.id).",
            evaluations: evaluations,
            failure: nil,
            usedFallback: true
        )
    }

    // MARK: - Exact Installation

    private static func selectExactInstallation(
        from installations: [ProviderInstallation],
        installationID: String,
        request: RuntimeSelectionRequest
    ) -> RuntimeSelectionResult {
        let exact = installations.first { $0.id == installationID }
        let evaluations = installations.map { installation in
            if installation.id == installationID {
                if installation.status != .validated {
                    return RuntimeCandidateEvaluation(
                        installation: installation,
                        accepted: false,
                        rejection: .notValidated(installation.status)
                    )
                }
                if let rejection = ArchitectureCompatibility.evaluate(
                    runtimeArchitecture: installation.architecture,
                    hostArchitecture: request.hostArchitecture,
                    rosettaAvailable: request.rosettaAvailable
                ) {
                    return RuntimeCandidateEvaluation(
                        installation: installation,
                        accepted: false,
                        rejection: rejection
                    )
                }
                return RuntimeCandidateEvaluation(
                    installation: installation,
                    accepted: true,
                    rejection: nil
                )
            }
            return RuntimeCandidateEvaluation(
                installation: installation,
                accepted: false,
                rejection: .notExactInstallation
            )
        }

        guard let exact, exact.status == .validated else {
            let failure: RuntimeSelectionRejection
            let reason: String
            if let exact {
                failure = .notValidated(exact.status)
                reason = "Exact requested installation '\(installationID)' is not validated. No fallback was used."
            } else {
                failure = .installationNotFound(installationID)
                reason = "Exact requested installation '\(installationID)' was not found. No fallback was used."
            }
            return RuntimeSelectionResult(
                selected: nil,
                selectionReason: reason,
                evaluations: evaluations,
                failure: failure,
                usedFallback: false
            )
        }

        // Check architecture compatibility.
        if let archRejection = ArchitectureCompatibility.evaluate(
            runtimeArchitecture: exact.architecture,
            hostArchitecture: request.hostArchitecture,
            rosettaAvailable: request.rosettaAvailable
        ) {
            return RuntimeSelectionResult(
                selected: nil,
                selectionReason: "Exact requested installation '\(installationID)' is not architecture-compatible with this host. No fallback was used.",
                evaluations: evaluations,
                failure: archRejection,
                usedFallback: false
            )
        }

        return RuntimeSelectionResult(
            selected: exact,
            selectionReason: "Selected exact requested installation: \(exact.id)",
            evaluations: evaluations,
            failure: nil,
            usedFallback: false
        )
    }

    // MARK: - Helpers

    /// Find the best valid candidate from a set of installations.
    /// A valid candidate must have `validated` status and architecture
    /// compatible with the host.
    private static func findBestValidCandidate(
        from installations: [ProviderInstallation],
        request: RuntimeSelectionRequest
    ) -> ProviderInstallation? {
        let ranked = rankCandidates(installations)
        return ranked.first { installation in
            installation.status == .validated
                && ArchitectureCompatibility.evaluate(
                    runtimeArchitecture: installation.architecture,
                    hostArchitecture: request.hostArchitecture,
                    rosettaAvailable: request.rosettaAvailable
                ) == nil
        }
    }

    /// Determine the actual rejection reason for a candidate based solely on
    /// its own validation status and architecture compatibility — independent
    /// of ranking or provider preference. Used whenever a candidate must be
    /// explained without reference to a selected "winner" (e.g. preferred
    /// provider with fallback prohibited).
    private static func candidateRejectionReason(
        _ installation: ProviderInstallation,
        request: RuntimeSelectionRequest
    ) -> RuntimeSelectionRejection {
        if installation.status != .validated {
            return .notValidated(installation.status)
        }
        if let archRejection = ArchitectureCompatibility.evaluate(
            runtimeArchitecture: installation.architecture,
            hostArchitecture: request.hostArchitecture,
            rosettaAvailable: request.rosettaAvailable
        ) {
            return archRejection
        }
        // Validated and architecture-compatible, but still not selected
        // (e.g. a different equally-valid candidate must exist, or the
        // caller determined it wasn't the best candidate some other way).
        return .notValidated(installation.status)
    }

    /// Build evaluations for all installations given a selected candidate.
    private static func buildEvaluations(
        installations: [ProviderInstallation],
        selected: ProviderInstallation,
        preferred: RuntimeProviderID?,
        request: RuntimeSelectionRequest,
        isFallback: Bool
    ) -> [RuntimeCandidateEvaluation] {
        let ranked = rankCandidates(installations)
        return ranked.map { installation in
            if installation.id == selected.id {
                return RuntimeCandidateEvaluation(
                    installation: installation,
                    accepted: true,
                    rejection: nil
                )
            }
            // Determine rejection reason.
            let rejection: RuntimeSelectionRejection
            if installation.status != .validated {
                rejection = .notValidated(installation.status)
            } else if let archRejection = ArchitectureCompatibility.evaluate(
                runtimeArchitecture: installation.architecture,
                hostArchitecture: request.hostArchitecture,
                rosettaAvailable: request.rosettaAvailable
            ) {
                rejection = archRejection
            } else if let preferred, installation.provider != preferred, isFallback {
                rejection = .notPreferredProvider(preferred)
            } else {
                rejection = .lowerRanked(selectedID: selected.id)
            }
            return RuntimeCandidateEvaluation(
                installation: installation,
                accepted: false,
                rejection: rejection
            )
        }
    }

    // MARK: - Candidate Ranking

    /// Rank candidates deterministically. Best candidates come first.
    ///
    /// Sorting uses a deterministic comparator based only on installation
    /// properties, not on filesystem state or external factors.
    static func rankCandidates(_ installations: [ProviderInstallation]) -> [ProviderInstallation] {
        installations.sorted { lhs, rhs in
            // 1. Status: validated > detected > notDetected
            let lhsScore = statusScore(lhs.status)
            let rhsScore = statusScore(rhs.status)
            guard lhsScore == rhsScore else { return lhsScore > rhsScore }

            // 2. Architecture: arm64 > universal > x86_64 > unknown
            let lhsArch = archScore(lhs.architecture)
            let rhsArch = archScore(rhs.architecture)
            guard lhsArch == rhsArch else { return lhsArch > rhsArch }

            // 3. Provider stability: CrossOver > Wine > Whisky > Sikarugir
            let lhsProvider = providerScore(lhs.provider)
            let rhsProvider = providerScore(rhs.provider)
            guard lhsProvider == rhsProvider else { return lhsProvider > rhsProvider }

            // 4. Deterministic tie-breaker: installation ID, compared using
            //    Swift's locale-independent Unicode ordering. Unlike
            //    `localizedStandardCompare`, this does not vary with the
            //    user's current locale and does not apply natural/numeric-
            //    aware sorting, so results are stable across environments.
            return lhs.id < rhs.id
        }
    }

    private static func statusScore(_ status: RuntimeInstallationStatus) -> Int {
        switch status {
        case .validated:    return 2
        case .detected:     return 1
        case .notDetected:  return 0
        }
    }

    private static func archScore(_ arch: RuntimeArchitecture) -> Int {
        switch arch {
        case .arm64:     return 3
        case .universal: return 2
        case .x8664:     return 1
        case .unknown:   return 0
        }
    }

    private static func providerScore(_ provider: RuntimeProviderID) -> Int {
        switch provider {
        case .crossover:  return 3
        case .wine:       return 2
        case .whisky:     return 1
        case .sikarugir:  return 0
        }
    }
}