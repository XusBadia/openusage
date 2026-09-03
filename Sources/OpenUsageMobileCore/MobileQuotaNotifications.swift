import Foundation

public enum MobileUsageAlertThreshold: Int, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case fiftyPercent = 50
    case eightyPercent = 80
    case ninetyPercent = 90
    case ninetyFivePercent = 95

    public var id: Int { rawValue }
    public var title: String { "\(rawValue)% Used" }
    var usedFraction: Double { Double(rawValue) / 100 }
}

public struct MobileProviderNotificationSettings: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var thresholds: Set<MobileUsageAlertThreshold>
    public var resetEnabled: Bool

    public init(
        isEnabled: Bool = true,
        thresholds: Set<MobileUsageAlertThreshold> = [.eightyPercent],
        resetEnabled: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.thresholds = thresholds
        self.resetEnabled = resetEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case thresholds
        case resetEnabled
        case threshold
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedThresholds: Set<MobileUsageAlertThreshold>
        if let thresholds = try container.decodeIfPresent(Set<MobileUsageAlertThreshold>.self, forKey: .thresholds) {
            decodedThresholds = thresholds
        } else if let legacyThreshold = try container.decodeIfPresent(
            MobileUsageAlertThreshold.self,
            forKey: .threshold
        ) {
            decodedThresholds = [legacyThreshold]
        } else {
            decodedThresholds = [.eightyPercent]
        }

        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            thresholds: decodedThresholds,
            resetEnabled: try container.decodeIfPresent(Bool.self, forKey: .resetEnabled) ?? true
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(thresholds, forKey: .thresholds)
        try container.encode(resetEnabled, forKey: .resetEnabled)
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
    var threshold: MobileUsageAlertThreshold?
    var providerID: String
    var metricID: String
    var title: String
    var subtitle: String
    var body: String
    var windowGeneration: Int

    var requestIdentifier: String {
        let event = threshold.map { "threshold.\($0.rawValue)" } ?? kind.rawValue
        return "openusage.mobile.\(providerID).\(metricID).\(windowGeneration).\(event)"
    }
}

struct MobileScheduledReset: Equatable, Sendable {
    var providerID: String
    var metricID: String
    var title: String
    var subtitle: String
    var body: String
    var date: Date

    var requestIdentifier: String {
        "openusage.mobile.reset.\(providerID).\(metricID)"
    }
}

struct MobileQuotaNotificationState: Codable, Equatable, Sendable {
    struct Observation: Codable, Equatable, Sendable {
        var resetsAt: Date?
        var lastUsedFraction: Double
        var configuredThresholds: Set<MobileUsageAlertThreshold>
        var deliveredThresholds: Set<MobileUsageAlertThreshold>
        var exhaustedDelivered: Bool
        var windowGeneration: Int

        private enum CodingKeys: String, CodingKey {
            case resetsAt
            case lastUsedFraction
            case configuredThresholds
            case deliveredThresholds
            case exhaustedDelivered
            case windowGeneration
            case threshold
            case thresholdDelivered
        }

        init(
            resetsAt: Date?,
            lastUsedFraction: Double,
            configuredThresholds: Set<MobileUsageAlertThreshold>,
            deliveredThresholds: Set<MobileUsageAlertThreshold>,
            exhaustedDelivered: Bool,
            windowGeneration: Int
        ) {
            self.resetsAt = resetsAt
            self.lastUsedFraction = lastUsedFraction
            self.configuredThresholds = configuredThresholds
            self.deliveredThresholds = deliveredThresholds
            self.exhaustedDelivered = exhaustedDelivered
            self.windowGeneration = windowGeneration
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let legacyThreshold = try container.decodeIfPresent(MobileUsageAlertThreshold.self, forKey: .threshold)
            let configured = try container.decodeIfPresent(
                Set<MobileUsageAlertThreshold>.self,
                forKey: .configuredThresholds
            ) ?? legacyThreshold.map { [$0] } ?? [.eightyPercent]
            let delivered: Set<MobileUsageAlertThreshold>
            if let decoded = try container.decodeIfPresent(
                Set<MobileUsageAlertThreshold>.self,
                forKey: .deliveredThresholds
            ) {
                delivered = decoded
            } else if try container.decodeIfPresent(Bool.self, forKey: .thresholdDelivered) == true,
                      let legacyThreshold {
                delivered = [legacyThreshold]
            } else {
                delivered = []
            }

            self.init(
                resetsAt: try container.decodeIfPresent(Date.self, forKey: .resetsAt),
                lastUsedFraction: try container.decode(Double.self, forKey: .lastUsedFraction),
                configuredThresholds: configured,
                deliveredThresholds: delivered,
                exhaustedDelivered: try container.decodeIfPresent(Bool.self, forKey: .exhaustedDelivered) ?? false,
                windowGeneration: try container.decodeIfPresent(Int.self, forKey: .windowGeneration) ?? 0
            )
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(resetsAt, forKey: .resetsAt)
            try container.encode(lastUsedFraction, forKey: .lastUsedFraction)
            try container.encode(configuredThresholds, forKey: .configuredThresholds)
            try container.encode(deliveredThresholds, forKey: .deliveredThresholds)
            try container.encode(exhaustedDelivered, forKey: .exhaustedDelivered)
            try container.encode(windowGeneration, forKey: .windowGeneration)
        }
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
                    next.observations[key] = makeBaselineObservation(
                        metric: metric,
                        used: used,
                        thresholds: providerSettings.thresholds,
                        windowGeneration: 0
                    )
                    continue
                }

