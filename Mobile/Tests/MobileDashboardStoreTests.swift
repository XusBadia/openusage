import XCTest
import OpenUsageMobileCore
@testable import UsageCompanion

@MainActor
final class MobileDashboardStoreTests: XCTestCase {
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

    private func usageDocument(now: Date) -> MobileUsageDocument {
        let provider = MobileProviderSnapshot(
            providerID: "claude",
            displayName: "Claude",
            refreshedAt: now,
            metrics: [
                MobileUsageMetric(
                    id: "claude.session",
                    label: "Session",
                    presentation: .progress,
                    used: 20,
                    limit: 100,
                    unit: MobileMetricUnit(kind: .percent)
                )
            ]
        )
        return MobileUsageDocument(
            deviceID: "mac-a",
            deviceName: "Mac",
            updatedAt: now,
            providerOrder: ["claude"],
            providers: ["claude": provider]
        )
    }

    private func historyDocument(now: Date) -> MobileUsageHistoryDocument {
        MobileUsageHistoryDocument(
            schema: "openusage.history.v1",
            deviceID: "mac-a",
            deviceName: "Mac",
            updatedAt: now,
            providers: [
                "claude": MobileProviderUsageHistory(
                    series: MobileDailyUsageSeries(
                        daily: [MobileDailyUsageEntry(date: "2033-05-18", totalTokens: 42, costUSD: 1)]
                    )
                )
            ]
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
