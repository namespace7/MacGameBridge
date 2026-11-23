import Foundation
import Testing

@testable import MacGameBridgeCore

// MARK: - Helpers

/// Build a minimal ProviderInstallation for testing.
private func makeInstallation(
    id: String? = nil,
    provider: RuntimeProviderID = .wine,
    architecture: RuntimeArchitecture = .arm64,
    status: RuntimeInstallationStatus = .validated
) -> ProviderInstallation {
    let displayName: String = {
        switch provider {
        case .wine: return "Wine"
        case .crossover: return "CrossOver"
        case .whisky: return "Whisky"
        case .sikarugir: return "Sikarugir / Wineskin"
        }
    }()
    if let customID = id {
        return ProviderInstallation(
            provider: provider,
            displayName: displayName,
            wineExecutableURL: URL(fileURLWithPath: "/usr/local/bin/\(customID)"),
            version: "1.0",
            architecture: architecture,
            status: status,
            evidence: ["Test fixture"]
        )
    }
    return ProviderInstallation(
        provider: provider,
        displayName: displayName,
        version: "1.0",
        architecture: architecture,
        status: status,
        evidence: ["Test fixture"]
    )
}

/// Default request: Apple Silicon with Rosetta confirmed available, fallback allowed.
/// Used by most tests where Rosetta compatibility is not the subject under test.
private let defaultRequest = RuntimeSelectionRequest(
    hostArchitecture: .arm64,
    rosettaAvailable: true,
    allowFallback: true
)

/// Request without Rosetta (x86_64 incompatible on Apple Silicon).
private let noRosettaRequest = RuntimeSelectionRequest(
    hostArchitecture: .arm64,
    rosettaAvailable: false,
    allowFallback: true
)

/// Request with fallback prohibited.
private let noFallbackRequest = RuntimeSelectionRequest(
    hostArchitecture: .arm64,
    rosettaAvailable: true,
    allowFallback: false
)

/// Request without Rosetta and with fallback prohibited.
private let noRosettaNoFallbackRequest = RuntimeSelectionRequest(
    hostArchitecture: .arm64,
    rosettaAvailable: false,
    allowFallback: false
)

// MARK: - Exact installation pin

@Test
func exactInstallationByIDSelectsCorrectly() {
    let target = makeInstallation(id: "my-wine", provider: .wine)
    let other = makeInstallation(id: "other", provider: .crossover)
    let result = RuntimeSelector.select(
        from: [other, target],
        policy: .exactInstallation(target.id),
        request: defaultRequest
    )

    #expect(result.selected?.id == target.id)
    #expect(!result.usedFallback)
    #expect(result.failure == nil)
}

@Test
func exactInstallationNotAvailableReturnsFailure() {
    let wine = makeInstallation(id: "wine", provider: .wine)
    let result = RuntimeSelector.select(
        from: [wine],
        policy: .exactInstallation("nonexistent"),
        request: defaultRequest
    )

    #expect(result.selected == nil)
    #expect(!result.usedFallback)
    #expect(result.failure != nil)
}

@Test
func exactInstallationMissingIDReportsInstallationNotFound() {
    // When the exact ID does not exist among any candidate, the failure must
    // be the dedicated `.installationNotFound` case, not `.notValidated`.
    // `.notValidated` is reserved for when the installation exists but its
    // status isn't `validated`.
    let wine = makeInstallation(id: "wine", provider: .wine, status: .validated)
    let result = RuntimeSelector.select(
        from: [wine],
        policy: .exactInstallation("nonexistent"),
        request: defaultRequest
    )

    #expect(result.selected == nil)
    #expect(result.failure == .installationNotFound("nonexistent"))
}

@Test
func exactInstallationNeverUsesFallback() {
    // Even when other valid installations exist, missing exact ID returns nil
    // with usedFallback = false and no fallback.
    let wine = makeInstallation(id: "wine", provider: .wine)
    let crossover = makeInstallation(id: "crossover", provider: .crossover)
    let result = RuntimeSelector.select(
        from: [wine, crossover],
        policy: .exactInstallation("nonexistent"),
        request: defaultRequest
    )

    #expect(result.selected == nil)
    #expect(!result.usedFallback)
}