                let resetAdvanced = resetWindowAdvanced(current: metric.resetsAt, previous: observation.resetsAt)
                // A few providers omit reset timestamps. A large fall is the safest local signal that
                // a new quota window started; smaller corrections and top-ups keep the existing dedupe.
                let inferredReset = metric.resetsAt == nil
                    && observation.resetsAt == nil
                    && observation.lastUsedFraction - used >= 0.5

                if resetAdvanced || inferredReset {
                    observation = makeBaselineObservation(
                        metric: metric,
                        used: used,
                        thresholds: providerSettings.thresholds,
                        windowGeneration: observation.windowGeneration + 1
                    )
                    next.observations[key] = observation
                    continue
                }

                let newlySelected = providerSettings.thresholds.subtracting(observation.configuredThresholds)
                observation.deliveredThresholds.formUnion(newlySelected.filter { used >= $0.usedFraction })

                let crossed = providerSettings.thresholds
                    .filter { !observation.deliveredThresholds.contains($0) }
                    .filter { observation.lastUsedFraction < $0.usedFraction && used >= $0.usedFraction }
                let exhaustedCrossed = observation.lastUsedFraction < 1 && used >= 1

                if exhaustedCrossed, !observation.exhaustedDelivered {
                    if canNotify {
                        alerts.append(alert(
                            kind: .exhausted,
                            provider: provider,
                            metric: metric,
                            threshold: nil,
                            windowGeneration: observation.windowGeneration
                        ))
                    }
                    observation.exhaustedDelivered = true
                    observation.deliveredThresholds.formUnion(
                        providerSettings.thresholds.filter { used >= $0.usedFraction }
                    )
                } else if !crossed.isEmpty {
                    if canNotify, let highest = crossed.max(by: { $0.rawValue < $1.rawValue }) {
                        alerts.append(alert(
                            kind: .threshold,
                            provider: provider,
                            metric: metric,
                            threshold: highest,
                            windowGeneration: observation.windowGeneration
                        ))
                    }
                    // One refresh can jump across several milestones. Send only the highest alert, but
                    // consume every crossed milestone so the next refresh cannot release a burst.
                    observation.deliveredThresholds.formUnion(crossed)
                }

                observation.configuredThresholds = providerSettings.thresholds
                observation.resetsAt = metric.resetsAt ?? observation.resetsAt
                observation.lastUsedFraction = used
                next.observations[key] = observation
            }
        }

        return Result(alerts: alerts, state: next)
    }

    private static func makeBaselineObservation(
        metric: MobileUsageMetric,
        used: Double,
        thresholds: Set<MobileUsageAlertThreshold>,
        windowGeneration: Int
    ) -> MobileQuotaNotificationState.Observation {
        MobileQuotaNotificationState.Observation(
            resetsAt: metric.resetsAt,
            lastUsedFraction: used,
            configuredThresholds: thresholds,
            deliveredThresholds: Set(thresholds.filter { used >= $0.usedFraction }),
            exhaustedDelivered: used >= 1,
            windowGeneration: windowGeneration
        )
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
        threshold: MobileUsageAlertThreshold?,
        windowGeneration: Int
    ) -> MobileQuotaAlert {
        let subtitle = "\(provider.displayName) · \(metric.label)"
        switch kind {
        case .threshold:
            let threshold = threshold ?? .eightyPercent
            let remaining = max(0, 100 - threshold.rawValue)
            return MobileQuotaAlert(
                kind: kind,
                threshold: threshold,
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
                threshold: nil,
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
