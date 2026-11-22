import Foundation

public struct HostInfo: Codable, Equatable {
    public let architecture: String
    public let chip: String
    public let physicalMemoryBytes: UInt64
    public let macOSVersion: String
    public let buildVersion: String
}

public struct GPUInfo: Codable, Equatable {
    public let available: Bool
    public let name: String?
    public let hasUnifiedMemory: Bool?
    public let recommendedMaxWorkingSetBytes: UInt64?
}

public struct RosettaInfo: Codable, Equatable {
    /// "verified", "not_verified", or "unavailable".
    public let status: String
    public let translatedArchitecture: String?
    public let detail: String
}

public struct StorageInfo: Codable, Equatable {
    public let volume: String
    public let totalBytes: UInt64?
    public let availableBytes: UInt64?
}

public struct RuntimeDetection: Codable, Equatable {
    public let name: String
    /// "detected_unverified" or "not_detected".
    public let status: String
    public let evidence: String?
}

public struct DiagnosticReport: Codable, Equatable {
    public let schemaVersion: String
    public let generatedAt: Date
    public let host: HostInfo
    public let gpu: GPUInfo
    public let rosetta: RosettaInfo
    public let storage: StorageInfo
    public let runtimes: [RuntimeDetection]
}
