import Foundation

/// Errors surfaced by the `environments` CLI with actionable guidance.
public enum EnvironmentCLIError: Error, Equatable, CustomStringConvertible {
    case missingSubcommand
    case unknownSubcommand(String)
    case missingOption(String)
    case invalidOptionValue(String, String)
    case unknownOption(String)
    case unexpectedArgument(String)
    case gameCatalogUnavailable(String)
    case invalidGameID(String, [String])
    case invalidPrefix(String, String)
    case duplicateEnvironment(id: String, gameProfileID: String, prefixPath: String)
    case environmentNotFound(String)
    case repository(String)

    public var description: String {
        switch self {
        case .missingSubcommand:
            return "Missing environments subcommand. \(EnvironmentCLI.shortUsage)"
        case .unknownSubcommand(let name):
            return "Unknown environments subcommand '\(name)'. \(EnvironmentCLI.shortUsage)"
        case .missingOption(let option):
            return "Missing required value for \(option). \(EnvironmentCLI.shortUsage)"
        case .invalidOptionValue(let option, let reason):
            return "Invalid value for \(option): \(reason)."
        case .unknownOption(let option):
            return "Unknown option '\(option)'. Run `macgamebridge environments help`."
        case .unexpectedArgument(let argument):
            return "Unexpected argument '\(argument)'. \(EnvironmentCLI.shortUsage)"
        case .gameCatalogUnavailable(let reason):
            return "Could not load the game catalog: \(reason). Run the command from the MacGameBridge repository root."
        case .invalidGameID(let id, let knownIDs):
            let available = knownIDs.isEmpty ? "none available" : knownIDs.joined(separator: ", ")
            return "Unknown game ID '\(id)'. Known IDs: \(available). Run `macgamebridge games` to list profiles."
        case .invalidPrefix(let path, let reason):
            return "Invalid prefix path '\(path)': \(reason). Use an absolute, normalized path such as /Users/me/Games/prefixes/my-game. No directory was created."
        case .duplicateEnvironment(let id, let gameProfileID, let prefixPath):
            return "An environment already exists for game '\(gameProfileID)' at prefix '\(prefixPath)' with ID '\(id)'. Run `macgamebridge environments show \(id)` or choose a different prefix."
        case .environmentNotFound(let id):
            return "No environment with ID '\(id)'. Run `macgamebridge environments list` to see recorded IDs."
        case .repository(let reason):
            return "Environment registry error: \(reason)"
        }
    }

    /// Usage errors use exit code 2; operational failures use 1.
    public var exitCode: Int32 {
        switch self {
        case .missingSubcommand, .unknownSubcommand, .missingOption,
             .invalidOptionValue, .unknownOption, .unexpectedArgument,
             .invalidGameID, .invalidPrefix:
            return 2
        case .gameCatalogUnavailable, .duplicateEnvironment,
             .environmentNotFound, .repository:
            return 1
        }
    }
}

public enum EnvironmentCommand: Equatable, Sendable {
    case list(asJSON: Bool)
    case create(gameID: String, name: String, prefixPath: String, asJSON: Bool)
    case show(id: String, asJSON: Bool)
    case validate(id: String, asJSON: Bool)
    case help
}

/// Injectable services for `EnvironmentCLI`.
///
/// Tests replace every external dependency with a fixture so they never use
/// real runtimes, the live game catalog, or the default registry location.
public struct EnvironmentCLIServices {
    public let repository: EnvironmentRepository
    public let loadGameProfiles: () throws -> [GameProfile]
    public let runtimeInstallations: () -> [ProviderInstallation]
    public let fileManager: FileManager
    public let now: () -> Date
    public let makeEnvironmentID: () -> String
    public let validatePrefixPath: (String) throws -> URL

