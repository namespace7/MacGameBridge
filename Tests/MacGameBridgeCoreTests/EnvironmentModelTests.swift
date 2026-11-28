import Foundation
import Testing

@testable import MacGameBridgeCore

@Test
func environmentJSONRoundTrip() throws {
    let environment = EnvironmentTestFixtures.environment(
        runtimeInstallationID: "wine:/usr/local/bin/wine64"
    )

    let data = try EnvironmentTestFixtures.encoder().encode(environment)
    let decoded = try EnvironmentTestFixtures.decoder().decode(GameEnvironment.self, from: data)

    #expect(decoded == environment)
    #expect(decoded.id == "env-1")
    #expect(decoded.gameProfileID == "game-b")
    #expect(decoded.runtimeInstallationID == "wine:/usr/local/bin/wine64")
    #expect(decoded.name == "Game B environment")
    #expect(decoded.prefixURL.path == environment.prefixPath)
    #expect(decoded.lifecycleState == .planned)
}

@Test
func environmentSerializationIsStable() throws {
    let environment = EnvironmentTestFixtures.environment()
    let first = try EnvironmentTestFixtures.encoder().encode(environment)
    let second = try EnvironmentTestFixtures.encoder().encode(environment)

    #expect(first == second)

    let text = String(decoding: first, as: UTF8.self)
    #expect(text.contains("\"id\""))
    #expect(text.contains("\"lifecycleState\""))
    #expect(text.contains("\"prefixURL\""))
}

@Test
func newEnvironmentDefaultsToPlannedState() {
    let environment = EnvironmentTestFixtures.environment()
    #expect(environment.lifecycleState == .planned)
    #expect(environment.runtimeInstallationID == nil)
}
