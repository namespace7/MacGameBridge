import Foundation

/// Resolves runtime adapters by provider ID.
///
/// Only providers with an explicit adapter are supported. Discovery may still
/// report CrossOver, Whisky, or Sikarugir installations, but the registry must
/// return an explicit unsupported-provider error for them in M3.1.
public struct RuntimeAdapterRegistry: Sendable {
    private let adapters: [RuntimeProviderID: any RuntimeAdapter]

    /// - Parameter adapters: Adapters to register. Duplicate provider IDs are
    ///   ignored after the first registration; pinning itself still requires an
    ///   exact installation ID from discovery.
    public init(adapters: [any RuntimeAdapter] = [WineRuntimeAdapter()]) {
        var resolved: [RuntimeProviderID: any RuntimeAdapter] = [:]
        for adapter in adapters where resolved[adapter.providerID] == nil {
            resolved[adapter.providerID] = adapter
        }
        self.adapters = resolved
    }

    /// Default registry: standalone Wine only.
    public static let `default` = RuntimeAdapterRegistry()

    /// Providers with a registered adapter, sorted for deterministic display.
    public var supportedProviders: [RuntimeProviderID] {
        adapters.keys.sorted { $0.rawValue < $1.rawValue }
    }

    /// Whether an adapter exists for a provider.
    public func supports(_ provider: RuntimeProviderID) -> Bool {
        adapters[provider] != nil
    }

    /// Resolve the adapter for a provider, or throw an explicit error.
    public func adapter(for provider: RuntimeProviderID) throws -> any RuntimeAdapter {
        guard let adapter = adapters[provider] else {
            throw RuntimeAdapterError.unsupportedProvider(provider)
        }
        return adapter
    }
}
