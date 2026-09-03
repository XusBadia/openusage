import Foundation
import OSLog
import UserNotifications

enum MobileResetNotificationPlanner {
    static func scheduledResets(
        snapshot: MobileSharedSnapshot,
        displaySettings: MobileProviderDisplaySettings,
        settings: MobileNotificationSettings,
        now: Date = Date()
    ) -> [MobileScheduledReset] {
        guard settings.isEnabled else { return [] }

        return snapshot.providers.flatMap { source -> [MobileScheduledReset] in
            let provider = source.provider
            let providerSettings = settings.settings(for: provider.providerID)
            guard providerSettings.isEnabled,
                  providerSettings.resetEnabled,
                  !displaySettings.hiddenProviderIDs.contains(provider.providerID)
            else { return [] }

            let visibleMetricIDs = Set(displaySettings.visibleMetrics(for: provider).map(\.id))
            return provider.metrics.compactMap { metric in
                guard metric.remainingFraction != nil,
                      visibleMetricIDs.contains(metric.id),
                      let reset = metric.resetsAt,
                      reset > now
                else { return nil }

                return MobileScheduledReset(
                    providerID: provider.providerID,
                    metricID: metric.id,
                    title: "Quota Reset",
                    subtitle: "\(provider.displayName) · \(metric.label)",
                    body: "This usage limit has reset.",
                    date: reset
                )
            }
        }
        .sorted { $0.date < $1.date }
    }
}

/// Schedules alerts after an iCloud refresh. Stable request identifiers let app and widget refreshes
/// replace the same pending reset notification instead of multiplying it.
public actor MobileQuotaNotificationScheduler {
    public static let shared = MobileQuotaNotificationScheduler()

    private static let resetRequestPrefix = "openusage.mobile.reset."
    private let logger = Logger(subsystem: "OpenUsageMobileCore", category: "notifications")

    public func evaluateAndSchedule(
        snapshot: MobileSharedSnapshot,
        store: MobileSharedSnapshotStore
    ) async {
        let settings = store.notificationSettings
        let center = UNUserNotificationCenter.current()
        let authorization = await center.notificationSettings().authorizationStatus
        let authorized = Self.isAuthorized(authorization)

        await reconcileScheduledResets(
            snapshot: snapshot,
            displaySettings: store.providerDisplaySettings,
            settings: settings,
            center: center,
            isAuthorized: authorized
        )

        guard settings.isEnabled, authorized else { return }

        let result = MobileQuotaNotificationEvaluator.evaluate(
            snapshot: snapshot,
            displaySettings: store.providerDisplaySettings,
            settings: settings,
            previous: store.quotaNotificationState
        )
        // Commit before scheduling. Avoiding a duplicate alert is more useful than retrying a stale
        // edge after a delivery error.
        store.quotaNotificationState = result.state

        for alert in result.alerts {
            let content = makeContent(
                title: alert.title,
                subtitle: alert.subtitle,
                body: alert.body,
                providerID: alert.providerID,
                metricID: alert.metricID,
                soundEnabled: settings.soundEnabled
            )

            do {
                try await center.add(UNNotificationRequest(
                    identifier: alert.requestIdentifier,
                    content: content,
                    trigger: nil
                ))
                logger.info(
                    "Scheduled \(alert.kind.rawValue, privacy: .public) alert for \(alert.providerID, privacy: .public)"
                )
            } catch {
                logger.error("Failed to schedule quota alert: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func reconcileScheduledResets(
        snapshot: MobileSharedSnapshot,
        store: MobileSharedSnapshotStore
    ) async {
        let center = UNUserNotificationCenter.current()
        let authorization = await center.notificationSettings().authorizationStatus
        await reconcileScheduledResets(
            snapshot: snapshot,
            displaySettings: store.providerDisplaySettings,
            settings: store.notificationSettings,
            center: center,
            isAuthorized: Self.isAuthorized(authorization)
        )
    }

    private func reconcileScheduledResets(
        snapshot: MobileSharedSnapshot,
        displaySettings: MobileProviderDisplaySettings,
        settings: MobileNotificationSettings,
        center: UNUserNotificationCenter,
        isAuthorized: Bool
    ) async {
        let desired = isAuthorized
            ? MobileResetNotificationPlanner.scheduledResets(
                snapshot: snapshot,
                displaySettings: displaySettings,
                settings: settings
            )
            : []
        let desiredIDs = Set(desired.map(\.requestIdentifier))
        let pending = await center.pendingNotificationRequests()
        let staleIDs = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.resetRequestPrefix) && !desiredIDs.contains($0) }
        if !staleIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIDs)
        }

        for reset in desired {
            let content = makeContent(
                title: reset.title,
                subtitle: reset.subtitle,
                body: reset.body,
                providerID: reset.providerID,
                metricID: reset.metricID,
                soundEnabled: settings.soundEnabled
            )
            var dateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: reset.date
            )
            dateComponents.timeZone = Calendar.current.timeZone

            do {
                try await center.add(UNNotificationRequest(
                    identifier: reset.requestIdentifier,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
                ))
            } catch {
                logger.error("Failed to schedule quota reset: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func makeContent(
        title: String,
        subtitle: String,
        body: String,
        providerID: String,
        metricID: String,
        soundEnabled: Bool
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.threadIdentifier = "openusage.mobile.quota"
        content.userInfo = ["providerID": providerID, "metricID": metricID]
        if soundEnabled { content.sound = .default }
        return content
    }

    private static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional:
            true
#if os(iOS)
        case .ephemeral:
            true
#endif
        default:
            false
        }
    }
}
