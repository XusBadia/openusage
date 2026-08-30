import AppIntents
import OpenUsageMobileCore
import SwiftUI
import WidgetKit

struct ProviderUsageEntry: TimelineEntry {
    var date: Date
    var provider: ResolvedMobileProvider?
    var hidesFinancialValues: Bool
}

struct ProviderUsageTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ProviderUsageEntry {
        ProviderUsageEntry(date: .now, provider: WidgetPreviewFixtures.provider(), hidesFinancialValues: false)
    }

    func snapshot(for configuration: ProviderWidgetIntent, in context: Context) async -> ProviderUsageEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: ProviderWidgetIntent, in context: Context) async -> Timeline<ProviderUsageEntry> {
        let entry = entry(for: configuration)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    private func entry(for configuration: ProviderWidgetIntent) -> ProviderUsageEntry {
        ProviderUsageEntry(
            date: .now,
            provider: WidgetDataAccess.provider(id: configuration.provider?.id),
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
        .supportedFamilies([.systemSmall])
    }
}

private struct ProviderUsageWidgetView: View {
    let entry: ProviderUsageEntry

    var body: some View {
        if let source = entry.provider, let metric = source.provider.primaryMetric {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    WidgetProviderIcon(providerID: source.provider.providerID)
                    Text(source.provider.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(WidgetFormatting.remaining(metric, hidesFinancialValues: entry.hidesFinancialValues))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                Text("available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let fraction = metric.remainingFraction {
                    WidgetQuotaBar(
                        fraction: fraction,
                        color: WidgetDesign.quotaColor(metric, providerID: source.provider.providerID)
                    )
                }
                if let reset = metric.resetsAt {
                    Text(WidgetFormatting.reset(reset, now: entry.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } else {
            ContentUnavailableView("No Usage", systemImage: "icloud.slash")
        }
    }
}
