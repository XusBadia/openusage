import OpenUsageMobileCore
import SwiftUI

struct ProviderDetailView: View {
    let source: ResolvedMobileProvider
    @Environment(MobileDashboardStore.self) private var store

    private var provider: MobileProviderSnapshot { source.provider }

    private var visibleMetrics: [MobileUsageMetric] {
        store.providerDisplaySettings.visibleMetrics(for: provider)
    }

    private var hiddenMetrics: [MobileUsageMetric] {
        let visibleIDs = Set(visibleMetrics.map(\.id))
        return store.providerDisplaySettings.orderedMetrics(for: provider)
            .filter { !visibleIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                identity
                ForEach(visibleMetrics) { metric in
                    metricCard(metric)
                }
                if !hiddenMetrics.isEmpty {
                    hiddenSection
                }
                sourceCard
            }
            .padding(16)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(MobilePalette.canvas.ignoresSafeArea())
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ProviderMetricCustomizationView(source: source)
                } label: {
                    Label("Customize", systemImage: "slider.horizontal.3")
                }
            }
        }
    }

    private func metricCard(_ metric: MobileUsageMetric) -> some View {
        MetricDetailCard(
            metric: metric,
            providerID: provider.providerID,
            hidesFinancialValues: store.hidesFinancialValues
        )
    }

    /// Hidden metrics stay synced, so this screen keeps them one tap away instead of pretending the Mac
    /// never published them.
    private var hiddenSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(hiddenMetrics) { metric in
                    metricCard(metric)
                }
            }
            .padding(.top, 12)
        } label: {
            Label("Hidden Metrics (\(hiddenMetrics.count))", systemImage: "eye.slash")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var identity: some View {
        HStack(spacing: 14) {
            ProviderIconView(providerID: provider.providerID, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(provider.displayName).font(.title2.bold())
                Text(provider.plan ?? "Plan unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Source", systemImage: "laptopcomputer")
                .font(.headline)
            LabeledContent("Mac", value: source.deviceName)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                LabeledContent("Generated", value: MobileFormatting.age(provider.refreshedAt, now: context.date))
            }
            Text("Checking iCloud does not contact the provider or wake this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .cardSurface()
    }
}

private struct MetricDetailCard: View {
    let metric: MobileUsageMetric
    let providerID: String
    let hidesFinancialValues: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(metric.label)
                .font(.headline)
            Text(MobileFormatting.remaining(metric, hidesFinancialValues: hidesFinancialValues))
                .font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit()
            if let fraction = metric.remainingFraction {
                QuotaProgressView(
                    fraction: fraction,
                    color: MobilePalette.quotaColor(for: metric, providerID: providerID)
                )
            }
            if let reset = metric.resetsAt {
                Label(MobileFormatting.reset(reset), systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if metric.values.count > 1 {
                Divider()
                ForEach(Array(metric.values.enumerated()), id: \.offset) { _, value in
                    Text(MobileFormatting.value(value, hidesFinancialValues: hidesFinancialValues))
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(18)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}
