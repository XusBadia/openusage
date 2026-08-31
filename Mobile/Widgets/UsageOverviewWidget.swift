import OpenUsageMobileCore
import SwiftUI
import WidgetKit

/// The most provider rows any family lists — the large one. The timeline entry carries this many so a
/// widget resized on the Home Screen renders from the entry it already has.
private let usageOverviewMaximumRows = 6

/// `TimelineProvider` predates Swift concurrency, so its completion handler is not `Sendable` and cannot
/// be passed into the task that reads iCloud. WidgetKit hands the handler over and expects it back once,
/// which is exactly what this carries.
private struct WidgetCompletion<Value>: @unchecked Sendable {
    private let handler: (Value) -> Void

    init(_ handler: @escaping (Value) -> Void) {
        self.handler = handler
    }

    func callAsFunction(_ value: Value) {
        handler(value)
    }
}

struct UsageOverviewEntry: TimelineEntry {
    var date: Date
    var providers: [ResolvedMobileProvider]
    var displaySettings: MobileProviderDisplaySettings
    var hidesFinancialValues: Bool
    var hasSyncedProviders: Bool
}

struct UsageOverviewTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageOverviewEntry {
        UsageOverviewEntry(
            date: .now,
            providers: WidgetPreviewFixtures.providers(),
            displaySettings: MobileProviderDisplaySettings(),
            hidesFinancialValues: false,
            hasSyncedProviders: true
        )
    }

    /// The gallery asks for this while someone is looking at it, so it renders the cache instead of
    /// waiting on iCloud.
    func getSnapshot(in context: Context, completion: @escaping (UsageOverviewEntry) -> Void) {
        completion(entry(from: WidgetDataAccess.cachedSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageOverviewEntry>) -> Void) {
        let deliver = WidgetCompletion(completion)
        Task {
            let entry = entry(from: await WidgetDataAccess.currentSnapshot())
            deliver(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }

    private func entry(from snapshot: MobileSharedSnapshot?) -> UsageOverviewEntry {
        UsageOverviewEntry(
            date: .now,
            providers: Array(WidgetDataAccess.providers(in: snapshot).prefix(usageOverviewMaximumRows)),
            displaySettings: WidgetDataAccess.displaySettings,
            hidesFinancialValues: WidgetDataAccess.hidesFinancialValues,
            hasSyncedProviders: !(snapshot?.providers.isEmpty ?? true)
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
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct UsageOverviewWidgetView: View {
    let entry: UsageOverviewEntry
    @Environment(\.widgetFamily) private var family

    /// The large family is twice as tall, so it lists twice as many providers before trimming.
    private var rowLimit: Int { family == .systemLarge ? usageOverviewMaximumRows : 3 }

    private var rows: [ResolvedMobileProvider] { Array(entry.providers.prefix(rowLimit)) }

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
                if family == .systemLarge { Spacer(minLength: 0) }
            }
        }
    }

    /// The metric this person put first for the provider, so the overview leads with the same number the
    /// Today card does.
    private func headlineMetric(_ source: ResolvedMobileProvider) -> MobileUsageMetric? {
        entry.displaySettings.cardMetrics(for: source.provider).headline
    }

    private func providerRow(_ source: ResolvedMobileProvider) -> some View {
        HStack(spacing: 10) {
            WidgetProviderIcon(providerID: source.provider.providerID, size: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(source.provider.displayName)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    if let metric = headlineMetric(source) {
                        Text(WidgetFormatting.remaining(metric, hidesFinancialValues: entry.hidesFinancialValues))
                            .font(.caption.weight(.bold).monospacedDigit())
                    }
                }
                if let metric = headlineMetric(source), let fraction = metric.remainingFraction {
                    WidgetQuotaBar(
                        fraction: fraction,
                        color: WidgetDesign.quotaColor(metric, providerID: source.provider.providerID)
                    )
                }
            }
        }
    }
}
