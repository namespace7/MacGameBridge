import Foundation

/// Errors raised by the JSON-backed environment registry.
public enum EnvironmentRepositoryError: Error, Equatable, CustomStringConvertible {
    case duplicateID(String)
    case duplicateGamePrefix(id: String, gameProfileID: String, prefixPath: String)
    case environmentNotFound(String)
    case staleRecord(String)
    case corruptedRegistry(URL, String)
    case unreadableRegistry(URL, String)
    case writeFailed(URL, String)
    case invalidEnvironment(String)

    public var description: String {
        switch self {
        case .duplicateID(let id):
            return "An environment with ID '\(id)' already exists. No record was changed."
        case .environmentNotFound(let id):
            return "No environment with ID '\(id)' is recorded. No record was changed."
        case .staleRecord(let id):
            return "Environment '\(id)' changed since it was read. No record was changed; re-read it and retry."
        case .duplicateGamePrefix(let id, let gameProfileID, let prefixPath):
            return "Environment '\(id)' already records game '\(gameProfileID)' at prefix '\(prefixPath)'. Use that ID or choose a different prefix. No record was changed."
        case .corruptedRegistry(let url, let reason):
            return "Environment registry at \(url.path) is corrupted: \(reason). It was left unchanged."
        case .unreadableRegistry(let url, let reason):
            return "Could not read environment registry at \(url.path): \(reason)."
        case .writeFailed(let url, let reason):
            return "Could not write environment registry at \(url.path): \(reason)."
        case .invalidEnvironment(let reason):
            return "Invalid environment record: \(reason)."
        }
    }
}

/// JSON-backed registry for `GameEnvironment` records.
///
/// The registry file contains only metadata. It never creates, modifies, or
/// deletes prefix directories, runtime installations, or game files.
public struct EnvironmentRepository {
    private struct RegistryDocument: Codable {
        let schemaVersion: String
        var environments: [GameEnvironment]
    }

    private static let currentSchemaVersion = "1.0"
    private static let lock = NSLock()

