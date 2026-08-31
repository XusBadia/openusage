import AppIntents
import OpenUsageMobileCore
import SwiftUI
import WidgetKit

/// The most provider rows any family and detail level lists. The timeline entry carries this many so a
/// widget resized or reconfigured on the Home Screen renders from the entry it already has.
private let usageOverviewMaximumRows = 10

struct UsageOverviewEntry: TimelineEntry {
    var date: Date
    var providers: [ResolvedMobileProvider]
    var displaySettings: MobileProviderDisplaySettings
    var detail: OverviewRowDetail
    var requestedRows: Int?
    var showsHeader: Bool
    var showsResets: Bool
    var showsPlans: Bool
    var hidesFinancialValues: Bool
    var hasSyncedProviders: Bool
}

struct UsageOverviewTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageOverviewEntry {
        entry(for: UsageOverviewIntent(), from: MobileSharedSnapshot(
            cachedAt: .now,
            providers: WidgetPreviewFixtures.providers(),
            dailyTotals: []
        ))
    }

    /// The gallery asks for this while someone is looking at it, so it renders the cache instead of
    /// waiting on iCloud.
    func snapshot(for configuration: UsageOverviewIntent, in context: Context) async -> UsageOverviewEntry {
        entry(for: configuration, from: WidgetDataAccess.cachedSnapshot())
    }

    func timeline(for configuration: UsageOverviewIntent, in context: Context) async -> Timeline<UsageOverviewEntry> {
        let entry = entry(for: configuration, from: await WidgetDataAccess.currentSnapshot())
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    private func entry(
        for configuration: UsageOverviewIntent,
        from snapshot: MobileSharedSnapshot?
    ) -> UsageOverviewEntry {
        let settings = WidgetDataAccess.displaySettings
        var providers = WidgetDataAccess.providers(in: snapshot)
        // An empty picker keeps following the app; naming providers here overrides that for this widget
        // only, and still respects whether the app is hiding one.
        if let chosen = configuration.providers, !chosen.isEmpty {
            let wanted = Set(chosen.map(\.id))
            providers = providers.filter { wanted.contains($0.provider.providerID) }
        }
        return UsageOverviewEntry(
            date: .now,
            providers: Array(
                settings.sortedProviders(providers, by: configuration.sort.sort).prefix(usageOverviewMaximumRows)
            ),
            displaySettings: settings,
            detail: configuration.detail,
            requestedRows: configuration.rows.requested,
            showsHeader: configuration.showsHeader,
            showsResets: configuration.showsResets,
            showsPlans: configuration.showsPlans,
            hidesFinancialValues: WidgetDataAccess.hidesFinancialValues,
            hasSyncedProviders: !(snapshot?.providers.isEmpty ?? true)
        )
    }
}

struct UsageOverviewWidget: Widget {
    let kind = "UsageOverviewWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: UsageOverviewIntent.self, provider: UsageOverviewTimelineProvider()) { entry in
            UsageOverviewWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(uiColor: .secondarySystemBackground) }
        }
        .configurationDisplayName("Usage Overview")
        .description("See available usage across your providers.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct UsageOverviewWidgetView: View {
    let entry: UsageOverviewEntry
    @Environment(\.widgetFamily) private var family

    /// What each size can show without clipping. A row count larger than this is trimmed to it, since a
    /// row half off the edge reads as a bug rather than as a choice.
    private var maximumRows: Int {
        switch (family, entry.detail) {
        case (.systemLarge, .compact): 10
        case (.systemLarge, .standard): 6
        case (.systemLarge, .expanded): 4
        case (_, .compact): 4
        case (_, .standard): 3
        case (_, .expanded): 2
        }
    }

    private var rows: [ResolvedMobileProvider] {
        Array(entry.providers.prefix(min(entry.requestedRows ?? maximumRows, maximumRows)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: entry.detail == .compact ? 6 : 12) {
            if entry.showsHeader { header }
            if rows.isEmpty {
                Spacer()
                Label(
                    entry.hasSyncedProviders ? "No providers selected" : "Waiting for your Mac",
                    systemImage: entry.hasSyncedProviders ? "slider.horizontal.3" : "icloud.slash"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(rows) { source in
                    providerRow(source)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Usage").font(.headline)
            Spacer()
            if let freshest = entry.providers.map(\.provider.refreshedAt).max() {
                Text(freshest, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func providerRow(_ source: ResolvedMobileProvider) -> some View {
        let card = entry.displaySettings.cardMetrics(for: source.provider)
        return HStack(alignment: .top, spacing: 10) {
            WidgetProviderIcon(providerID: source.provider.providerID, size: entry.detail == .compact ? 18 : 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(source.provider.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if entry.showsPlans, let plan = source.provider.plan {
                        Text(plan)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let metric = card.headline {
                        Text(WidgetFormatting.remaining(metric, hidesFinancialValues: entry.hidesFinancialValues))
                            .font(.caption.weight(.bold).monospacedDigit())
                    }
                }
                if entry.detail != .compact {
                    barRow(card.headline, providerID: source.provider.providerID)
                }
                if entry.detail == .expanded, !card.secondary.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(card.secondary.prefix(2)) { metric in
                            Text("\(metric.label) \(WidgetFormatting.remaining(metric, hidesFinancialValues: entry.hidesFinancialValues))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func barRow(_ metric: MobileUsageMetric?, providerID: String) -> some View {
        HStack(spacing: 8) {
            if let metric, let fraction = metric.remainingFraction {
                WidgetQuotaBar(
                    fraction: fraction,
                    color: WidgetDesign.quotaColor(metric, providerID: providerID)
                )
            }
            if entry.showsResets, let reset = metric?.resetsAt {
                Text(WidgetFormatting.reset(reset, now: entry.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}
