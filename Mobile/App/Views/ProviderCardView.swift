import OpenUsageMobileCore
import SwiftUI

struct ProviderCardView: View {
    let source: ResolvedMobileProvider
    let hidesFinancialValues: Bool

    private var provider: MobileProviderSnapshot { source.provider }
    private var primary: MobileUsageMetric? { provider.primaryMetric }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if let primary {
                primaryMetric(primary)
            } else {
                Text(provider.status == .unavailable ? "Update unavailable" : "No numeric usage yet")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if provider.metrics.count > 1 {
                Divider()
                HStack(spacing: 18) {
                    ForEach(Array(provider.metrics.dropFirst().prefix(2))) { metric in
                        secondaryMetric(metric)
                        if metric.id != provider.metrics.dropFirst().prefix(2).last?.id {
                            Divider().frame(height: 34)
                        }
                    }
                }
            }
            footer
        }
        .padding(20)
        .cardSurface()
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ProviderIconView(providerID: provider.providerID)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let plan = provider.plan {
                    Text(plan).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            statusSymbol
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
    }

    private var statusSymbol: some View {
        Image(systemName: statusIconName)
        .foregroundStyle(statusColor)
        .imageScale(.small)
        .accessibilityLabel(statusLabel)
    }

    private var statusIconName: String {
        switch provider.status {
        case .available: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.circle.fill"
        case .unavailable: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch provider.status {
        case .available: return .green
        case .attention: return .orange
        case .unavailable: return .red
        }
    }

    private var statusLabel: String {
        switch provider.status {
        case .available: return "Available"
        case .attention: return "Needs attention"
        case .unavailable: return "Update unavailable"
        }
    }

    private func primaryMetric(_ metric: MobileUsageMetric) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    Text(MobileFormatting.remaining(metric, hidesFinancialValues: hidesFinancialValues))
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .tracking(-0.8)
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 12)
                if let reset = metric.resetsAt {
                    Text(MobileFormatting.reset(reset))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            if let fraction = metric.remainingFraction {
                QuotaProgressView(
                    fraction: fraction,
                    color: MobilePalette.quotaColor(for: metric, providerID: provider.providerID)
                )
            }
        }
    }

    private func secondaryMetric(_ metric: MobileUsageMetric) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.label).font(.caption).foregroundStyle(.secondary)
            Text(MobileFormatting.remaining(metric, hidesFinancialValues: hidesFinancialValues))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let reset = metric.resetsAt {
                Text(MobileFormatting.reset(reset))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Label {
                Text("From \(source.deviceName) · \(MobileFormatting.age(provider.refreshedAt, now: context.date))")
            } icon: {
                Image(systemName: "laptopcomputer")
            }
            .font(.caption2)
            .foregroundStyle(context.date.timeIntervalSince(provider.refreshedAt) >= 3_600 ? Color.orange : Color.secondary)
            .lineLimit(1)
        }
    }
}
