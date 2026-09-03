import Foundation
import OpenUsageMobileCore
import OSLog

enum WidgetDataAccess {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "UsageCompanionWidgets",
        category: "widget"
    )

    static var appGroupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
            ?? "group.com.example.usage-companion"
    }

    private static var store: MobileSharedSnapshotStore {
        MobileSharedSnapshotStore(suiteName: appGroupIdentifier)
    }

    static func cachedSnapshot() -> MobileSharedSnapshot? {
        store.load()
    }

    /// Reads iCloud for this timeline and updates the shared cache, so a widget stays current without
    /// anyone opening the app. A failed read keeps the last cached values rather than blanking the
    /// widget, and says so in the log.
    static func currentSnapshot() async -> MobileSharedSnapshot? {
        do {
            let snapshot = try await MobileSnapshotSync.refresh(
                reader: ICloudMobileReader(),
                store: store
            ).snapshot
            await MobileQuotaNotificationScheduler.shared.evaluateAndSchedule(snapshot: snapshot, store: store)
            return snapshot
        } catch {
            logger.warning("Widget refresh fell back to the cached snapshot: \(error.localizedDescription, privacy: .public)")
            return cachedSnapshot()
        }
    }

    static var hidesFinancialValues: Bool {
        store.hidesFinancialValues
    }

    /// The same provider and metric choices the app screen writes, so a widget never shows something the
    /// person removed from Today.
    static var displaySettings: MobileProviderDisplaySettings {
        store.providerDisplaySettings
    }

    static func providers(in snapshot: MobileSharedSnapshot?) -> [ResolvedMobileProvider] {
        displaySettings.visibleProviders(from: snapshot?.providers ?? [])
    }

    static func provider(id: String?, in snapshot: MobileSharedSnapshot?) -> ResolvedMobileProvider? {
        let providers = providers(in: snapshot)
        guard let id else { return providers.first }
        return providers.first { $0.provider.providerID == id }
    }

    /// Metrics offered when configuring a widget: one provider's when the configuration already names
    /// one, otherwise every visible provider's so a previously chosen metric still resolves. The
    /// configuration sheet reads the cache — the app was just open to reach it.
    static func visibleMetrics(providerID: String?) -> [(provider: MobileProviderSnapshot, metric: MobileUsageMetric)] {
        let settings = displaySettings
        let cached = providers(in: cachedSnapshot())
        let sources = providerID.map { id in cached.filter { $0.provider.providerID == id } } ?? cached
        return sources.flatMap { source in
            settings.visibleMetrics(for: source.provider).map { (source.provider, $0) }
        }
    }
}
