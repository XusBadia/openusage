import Foundation
import OSLog
import UserNotifications

public enum MobileUsageAlertThreshold: Int, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case eightyPercent = 80
    case ninetyPercent = 90
    case ninetyFivePercent = 95

    public var id: Int { rawValue }
    public var title: String { "\(rawValue)% Used" }
    var usedFraction: Double { Double(rawValue) / 100 }
}

public struct MobileProviderNotificationSettings: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var threshold: MobileUsageAlertThreshold

    public init(isEnabled: Bool = true, threshold: MobileUsageAlertThreshold = .eightyPercent) {
        self.isEnabled = isEnabled
        self.threshold = threshold
    }
}

/// Notification choices shared by the iOS app and its widgets through the App Group.
public struct MobileNotificationSettings: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var soundEnabled: Bool
    public var providers: [String: MobileProviderNotificationSettings]

    public init(
        isEnabled: Bool = false,
        soundEnabled: Bool = true,
        providers: [String: MobileProviderNotificationSettings] = [:]
    ) {
        self.isEnabled = isEnabled
        self.soundEnabled = soundEnabled
        self.providers = providers
    }

    public func settings(for providerID: String) -> MobileProviderNotificationSettings {
        providers[providerID] ?? MobileProviderNotificationSettings()
    }

    public mutating func updateProvider(
        _ providerID: String,
        _ update: (inout MobileProviderNotificationSettings) -> Void
    ) {
        var value = settings(for: providerID)
        update(&value)
        if value == MobileProviderNotificationSettings() {
            providers.removeValue(forKey: providerID)
        } else {
            providers[providerID] = value
        }
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case soundEnabled
        case providers
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false,
            soundEnabled: try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true,
            providers: try container.decodeIfPresent(
                [String: MobileProviderNotificationSettings].self,
                forKey: .providers
            ) ?? [:]
        )
    }
}

enum MobileQuotaAlertKind: String, Codable, Hashable, Sendable {
    case threshold
    case exhausted
}

struct MobileQuotaAlert: Equatable, Sendable {
    var kind: MobileQuotaAlertKind
    var providerID: String
    var metricID: String
    var title: String
    var subtitle: String
    var body: String
    var windowGeneration: Int

    var requestIdentifier: String {
        "openusage.mobile.\(providerID).\(metricID).\(windowGeneration).\(kind.rawValue)"
    }
}

struct MobileQuotaNotificationState: Codable, Equatable, Sendable {
    struct Observation: Codable, Equatable, Sendable {
        var resetsAt: Date?
        var lastUsedFraction: Double
        var threshold: MobileUsageAlertThreshold
        var thresholdDelivered: Bool
        var exhaustedDelivered: Bool
        var windowGeneration: Int
    }

    var observations: [String: Observation] = [:]
}

/// Pure edge detection for quota alerts. Every metric is observed even when its provider is muted, so
/// turning alerts back on establishes future edges instead of replaying changes that happened while off.
enum MobileQuotaNotificationEvaluator {
    static let resetWindowJitterTolerance: TimeInterval = 1

    struct Result: Equatable {
        var alerts: [MobileQuotaAlert]
        var state: MobileQuotaNotificationState
    }

