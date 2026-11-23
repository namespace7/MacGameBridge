import Foundation

/// Read-only dependencies used by `EnvironmentValidator`.
///
/// Every dependency can be replaced with a fixture, so validation never needs
/// real installed runtimes or the repository's live game catalog in tests.
public struct EnvironmentValidationDependencies {
    public let gameProfiles: () throws -> [GameProfile]
    public let runtimeInstallations: () -> [ProviderInstallation]
    public let fileManager: FileManager
    public let validatePrefixPath: (String) throws -> URL

    public init(
        gameProfiles: @escaping () throws -> [GameProfile] = { try GameProfileCatalog.load() },
        runtimeInstallations: @escaping () -> [ProviderInstallation] = {
            RuntimeScanner.scan(paths: .current).installations
        },
        fileManager: FileManager = .default,
        validatePrefixPath: @escaping (String) throws -> URL = { try EnvironmentPrefixPolicy.validate($0) }
    ) {
        self.gameProfiles = gameProfiles
        self.runtimeInstallations = runtimeInstallations
        self.fileManager = fileManager
        self.validatePrefixPath = validatePrefixPath
    }
}

public enum EnvironmentValidationSeverity: String, Codable, Sendable {
    case error
    case warning
    case info
}

public enum EnvironmentValidationIssueCode: String, Codable, Sendable {
    case gameCatalogUnavailable = "game_catalog_unavailable"
    case gameProfileMissing = "game_profile_missing"
    case runtimeInstallationMissing = "runtime_installation_missing"
    case runtimeInstallationUnvalidated = "runtime_installation_unvalidated"
    case runtimeArchitectureUnknown = "runtime_architecture_unknown"
    case prefixPathInvalid = "prefix_path_invalid"
    case prefixPathIsFile = "prefix_path_is_file"
    case prefixDirectoryExists = "prefix_directory_exists"
    case environmentNotProvisioned = "environment_not_provisioned"
    case provisionedStateUnsupported = "provisioned_state_unsupported"
    case runtimeNotPinned = "runtime_not_pinned"
}

public struct EnvironmentValidationIssue: Codable, Equatable, Sendable {
    public let code: EnvironmentValidationIssueCode
    public let severity: EnvironmentValidationSeverity
    public let message: String

    public init(
        code: EnvironmentValidationIssueCode,
        severity: EnvironmentValidationSeverity,
        message: String
    ) {
        self.code = code
        self.severity = severity
        self.message = message
    }
}

/// How much evidence exists that an environment's prefix was initialized.
///
/// This MVP has no provisioning path, so only `notInitialized` can be produced.
public enum PrefixInitializationStatus: String, Codable, Sendable {
    case notInitialized = "not_initialized"
}

public struct EnvironmentValidationReport: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let environmentID: String
    public let lifecycleState: EnvironmentLifecycleState
    public let isValid: Bool
    public let issues: [EnvironmentValidationIssue]
    public let prefixDirectoryExists: Bool
    public let prefixInitializationStatus: PrefixInitializationStatus

    /// Always false in this MVP: no environment can be launched or provisioned.
    public let readyToLaunch: Bool

    public init(
        schemaVersion: String = "1.0",
        environmentID: String,
        lifecycleState: EnvironmentLifecycleState,
        isValid: Bool,
        issues: [EnvironmentValidationIssue],
        prefixDirectoryExists: Bool,
        prefixInitializationStatus: PrefixInitializationStatus = .notInitialized,
        readyToLaunch: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.environmentID = environmentID
        self.lifecycleState = lifecycleState
        self.isValid = isValid
        self.issues = issues
        self.prefixDirectoryExists = prefixDirectoryExists
        self.prefixInitializationStatus = prefixInitializationStatus
        self.readyToLaunch = readyToLaunch
    }
}

