import OpenUsageMobileCore
import SwiftUI
import WidgetKit

struct UsageOverviewEntry: TimelineEntry {
    var date: Date
    var providers: [ResolvedMobileProvider]
    var hidesFinancialValues: Bool
}

struct UsageOverviewTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageOverviewEntry {
        UsageOverviewEntry(date: .now, providers: WidgetPreviewFixtures.providers(), hidesFinancialValues: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageOverviewEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageOverviewEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(15 * 60))))
    }

    private func entry() -> UsageOverviewEntry {
        UsageOverviewEntry(
            date: .now,
            providers: Array((WidgetDataAccess.snapshot()?.providers ?? []).prefix(3)),
            hidesFinancialValues: WidgetDataAccess.hidesFinancialValues
        )
    }
}

struct UsageOverviewWidget: Widget {
    let kind = "UsageOverviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageOverviewTimelineProvider()) { entry in
            UsageOverviewWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(uiColor: .secondarySystemBackground) }
        }
        .configurationDisplayName("Usage Overview")
        .description("See available usage across your providers.")
        .supportedFamilies([.systemMedium])
    }
}

private struct UsageOverviewWidgetView: View {
    let entry: UsageOverviewEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Usage").font(.headline)
                Spacer()
                if let freshest = entry.providers.map(\.provider.refreshedAt).max() {
                    Text(freshest, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if entry.providers.isEmpty {
                Spacer()
                Label("Waiting for your Mac", systemImage: "icloud.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.providers.prefix(3)) { source in
                    providerRow(source)
                }
            }
        }
    }

    private func providerRow(_ source: ResolvedMobileProvider) -> some View {
        HStack(spacing: 10) {
            WidgetProviderIcon(providerID: source.provider.providerID, size: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(source.provider.displayName)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    if let metric = source.provider.primaryMetric {
                        Text(WidgetFormatting.remaining(metric, hidesFinancialValues: entry.hidesFinancialValues))
                            .font(.caption.weight(.bold).monospacedDigit())
                    }
                }
                if let metric = source.provider.primaryMetric, let fraction = metric.remainingFraction {
                    WidgetQuotaBar(
                        fraction: fraction,
                        color: WidgetDesign.quotaColor(metric, providerID: source.provider.providerID)
                    )
                }
            }
        }
    }
}