    public init(
        repository: EnvironmentRepository,
        loadGameProfiles: @escaping () throws -> [GameProfile],
        runtimeInstallations: @escaping () -> [ProviderInstallation],
        fileManager: FileManager = .default,
        now: @escaping () -> Date = { Date() },
        makeEnvironmentID: @escaping () -> String = { "env-\(UUID().uuidString)" },
        validatePrefixPath: @escaping (String) throws -> URL = { try EnvironmentPrefixPolicy.validate($0) }
    ) {
        self.repository = repository
        self.loadGameProfiles = loadGameProfiles
        self.runtimeInstallations = runtimeInstallations
        self.fileManager = fileManager
        self.now = now
        self.makeEnvironmentID = makeEnvironmentID
        self.validatePrefixPath = validatePrefixPath
    }

    public static var production: EnvironmentCLIServices {
        EnvironmentCLIServices(
            repository: EnvironmentRepository(),
            loadGameProfiles: { try GameProfileCatalog.load() },
            runtimeInstallations: { RuntimeScanner.scan(paths: .current).installations },
            fileManager: .default
        )
    }
}

/// Parser and runner for `macgamebridge environments ...`.
///
/// Parsing is pure and testable; running returns a string for the CLI layer to
/// print. No function in this type launches a runtime or modifies a prefix.
public enum EnvironmentCLI {
    private struct EnvironmentListResponse: Codable {
        let schemaVersion: String
        let environments: [GameEnvironment]
    }

    public static let shortUsage = "Usage: macgamebridge environments list|create|show|validate [options]"

    public static let helpText = """
    MacGameBridge — environment metadata manager

    Usage:
      macgamebridge environments list [--json]
      macgamebridge environments create --game <id> --name <name> --prefix <absolute-path> [--json]
      macgamebridge environments show <id> [--json]
      macgamebridge environments validate <id> [--json]
      macgamebridge environments help

    Creation saves metadata only. It never creates a prefix directory, runs Wine,
    installs software, or changes system settings. Recorded environments start as
    'planned'; this MVP has no provisioning step.

    """

    // MARK: - Parsing

    public static func parse(_ arguments: [String]) throws -> EnvironmentCommand {
        guard let subcommand = arguments.first else {
            throw EnvironmentCLIError.missingSubcommand
        }

        switch subcommand {
        case "help", "--help", "-h":
            return .help
        case "list":
            var asJSON = false
            for argument in arguments.dropFirst() {
                guard argument == "--json" else {
                    throw EnvironmentCLIError.unknownOption(argument)
                }
                asJSON = true
            }
            return .list(asJSON: asJSON)
        case "create":
            return try parseCreate(Array(arguments.dropFirst()))
        case "show", "validate":
            return try parseIdentifierCommand(subcommand, arguments: Array(arguments.dropFirst()))
        default:
            throw EnvironmentCLIError.unknownSubcommand(subcommand)
        }
    }

