import Charts
import OpenUsageMobileCore
import SwiftUI

struct HistoryView: View {
    private enum Measure: String, CaseIterable, Identifiable {
        case tokens = "Tokens"
        case cost = "Cost"
        var id: Self { self }
    }

    @Environment(MobileDashboardStore.self) private var store
    @State private var period = 7
    @State private var measure = Measure.tokens
    @State private var providerID: String?

    private var totals: [MobileDailyTotal] {
        Array(store.totals(for: providerID).suffix(period))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                controls
                summary
                chartCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(MobilePalette.canvas.ignoresSafeArea())
        .navigationTitle("History")
        .refreshable { await store.refresh() }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("Period", selection: $period) {
                Text("7 Days").tag(7)
                Text("30 Days").tag(30)
            }
            .pickerStyle(.segmented)

            HStack {
                Picker("Measure", selection: $measure) {
                    ForEach(Measure.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Menu {
                    Button("All Providers") { providerID = nil }
                    ForEach(store.historyProviderIDs, id: \.self) { id in
                        Button(store.providerName(for: id)) { providerID = id }
                    }
                } label: {
                    Label(providerID.map(store.providerName) ?? "All", systemImage: "line.3.horizontal.decrease")
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 4)
    }

    private var summary: some View {
        HStack(spacing: 24) {
            valueSummary(
                title: "Tokens",
                value: MobileFormatting.compact(Double(totals.reduce(0) { $0 + $1.totalTokens }))
            )
            Divider().frame(height: 40)
            valueSummary(
                title: "Estimated Cost",
                value: store.hidesFinancialValues
                    ? "••••"
                    : MobileFormatting.currency(totals.compactMap(\.costUSD).reduce(0, +))
            )
            Spacer(minLength: 0)
        }
        .padding(18)
        .cardSurface()
    }

    private func valueSummary(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold().monospacedDigit())
        }
    }

    @ViewBuilder
    private var chartCard: some View {
        if totals.isEmpty {
            ContentUnavailableView(
                "No History Yet",
                systemImage: "chart.bar.xaxis",
                description: Text("Enable Sync Across Macs to publish daily usage history.")
            )
            .frame(minHeight: 300)
            .cardSurface()
        } else if measure == .cost, store.hidesFinancialValues {
            ContentUnavailableView(
                "Cost Is Hidden",
                systemImage: "eye.slash",
                description: Text("You can show financial values again in Settings.")
            )
            .frame(minHeight: 300)
            .cardSurface()
        } else {
            VStack(alignment: .leading, spacing: 18) {
                Text(providerID.map(store.providerName) ?? "All Providers")
                    .font(.headline)
                Chart(totals) { entry in
                    if let date = MobileFormatting.date(fromDayKey: entry.date) {
                        BarMark(
                            x: .value("Day", date, unit: .day),
                            y: .value(measure.rawValue, chartValue(entry))
                        )
                        .foregroundStyle(chartColor)
                        .cornerRadius(3)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: period == 7 ? 7 : 6)) { _ in
                        AxisGridLine().foregroundStyle(.clear)
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(MobilePalette.hairline)
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(measure == .tokens ? MobileFormatting.compact(number) : MobileFormatting.currency(number))
                            }
                        }
                    }
                }
                .frame(height: 240)
            }
            .padding(18)
            .cardSurface()
            .animation(.spring(response: 0.38, dampingFraction: 1), value: period)
        }
    }

    private var chartColor: Color {
        providerID.map(MobilePalette.accent) ?? Color.accentColor
    }

    private func chartValue(_ entry: MobileDailyTotal) -> Double {
        switch measure {
        case .tokens: return Double(entry.totalTokens)
        case .cost: return entry.costUSD ?? 0
        }
    }
}