@Test
func exactInstallationDetectedButNotValidatedReturnsFailure() {
    let detected = makeInstallation(id: "detected", provider: .wine, status: .detected)
    let result = RuntimeSelector.select(
        from: [detected],
        policy: .exactInstallation(detected.id),
        request: defaultRequest
    )

    #expect(result.selected == nil)
    #expect(!result.usedFallback)
    // The installation exists but isn't validated: the real `.notValidated`
    // reason must be preserved, not the "missing" rejection.
    #expect(result.failure == .notValidated(.detected))
    let eval = result.evaluations.first { $0.installation.id == detected.id }
    #expect(eval?.rejection != nil)
}

// MARK: - Preferred provider

@Test
func preferredProviderSelectsFromThatProvider() {
    let crossover = makeInstallation(id: "crossover", provider: .crossover)
    let wine = makeInstallation(id: "wine", provider: .wine)
    let result = RuntimeSelector.select(
        from: [wine, crossover],
        policy: .preferProvider(.crossover),
        request: defaultRequest
    )

    #expect(result.selected?.id == crossover.id)
    #expect(!result.usedFallback)
    #expect(result.failure == nil)
}

@Test
func preferredProviderPrefersValidatedWhenMultipleFromSameProvider() {
    let validated = makeInstallation(
        id: "crossover-validated", provider: .crossover, status: .validated
    )
    let detected = makeInstallation(
        id: "crossover-detected", provider: .crossover, status: .detected
    )
    let result = RuntimeSelector.select(
        from: [detected, validated],
        policy: .preferProvider(.crossover),
        request: defaultRequest
    )

    #expect(result.selected?.id == validated.id)
}

@Test
func preferredProviderFallsBackWhenNoCandidate() {
    let wine = makeInstallation(id: "wine", provider: .wine)
    let result = RuntimeSelector.select(
        from: [wine],
        policy: .preferProvider(.crossover),
        request: defaultRequest
    )

    #expect(result.selected?.id == wine.id)
    #expect(result.usedFallback)
}

@Test
func preferredProviderReturnsNilWhenNoCandidatesAtAll() {
    let result = RuntimeSelector.select(
        from: [],
        policy: .preferProvider(.crossover),
        request: defaultRequest
    )

    #expect(result.selected == nil)
    #expect(result.usedFallback)
}

@Test
func preferredProviderNoFallbackWhenDisallowed() {
    let wine = makeInstallation(id: "wine", provider: .wine)
    let result = RuntimeSelector.select(
        from: [wine],
        policy: .preferProvider(.crossover),
        request: noFallbackRequest
    )

    #expect(result.selected == nil)
    #expect(!result.usedFallback)
    #expect(result.failure != nil)
}

@Test
func preferredProviderNoFallbackReportsRosettaNotNotValidatedForValidatedX8664() {
    // The preferred-provider candidate IS validated, but architecture-
    // incompatible (x86_64 on ARM64 host without Rosetta). Fallback is
    // prohibited. The rejection must reflect the real reason (Rosetta
    // unavailability), not a misleading "not validated" claim about a
    // candidate whose status is actually `.validated`.
    let crossoverX8664 = makeInstallation(
        id: "crossover-x86_64", provider: .crossover, architecture: .x8664, status: .validated
    )
    let result = RuntimeSelector.select(
        from: [crossoverX8664],
        policy: .preferProvider(.crossover),
        request: noRosettaNoFallbackRequest
    )

    #expect(result.selected == nil)
    #expect(!result.usedFallback)
    #expect(result.failure == .rosettaNotAvailable)

    let eval = result.evaluations.first { $0.installation.id == crossoverX8664.id }
    #expect(eval?.rejection == .rosettaNotAvailable)
}