    static func evaluate(
        snapshot: MobileSharedSnapshot,
        displaySettings: MobileProviderDisplaySettings,
        settings: MobileNotificationSettings,
        previous: MobileQuotaNotificationState
    ) -> Result {
        var alerts: [MobileQuotaAlert] = []
        var next = MobileQuotaNotificationState()

        for source in snapshot.providers {
            let provider = source.provider
            let providerSettings = settings.settings(for: provider.providerID)
            let visibleMetricIDs = Set(displaySettings.visibleMetrics(for: provider).map(\.id))
            let providerIsVisible = !displaySettings.hiddenProviderIDs.contains(provider.providerID)

            for metric in provider.metrics {
                guard let remaining = metric.remainingFraction else { continue }
                let used = 1 - remaining
                let key = "\(provider.providerID)|\(metric.id)"
                let canNotify = settings.isEnabled
                    && providerSettings.isEnabled
                    && providerIsVisible
                    && visibleMetricIDs.contains(metric.id)

                guard var observation = previous.observations[key] else {
                    next.observations[key] = MobileQuotaNotificationState.Observation(
                        resetsAt: metric.resetsAt,
                        lastUsedFraction: used,
                        threshold: providerSettings.threshold,
                        thresholdDelivered: false,
                        exhaustedDelivered: false,
                        windowGeneration: 0
                    )
                    continue
                }

                let resetAdvanced = resetWindowAdvanced(
                    current: metric.resetsAt,
                    previous: observation.resetsAt
                )
                // A few providers omit reset timestamps. A large fall is the safest local signal that
                // a new quota window started; smaller corrections and top-ups keep the existing dedupe.
                let inferredReset = metric.resetsAt == nil
                    && observation.resetsAt == nil
                    && observation.lastUsedFraction - used >= 0.5

                if resetAdvanced || inferredReset {
                    observation = MobileQuotaNotificationState.Observation(
                        resetsAt: metric.resetsAt,
                        lastUsedFraction: used,
                        threshold: providerSettings.threshold,
                        thresholdDelivered: false,
                        exhaustedDelivered: false,
                        windowGeneration: observation.windowGeneration + 1
                    )
                    next.observations[key] = observation
                    continue
                }

                if observation.threshold != providerSettings.threshold {
                    // A preference change is a new baseline, never a reason to alert immediately.
                    observation.threshold = providerSettings.threshold
                    observation.thresholdDelivered = used >= providerSettings.threshold.usedFraction
                }

                let exhaustedCrossed = observation.lastUsedFraction < 1 && used >= 1
                let thresholdCrossed = observation.lastUsedFraction < providerSettings.threshold.usedFraction
                    && used >= providerSettings.threshold.usedFraction

                if canNotify, exhaustedCrossed, !observation.exhaustedDelivered {
                    alerts.append(alert(
                        kind: .exhausted,
                        provider: provider,
                        metric: metric,
                        threshold: providerSettings.threshold,
                        windowGeneration: observation.windowGeneration
                    ))
                    observation.exhaustedDelivered = true
                    observation.thresholdDelivered = true
                } else if canNotify, thresholdCrossed, !observation.thresholdDelivered {
                    alerts.append(alert(
                        kind: .threshold,
                        provider: provider,
                        metric: metric,
                        threshold: providerSettings.threshold,
                        windowGeneration: observation.windowGeneration
                    ))
                    observation.thresholdDelivered = true
                }

                observation.resetsAt = metric.resetsAt ?? observation.resetsAt
                observation.lastUsedFraction = used
                next.observations[key] = observation
            }
        }

        return Result(alerts: alerts, state: next)
    }

    private static func resetWindowAdvanced(current: Date?, previous: Date?) -> Bool {
        guard let current else { return false }
        guard let previous else { return true }
        return current.timeIntervalSince(previous) > resetWindowJitterTolerance
    }

    private static func alert(
        kind: MobileQuotaAlertKind,
        provider: MobileProviderSnapshot,
        metric: MobileUsageMetric,
        threshold: MobileUsageAlertThreshold,
        windowGeneration: Int
    ) -> MobileQuotaAlert {
        let subtitle = "\(provider.displayName) · \(metric.label)"
        switch kind {
        case .threshold:
            let remaining = max(0, 100 - threshold.rawValue)
            return MobileQuotaAlert(
                kind: kind,
                providerID: provider.providerID,
                metricID: metric.id,
                title: threshold.title,
                subtitle: subtitle,
                body: "\(remaining)% remains for this limit.",
                windowGeneration: windowGeneration
            )
        case .exhausted:
            return MobileQuotaAlert(
                kind: kind,
                providerID: provider.providerID,
                metricID: metric.id,
                title: "Limit Reached",
                subtitle: subtitle,
                body: "No usage remains for this limit.",
                windowGeneration: windowGeneration
            )
        }
    }
}

/// Schedules the alerts found after an iCloud refresh. The app and WidgetKit use the same actor and App
/// Group state, while stable request identifiers keep coincident widget refreshes from multiplying an
/// alert. Authorization is requested only by the containing app after the person opts in.
public actor MobileQuotaNotificationScheduler {
    public static let shared = MobileQuotaNotificationScheduler()

    private let logger = Logger(subsystem: "OpenUsageMobileCore", category: "notifications")

    public func evaluateAndSchedule(
        snapshot: MobileSharedSnapshot,
        store: MobileSharedSnapshotStore
    ) async {
        let settings = store.notificationSettings
        guard settings.isEnabled else { return }

        let center = UNUserNotificationCenter.current()
        let authorization = await center.notificationSettings().authorizationStatus
        guard Self.isAuthorized(authorization) else { return }

        let result = MobileQuotaNotificationEvaluator.evaluate(
            snapshot: snapshot,
            displaySettings: store.providerDisplaySettings,
            settings: settings,
            previous: store.quotaNotificationState
        )
        // Commit before scheduling. App and widget processes may refresh together, and avoiding a
        // duplicate alert is more useful than retrying the same stale edge after a delivery error.
        store.quotaNotificationState = result.state

        for alert in result.alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.subtitle = alert.subtitle
            content.body = alert.body
            content.threadIdentifier = "openusage.mobile.quota"
            content.userInfo = ["providerID": alert.providerID, "metricID": alert.metricID]
            if settings.soundEnabled { content.sound = .default }

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
