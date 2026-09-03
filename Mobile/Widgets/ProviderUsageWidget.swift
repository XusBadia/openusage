import AppIntents
import OpenUsageMobileCore
import SwiftUI
import WidgetKit

struct ProviderUsageEntry: TimelineEntry {
    var date: Date
    var provider: ResolvedMobileProvider?
    var metrics: MobileProviderCardMetrics
    var hidesFinancialValues: Bool
}

struct ProviderUsageTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ProviderUsageEntry {
        let provider = WidgetPreviewFixtures.provider()
        return ProviderUsageEntry(
            date: .now,
            provider: provider,
            metrics: MobileProviderDisplaySettings().cardMetrics(for: provider.provider),
            hidesFinancialValues: false
        )
    }

    /// The configuration sheet asks for this while someone is looking at it, so it renders the cache
    /// instead of waiting on iCloud.
    func snapshot(for configuration: ProviderWidgetIntent, in context: Context) async -> ProviderUsageEntry {
        entry(for: configuration, snapshot: WidgetDataAccess.cachedSnapshot())
    }

    func timeline(for configuration: ProviderWidgetIntent, in context: Context) async -> Timeline<ProviderUsageEntry> {
        let snapshot = await WidgetDataAccess.currentSnapshot()
        let start = Date()
        let entries = WidgetTimelineSchedule.dates(startingAt: start).map { date in
            entry(for: configuration, snapshot: snapshot, date: date)
        }
        return Timeline(
            entries: entries,
            policy: .after(start.addingTimeInterval(WidgetTimelineSchedule.reloadInterval))
        )
    }

    private func entry(
        for configuration: ProviderWidgetIntent,
        snapshot: MobileSharedSnapshot?,
        date: Date = .now
    ) -> ProviderUsageEntry {
        let source = WidgetDataAccess.provider(id: configuration.provider?.id, in: snapshot)
        return ProviderUsageEntry(
            date: date,
            provider: source,
            metrics: source.map {
                WidgetDataAccess.displaySettings.cardMetrics(
                    for: $0.provider,
                    headlineMetricID: configuration.metric?.id
                )
            } ?? MobileProviderCardMetrics(headline: nil, secondary: []),
            hidesFinancialValues: WidgetDataAccess.hidesFinancialValues
        )
    }
}

struct ProviderUsageWidget: Widget {
    let kind = "ProviderUsageWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ProviderWidgetIntent.self, provider: ProviderUsageTimelineProvider()) { entry in
            ProviderUsageWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(uiColor: .secondarySystemBackground) }
        }
        .configurationDisplayName("Provider Usage")
        .description("See one provider’s available usage and next reset.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct ProviderUsageWidgetView: View {
    let entry: ProviderUsageEntry
    @Environment(\.widgetFamily) private var family

    private var secondary: [MobileUsageMetric] {
        family == .systemSmall ? [] : Array(entry.metrics.secondary.prefix(2))
    }

    var body: some View {
        if let source = entry.provider, let metric = entry.metrics.headline {
            VStack(alignment: .leading, spacing: 10) {
                header(source.provider, metric: metric)
                Spacer(minLength: 0)
                // The medium family spends its extra width on the other metrics this provider is set to
                // show, so both families keep the same height for the headline.
                if secondary.isEmpty {
                    headline(metric, providerID: source.provider.providerID)
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        headline(metric, providerID: source.provider.providerID)
                        Divider()
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(secondary) { metric in
                                secondaryMetric(metric)
                            }
                        }
                        .frame(width: 108, alignment: .leading)
                    }
                }
            }
        } else {
            ContentUnavailableView("No Usage", systemImage: "icloud.slash")
        }
    }

    private func header(_ provider: MobileProviderSnapshot, metric: MobileUsageMetric) -> some View {
        HStack(spacing: 8) {
            WidgetProviderIcon(providerID: provider.providerID)
            Text(provider.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if family != .systemSmall {
                Spacer(minLength: 0)
                Text(metric.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func headline(_ metric: MobileUsageMetric, providerID: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(WidgetFormatting.remaining(metric, hidesFinancialValues: entry.hidesFinancialValues))
                .font(.system(.title, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.72)
                .lineLimit(1)
            // The medium family already names the metric in its header.
            if family == .systemSmall {
                Text(metric.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let fraction = metric.remainingFraction {
                WidgetQuotaBar(
                    fraction: fraction,
                    color: WidgetDesign.quotaColor(metric, providerID: providerID)
                )
            }
            if let reset = metric.resetsAt {
                Text(WidgetFormatting.reset(reset, now: entry.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func secondaryMetric(_ metric: MobileUsageMetric) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(WidgetFormatting.remaining(metric, hidesFinancialValues: entry.hidesFinancialValues))
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let reset = metric.resetsAt {
                Text(WidgetFormatting.reset(reset, now: entry.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