@Test
func preferredProviderFallbackAllowedButNoEligibleCandidatePreservesActualRejectionReasons() {
    // Fallback IS allowed, but no candidate anywhere (preferred provider or
    // otherwise) is eligible: the preferred CrossOver candidate is validated
    // but architecture-incompatible (x86_64 on ARM64 host, no Rosetta), and
    // the only other candidate is simply not validated. This exercises the
    // "fall back to automatic ranking" branch when `findBestValidCandidate`
    // over *all* installations also returns nil. Each candidate's evaluation
    // must preserve its actual rejection reason rather than reporting every
    // candidate as `.notValidated`.
    let crossoverX8664 = makeInstallation(
        id: "crossover-x86_64", provider: .crossover, architecture: .x8664, status: .validated
    )
    let wineDetected = makeInstallation(
        id: "wine-detected", provider: .wine, architecture: .arm64, status: .detected
    )
    let result = RuntimeSelector.select(
        from: [crossoverX8664, wineDetected],
        policy: .preferProvider(.crossover),
        request: noRosettaRequest  // allowFallback: true, rosettaAvailable: false
    )

    #expect(result.selected == nil)
    #expect(result.usedFallback)
    #expect(result.failure == .noCandidates)

    let crossoverEval = result.evaluations.first { $0.installation.id == crossoverX8664.id }
    #expect(crossoverEval?.rejection == .rosettaNotAvailable)

    let wineEval = result.evaluations.first { $0.installation.id == wineDetected.id }
    #expect(wineEval?.rejection == .notValidated(.detected))
}

// MARK: - Automatic selection

@Test
func automaticSelectsValidatedOverDetected() {
    let validated = makeInstallation(id: "validated", status: .validated)
    let detected = makeInstallation(id: "detected", status: .detected)
    let result = RuntimeSelector.select(from: [detected, validated], request: defaultRequest)

    #expect(result.selected?.id == validated.id)
    #expect(result.selectionReason.contains("validated"))
    #expect(!result.usedFallback)
}

@Test
func automaticDoesNotSelectDetectedOnly() {
    // When only detected candidates exist, none should be selected.
    let detected = makeInstallation(id: "detected", status: .detected)
    let result = RuntimeSelector.select(from: [detected], request: defaultRequest)

    #expect(result.selected == nil)
    #expect(result.failure != nil)
}

@Test
func automaticPrefersARM64OverX8664() {
    let arm64 = makeInstallation(id: "arm64", architecture: .arm64)
    let x8664 = makeInstallation(id: "x86_64", architecture: .x8664)
    let result = RuntimeSelector.select(from: [x8664, arm64], request: defaultRequest)

    #expect(result.selected?.id == arm64.id)
    #expect(result.selectionReason.contains("arm64"))
}

@Test
func automaticPrefersCrossOverOverWine() {
    let crossover = makeInstallation(id: "crossover", provider: .crossover)
    let wine = makeInstallation(id: "wine", provider: .wine)
    let result = RuntimeSelector.select(from: [wine, crossover], request: defaultRequest)

    #expect(result.selected?.id == crossover.id)
    #expect(result.selectionReason.contains("crossover"))
}

@Test
func automaticDeterministicTieBreaking() {
    // Two identical candidates should sort by ID lexicographically.
    let a = makeInstallation(id: "alpha", provider: .wine, architecture: .arm64, status: .validated)
    let b = makeInstallation(id: "beta", provider: .wine, architecture: .arm64, status: .validated)
    let resultAscending = RuntimeSelector.select(from: [b, a], request: defaultRequest)

    #expect(resultAscending.selected?.id == a.id)
}

@Test
func automaticEvaluationsExplainLowerRankedValidCandidate() throws {
    // Two equally valid (validated, arm64, same provider) candidates differ
    // only by ID. The selected one should be accepted with no rejection; the
    // non-selected one is still valid but outranked, so it must carry
    // `.lowerRanked(selectedID:)` rather than a nil rejection.
    let alpha = makeInstallation(id: "alpha", provider: .wine, architecture: .arm64, status: .validated)
    let beta = makeInstallation(id: "beta", provider: .wine, architecture: .arm64, status: .validated)
    let result = RuntimeSelector.select(from: [alpha, beta], request: defaultRequest)

    #expect(result.selected?.id == alpha.id)

    let selectedEval = try #require(result.evaluations.first { $0.installation.id == alpha.id })
    #expect(selectedEval.accepted)
    #expect(selectedEval.rejection == nil)

    let otherEval = try #require(result.evaluations.first { $0.installation.id == beta.id })
    #expect(!otherEval.accepted)
    #expect(otherEval.rejection == .lowerRanked(selectedID: alpha.id))
}

