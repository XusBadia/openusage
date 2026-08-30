import Foundation
import Observation
import OpenUsageMobileCore
import WidgetKit

struct MobileDeviceSummary: Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var updatedAt: Date
    var publishesStatus: Bool
    var publishesHistory: Bool
}

@MainActor
@Observable
final class MobileDashboardStore {
    enum Phase: Equatable {
        case loading
        case waitingForMac
        case content
        case failure(String)
    }

    private let reader: any MobileSnapshotReading
    private let sharedStore: MobileSharedSnapshotStore
    private let usesPreviewData: Bool

    var phase: Phase = .loading
    private(set) var allProviders: [ResolvedMobileProvider] = []
    var dailyTotals: [MobileDailyTotal] = []
    var providerDailyTotals: [String: [MobileDailyTotal]] = [:]
    var devices: [MobileDeviceSummary] = []
    var invalidFileCount = 0
    var lastReadAt: Date?
    var refreshNotice: String?
    private(set) var isRefreshing = false
    private(set) var hidesFinancialValues: Bool
    private(set) var providerDisplaySettings: MobileProviderDisplaySettings

    init(
        reader: any MobileSnapshotReading = ICloudMobileReader(),
        appGroupIdentifier: String = AppConfiguration.appGroupIdentifier,
        usesPreviewData: Bool = AppConfiguration.usesPreviewData
    ) {
        self.reader = reader
        self.sharedStore = MobileSharedSnapshotStore(suiteName: appGroupIdentifier)
        self.usesPreviewData = usesPreviewData
        self.hidesFinancialValues = sharedStore.hidesFinancialValues
        self.providerDisplaySettings = sharedStore.providerDisplaySettings

        if usesPreviewData {
            apply(PreviewFixtures.make())
        } else if let cached = sharedStore.load(), !cached.providers.isEmpty {
            allProviders = cached.providers
            dailyTotals = cached.dailyTotals
            lastReadAt = cached.cachedAt
            phase = .content
        }
    }

    var today: MobileDailyTotal? {
        let key = Self.dayKey(Date())
        return totals(for: nil).first { $0.date == key }
    }

    var providers: [ResolvedMobileProvider] {
        providerDisplaySettings.visibleProviders(from: allProviders)
    }

    var customizableProviders: [ResolvedMobileProvider] {
        providerDisplaySettings.orderedProviders(from: allProviders)
    }

    var providerListIsCustomized: Bool {
        !providerDisplaySettings.providerOrder.isEmpty || !providerDisplaySettings.hiddenProviderIDs.isEmpty
    }

    var freshestUpdate: Date? {
        providers.map(\.provider.refreshedAt).max()
    }

    var historyProviderIDs: [String] {
        let historyIDs = Set(providerDailyTotals.keys)
        return providers.map(\.provider.providerID).filter(historyIDs.contains)
    }

    func totals(for providerID: String?) -> [MobileDailyTotal] {
        if let providerID { return providerDailyTotals[providerID] ?? [] }
        guard !providerDailyTotals.isEmpty else { return dailyTotals }

        var totalsByDay: [String: (tokens: Int, cost: Double?)] = [:]
        for providerID in providers.map(\.provider.providerID) {
            for entry in providerDailyTotals[providerID] ?? [] {
                let existing = totalsByDay[entry.date] ?? (0, nil)
                let costs = [existing.cost, entry.costUSD].compactMap { $0 }
                totalsByDay[entry.date] = (
                    existing.tokens + entry.totalTokens,
                    costs.isEmpty ? nil : costs.reduce(0, +)
                )
            }
        }
        return totalsByDay.map {
            MobileDailyTotal(date: $0.key, totalTokens: $0.value.tokens, costUSD: $0.value.cost)
        }
        .sorted { $0.date < $1.date }
    }

    func providerName(for id: String) -> String {
        allProviders.first { $0.provider.providerID == id }?.provider.displayName ?? id.capitalized
    }

