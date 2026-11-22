import Foundation

public struct GameProfile: Decodable {
    public let id: String
    public let title: String
    public let editionsToInvestigate: [String]
    public let primaryRisks: [String]
    public let initialMode: String
}

public enum GameCatalog {
    public static func printGames() {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("database/games.json")

        guard let data = try? Data(contentsOf: url),
              let profiles = try? JSONDecoder().decode([GameProfile].self, from: data) else {
            print("Could not load database/games.json.")
            print("Run this command from the MacGameBridge repository root.")
            return
        }

        for profile in profiles {
            print("\n\(profile.title) [\(profile.id)]")
            print("  Editions: \(profile.editionsToInvestigate.joined(separator: ", "))")
            print("  Initial mode: \(profile.initialMode)")
            print("  Risks: \(profile.primaryRisks.joined(separator: "; "))")
        }
    }
}