@Test
func noAvailableCandidatesReturnsFailure() {
    let result = RuntimeSelector.select(from: [], request: defaultRequest)

    #expect(result.selected == nil)
    #expect(result.selectionReason.contains("No suitable"))
    #expect(!result.usedFallback)
    #expect(result.failure != nil)
}

@Test
func onlyNotDetectedCandidatesReturnsFailure() {
    let nd = makeInstallation(id: "nd", status: .notDetected)
    let result = RuntimeSelector.select(from: [nd], request: defaultRequest)

    #expect(result.selected == nil)
    #expect(result.failure != nil)
}

// MARK: - Architecture compatibility

@Test
func arm64RuntimeCompatibleOnARM64Host() {
    let arm64 = makeInstallation(id: "arm64", architecture: .arm64)
    let result = RuntimeSelector.select(from: [arm64], request: defaultRequest)
    #expect(result.selected?.id == arm64.id)
}

@Test
func x8664RuntimeCompatibleWithRosetta() {
    let x8664 = makeInstallation(id: "x86_64", architecture: .x8664)
    let result = RuntimeSelector.select(from: [x8664], request: defaultRequest)
    #expect(result.selected?.id == x8664.id)
}

@Test
func x8664RuntimeIncompatibleWithoutRosetta() {
    let x8664 = makeInstallation(id: "x86_64", architecture: .x8664)
    let result = RuntimeSelector.select(from: [x8664], request: noRosettaRequest)

    #expect(result.selected == nil)
    #expect(result.failure != nil)
    // The rejection should mention Rosetta.
    let eval = result.evaluations.first
    #expect(eval?.rejection == .rosettaNotAvailable)
}

@Test
func universalRuntimeCompatibleOnARM64() {
    let universal = makeInstallation(id: "universal", architecture: .universal)
    let result = RuntimeSelector.select(from: [universal], request: defaultRequest)
    #expect(result.selected?.id == universal.id)
}

@Test
func universalRuntimeCompatibleOnX8664Host() {
    let universal = makeInstallation(id: "universal", architecture: .universal)
    let intelRequest = RuntimeSelectionRequest(
        hostArchitecture: .x8664,
        rosettaAvailable: false,
        allowFallback: true
    )
    let result = RuntimeSelector.select(from: [universal], request: intelRequest)
    #expect(result.selected?.id == universal.id)
}

@Test
func unknownArchitectureRejected() {
    let unknown = makeInstallation(id: "unknown", architecture: .unknown)
    let result = RuntimeSelector.select(from: [unknown], request: defaultRequest)

    #expect(result.selected == nil)
    #expect(result.failure != nil)
    let eval = result.evaluations.first
    #expect(eval?.rejection == .unknownArchitecture)
}

// MARK: - Unknown host architecture

@Test
func unknownHostRejectsAllRuntimesWithRosetta() {
    let unknownHostRequest = RuntimeSelectionRequest(
        hostArchitecture: .unknown,
        rosettaAvailable: true,
        allowFallback: true
    )
    let arm64 = makeInstallation(id: "arm64", architecture: .arm64)
    let result = RuntimeSelector.select(from: [arm64], request: unknownHostRequest)

    #expect(result.selected == nil)
    #expect(result.failure != nil)
    let eval = result.evaluations.first
    #expect(eval?.rejection == .architectureIncompatible("Host architecture is unknown"))
}

@Test
func unknownHostRejectsAllRuntimesWithoutRosetta() {
    let unknownHostRequest = RuntimeSelectionRequest(
        hostArchitecture: .unknown,
        rosettaAvailable: false,
        allowFallback: true
    )
    let x8664 = makeInstallation(id: "x86_64", architecture: .x8664)
    let result = RuntimeSelector.select(from: [x8664], request: unknownHostRequest)

    #expect(result.selected == nil)
    let eval = result.evaluations.first
    #expect(eval?.rejection == .architectureIncompatible("Host architecture is unknown"))
}

