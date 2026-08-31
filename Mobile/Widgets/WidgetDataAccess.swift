import Foundation
import OpenUsageMobileCore

enum WidgetDataAccess {
    static var appGroupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
            ?? "group.com.example.usage-companion"
    }

    private static var store: MobileSharedSnapshotStore {
        MobileSharedSnapshotStore(suiteName: appGroupIdentifier)
    }

    static func snapshot() -> MobileSharedSnapshot? {
        store.load()
    }

    static var hidesFinancialValues: Bool {
        store.hidesFinancialValues
    }

    /// The same provider and metric choices the app screen writes, so a widget never shows something the
    /// person removed from Today.
    static var displaySettings: MobileProviderDisplaySettings {
        store.providerDisplaySettings
    }

    static func providers() -> [ResolvedMobileProvider] {
        displaySettings.visibleProviders(from: snapshot()?.providers ?? [])
    }

    static func provider(id: String?) -> ResolvedMobileProvider? {
        let providers = providers()
        guard let id else { return providers.first }
        return providers.first { $0.provider.providerID == id }
    }

    /// Metrics offered when configuring a widget: one provider's when the configuration already names
    /// one, otherwise every visible provider's so a previously chosen metric still resolves.
    static func visibleMetrics(providerID: String?) -> [(provider: MobileProviderSnapshot, metric: MobileUsageMetric)] {
        let settings = displaySettings
        let sources = providerID.map { id in providers().filter { $0.provider.providerID == id } } ?? providers()
        return sources.flatMap { source in
            settings.visibleMetrics(for: source.provider).map { (source.provider, $0) }
        }
    }
}
