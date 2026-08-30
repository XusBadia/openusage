import OpenUsageMobileCore
import SwiftUI

struct ProviderDetailView: View {
    let source: ResolvedMobileProvider
    @Environment(MobileDashboardStore.self) private var store

    private var provider: MobileProviderSnapshot { source.provider }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                identity
                ForEach(provider.metrics) { metric in
                    MetricDetailCard(
                        metric: metric,
                        providerID: provider.providerID,
                        hidesFinancialValues: store.hidesFinancialValues
                    )
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
