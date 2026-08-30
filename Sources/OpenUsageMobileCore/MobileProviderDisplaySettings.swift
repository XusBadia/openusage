import Foundation

/// User-owned presentation preferences shared by the iOS app and its WidgetKit extensions.
///
/// The iCloud snapshot remains complete. These settings only decide which providers are presented
/// and in what order, so hiding a provider never deletes its synced data.
public struct MobileProviderDisplaySettings: Codable, Hashable, Sendable {
    public var providerOrder: [String]
    public var hiddenProviderIDs: Set<String>

    public init(
        providerOrder: [String] = [],
        hiddenProviderIDs: Set<String> = []
    ) {
        self.providerOrder = providerOrder.uniqued()
        self.hiddenProviderIDs = hiddenProviderIDs
    }

    public func orderedProviders(from providers: [ResolvedMobileProvider]) -> [ResolvedMobileProvider] {
        let providersByID = Dictionary(uniqueKeysWithValues: providers.map { ($0.provider.providerID, $0) })
        let saved = providerOrder.compactMap { providersByID[$0] }
        let savedIDs = Set(saved.map(\.provider.providerID))
        return saved + providers.filter { !savedIDs.contains($0.provider.providerID) }
    }

    public func visibleProviders(from providers: [ResolvedMobileProvider]) -> [ResolvedMobileProvider] {
        orderedProviders(from: providers).filter { !hiddenProviderIDs.contains($0.provider.providerID) }
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
