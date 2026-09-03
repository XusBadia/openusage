import OpenUsageMobileCore
import SwiftUI

struct ProviderCardView: View {
    let source: ResolvedMobileProvider
    let hidesFinancialValues: Bool
    let displaySettings: MobileProviderDisplaySettings

    private var provider: MobileProviderSnapshot { source.provider }
    private var cardMetrics: MobileProviderCardMetrics { displaySettings.cardMetrics(for: provider) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            card(now: context.date)
        }
    }

    private func card(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if let headline = cardMetrics.headline {
                primaryMetric(headline, now: now)
            } else {
                Text(emptyStateText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            let secondary = cardMetrics.secondary
            if !secondary.isEmpty {
                Divider()
                secondaryGrid(secondary, now: now)
            }
            footer(now: now)
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

    private func primaryMetric(_ metric: MobileUsageMetric, now: Date) -> some View {
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
                    Text(MobileFormatting.reset(reset, now: now))
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

    private var emptyStateText: String {
        switch provider.status {
        case .unavailable: "Update unavailable"
        default: provider.metrics.isEmpty ? "No numeric usage yet" : "Every metric is hidden"
        }
    }

    /// Two metrics per row, so a Detailed card grows downward instead of squeezing every metric into one
    /// line. Rows keep the vertical rule between the two columns the Standard card has always used.
    private func secondaryGrid(_ metrics: [MobileUsageMetric], now: Date) -> some View {
        let rows = stride(from: 0, to: metrics.count, by: 2).map { start in
            Array(metrics[start..<min(start + 2, metrics.count)])
        }
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(rows.enumerated()), id: \.offset) { offset, row in
                if offset > 0 { Divider() }
                HStack(spacing: 18) {
                    secondaryMetric(row[0], now: now)
                    if row.count > 1 {
                        Divider().frame(height: 34)
                        secondaryMetric(row[1], now: now)
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func secondaryMetric(_ metric: MobileUsageMetric, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.label).font(.caption).foregroundStyle(.secondary)
            Text(MobileFormatting.remaining(metric, hidesFinancialValues: hidesFinancialValues))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let reset = metric.resetsAt {
                Text(MobileFormatting.reset(reset, now: now))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func footer(now: Date) -> some View {
        Label {
            Text("From \(source.deviceName) · \(MobileFormatting.age(provider.refreshedAt, now: now))")
        } icon: {
            Image(systemName: "laptopcomputer")
        }
        .font(.caption2)
        .foregroundStyle(now.timeIntervalSince(provider.refreshedAt) >= 3_600 ? Color.orange : Color.secondary)
        .lineLimit(1)
    }
}