/// Read-only validation of environment metadata.
///
/// Validation never creates a prefix, initializes Wine, installs software, or
/// changes an environment's lifecycle state. A directory existing at the
/// intended prefix path is reported as information, not as provisioning
/// evidence.
public enum EnvironmentValidator {
    public static func validate(
        _ environment: GameEnvironment,
        using dependencies: EnvironmentValidationDependencies = EnvironmentValidationDependencies()
    ) -> EnvironmentValidationReport {
        var issues: [EnvironmentValidationIssue] = []

        do {
            // A successfully loaded catalogue is authoritative, even when empty:
            // any referenced profile is then missing.
            let profiles = try dependencies.gameProfiles()
            if !profiles.contains(where: { $0.id == environment.gameProfileID }) {
                issues.append(
                    EnvironmentValidationIssue(
                        code: .gameProfileMissing,
                        severity: .error,
                        message: "Referenced game profile '\(environment.gameProfileID)' was not found."
                    )
                )
            }
        } catch {
            // A loading failure is reported on its own; absence cannot be
            // concluded from a catalogue that could not be read.
            issues.append(
                EnvironmentValidationIssue(
                    code: .gameCatalogUnavailable,
                    severity: .error,
                    message: "Game catalog could not be loaded: \(error.localizedDescription)"
                )
            )
        }

        if let runtimeID = environment.runtimeInstallationID {
            if let installation = dependencies.runtimeInstallations().first(where: { $0.id == runtimeID }) {
                if installation.status != .validated {
                    issues.append(
                        EnvironmentValidationIssue(
                            code: .runtimeInstallationUnvalidated,
                            severity: .error,
                            message: "Runtime installation '\(runtimeID)' has status '\(installation.status.rawValue)'; only validated installations are eligible."
                        )
                    )
                }
                if installation.architecture == .unknown {
                    issues.append(
                        EnvironmentValidationIssue(
                            code: .runtimeArchitectureUnknown,
                            severity: .warning,
                            message: "Runtime installation '\(runtimeID)' has unknown architecture."
                        )
                    )
                }
            } else {
                issues.append(
                    EnvironmentValidationIssue(
                        code: .runtimeInstallationMissing,
                        severity: .error,
                        message: "Referenced runtime installation '\(runtimeID)' could not be resolved."
                    )
                )
            }
        } else {
            issues.append(
                EnvironmentValidationIssue(
                    code: .runtimeNotPinned,
                    severity: .info,
                    message: "No runtime installation is pinned. A validated runtime must be selected before provisioning."
                )
            )
        }

        var prefixDirectoryExists = false
        if environment.prefixURL.isFileURL {
            do {
                let prefixURL = try dependencies.validatePrefixPath(environment.prefixPath)
                var isDirectory: ObjCBool = false
                if dependencies.fileManager.fileExists(atPath: prefixURL.path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        prefixDirectoryExists = true
                        issues.append(
                            EnvironmentValidationIssue(
                                code: .prefixDirectoryExists,
                                severity: .info,
                                message: "A directory exists at '\(prefixURL.path)'. Directory presence is not evidence of Wine prefix initialization."
                            )
                        )
                    } else {
                        issues.append(
                            EnvironmentValidationIssue(
                                code: .prefixPathIsFile,
                                severity: .error,
                                message: "Intended prefix path '\(prefixURL.path)' is a regular file, not a directory."
                            )
                        )
                    }
                }
            } catch {
                issues.append(
                    EnvironmentValidationIssue(
                        code: .prefixPathInvalid,
                        severity: .error,
                        message: "Invalid prefix path '\(environment.prefixPath)': \(error.localizedDescription)"
                    )
                )
            }
        } else {
            // Non-file URLs are metadata errors only. Do not pass their path to
            // the lexical policy or inspect any filesystem location.
            issues.append(
                EnvironmentValidationIssue(
                    code: .prefixPathInvalid,
                    severity: .error,
                    message: "Intended prefix URL '\(environment.prefixURL.absoluteString)' is not a local filesystem URL."
                )
            )
        }

        if environment.lifecycleState == .provisioned {
            issues.append(
                EnvironmentValidationIssue(
                    code: .provisionedStateUnsupported,
                    severity: .error,
                    message: "Recorded state is 'provisioned', but this MVP has no provisioning evidence; metadata alone cannot establish a ready prefix."
                )
            )
        } else {
            issues.append(
                EnvironmentValidationIssue(
                    code: .environmentNotProvisioned,
                    severity: .info,
                    message: "Environment is planned; validation does not initialize prefixes or change lifecycle state."
                )
            )
        }

        let isValid = !issues.contains { $0.severity == .error }
        return EnvironmentValidationReport(
            environmentID: environment.id,
            lifecycleState: environment.lifecycleState,
            isValid: isValid,
            issues: issues,
            prefixDirectoryExists: prefixDirectoryExists
        )
    }
}
