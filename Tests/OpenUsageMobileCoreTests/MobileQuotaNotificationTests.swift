import XCTest
@testable import OpenUsageMobileCore

final class MobileQuotaNotificationTests: XCTestCase {
    func testFirstObservationPrimesWithoutAlerting() {
        let result = evaluate(used: 85)

        XCTAssertTrue(result.alerts.isEmpty)
        XCTAssertEqual(result.state.observations[metricKey]?.lastUsedFraction ?? -1, 0.85, accuracy: 0.0001)
    }

    func testCrossingProviderThresholdAlertsOncePerWindow() {
        let baseline = evaluate(used: 79)
        let crossed = evaluate(used: 81, previous: baseline.state)
        let repeated = evaluate(used: 90, previous: crossed.state)

        XCTAssertEqual(crossed.alerts.map(\.kind), [.threshold])
        XCTAssertEqual(crossed.alerts.first?.title, "80% Used")
        XCTAssertTrue(repeated.alerts.isEmpty)
    }

    func testJumpingToExhaustedSendsOnlyTheUrgentAlert() {
        let baseline = evaluate(used: 79)
        let exhausted = evaluate(used: 100, previous: baseline.state)

        XCTAssertEqual(exhausted.alerts.map(\.kind), [.exhausted])
        XCTAssertEqual(exhausted.alerts.first?.title, "Limit Reached")
    }

    func testNewResetWindowRearmsButPrimesItsFirstValue() {
        let baseline = evaluate(used: 79, reset: reset)
        let crossed = evaluate(used: 81, reset: reset, previous: baseline.state)
        let newWindow = evaluate(used: 10, reset: reset.addingTimeInterval(3_600), previous: crossed.state)
        let crossedAgain = evaluate(
            used: 82,
            reset: reset.addingTimeInterval(3_600),
            previous: newWindow.state
        )

        XCTAssertTrue(newWindow.alerts.isEmpty)
        XCTAssertEqual(crossedAgain.alerts.map(\.kind), [.threshold])
        XCTAssertEqual(crossedAgain.alerts.first?.windowGeneration, 1)
    }

    func testMutedProviderIsStillObservedWithoutAlerting() {
        var settings = MobileNotificationSettings(isEnabled: true)
        settings.updateProvider("claude") { $0.isEnabled = false }
        let baseline = evaluate(used: 79, settings: settings)
        let crossedWhileMuted = evaluate(used: 90, settings: settings, previous: baseline.state)

        settings.updateProvider("claude") { $0.isEnabled = true }
        let unmuted = evaluate(used: 91, settings: settings, previous: crossedWhileMuted.state)

        XCTAssertTrue(crossedWhileMuted.alerts.isEmpty)
        XCTAssertTrue(unmuted.alerts.isEmpty)
    }

    func testHiddenMetricsDoNotAlert() {
        var display = MobileProviderDisplaySettings()
        display.updateMetricSettings(for: "claude") { $0.hiddenMetricIDs.insert("claude.session") }
        let baseline = evaluate(used: 79, displaySettings: display)
        let crossed = evaluate(used: 90, displaySettings: display, previous: baseline.state)

        XCTAssertTrue(crossed.alerts.isEmpty)
    }

    func testNotificationSettingsRoundTripThroughAppGroupStore() {
        let suiteName = "OpenUsageMobileCoreTests.Notifications.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let store = MobileSharedSnapshotStore(suiteName: suiteName)
        var settings = MobileNotificationSettings(isEnabled: true, soundEnabled: false)
        settings.updateProvider("claude") {
            $0.isEnabled = false
            $0.threshold = .ninetyFivePercent
        }

        store.notificationSettings = settings

        XCTAssertEqual(store.notificationSettings, settings)
    }

    private let reset = Date(timeIntervalSince1970: 2_000_000_000)
    private let metricKey = "claude|claude.session"

    private func evaluate(
        used: Double,
        reset: Date? = Date(timeIntervalSince1970: 2_000_000_000),
        settings: MobileNotificationSettings = MobileNotificationSettings(isEnabled: true),
        displaySettings: MobileProviderDisplaySettings = MobileProviderDisplaySettings(),
        previous: MobileQuotaNotificationState = MobileQuotaNotificationState()
    ) -> MobileQuotaNotificationEvaluator.Result {
        let provider = MobileProviderSnapshot(
            providerID: "claude",
            displayName: "Claude",
            refreshedAt: .now,
            metrics: [
                MobileUsageMetric(
                    id: "claude.session",
                    label: "Session",
                    presentation: .progress,
                    used: used,
                    limit: 100,
                    unit: MobileMetricUnit(kind: .percent),
                    resetsAt: reset
                )
            ]
        )
        return MobileQuotaNotificationEvaluator.evaluate(
            snapshot: MobileSharedSnapshot(
                cachedAt: .now,
                providers: [ResolvedMobileProvider(
                    provider: provider,
                    deviceID: "mac-a",
                    deviceName: "Mac",
                    documentUpdatedAt: .now
                )],
                dailyTotals: []
            ),
            displaySettings: displaySettings,
            settings: settings,
            previous: previous
        )
    }
}
