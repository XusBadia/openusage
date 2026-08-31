import XCTest
@testable import OpenUsageMobileCore

final class MobileProviderSortTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testCustomKeepsTheOrderTheListArrivedIn() {
        let settings = MobileProviderDisplaySettings()
        let providers = [
            provider(id: "claude", remaining: 0.9, resetsIn: 7_200),
            provider(id: "codex", remaining: 0.1, resetsIn: 600),
        ]

        XCTAssertEqual(
            settings.sortedProviders(providers, by: .custom).map(\.provider.providerID),
            ["claude", "codex"]
        )
    }

    func testLowestRemainingLeadsWithWhatIsClosestToRunningOut() {
        let settings = MobileProviderDisplaySettings()
        let providers = [
            provider(id: "claude", remaining: 0.9, resetsIn: 7_200),
            provider(id: "codex", remaining: 0.1, resetsIn: 600),
            provider(id: "cursor", remaining: 0.5, resetsIn: 60),
        ]

        XCTAssertEqual(
            settings.sortedProviders(providers, by: .lowestRemaining).map(\.provider.providerID),
            ["codex", "cursor", "claude"]
        )
    }

    func testSoonestResetLeadsWithTheNextResetAndParksUnboundedProvidersLast() {
        let settings = MobileProviderDisplaySettings()
        let providers = [
            provider(id: "claude", remaining: 0.9, resetsIn: 7_200),
            provider(id: "grok", remaining: nil, resetsIn: nil),
            provider(id: "codex", remaining: 0.1, resetsIn: 600),
        ]

        XCTAssertEqual(
            settings.sortedProviders(providers, by: .soonestReset).map(\.provider.providerID),
            ["codex", "claude", "grok"]
        )
        // A provider with no bounded meter has no fraction either, so it parks last there too rather
        // than jumping to the front as a zero.
        XCTAssertEqual(
            settings.sortedProviders(providers, by: .lowestRemaining).map(\.provider.providerID),
            ["codex", "claude", "grok"]
        )
    }

    func testSortsOnTheHeadlineMetricThePersonChose() {
        var settings = MobileProviderDisplaySettings()
        let providers = [
            provider(id: "claude", remaining: 0.9, resetsIn: 7_200, secondRemaining: 0.05),
            provider(id: "codex", remaining: 0.4, resetsIn: 600),
        ]
        XCTAssertEqual(
            settings.sortedProviders(providers, by: .lowestRemaining).map(\.provider.providerID),
            ["codex", "claude"]
        )

        // Promoting Claude's nearly empty second meter to the headline moves Claude to the front.
        settings.updateMetricSettings(for: "claude") { $0.metricOrder = ["claude.second", "claude.session"] }

        XCTAssertEqual(
            settings.sortedProviders(providers, by: .lowestRemaining).map(\.provider.providerID),
            ["claude", "codex"]
        )
    }

    private func provider(
        id: String,
        remaining: Double?,
        resetsIn: TimeInterval?,
        secondRemaining: Double? = nil
    ) -> ResolvedMobileProvider {
        var metrics: [MobileUsageMetric] = []
        if let remaining {
            metrics.append(MobileUsageMetric(
                id: "\(id).session",
                label: "Session",
                presentation: .progress,
                used: (1 - remaining) * 100,
                limit: 100,
                unit: MobileMetricUnit(kind: .percent),
                resetsAt: resetsIn.map { now.addingTimeInterval($0) }
            ))
        } else {
            metrics.append(MobileUsageMetric(
                id: "\(id).balance",
                label: "Balance",
                presentation: .values,
                values: [MobileMetricValue(number: 12, unit: MobileMetricUnit(kind: .dollars))]
            ))
        }
        if let secondRemaining {
            metrics.append(MobileUsageMetric(
                id: "\(id).second",
                label: "Weekly",
                presentation: .progress,
                used: (1 - secondRemaining) * 100,
                limit: 100,
                unit: MobileMetricUnit(kind: .percent)
            ))
        }
        let snapshot = MobileProviderSnapshot(
            providerID: id,
            displayName: id.capitalized,
            refreshedAt: now,
            metrics: metrics
        )
        return ResolvedMobileProvider(
            provider: snapshot,
            deviceID: "mac",
            deviceName: "Mac",
            documentUpdatedAt: now
        )
    }
}