    func refresh() async {
        guard !usesPreviewData, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let result = try await reader.load()
            let resolved = MobileUsageResolver.resolve(result.usageDocuments)
            let totals = MobileHistoryAggregator.totals(from: result.historyDocuments)
            allProviders = resolved
            dailyTotals = totals
            let historyProviderIDs = Set(result.historyDocuments.flatMap { $0.providers.keys })
            providerDailyTotals = Dictionary(uniqueKeysWithValues: historyProviderIDs.map { providerID in
                (
                    providerID,
                    MobileHistoryAggregator.totals(from: result.historyDocuments, providerIDs: Set([providerID]))
                )
            })
            devices = Self.resolveDevices(status: result.usageDocuments, history: result.historyDocuments)
            invalidFileCount = result.invalidFileCount
            lastReadAt = Date()
            refreshNotice = nil
            phase = resolved.isEmpty ? .waitingForMac : .content
            let cache = MobileSharedSnapshot(cachedAt: Date(), providers: resolved, dailyTotals: totals)
            try sharedStore.save(cache)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            refreshNotice = error.localizedDescription
            if allProviders.isEmpty {
                phase = .failure(error.localizedDescription)
            }
        }
    }

    func setHidesFinancialValues(_ value: Bool) {
        hidesFinancialValues = value
        sharedStore.hidesFinancialValues = value
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setProvider(_ providerID: String, isVisible: Bool) {
        guard allProviders.contains(where: { $0.provider.providerID == providerID }) else { return }
        if isVisible {
            providerDisplaySettings.hiddenProviderIDs.remove(providerID)
        } else {
            providerDisplaySettings.hiddenProviderIDs.insert(providerID)
        }
        persistProviderDisplaySettings()
    }

    func moveProviders(fromOffsets: IndexSet, toOffset: Int) {
        var ids = customizableProviders.map(\.provider.providerID)
        let validOffsets = fromOffsets.filter(ids.indices.contains).sorted()
        guard !validOffsets.isEmpty else { return }
        let moving = validOffsets.map { ids[$0] }
        for offset in validOffsets.reversed() { ids.remove(at: offset) }
        let removedBeforeDestination = validOffsets.filter { $0 < toOffset }.count
        let destination = max(0, min(ids.count, toOffset - removedBeforeDestination))
        ids.insert(contentsOf: moving, at: destination)
        providerDisplaySettings.providerOrder = ids
        persistProviderDisplaySettings()
    }

    func resetProviderDisplaySettings() {
        providerDisplaySettings = MobileProviderDisplaySettings()
        persistProviderDisplaySettings()
    }

    private func apply(_ fixture: MobilePreviewData) {
        allProviders = fixture.providers
        dailyTotals = fixture.dailyTotals
        providerDailyTotals = fixture.providerDailyTotals
        devices = fixture.devices
        lastReadAt = Date()
        phase = .content
    }

    private func persistProviderDisplaySettings() {
        sharedStore.providerDisplaySettings = providerDisplaySettings
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func resolveDevices(
        status: [MobileUsageDocument],
        history: [MobileUsageHistoryDocument]
    ) -> [MobileDeviceSummary] {
        var result: [String: MobileDeviceSummary] = [:]
        for document in MobileUsageDocument.newestByDevice(status) {
            result[document.deviceID] = MobileDeviceSummary(
                id: document.deviceID,
                name: document.deviceName,
                updatedAt: document.updatedAt,
                publishesStatus: true,
                publishesHistory: false
            )
        }
        for document in MobileUsageHistoryDocument.newestByDevice(history) {
            if var existing = result[document.deviceID] {
                existing.updatedAt = max(existing.updatedAt, document.updatedAt)
                existing.publishesHistory = true
                result[document.deviceID] = existing
            } else {
                result[document.deviceID] = MobileDeviceSummary(
                    id: document.deviceID,
                    name: document.deviceName,
                    updatedAt: document.updatedAt,
                    publishesStatus: false,
                    publishesHistory: true
                )
            }
        }
        return result.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
