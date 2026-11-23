import Foundation

/// Reasons an intended prefix path is rejected.
///
/// These checks are purely lexical: they never inspect, create, or modify the
/// path on disk.
public enum EnvironmentPrefixPathError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case empty
    case containsNullByte
    case notAbsolute(String)
    case notNormalized(String)
    case reserved(String)
    case insideApplicationBundle(String)

    public var description: String {
        switch self {
        case .empty:
            return "Prefix path must not be empty"
        case .containsNullByte:
            return "Prefix path must not contain NUL bytes"
        case .notAbsolute(let path):
            return "Prefix path '\(path)' is not absolute; use a full path starting with /"
        case .notNormalized(let path):
            return "Prefix path '\(path)' must be normalized (no '.', '..', repeated slashes, or trailing slash)"
        case .reserved(let path):
            return "Prefix path '\(path)' is reserved; choose a dedicated directory"
        case .insideApplicationBundle(let path):
            return "Prefix path '\(path)' is inside an application bundle; choose a dedicated directory"
        }
    }

    public var errorDescription: String? { description }
}

/// Read-only safety policy for intended prefix paths.
public enum EnvironmentPrefixPolicy {
    /// Validate and convert a POSIX path into an absolute file URL.
    ///
    /// This function does not touch the file system. A path is accepted only
    /// when it is absolute, normalized, non-empty, not a filesystem root or
    /// home directory, and not inside an `.app` bundle.
    public static func validate(_ path: String) throws -> URL {
        guard !path.isEmpty else { throw EnvironmentPrefixPathError.empty }
        guard !path.utf8.contains(0) else { throw EnvironmentPrefixPathError.containsNullByte }
        guard path.hasPrefix("/") else { throw EnvironmentPrefixPathError.notAbsolute(path) }
        guard !path.contains("//") else { throw EnvironmentPrefixPathError.notNormalized(path) }

        let url = URL(fileURLWithPath: path)
        guard url.standardizedFileURL.path == path else {
            throw EnvironmentPrefixPathError.notNormalized(path)
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.contains("."), !components.contains("..") else {
            throw EnvironmentPrefixPathError.notNormalized(path)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path != "/", path != home else {
            throw EnvironmentPrefixPathError.reserved(path)
        }

        let insideBundle = components.contains { component in
            (component as NSString).pathExtension.lowercased() == "app"
        }
        guard !insideBundle else {
            throw EnvironmentPrefixPathError.insideApplicationBundle(path)
        }

        return url
    }
}