@Test
func unknownHostRejectsUniversalRuntimes() {
    let unknownHostRequest = RuntimeSelectionRequest(
        hostArchitecture: .unknown,
        rosettaAvailable: true,
        allowFallback: true
    )
    let universal = makeInstallation(id: "universal", architecture: .universal)
    let result = RuntimeSelector.select(from: [universal], request: unknownHostRequest)

    #expect(result.selected == nil)
    let eval = result.evaluations.first
    #expect(eval?.rejection == .architectureIncompatible("Host architecture is unknown"))
}

// MARK: - Multiple valid candidates

@Test
func multipleValidCandidatesPicksBestRanked() {
    let wineArm64 = makeInstallation(id: "wine-arm64", provider: .wine, architecture: .arm64)
    let wineX8664 = makeInstallation(id: "wine-x86_64", provider: .wine, architecture: .x8664)
    let crossOver = makeInstallation(id: "crossover", provider: .crossover, architecture: .arm64)

    let result = RuntimeSelector.select(
        from: [wineArm64, wineX8664, crossOver],
        request: defaultRequest
    )

    // CrossOver > Wine, arm64 > x86_64 — CrossOver arm64 should win.
    #expect(result.selected?.id == crossOver.id)
}

// MARK: - Explainable results

@Test
func selectionResultExplainsRejectionReasons() throws {
    let wine = makeInstallation(id: "wine", provider: .wine, status: .validated)
    let notDetected = makeInstallation(id: "nd", provider: .crossover, status: .notDetected)

    let result = RuntimeSelector.select(from: [wine, notDetected], request: defaultRequest)

    #expect(result.selected?.id == wine.id)
    #expect(result.evaluations.count == 2)

    let wineEval = try #require(result.evaluations.first { $0.installation.id == wine.id })
    #expect(wineEval.accepted)
    #expect(wineEval.rejection == nil)

    let ndEval = try #require(result.evaluations.first { $0.installation.id == notDetected.id })
    #expect(!ndEval.accepted)
    #expect(ndEval.rejection != nil)
}

@Test
func preferredProviderEvaluationsIncludePreferenceInfo() throws {
    let crossover = makeInstallation(id: "crossover", provider: .crossover)
    let wine = makeInstallation(id: "wine", provider: .wine)
    let result = RuntimeSelector.select(
        from: [crossover, wine],
        policy: .preferProvider(.crossover),
        request: defaultRequest
    )

    #expect(result.selected?.id == crossover.id)

    let wineEval = try #require(result.evaluations.first { $0.installation.id == wine.id })
    #expect(!wineEval.accepted)
    let rejection = try #require(wineEval.rejection)
    #expect(rejection != .notExactInstallation)
}

// MARK: - Input order independence

@Test
func selectionIsIndependentOfInputOrder() {
    let a = makeInstallation(id: "a", provider: .wine, architecture: .arm64)
    let b = makeInstallation(id: "b", provider: .crossover, architecture: .arm64)

    let result1 = RuntimeSelector.select(from: [a, b], request: defaultRequest)
    let result2 = RuntimeSelector.select(from: [b, a], request: defaultRequest)

    #expect(result1.selected?.id == result2.selected?.id)
}

@Test
func selectionIsIndependentOfInputOrderWithCaseAndNumericIDs() {
    // Exercise IDs with case differences and embedded numbers to confirm the
    // deterministic tie-break is stable across orderings regardless of
    // locale-sensitive or natural/numeric sorting quirks.
    let item9 = makeInstallation(id: "item9", provider: .wine, architecture: .arm64, status: .validated)
    let item10 = makeInstallation(id: "item10", provider: .wine, architecture: .arm64, status: .validated)
    let upperBeta = makeInstallation(id: "Beta", provider: .wine, architecture: .arm64, status: .validated)

    let resultA = RuntimeSelector.select(from: [item9, item10, upperBeta], request: defaultRequest)
    let resultB = RuntimeSelector.select(from: [upperBeta, item10, item9], request: defaultRequest)
    let resultC = RuntimeSelector.select(from: [item10, item9, upperBeta], request: defaultRequest)

    #expect(resultA.selected?.id == resultB.selected?.id)
    #expect(resultB.selected?.id == resultC.selected?.id)
    // Uppercase 'B' (U+0042) sorts before lowercase 'i' (U+0069) under plain
    // Unicode-scalar comparison, so "Beta" wins the tie-break deterministically.
    #expect(resultA.selected?.id == upperBeta.id)
}