    public let storageURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Default registry location:
    /// `~/Library/Application Support/MacGameBridge/environments.json`.
    public static var defaultStorageURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent("MacGameBridge", isDirectory: true)
            .appendingPathComponent("environments.json", isDirectory: false)
    }

    public init(storageURL: URL? = nil, fileManager: FileManager = .default) {
        self.storageURL = storageURL ?? Self.defaultStorageURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// All recorded environments, sorted by stable ID for deterministic output.
    public func list() throws -> [GameEnvironment] {
        try readDocument().environments.sorted { $0.id < $1.id }
    }

    /// Look up one environment by its stable ID.
    public func get(id: String) throws -> GameEnvironment? {
        try list().first { $0.id == id }
    }

    /// Add a new environment record.
    ///
    /// Duplicate IDs and duplicate game/prefix pairs are rejected. The registry
    /// is read immediately before the write so existing records are preserved;
    /// no cleanup or deletion occurs.
    public func create(_ environment: GameEnvironment) throws {
        try validateRecord(environment)

        Self.lock.lock()
        defer { Self.lock.unlock() }

        var document = try readDocument()
        guard !document.environments.contains(where: { $0.id == environment.id }) else {
            throw EnvironmentRepositoryError.duplicateID(environment.id)
        }

        let prefixPath = normalizedPrefixPath(environment.prefixURL.path)
        if let existing = document.environments.first(where: {
            $0.gameProfileID == environment.gameProfileID
                && normalizedPrefixPath($0.prefixURL.path) == prefixPath
        }) {
            throw EnvironmentRepositoryError.duplicateGamePrefix(
                id: existing.id,
                gameProfileID: existing.gameProfileID,
                prefixPath: normalizedPrefixPath(existing.prefixURL.path)
            )
        }

        document.environments.append(environment)
        document.environments.sort { $0.id < $1.id }
        try writeDocument(document)
    }

    /// Change only the runtime pin and `updatedAt` of an existing record.
    ///
    /// - Parameters:
    ///   - expected: The record as read by the caller. The stored record must be
    ///     equal to it; this rejects stale updates instead of overwriting a
    ///     concurrent change.
    ///   - runtimeInstallationID: The exact installation ID to store, or nil to unpin.
    ///   - updatedAt: Timestamp supplied by the injected time provider.
    /// - Returns: The updated record.
    ///
    /// The read, checks, and atomic write happen under the repository's existing
    /// lock. ID, game profile, name, prefix URL, lifecycle state, and creation
    /// timestamp are copied from the stored record and cannot change here.
    /// Duplicate-ID and duplicate-game-prefix safeguards are re-applied before
    /// writing. No prefix directory is created, modified, or inspected.
    public func updateRuntimeInstallationID(
        for expected: GameEnvironment,
        runtimeInstallationID: String?,
        updatedAt: Date
    ) throws -> GameEnvironment {
        guard !expected.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EnvironmentRepositoryError.invalidEnvironment("ID must not be empty")
        }
        if let runtimeInstallationID,
           runtimeInstallationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw EnvironmentRepositoryError.invalidEnvironment("runtime installation ID must not be empty")
        }

        Self.lock.lock()
        defer { Self.lock.unlock() }

        var document = try readDocument()
        let matchingIndexes = document.environments.indices.filter {
            document.environments[$0].id == expected.id
        }
        guard matchingIndexes.count <= 1 else {
            throw EnvironmentRepositoryError.duplicateID(expected.id)
        }
        guard let index = matchingIndexes.first else {
            throw EnvironmentRepositoryError.environmentNotFound(expected.id)
        }
        guard document.environments[index] == expected else {
            throw EnvironmentRepositoryError.staleRecord(expected.id)
        }

        let current = document.environments[index]
        let updated = GameEnvironment(
            id: current.id,
            gameProfileID: current.gameProfileID,
            runtimeInstallationID: runtimeInstallationID,
            name: current.name,
            prefixURL: current.prefixURL,
            lifecycleState: current.lifecycleState,
            createdAt: current.createdAt,
            updatedAt: updatedAt
        )
        try validateRecord(updated)

        let prefixPath = normalizedPrefixPath(updated.prefixURL.path)
        if let duplicate = document.environments.first(where: {
            $0.id != updated.id
                && $0.gameProfileID == updated.gameProfileID
                && normalizedPrefixPath($0.prefixURL.path) == prefixPath
        }) {
            throw EnvironmentRepositoryError.duplicateGamePrefix(
                id: duplicate.id,
                gameProfileID: duplicate.gameProfileID,
                prefixPath: normalizedPrefixPath(duplicate.prefixURL.path)
            )
        }

        document.environments[index] = updated
        document.environments.sort { $0.id < $1.id }
        try writeDocument(document)
        return updated
    }

    // MARK: - Reading

    private func readDocument() throws -> RegistryDocument {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return RegistryDocument(schemaVersion: Self.currentSchemaVersion, environments: [])
        }

        let data: Data
        do {
            data = try Data(contentsOf: storageURL)
        } catch {
            throw EnvironmentRepositoryError.unreadableRegistry(storageURL, error.localizedDescription)
        }

        let document: RegistryDocument
        do {
            document = try decoder.decode(RegistryDocument.self, from: data)
        } catch {
            throw EnvironmentRepositoryError.corruptedRegistry(storageURL, error.localizedDescription)
        }

        guard document.schemaVersion == Self.currentSchemaVersion else {
            throw EnvironmentRepositoryError.corruptedRegistry(
                storageURL,
                "unsupported schema version '\(document.schemaVersion)'"
            )
        }
        return document
    }

    // MARK: - Writing

    private func writeDocument(_ document: RegistryDocument) throws {
        let data: Data
        do {
            data = try encoder.encode(document)
        } catch {
            throw EnvironmentRepositoryError.writeFailed(storageURL, error.localizedDescription)
        }

        let directory = storageURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw EnvironmentRepositoryError.writeFailed(directory, error.localizedDescription)
            }
        }

        do {
            // Foundation writes to an auxiliary file in the same directory and
            // renames it into place, so readers never observe a partial registry.
            try data.write(to: storageURL, options: .atomic)
        } catch {
            throw EnvironmentRepositoryError.writeFailed(storageURL, error.localizedDescription)
        }
    }

    // MARK: - Record checks

    private func validateRecord(_ environment: GameEnvironment) throws {
        guard !environment.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EnvironmentRepositoryError.invalidEnvironment("ID must not be empty")
        }
        guard !environment.gameProfileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EnvironmentRepositoryError.invalidEnvironment("game profile ID must not be empty")
        }
        guard !environment.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EnvironmentRepositoryError.invalidEnvironment("display name must not be empty")
        }
        guard environment.prefixURL.isFileURL else {
            throw EnvironmentRepositoryError.invalidEnvironment("prefix URL must be a local filesystem URL")
        }
        do {
            // Lexical and read-only: no symlink resolution and no directory access.
            _ = try EnvironmentPrefixPolicy.validate(environment.prefixURL.path)
        } catch let error as EnvironmentPrefixPathError {
            throw EnvironmentRepositoryError.invalidEnvironment("unsafe prefix path: \(error.description)")
        } catch {
            throw EnvironmentRepositoryError.invalidEnvironment("unsafe prefix path: \(error.localizedDescription)")
        }
    }

    /// Canonicalize a stored path for duplicate comparison only.
    ///
    /// This is deliberately not used for acceptance: new records must already
    /// pass `EnvironmentPrefixPolicy.validate` in `validateRecord`.
    private func normalizedPrefixPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
