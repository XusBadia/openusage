import XCTest
@testable import OpenUsageMobileCore

final class MobileQuotaNotificationTests: XCTestCase {
    func testFirstObservationPrimesEveryReachedMilestoneWithoutAlerting() {
        let result = evaluate(used: 85, thresholds: [.fiftyPercent, .eightyPercent, .ninetyPercent])

        XCTAssertTrue(result.alerts.isEmpty)
        XCTAssertEqual(result.state.observations[metricKey]?.lastUsedFraction ?? -1, 0.85, accuracy: 0.0001)
        XCTAssertEqual(
            result.state.observations[metricKey]?.deliveredThresholds,
            [.fiftyPercent, .eightyPercent]
        )
    }

    func testSelectedMilestonesAlertOnceEachPerWindow() {
        let thresholds: Set<MobileUsageAlertThreshold> = [.fiftyPercent, .eightyPercent]
        let baseline = evaluate(used: 49, thresholds: thresholds)
        let crossedFifty = evaluate(used: 51, thresholds: thresholds, previous: baseline.state)
        let repeated = evaluate(used: 60, thresholds: thresholds, previous: crossedFifty.state)
        let crossedEighty = evaluate(used: 81, thresholds: thresholds, previous: repeated.state)

        XCTAssertEqual(crossedFifty.alerts.first?.title, "50% Used")
        XCTAssertTrue(repeated.alerts.isEmpty)
        XCTAssertEqual(crossedEighty.alerts.first?.title, "80% Used")
        XCTAssertNotEqual(
            crossedFifty.alerts.first?.requestIdentifier,
            crossedEighty.alerts.first?.requestIdentifier
        )
    }

    func testJumpingAcrossSeveralMilestonesSendsOnlyHighestAndConsumesAll() {
        let thresholds: Set<MobileUsageAlertThreshold> = [.fiftyPercent, .eightyPercent, .ninetyPercent]
        let baseline = evaluate(used: 49, thresholds: thresholds)
        let jumped = evaluate(used: 91, thresholds: thresholds, previous: baseline.state)

        XCTAssertEqual(jumped.alerts.count, 1)
        XCTAssertEqual(jumped.alerts.first?.title, "90% Used")
        XCTAssertEqual(jumped.state.observations[metricKey]?.deliveredThresholds, thresholds)
    }

    func testJumpingToExhaustedSendsOnlyTheUrgentAlert() {
        let thresholds: Set<MobileUsageAlertThreshold> = [.fiftyPercent, .eightyPercent, .ninetyFivePercent]
        let baseline = evaluate(used: 49, thresholds: thresholds)
        let exhausted = evaluate(used: 100, thresholds: thresholds, previous: baseline.state)

        XCTAssertEqual(exhausted.alerts.map(\.kind), [.exhausted])
        XCTAssertEqual(exhausted.alerts.first?.title, "Limit Reached")
        XCTAssertEqual(exhausted.state.observations[metricKey]?.deliveredThresholds, thresholds)
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

    func testNewlySelectedReachedMilestoneDoesNotAlertImmediately() {
        let baseline = evaluate(used: 85, thresholds: [.eightyPercent])
        let changed = evaluate(
            used: 86,
            thresholds: [.fiftyPercent, .eightyPercent],
            previous: baseline.state
        )

        XCTAssertTrue(changed.alerts.isEmpty)
        XCTAssertEqual(
            changed.state.observations[metricKey]?.deliveredThresholds,
            [.fiftyPercent, .eightyPercent]
        )
    }

    func testMutedProviderConsumesCrossedMilestonesWithoutAlerting() {
        var settings = MobileNotificationSettings(isEnabled: true)
        settings.updateProvider("claude") {
            $0.isEnabled = false
            $0.thresholds = [.eightyPercent, .ninetyPercent]
        }
        let baseline = evaluate(used: 79, settings: settings)
        let crossedWhileMuted = evaluate(used: 91, settings: settings, previous: baseline.state)

        settings.updateProvider("claude") { $0.isEnabled = true }
        let unmuted = evaluate(used: 92, settings: settings, previous: crossedWhileMuted.state)

        XCTAssertTrue(crossedWhileMuted.alerts.isEmpty)
        XCTAssertTrue(unmuted.alerts.isEmpty)
        XCTAssertEqual(
            crossedWhileMuted.state.observations[metricKey]?.deliveredThresholds,
            [.eightyPercent, .ninetyPercent]
        )
    }

    func testHiddenMetricsDoNotAlert() {
        var display = MobileProviderDisplaySettings()
        display.updateMetricSettings(for: "claude") { $0.hiddenMetricIDs.insert("claude.session") }
        let baseline = evaluate(used: 79, displaySettings: display)
        let crossed = evaluate(used: 90, displaySettings: display, previous: baseline.state)

        XCTAssertTrue(crossed.alerts.isEmpty)
    }

    func testResetPlannerIncludesOnlyEnabledVisibleFutureQuotas() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let futureReset = now.addingTimeInterval(3_600)
        var settings = MobileNotificationSettings(isEnabled: true)
        settings.updateProvider("claude") {
            $0.thresholds = [.fiftyPercent, .ninetyPercent]
            $0.resetEnabled = true
        }

        let planned = MobileResetNotificationPlanner.scheduledResets(
            snapshot: snapshot(used: 25, reset: futureReset),
            displaySettings: MobileProviderDisplaySettings(),
            settings: settings,
            now: now
        )

        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned.first?.date, futureReset)
        XCTAssertEqual(planned.first?.title, "Quota Reset")
        XCTAssertEqual(planned.first?.requestIdentifier, "openusage.mobile.reset.claude.claude.session")

