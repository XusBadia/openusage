import XCTest
@testable import OpenUsageMobileCore

final class MobileProviderDisplaySettingsTests: XCTestCase {
    func testAppliesSavedOrderVisibilityAndAppendsNewProviders() {
        let input = [
            resolvedProvider(id: "claude"),
            resolvedProvider(id: "codex"),
            resolvedProvider(id: "cursor"),
        ]
        let settings = MobileProviderDisplaySettings(
            providerOrder: ["codex", "claude"],
            hiddenProviderIDs: ["claude"]
        )

        XCTAssertEqual(
            settings.orderedProviders(from: input).map(\.provider.providerID),
            ["codex", "claude", "cursor"]
        )
        XCTAssertEqual(
            settings.visibleProviders(from: input).map(\.provider.providerID),
            ["codex", "cursor"]
        )
    }

    func testSharedStorePersistsDisplaySettings() {
        let suiteName = "OpenUsageMobileCoreTests.Display.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let store = MobileSharedSnapshotStore(suiteName: suiteName)
        let expected = MobileProviderDisplaySettings(
            providerOrder: ["cursor", "codex", "claude"],
            hiddenProviderIDs: ["codex"],
            metricSettings: [
                "claude": MobileMetricDisplaySettings(
                    metricOrder: ["claude.weekly", "claude.session"],
                    hiddenMetricIDs: ["claude.today"],
                    detail: .detailed
                )
            ]
        )

        store.providerDisplaySettings = expected

        XCTAssertEqual(MobileSharedSnapshotStore(suiteName: suiteName).providerDisplaySettings, expected)
    }

    func testMetricOrderVisibilityAndDetailDecideWhatACardShows() {
        let provider = multiMetricProvider()
        var settings = MobileProviderDisplaySettings()

        // Untouched: the progress meter leads and Standard keeps two rows under it.
        let untouched = settings.cardMetrics(for: provider)
        XCTAssertEqual(untouched.headline?.id, "claude.session")
        XCTAssertEqual(untouched.secondary.map(\.id), ["claude.today", "claude.weekly"])

        settings.updateMetricSettings(for: "claude") {
            $0.metricOrder = ["claude.weekly", "claude.session", "claude.credits"]
            $0.hiddenMetricIDs = ["claude.today"]
        }
        XCTAssertEqual(
            settings.visibleMetrics(for: provider).map(\.id),
            ["claude.weekly", "claude.session", "claude.credits"]
        )

        let reordered = settings.cardMetrics(for: provider)
        XCTAssertEqual(reordered.headline?.id, "claude.weekly")
        XCTAssertEqual(reordered.secondary.map(\.id), ["claude.session", "claude.credits"])

        settings.updateMetricSettings(for: "claude") { $0.detail = .compact }
        XCTAssertEqual(settings.cardMetrics(for: provider).secondary, [])

        settings.updateMetricSettings(for: "claude") { $0.detail = .detailed }
        XCTAssertEqual(
            settings.cardMetrics(for: provider).secondary.map(\.id),
            ["claude.session", "claude.credits"]
        )
    }

    func testWidgetHeadlineFallsBackWhenTheChosenMetricIsNoLongerVisible() {
        let provider = multiMetricProvider()
        var settings = MobileProviderDisplaySettings()
        settings.updateMetricSettings(for: "claude") { $0.hiddenMetricIDs = ["claude.credits"] }

        XCTAssertEqual(
            settings.cardMetrics(for: provider, headlineMetricID: "claude.weekly").headline?.id,
            "claude.weekly"
        )
        XCTAssertEqual(
            settings.cardMetrics(for: provider, headlineMetricID: "claude.credits").headline?.id,
            "claude.session"
        )
        XCTAssertEqual(
            settings.cardMetrics(for: provider, headlineMetricID: "claude.retired").headline?.id,
            "claude.session"
        )
    }

    func testCustomizingBackToTheDefaultDropsTheStoredEntry() {
        var settings = MobileProviderDisplaySettings()
        settings.updateMetricSettings(for: "claude") { $0.hiddenMetricIDs = ["claude.today"] }
        XCTAssertEqual(settings.metricSettings.count, 1)

        settings.updateMetricSettings(for: "claude") { $0.hiddenMetricIDs = [] }
        XCTAssertTrue(settings.metricSettings.isEmpty)
    }

    func testDecodesSettingsStoredBeforeMetricPreferencesShipped() throws {
        let stored = Data(#"{"providerOrder":["codex"],"hiddenProviderIDs":["claude"]}"#.utf8)

        let settings = try JSONDecoder().decode(MobileProviderDisplaySettings.self, from: stored)

        XCTAssertEqual(settings.providerOrder, ["codex"])
        XCTAssertEqual(settings.hiddenProviderIDs, ["claude"])
        XCTAssertTrue(settings.metricSettings.isEmpty)
        XCTAssertEqual(settings.metricSettings(for: "codex").detail, .standard)
    }

    private func multiMetricProvider() -> MobileProviderSnapshot {
        MobileProviderSnapshot(
            providerID: "claude",
            displayName: "Claude",
            refreshedAt: Date(timeIntervalSince1970: 100),
            metrics: [
                MobileUsageMetric(
                    id: "claude.today",
                    label: "Today",
                    presentation: .values,
                    values: [MobileMetricValue(number: 4.2, unit: MobileMetricUnit(kind: .dollars))]
                ),
                MobileUsageMetric(
                    id: "claude.session",
                    label: "Session",
                    presentation: .progress,
                    used: 25,
                    limit: 100,
                    unit: MobileMetricUnit(kind: .percent)
                ),
                MobileUsageMetric(
                    id: "claude.weekly",
                    label: "Weekly",
                    presentation: .progress,
                    used: 60,
                    limit: 100,
                    unit: MobileMetricUnit(kind: .percent)
                ),
                MobileUsageMetric(
                    id: "claude.credits",
                    label: "Credits",
                    presentation: .values,
                    values: [MobileMetricValue(number: 12, unit: MobileMetricUnit(kind: .count))]
                ),
            ]
        )
    }

    private func resolvedProvider(id: String) -> ResolvedMobileProvider {
        let provider = MobileProviderSnapshot(
            providerID: id,
            displayName: id.capitalized,
            refreshedAt: Date(timeIntervalSince1970: 100),
            metrics: [
                MobileUsageMetric(
                    id: "\(id).session",
                    label: "Session",
                    presentation: .progress,
                    used: 25,
                    limit: 100,
                    unit: MobileMetricUnit(kind: .percent)
                )
            ]
        )
        return ResolvedMobileProvider(
            provider: provider,
            deviceID: "mac",
            deviceName: "Mac",
            documentUpdatedAt: provider.refreshedAt
        )
    }
}
