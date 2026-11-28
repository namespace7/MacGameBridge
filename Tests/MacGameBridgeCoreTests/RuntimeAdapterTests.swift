import Foundation
import Testing

@testable import MacGameBridgeCore

// MARK: - Wine adapter validation

@Test
func wineAdapterAcceptsValidatedStandaloneInstallation() throws {
    let installation = EnvironmentTestFixtures.installation(
        id: "wine:/opt/wine/bin/wine64",
        path: "/opt/wine/bin/wine64"
    )
    let adapter = WineRuntimeAdapter()

    #expect(adapter.providerID == .wine)
    #expect(adapter.capabilities.readOnlyValidation)
    #expect(adapter.capabilities.exactPinning)
    #expect(!adapter.capabilities.provisioning)
    #expect(!adapter.capabilities.launchConfiguration)

    let result = try adapter.validate(installation, host: EnvironmentTestFixtures.host())
    #expect(result.isEligible)
    #expect(result.issues.isEmpty)
    #expect(result.architectureRejection == nil)
    #expect(result.installationID == installation.id)
    #expect(result.providerID == .wine)
}

@Test
func wineAdapterRejectsInstallationFromAnotherProvider() {
    let crossover = EnvironmentTestFixtures.installation(
        id: "crossover:/Applications/CrossOver.app",
        provider: .crossover,
        bundleURL: URL(fileURLWithPath: "/Applications/CrossOver.app")
    )

    do {
        _ = try WineRuntimeAdapter().validate(crossover, host: EnvironmentTestFixtures.host())
        Issue.record("Expected a provider mismatch")
    } catch let error as RuntimeAdapterError {
        #expect(error == .providerMismatch(expected: .wine, actual: .crossover))
        #expect(error.description.contains("crossover"))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test
func wineAdapterRejectsWrapperShapeForStandaloneProvider() throws {
    let wrapped = EnvironmentTestFixtures.installation(
        id: "wine:/Applications/Whisky.app",
        bundleURL: URL(fileURLWithPath: "/Applications/Whisky.app"),
        path: "/Applications/Whisky.app/Contents/SharedSupport/wine/bin/wine64"
    )

    let result = try WineRuntimeAdapter().validate(wrapped, host: EnvironmentTestFixtures.host())
    #expect(!result.isEligible)
    #expect(result.issues.map(\.code) == [.unsupportedInstallationShape])
}

@Test
func wineAdapterRejectsUnvalidatedInstallation() throws {
    let detected = EnvironmentTestFixtures.installation(status: .detected)

    let result = try WineRuntimeAdapter().validate(detected, host: EnvironmentTestFixtures.host())
    #expect(!result.isEligible)
    #expect(result.issues.map(\.code).contains(.statusNotValidated))
}

@Test
func wineAdapterUsesInjectedRosettaFactsForArchitecture() throws {
    let x8664 = EnvironmentTestFixtures.installation(
        id: "wine:/opt/wine/bin/wine",
        architecture: .x8664,
        path: "/opt/wine/bin/wine"
    )
    let adapter = WineRuntimeAdapter()

    let withoutRosetta = try adapter.validate(
        x8664,
        host: EnvironmentTestFixtures.host(rosetta: .notVerified)
    )
    #expect(!withoutRosetta.isEligible)
    #expect(withoutRosetta.architectureRejection == .rosettaNotAvailable)
    #expect(withoutRosetta.issues.map(\.code).contains(.architectureIncompatible))

    let withRosetta = try adapter.validate(
        x8664,
        host: EnvironmentTestFixtures.host(rosetta: .verified)
    )
    #expect(withRosetta.isEligible)
    #expect(withRosetta.architectureRejection == nil)
}

@Test
func wineAdapterRejectsUnknownArchitecture() throws {
    let unknown = EnvironmentTestFixtures.installation(architecture: .unknown)

    let result = try WineRuntimeAdapter().validate(unknown, host: EnvironmentTestFixtures.host())
    #expect(!result.isEligible)
    #expect(result.issues.map(\.code).contains(.unknownArchitecture))
    #expect(result.architectureRejection == .unknownArchitecture)
}

@Test
func wineAdapterValidationIsMetadataOnly() throws {
    // The path does not exist. Validation must still be a pure metadata check
    // on the already-discovered installation; it must never probe the binary.
    let fixture = EnvironmentTestFixtures.installation(
        id: "wine:/definitely/not/installed/wine64",
        path: "/definitely/not/installed/wine64"
    )
    #expect(!FileManager.default.fileExists(atPath: fixture.wineExecutableURL!.path))

    let result = try WineRuntimeAdapter().validate(fixture, host: EnvironmentTestFixtures.host())
    #expect(result.isEligible)
}

// MARK: - Registry

@Test
func registryResolvesWineAndExplicitlyRejectsUnsupportedProviders() throws {
    let registry = RuntimeAdapterRegistry.default
    #expect(registry.supportedProviders == [.wine])
    #expect(registry.supports(.wine))
    #expect(!registry.supports(.crossover))

    let resolved = try registry.adapter(for: .wine)
    #expect(resolved.providerID == .wine)

    for provider in [RuntimeProviderID.crossover, .whisky, .sikarugir] {
        #expect(!registry.supports(provider))
        do {
            _ = try registry.adapter(for: provider)
            Issue.record("Expected unsupported provider error for \(provider.rawValue)")
        } catch let error as RuntimeAdapterError {
            #expect(error == .unsupportedProvider(provider))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

@Test
func customRegistryCanBeEmpty() {
    let registry = RuntimeAdapterRegistry(adapters: [])
    #expect(registry.supportedProviders.isEmpty)
    #expect(!registry.supports(.wine))
}
