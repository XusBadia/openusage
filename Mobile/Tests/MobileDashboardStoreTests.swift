import XCTest
import OpenUsageMobileCore
@testable import UsageCompanion

@MainActor
final class MobileDashboardStoreTests: XCTestCase {
    func testRoomyRelativeTimesKeepTheMinuteRemainder() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let eightyMinutes: TimeInterval = 80 * 60

        XCTAssertEqual(MobileFormatting.reset(now.addingTimeInterval(eightyMinutes), now: now),
                       "Resets in 1h 20m")
        XCTAssertEqual(MobileFormatting.age(now.addingTimeInterval(-eightyMinutes), now: now),
                       "1h 20m ago")
    }

    func testRelativeTimeBoundariesStayFriendly() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertEqual(MobileFormatting.reset(now, now: now), "Reset due")
        XCTAssertEqual(MobileFormatting.age(now.addingTimeInterval(-59), now: now), "just now")
        XCTAssertEqual(MobileFormatting.age(now.addingTimeInterval(60), now: now), "just now")
    }

    func testRefreshResolvesNewestProviderAndBuildsHistory() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reader = TestMobileReader(result: .init(
            usageDocuments: [usageDocument(now: now)],
            historyDocuments: [historyDocument(now: now)],
            invalidFileCount: 0
        ))
        let store = MobileDashboardStore(
            reader: reader,
            appGroupIdentifier: "OpenUsageTests.Mobile.\(UUID().uuidString)",
            usesPreviewData: false
        )

        await store.refresh()

        XCTAssertEqual(store.phase, .content)
        XCTAssertEqual(store.providers.first?.provider.providerID, "claude")
        XCTAssertEqual(store.dailyTotals.first?.totalTokens, 42)
        XCTAssertEqual(store.devices.first?.publishesStatus, true)
        XCTAssertEqual(store.devices.first?.publishesHistory, true)
    }

    func testProviderVisibilityAndOrderPersistForWidgets() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let suiteName = "OpenUsageTests.Mobile.Display.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let reader = TestMobileReader(result: .init(
            usageDocuments: [usageDocument(now: now, includesCodex: true)],
            historyDocuments: [historyDocument(now: now, includesCodex: true)],
            invalidFileCount: 0
        ))
        let store = MobileDashboardStore(
            reader: reader,
            appGroupIdentifier: suiteName,
            usesPreviewData: false
        )
        await store.refresh()

        store.moveProviders(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        store.setProvider("claude", isVisible: false)

        XCTAssertEqual(store.customizableProviders.map(\.provider.providerID), ["codex", "claude"])
        XCTAssertEqual(store.providers.map(\.provider.providerID), ["codex"])
        XCTAssertEqual(store.totals(for: nil).first?.totalTokens, 10)
        let sharedSettings = MobileSharedSnapshotStore(suiteName: suiteName).providerDisplaySettings
        XCTAssertEqual(sharedSettings.providerOrder, ["codex", "claude"])
        XCTAssertEqual(sharedSettings.hiddenProviderIDs, ["claude"])
    }

    private func usageDocument(now: Date, includesCodex: Bool = false) -> MobileUsageDocument {
        let claude = provider(id: "claude", name: "Claude", now: now)
        let codex = provider(id: "codex", name: "Codex", now: now)
        let order = includesCodex ? ["claude", "codex"] : ["claude"]
        let providers = includesCodex ? ["claude": claude, "codex": codex] : ["claude": claude]
        return MobileUsageDocument(
            deviceID: "mac-a",
            deviceName: "Mac",
            updatedAt: now,
            providerOrder: order,
            providers: providers
        )
    }

    private func provider(id: String, name: String, now: Date) -> MobileProviderSnapshot {
        MobileProviderSnapshot(
            providerID: id,
            displayName: name,
            refreshedAt: now,
            metrics: [
                MobileUsageMetric(
                    id: "\(id).session",
                    label: "Session",
                    presentation: .progress,
                    used: 20,
                    limit: 100,
                    unit: MobileMetricUnit(kind: .percent)
                )
            ]
        )
    }

    private func historyDocument(now: Date, includesCodex: Bool = false) -> MobileUsageHistoryDocument {
        var providers = [
            "claude": MobileProviderUsageHistory(
                series: MobileDailyUsageSeries(
                    daily: [MobileDailyUsageEntry(date: "2033-05-18", totalTokens: 42, costUSD: 1)]
                )
            )
        ]
        if includesCodex {
            providers["codex"] = MobileProviderUsageHistory(
                series: MobileDailyUsageSeries(
                    daily: [MobileDailyUsageEntry(date: "2033-05-18", totalTokens: 10, costUSD: 2)]
                )
            )
        }
        return MobileUsageHistoryDocument(
            schema: "openusage.history.v1",
            deviceID: "mac-a",
            deviceName: "Mac",
            updatedAt: now,
            providers: providers
        )
    }
}

private actor TestMobileReader: MobileSnapshotReading {
    let result: ICloudMobileReadResult

    init(result: ICloudMobileReadResult) {
        self.result = result
    }

    func load() async throws -> ICloudMobileReadResult { result }
}
