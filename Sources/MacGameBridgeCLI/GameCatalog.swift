import Foundation

struct GameProfile: Decodable {
    let id: String
    let title: String
    let editionsToInvestigate: [String]
    let primaryRisks: [String]
    let initialMode: String
}

enum GameCatalog {
    static func printGames() {
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