    private static func parseCreate(_ arguments: [String]) throws -> EnvironmentCommand {
        var gameID: String?
        var name: String?
        var prefixPath: String?
        var asJSON = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--game", "--name", "--prefix":
                guard index + 1 < arguments.count,
                      !arguments[index + 1].hasPrefix("--") else {
                    throw EnvironmentCLIError.missingOption(argument)
                }
                let value = arguments[index + 1]
                switch argument {
                case "--game":
                    guard gameID == nil else {
                        throw EnvironmentCLIError.invalidOptionValue(argument, "specified more than once")
                    }
                    gameID = value
                case "--name":
                    guard name == nil else {
                        throw EnvironmentCLIError.invalidOptionValue(argument, "specified more than once")
                    }
                    name = value
                default:
                    guard prefixPath == nil else {
                        throw EnvironmentCLIError.invalidOptionValue(argument, "specified more than once")
                    }
                    prefixPath = value
                }
                index += 2
            case "--json":
                asJSON = true
                index += 1
            default:
                throw EnvironmentCLIError.unknownOption(argument)
            }
        }

        guard let gameID, !gameID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EnvironmentCLIError.missingOption("--game")
        }
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EnvironmentCLIError.missingOption("--name")
        }
        guard let prefixPath, !prefixPath.isEmpty else {
            throw EnvironmentCLIError.missingOption("--prefix")
        }

        return .create(gameID: gameID, name: name, prefixPath: prefixPath, asJSON: asJSON)
    }

    private static func parseIdentifierCommand(
        _ subcommand: String,
        arguments: [String]
    ) throws -> EnvironmentCommand {
        var id: String?
        var asJSON = false

        for argument in arguments {
            if argument == "--json" {
                asJSON = true
            } else if argument.hasPrefix("--") {
                throw EnvironmentCLIError.unknownOption(argument)
            } else if id == nil {
                id = argument
            } else {
                throw EnvironmentCLIError.unexpectedArgument(argument)
            }
        }

        guard let id, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EnvironmentCLIError.missingOption("<id>")
        }

        return subcommand == "show"
            ? .show(id: id, asJSON: asJSON)
            : .validate(id: id, asJSON: asJSON)
    }

    // MARK: - Running

    public static func run(
        _ arguments: [String],
        services: EnvironmentCLIServices = .production
    ) throws -> String {
        try execute(parse(arguments), services: services)
    }

    public static func execute(
        _ command: EnvironmentCommand,
        services: EnvironmentCLIServices
    ) throws -> String {
        switch command {
        case .help:
            return helpText
        case .list(let asJSON):
            return try list(asJSON: asJSON, services: services)
        case .create(let gameID, let name, let prefixPath, let asJSON):
            return try create(
                gameID: gameID, name: name, prefixPath: prefixPath,
                asJSON: asJSON, services: services
            )
        case .show(let id, let asJSON):
            return try show(id: id, asJSON: asJSON, services: services)
        case .validate(let id, let asJSON):
            return try validate(id: id, asJSON: asJSON, services: services)
        }
    }

    private static func list(asJSON: Bool, services: EnvironmentCLIServices) throws -> String {
        let environments = try listEnvironments(services: services)
        if asJSON {
            let response = EnvironmentListResponse(
                schemaVersion: "1.0",
                environments: environments
            )
            return try encode(response)
        }

        guard !environments.isEmpty else {
            return "No environments recorded.\nCreate one with: macgamebridge environments create --game <id> --name <name> --prefix <absolute-path>\n"
        }

        var lines = ["MacGameBridge — environments (metadata only)", ""]
        for environment in environments {
            lines.append("\(environment.id)  \(environment.name)")
            lines.append("  State:  \(environment.lifecycleState.rawValue)")
            lines.append("  Game:   \(environment.gameProfileID)")
            lines.append("  Prefix: \(environment.prefixPath)")
            lines.append("  Runtime: \(environment.runtimeInstallationID ?? "not pinned")")
            lines.append("")
        }
        lines.append("Run `macgamebridge environments show <id>` for details.")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func create(
        gameID: String,
        name: String,
        prefixPath: String,
        asJSON: Bool,
        services: EnvironmentCLIServices
    ) throws -> String {
        let profiles: [GameProfile]
        do {
            profiles = try services.loadGameProfiles()
        } catch {
            throw EnvironmentCLIError.gameCatalogUnavailable(error.localizedDescription)
        }

        guard profiles.contains(where: { $0.id == gameID }) else {
            throw EnvironmentCLIError.invalidGameID(gameID, profiles.map(\.id).sorted())
        }

        let prefixURL: URL
        do {
            prefixURL = try services.validatePrefixPath(prefixPath)
        } catch {
            throw EnvironmentCLIError.invalidPrefix(prefixPath, error.localizedDescription)
        }

        let existing = try listEnvironments(services: services)
        if let duplicate = existing.first(where: {
            $0.gameProfileID == gameID && $0.prefixPath == prefixURL.path
        }) {
            throw EnvironmentCLIError.duplicateEnvironment(
                id: duplicate.id,
                gameProfileID: gameID,
                prefixPath: duplicate.prefixPath
            )
        }

        let timestamp = services.now()
        let environment = GameEnvironment(
            id: services.makeEnvironmentID(),
            gameProfileID: gameID,
            name: name,
            prefixURL: prefixURL,
            lifecycleState: .planned,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        do {
            try services.repository.create(environment)
        } catch let error as EnvironmentRepositoryError {
            switch error {
            case .duplicateID(let id):
                throw EnvironmentCLIError.duplicateEnvironment(
                    id: id,
                    gameProfileID: gameID,
                    prefixPath: prefixURL.path
                )
            case .duplicateGamePrefix(let id, let duplicateGameID, let duplicatePrefixPath):
                throw EnvironmentCLIError.duplicateEnvironment(
                    id: id,
                    gameProfileID: duplicateGameID,
                    prefixPath: duplicatePrefixPath
                )
            default:
                throw EnvironmentCLIError.repository(error.description)
            }
        } catch {
            throw EnvironmentCLIError.repository(error.localizedDescription)
        }

        if asJSON {
            return try encode(environment)
        }

        return """
        Created planned environment \(environment.id).
          Name:  \(environment.name)
          Game:  \(environment.gameProfileID)
          Prefix: \(environment.prefixPath) (intended path only; no directory was created)
          Runtime: not pinned

        Metadata was saved. No prefix, runtime, or game was created or launched.
        Next: macgamebridge environments validate \(environment.id)
        """
    }

    private static func show(id: String, asJSON: Bool, services: EnvironmentCLIServices) throws -> String {
        let environment = try requireEnvironment(id: id, services: services)
        if asJSON {
            return try encode(environment)
        }

        let formatter = ISO8601DateFormatter()
        return """
        Environment \(environment.id)
          Name:  \(environment.name)
          Game profile: \(environment.gameProfileID)
          Runtime installation: \(environment.runtimeInstallationID ?? "not pinned")
          Intended prefix: \(environment.prefixPath)
          Recorded state: \(environment.lifecycleState.rawValue) (metadata only; not proof of provisioning)
          Created: \(formatter.string(from: environment.createdAt))
          Updated: \(formatter.string(from: environment.updatedAt))

        Next: macgamebridge environments validate \(environment.id)
        """
    }

    private static func validate(id: String, asJSON: Bool, services: EnvironmentCLIServices) throws -> String {
        let environment = try requireEnvironment(id: id, services: services)
        let dependencies = EnvironmentValidationDependencies(
            gameProfiles: services.loadGameProfiles,
            runtimeInstallations: services.runtimeInstallations,
            fileManager: services.fileManager,
            validatePrefixPath: services.validatePrefixPath
        )
        let report = EnvironmentValidator.validate(environment, using: dependencies)

        if asJSON {
            return try encode(report)
        }

        var lines = [
            "MacGameBridge — environment validation",
            "",
            "ID: \(report.environmentID)",
            "Metadata valid: \(report.isValid ? "yes" : "no")",
            "Recorded state: \(report.lifecycleState.rawValue)",
            "Prefix directory exists: \(report.prefixDirectoryExists ? "yes" : "no") (informational only)",
            "Prefix initialization: \(report.prefixInitializationStatus.rawValue)",
            "Ready to launch: no (no launch or provisioning support in this MVP)",
            ""
        ]

        if report.issues.isEmpty {
            lines.append("Issues: none.")
        } else {
            lines.append("Issues:")
            for issue in report.issues {
                lines.append("  [\(issue.severity.rawValue.uppercased())] \(issue.code.rawValue): \(issue.message)")
            }
        }

        lines.append("")
        lines.append("Validation is read-only. No prefix was initialized and no runtime was launched.")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Helpers

    private static func listEnvironments(services: EnvironmentCLIServices) throws -> [GameEnvironment] {
        do {
            return try services.repository.list()
        } catch {
            throw EnvironmentCLIError.repository(error.localizedDescription)
        }
    }

    private static func requireEnvironment(
        id: String,
        services: EnvironmentCLIServices
    ) throws -> GameEnvironment {
        guard let environment = try listEnvironments(services: services).first(where: { $0.id == id }) else {
            throw EnvironmentCLIError.environmentNotFound(id)
        }
        return environment
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
