import Foundation

/// User-owned presentation preferences shared by the iOS app and its WidgetKit extensions.
///
/// The iCloud snapshot remains complete. These settings only decide which providers and metrics are
/// presented, in what order, and how many of them fit on a card, so hiding anything never deletes its
/// synced data.
public struct MobileProviderDisplaySettings: Codable, Hashable, Sendable {
    public var providerOrder: [String]
    public var hiddenProviderIDs: Set<String>
    /// Per-provider metric preferences keyed by provider id. A provider with no entry keeps the order
    /// published by the Mac and shows every metric.
    public var metricSettings: [String: MobileMetricDisplaySettings]

    public init(
        providerOrder: [String] = [],
        hiddenProviderIDs: Set<String> = [],
        metricSettings: [String: MobileMetricDisplaySettings] = [:]
    ) {
        self.providerOrder = providerOrder.uniqued()
        self.hiddenProviderIDs = hiddenProviderIDs
        self.metricSettings = metricSettings
    }

    // MARK: - Providers

    public func orderedProviders(from providers: [ResolvedMobileProvider]) -> [ResolvedMobileProvider] {
        let providersByID = Dictionary(uniqueKeysWithValues: providers.map { ($0.provider.providerID, $0) })
        let saved = providerOrder.compactMap { providersByID[$0] }
        let savedIDs = Set(saved.map(\.provider.providerID))
        return saved + providers.filter { !savedIDs.contains($0.provider.providerID) }
    }

    public func visibleProviders(from providers: [ResolvedMobileProvider]) -> [ResolvedMobileProvider] {
        orderedProviders(from: providers).filter { !hiddenProviderIDs.contains($0.provider.providerID) }
    }

    // MARK: - Metrics

    public func metricSettings(for providerID: String) -> MobileMetricDisplaySettings {
        metricSettings[providerID] ?? MobileMetricDisplaySettings()
    }

    public mutating func updateMetricSettings(
        for providerID: String,
        _ update: (inout MobileMetricDisplaySettings) -> Void
    ) {
        var settings = metricSettings(for: providerID)
        update(&settings)
        if settings.isCustomized {
            metricSettings[providerID] = settings
        } else {
            metricSettings.removeValue(forKey: providerID)
        }
    }

    /// Every metric the Mac published, in the order this person chose. New metrics a Mac starts
    /// publishing land after the saved ones instead of disappearing.
    public func orderedMetrics(for provider: MobileProviderSnapshot) -> [MobileUsageMetric] {
        let published = provider.defaultMetricOrder
        let metricsByID = Dictionary(published.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let saved = metricSettings(for: provider.providerID).metricOrder.compactMap { metricsByID[$0] }
        let savedIDs = Set(saved.map(\.id))
        return saved + published.filter { !savedIDs.contains($0.id) }
    }

    public func visibleMetrics(for provider: MobileProviderSnapshot) -> [MobileUsageMetric] {
        let hidden = metricSettings(for: provider.providerID).hiddenMetricIDs
        return orderedMetrics(for: provider).filter { !hidden.contains($0.id) }
    }

    /// The headline metric plus the secondary rows a card has room for. The headline defaults to the
    /// first visible metric, so reordering in Settings moves it to the top of the app card and the
    /// widgets; a widget configured to lead with one metric passes its id and gets the rest below it.
    /// An id that names a hidden or no-longer-published metric falls back to the first visible one.
    public func cardMetrics(
        for provider: MobileProviderSnapshot,
        headlineMetricID: String? = nil
    ) -> MobileProviderCardMetrics {
        let visible = visibleMetrics(for: provider)
        let requested = headlineMetricID.flatMap { id in visible.first { $0.id == id } }
        guard let headline = requested ?? visible.first else {
            return MobileProviderCardMetrics(headline: nil, secondary: [])
        }
        let rest = visible.filter { $0.id != headline.id }
        guard let limit = metricSettings(for: provider.providerID).detail.secondaryLimit else {
            return MobileProviderCardMetrics(headline: headline, secondary: rest)
        }
        return MobileProviderCardMetrics(headline: headline, secondary: Array(rest.prefix(limit)))
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case providerOrder
        case hiddenProviderIDs
        case metricSettings
    }

    /// Decoded field by field so a build that predates a preference keeps the ones it did store instead
    /// of dropping the whole customization.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            providerOrder: try container.decodeIfPresent([String].self, forKey: .providerOrder) ?? [],
            hiddenProviderIDs: try container.decodeIfPresent(Set<String>.self, forKey: .hiddenProviderIDs) ?? [],
            metricSettings: try container.decodeIfPresent(
                [String: MobileMetricDisplaySettings].self,
                forKey: .metricSettings
            ) ?? [:]
        )
    }
}

/// How much of one provider is presented: which metrics, in what order, and how many fit on a card.
public struct MobileMetricDisplaySettings: Codable, Hashable, Sendable {
    /// How many secondary rows a provider card shows under its headline metric.
    public enum Detail: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
        case compact
        case standard
        case detailed

        public var id: String { rawValue }

        /// Secondary rows allowed under the headline. `nil` means every remaining visible metric.
        public var secondaryLimit: Int? {
            switch self {
            case .compact: 0
            case .standard: 2
            case .detailed: nil
            }
        }

        public var title: String {
            switch self {
            case .compact: "Compact"
            case .standard: "Standard"
            case .detailed: "Detailed"
            }
        }

        public var summary: String {
            switch self {
            case .compact: "Headline metric only."
            case .standard: "Headline metric and two more."
            case .detailed: "Headline metric and every other metric you keep visible."
            }
        }
    }

    public var metricOrder: [String]
    public var hiddenMetricIDs: Set<String>
    public var detail: Detail

    public init(
        metricOrder: [String] = [],
        hiddenMetricIDs: Set<String> = [],
        detail: Detail = .standard
    ) {
        self.metricOrder = metricOrder.uniqued()
        self.hiddenMetricIDs = hiddenMetricIDs
        self.detail = detail
    }

    public var isCustomized: Bool {
        !metricOrder.isEmpty || !hiddenMetricIDs.isEmpty || detail != .standard
    }

    private enum CodingKeys: String, CodingKey {
        case metricOrder
        case hiddenMetricIDs
        case detail
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            metricOrder: try container.decodeIfPresent([String].self, forKey: .metricOrder) ?? [],
            hiddenMetricIDs: try container.decodeIfPresent(Set<String>.self, forKey: .hiddenMetricIDs) ?? [],
            detail: try container.decodeIfPresent(Detail.self, forKey: .detail) ?? .standard
        )
    }
}

/// What one provider card renders: a headline metric and the secondary rows below it.
public struct MobileProviderCardMetrics: Hashable, Sendable {
    public var headline: MobileUsageMetric?
    public var secondary: [MobileUsageMetric]

    public init(headline: MobileUsageMetric?, secondary: [MobileUsageMetric]) {
        self.headline = headline
        self.secondary = secondary
    }
}

public extension MobileProviderSnapshot {
    /// The published metrics with the provider's primary meter first, which is the order a person sees
    /// before customizing anything.
    var defaultMetricOrder: [MobileUsageMetric] {
        guard let primary = primaryMetric else { return metrics }
        return [primary] + metrics.filter { $0.id != primary.id }
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
