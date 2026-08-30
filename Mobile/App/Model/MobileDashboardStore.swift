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
    var providers: [ResolvedMobileProvider] = []
    var dailyTotals: [MobileDailyTotal] = []
    var providerDailyTotals: [String: [MobileDailyTotal]] = [:]
    var devices: [MobileDeviceSummary] = []
    var invalidFileCount = 0
    var lastReadAt: Date?
    var refreshNotice: String?
    private(set) var isRefreshing = false
    private(set) var hidesFinancialValues: Bool

    init(
        reader: any MobileSnapshotReading = ICloudMobileReader(),
        appGroupIdentifier: String = AppConfiguration.appGroupIdentifier,
        usesPreviewData: Bool = AppConfiguration.usesPreviewData
    ) {
        self.reader = reader
        self.sharedStore = MobileSharedSnapshotStore(suiteName: appGroupIdentifier)
        self.usesPreviewData = usesPreviewData
        self.hidesFinancialValues = sharedStore.hidesFinancialValues

        if usesPreviewData {
            apply(PreviewFixtures.make())
        } else if let cached = sharedStore.load(), !cached.providers.isEmpty {
            providers = cached.providers
            dailyTotals = cached.dailyTotals
            lastReadAt = cached.cachedAt
            phase = .content
        }
    }

    var today: MobileDailyTotal? {
        let key = Self.dayKey(Date())
        return dailyTotals.first { $0.date == key }
    }

    var freshestUpdate: Date? {
        providers.map(\.provider.refreshedAt).max()
    }

    var historyProviderIDs: [String] {
        Array(Set(providerDailyTotals.keys)).sorted { lhs, rhs in
            providerName(for: lhs).localizedCaseInsensitiveCompare(providerName(for: rhs)) == .orderedAscending
        }
    }

    func totals(for providerID: String?) -> [MobileDailyTotal] {
        guard let providerID else { return dailyTotals }
        return providerDailyTotals[providerID] ?? []
    }

    func providerName(for id: String) -> String {
        providers.first { $0.provider.providerID == id }?.provider.displayName ?? id.capitalized
    }

    func refresh() async {
        guard !usesPreviewData, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let result = try await reader.load()
            let resolved = MobileUsageResolver.resolve(result.usageDocuments)
            let totals = MobileHistoryAggregator.totals(from: result.historyDocuments)
            providers = resolved
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
            if providers.isEmpty {
                phase = .failure(error.localizedDescription)
            }
        }
    }

    func setHidesFinancialValues(_ value: Bool) {
        hidesFinancialValues = value
        sharedStore.hidesFinancialValues = value
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func apply(_ fixture: MobilePreviewData) {
        providers = fixture.providers
        dailyTotals = fixture.dailyTotals
        providerDailyTotals = fixture.providerDailyTotals
        devices = fixture.devices
        lastReadAt = Date()
        phase = .content
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
