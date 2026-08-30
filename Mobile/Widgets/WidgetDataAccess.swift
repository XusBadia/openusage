import Foundation
import OpenUsageMobileCore

enum WidgetDataAccess {
    static var appGroupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
            ?? "group.com.example.usage-companion"
    }

    static func snapshot() -> MobileSharedSnapshot? {
        MobileSharedSnapshotStore(suiteName: appGroupIdentifier).load()
    }

    static var hidesFinancialValues: Bool {
        MobileSharedSnapshotStore(suiteName: appGroupIdentifier).hidesFinancialValues
    }

    static func providers() -> [ResolvedMobileProvider] {
        let store = MobileSharedSnapshotStore(suiteName: appGroupIdentifier)
        return store.providerDisplaySettings.visibleProviders(from: store.load()?.providers ?? [])
    }

    static func provider(id: String?) -> ResolvedMobileProvider? {
        let providers = providers()
        guard let id else { return providers.first }
        return providers.first { $0.provider.providerID == id }
    }
}
