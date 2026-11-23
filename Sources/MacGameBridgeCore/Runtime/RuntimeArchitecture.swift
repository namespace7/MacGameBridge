import Foundation

/// Executable architectures supported by MacGameBridge.
///
/// These represent the Mach-O slice architecture of a runtime executable,
/// independent of the host architecture.
public enum RuntimeArchitecture: String, Codable, CaseIterable, Sendable {
    case arm64 = "arm64"
    case x8664 = "x86_64"
    case universal = "universal"
    case unknown = "unknown"

    public var displayName: String {
        switch self {
        case .arm64: return "ARM64"
        case .x8664: return "x86_64"
        case .universal: return "Universal (ARM64 + x86_64)"
        case .unknown: return "Unknown"
        }
    }
}