// MARK: - Ranking (unit-level)

@Test
func rankCandidatesSortsByStatusFirst() {
    let validated = makeInstallation(id: "v", status: .validated)
    let detected = makeInstallation(id: "d", status: .detected)
    let notDetected = makeInstallation(id: "n", status: .notDetected)

    let ranked = RuntimeSelector.rankCandidates([notDetected, detected, validated])
    #expect(ranked[0].id == validated.id)
    #expect(ranked[1].id == detected.id)
    #expect(ranked[2].id == notDetected.id)
}

@Test
func rankCandidatesSortsByArchitectureWithinSameStatus() {
    let arm64 = makeInstallation(id: "a", architecture: .arm64)
    let universal = makeInstallation(id: "u", architecture: .universal)
    let x8664 = makeInstallation(id: "x", architecture: .x8664)
    let unknown = makeInstallation(id: "?", architecture: .unknown)

    let ranked = RuntimeSelector.rankCandidates([x8664, unknown, arm64, universal])
    #expect(ranked[0].id == arm64.id)
    #expect(ranked[1].id == universal.id)
    #expect(ranked[2].id == x8664.id)
    #expect(ranked[3].id == unknown.id)
}

@Test
func rankCandidatesSortsByProviderWithinSameStatusAndArch() {
    let crossover = makeInstallation(id: "co", provider: .crossover)
    let wine = makeInstallation(id: "wi", provider: .wine)
    let whisky = makeInstallation(id: "wh", provider: .whisky)
    let sikarugir = makeInstallation(id: "si", provider: .sikarugir)

    let ranked = RuntimeSelector.rankCandidates([whisky, crossover, sikarugir, wine])
    #expect(ranked[0].id == crossover.id)
    #expect(ranked[1].id == wine.id)
    #expect(ranked[2].id == whisky.id)
    #expect(ranked[3].id == sikarugir.id)
}

@Test
func rankCandidatesTiesBrokenByID() {
    let beta = makeInstallation(id: "beta", provider: .wine, architecture: .arm64, status: .validated)
    let alpha = makeInstallation(id: "alpha", provider: .wine, architecture: .arm64, status: .validated)

    let ranked = RuntimeSelector.rankCandidates([beta, alpha])
    #expect(ranked[0].id == alpha.id)
    #expect(ranked[1].id == beta.id)
}

@Test
func rankCandidatesTieBreakUsesLocaleIndependentOrdering() {
    // "item9" vs "item10": plain lexicographic (Unicode-scalar) comparison
    // orders "item10" before "item9" because '1' < '9' at the first
    // differing character. A locale-aware "natural sort" (as performed by
    // `localizedStandardCompare`) would instead order "item9" before
    // "item10" by numeric value. The selector must use the former so that
    // ranking does not depend on locale or natural-sort behavior.
    let item9 = makeInstallation(id: "item9", provider: .wine, architecture: .arm64, status: .validated)
    let item10 = makeInstallation(id: "item10", provider: .wine, architecture: .arm64, status: .validated)

    let ranked = RuntimeSelector.rankCandidates([item9, item10])
    #expect(ranked[0].id == item10.id)
    #expect(ranked[1].id == item9.id)
}

// MARK: - Rejection reasons (structured)

@Test
func notValidatedRejectionForDetectedStatus() {
    let detected = makeInstallation(id: "detected", status: .detected)
    let result = RuntimeSelector.select(from: [detected], request: defaultRequest)

    #expect(result.selected == nil)
    let eval = try! #require(result.evaluations.first)
    #expect(eval.rejection == .notValidated(.detected))
}

@Test
func rosettaRejectionForX8664WithoutRosetta() {
    let x8664 = makeInstallation(id: "x86_64", architecture: .x8664)
    let result = RuntimeSelector.select(from: [x8664], request: noRosettaRequest)

    let eval = try! #require(result.evaluations.first)
    #expect(eval.rejection == .rosettaNotAvailable)
}

// MARK: - Selection failure via structured enum

@Test
func selectionFailureHasStructuredReason() {
    let result = RuntimeSelector.select(from: [], request: defaultRequest)
    #expect(result.failure == .noCandidates)
}