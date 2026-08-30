import XCTest
@testable import OpenUsageMobileCore

final class MobileUsageHistoryTests: XCTestCase {
    func testAggregatesNewestDocumentPerDevice() throws {
        let old = document(device: "mac-a", updatedAt: Date(timeIntervalSince1970: 100), tokens: 10, cost: 1)
        let replacement = document(device: "mac-a", updatedAt: Date(timeIntervalSince1970: 200), tokens: 20, cost: 2)
        let peer = document(device: "mac-b", updatedAt: Date(timeIntervalSince1970: 150), tokens: 30, cost: nil)

        for value in [old, replacement, peer] { try value.validate() }
        let totals = MobileHistoryAggregator.totals(from: [old, replacement, peer])

        XCTAssertEqual(totals, [MobileDailyTotal(date: "2026-08-29", totalTokens: 50, costUSD: 2)])
    }

    private func document(device: String, updatedAt: Date, tokens: Int, cost: Double?) -> MobileUsageHistoryDocument {
        MobileUsageHistoryDocument(
            schema: "openusage.history.v1",
            deviceID: device,
            deviceName: device,
            updatedAt: updatedAt,
            providers: [
                "claude": MobileProviderUsageHistory(
                    series: MobileDailyUsageSeries(
                        daily: [MobileDailyUsageEntry(date: "2026-08-29", totalTokens: tokens, costUSD: cost)]
                    )
                )
            ]
        )
    }
}
