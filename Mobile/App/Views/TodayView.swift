import OpenUsageMobileCore
import SwiftUI

struct TodayView: View {
    @Environment(MobileDashboardStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                freshness
                if store.providers.isEmpty {
                    ContentUnavailableView(
                        "No Providers Shown",
                        systemImage: "slider.horizontal.3",
                        description: Text("Choose the providers you want to see in Settings.")
                    )
                    .frame(minHeight: 300)
                    .cardSurface()
                } else if let today = store.today {
                    TodaySummaryView(total: today, hidesFinancialValues: store.hidesFinancialValues)
                }
                ForEach(store.providers) { source in
                    NavigationLink {
                        ProviderDetailView(source: source)
                    } label: {
                        ProviderCardView(
                            source: source,
                            hidesFinancialValues: store.hidesFinancialValues,
                            displaySettings: store.providerDisplaySettings
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(MobilePalette.canvas.ignoresSafeArea())
        .navigationTitle("Today")
        .refreshable { await store.refresh() }
    }

    private var freshness: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 8) {
                Circle()
                    .fill(freshnessColor(now: context.date))
                    .frame(width: 7, height: 7)
                Text(freshnessLabel(now: context.date))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if store.isRefreshing { ProgressView().controlSize(.small) }
            }
            .padding(.top, 2)
            .accessibilityElement(children: .combine)
        }
    }

    private func freshnessLabel(now: Date) -> String {
        guard let date = store.freshestUpdate else { return "Waiting for an update" }
        let age = now.timeIntervalSince(date)
        if age < 90 { return "Updated just now" }
        return "Updated \(MobileFormatting.age(date, now: now))"
    }

    private func freshnessColor(now: Date) -> Color {
        guard let date = store.freshestUpdate else { return .secondary }
        let age = now.timeIntervalSince(date)
        if age >= 3_600 { return .red }
        if age >= 15 * 60 { return .orange }
        return .green
    }
}

private struct TodaySummaryView: View {
    let total: MobileDailyTotal
    let hidesFinancialValues: Bool

    var body: some View {
        HStack(spacing: 18) {
            summary(value: MobileFormatting.compact(Double(total.totalTokens)), label: "tokens")
            Divider().frame(height: 32)
            summary(
                value: hidesFinancialValues ? "••••" : total.costUSD.map(MobileFormatting.currency) ?? "—",
                label: total.costUSD == nil ? "cost unavailable" : "estimated today"
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }

    private func summary(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
