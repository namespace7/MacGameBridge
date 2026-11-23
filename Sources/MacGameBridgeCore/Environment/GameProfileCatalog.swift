import Foundation

public enum GameProfileCatalogError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case unavailable(URL, String)
    case invalidFormat(URL, String)

    public var description: String {
        switch self {
        case .unavailable(let url, let reason):
            return "Could not read game catalog at \(url.path): \(reason)"
        case .invalidFormat(let url, let reason):
            return "Game catalog at \(url.path) has an invalid format: \(reason)"
        }
    }

    public var errorDescription: String? { description }
}

/// Loader for the existing `database/games.json` catalog.
///
/// This adds a read-only lookup API without changing the existing `games`
/// command or its JSON contract.
public enum GameProfileCatalog {
    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("database/games.json", isDirectory: false)
    }

    public static func load(from url: URL? = nil) throws -> [GameProfile] {
        let resolvedURL = url ?? defaultURL()

        let data: Data
        do {
            data = try Data(contentsOf: resolvedURL)
        } catch {
            throw GameProfileCatalogError.unavailable(resolvedURL, error.localizedDescription)
        }

        do {
            return try JSONDecoder().decode([GameProfile].self, from: data)
        } catch {
            throw GameProfileCatalogError.invalidFormat(resolvedURL, error.localizedDescription)
        }
    }
}