        settings.updateProvider("claude") { $0.resetEnabled = false }
        XCTAssertTrue(MobileResetNotificationPlanner.scheduledResets(
            snapshot: snapshot(used: 25, reset: futureReset),
            displaySettings: MobileProviderDisplaySettings(),
            settings: settings,
            now: now
        ).isEmpty)
    }

    func testResetPlannerOmitsHiddenAndExpiredQuotas() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var display = MobileProviderDisplaySettings()
        display.updateMetricSettings(for: "claude") { $0.hiddenMetricIDs.insert("claude.session") }

        XCTAssertTrue(MobileResetNotificationPlanner.scheduledResets(
            snapshot: snapshot(used: 25, reset: now.addingTimeInterval(3_600)),
            displaySettings: display,
            settings: MobileNotificationSettings(isEnabled: true),
            now: now
        ).isEmpty)
        XCTAssertTrue(MobileResetNotificationPlanner.scheduledResets(
            snapshot: snapshot(used: 25, reset: now.addingTimeInterval(-1)),
            displaySettings: MobileProviderDisplaySettings(),
            settings: MobileNotificationSettings(isEnabled: true),
            now: now
        ).isEmpty)
    }

    func testNotificationSettingsRoundTripThroughAppGroupStore() {
        let suiteName = "OpenUsageMobileCoreTests.Notifications.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let store = MobileSharedSnapshotStore(suiteName: suiteName)
        var settings = MobileNotificationSettings(isEnabled: true, soundEnabled: false)
        settings.updateProvider("claude") {
            $0.isEnabled = false
            $0.thresholds = [.fiftyPercent, .ninetyFivePercent]
            $0.resetEnabled = false
        }

        store.notificationSettings = settings

        XCTAssertEqual(store.notificationSettings, settings)
    }

    func testLegacySingleThresholdSettingsMigrate() throws {
        let data = Data(#"{"isEnabled":true,"soundEnabled":false,"providers":{"claude":{"isEnabled":true,"threshold":90}}}"#.utf8)
        let settings = try JSONDecoder().decode(MobileNotificationSettings.self, from: data)

        XCTAssertEqual(settings.settings(for: "claude").thresholds, [.ninetyPercent])
        XCTAssertTrue(settings.settings(for: "claude").resetEnabled)
    }

    func testLegacyObservationStateMigratesDelivery() throws {
        let data = Data(#"{"observations":{"claude|claude.session":{"lastUsedFraction":0.91,"threshold":90,"thresholdDelivered":true,"exhaustedDelivered":false,"windowGeneration":2}}}"#.utf8)
        let state = try JSONDecoder().decode(MobileQuotaNotificationState.self, from: data)
        let observation = try XCTUnwrap(state.observations[metricKey])

        XCTAssertEqual(observation.configuredThresholds, [.ninetyPercent])
        XCTAssertEqual(observation.deliveredThresholds, [.ninetyPercent])
        XCTAssertEqual(observation.windowGeneration, 2)
    }

    private let reset = Date(timeIntervalSince1970: 2_000_000_000)
    private let metricKey = "claude|claude.session"

    private func evaluate(
        used: Double,
        reset: Date? = Date(timeIntervalSince1970: 2_000_000_000),
        thresholds: Set<MobileUsageAlertThreshold> = [.eightyPercent],
        settings suppliedSettings: MobileNotificationSettings? = nil,
        displaySettings: MobileProviderDisplaySettings = MobileProviderDisplaySettings(),
        previous: MobileQuotaNotificationState = MobileQuotaNotificationState()
    ) -> MobileQuotaNotificationEvaluator.Result {
        var settings = suppliedSettings ?? MobileNotificationSettings(isEnabled: true)
        if suppliedSettings == nil {
            settings.updateProvider("claude") { $0.thresholds = thresholds }
        }
        return MobileQuotaNotificationEvaluator.evaluate(
            snapshot: snapshot(used: used, reset: reset),
            displaySettings: displaySettings,
            settings: settings,
            previous: previous
        )
    }

    private func snapshot(used: Double, reset: Date?) -> MobileSharedSnapshot {
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
        return MobileSharedSnapshot(
            cachedAt: .now,
            providers: [ResolvedMobileProvider(
                provider: provider,
                deviceID: "mac-a",
                deviceName: "Mac",
                documentUpdatedAt: .now
            )],
            dailyTotals: []
        )
    }
}
