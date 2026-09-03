import Foundation
import OpenUsageMobileCore

struct MobilePreviewData {
    var providers: [ResolvedMobileProvider]
    var dailyTotals: [MobileDailyTotal]
    var providerDailyTotals: [String: [MobileDailyTotal]]
    var devices: [MobileDeviceSummary]
}

enum PreviewFixtures {
    static func make(now: Date = Date()) -> MobilePreviewData {
        let macName = "Studio Mac"
        let document = MobileUsageDocument(
            deviceID: "preview-mac",
            deviceName: macName,
            updatedAt: now.addingTimeInterval(-52),
            providerOrder: ["claude", "codex"],
            providers: [
                "claude": provider(
                    id: "claude",
                    name: "Claude",
                    plan: "Max",
                    refreshedAt: now.addingTimeInterval(-82),
                    accent: "#D97757",
                    sessionUsed: 31,
                    sessionReset: now.addingTimeInterval(2 * 3_600 + 44 * 60),
                    weeklyUsed: 0,
                    weeklyReset: now.addingTimeInterval(4 * 86_400 + 7 * 3_600)
                ),
                "codex": provider(
                    id: "codex",
                    name: "Codex",
                    plan: "Plus",
                    refreshedAt: now.addingTimeInterval(-116),
                    accent: "#8C7CF6",
                    sessionUsed: 18,
                    sessionReset: now.addingTimeInterval(4 * 3_600 + 12 * 60),
                    weeklyUsed: 73,
                    weeklyReset: now.addingTimeInterval(2 * 86_400 + 19 * 3_600)
                ),
            ]
        )

        let history = makeHistory(now: now)
        return MobilePreviewData(
            providers: MobileUsageResolver.resolve([document]),
            dailyTotals: history,
            providerDailyTotals: [
                "claude": scaled(history, factor: 0.62),
                "codex": scaled(history, factor: 0.38),
            ],
            devices: [
                MobileDeviceSummary(
                    id: "preview-mac",
                    name: macName,
                    updatedAt: now.addingTimeInterval(-52),
                    publishesStatus: true,
                    publishesHistory: true
                )
            ]
        )
    }

    private static func scaled(_ values: [MobileDailyTotal], factor: Double) -> [MobileDailyTotal] {
        values.map {
            MobileDailyTotal(
                date: $0.date,
                totalTokens: Int(Double($0.totalTokens) * factor),
                costUSD: $0.costUSD.map { $0 * factor }
            )
        }
    }

    private static func provider(
        id: String,
        name: String,
        plan: String,
        refreshedAt: Date,
        accent: String,
        sessionUsed: Double,
        sessionReset: Date,
        weeklyUsed: Double,
        weeklyReset: Date
    ) -> MobileProviderSnapshot {
        MobileProviderSnapshot(
            providerID: id,
            displayName: name,
            plan: plan,
            refreshedAt: refreshedAt,
            metrics: [
                MobileUsageMetric(
                    id: "\(id).session",
                    label: "Session",
                    presentation: .progress,
                    used: sessionUsed,
                    limit: 100,
                    unit: MobileMetricUnit(kind: .percent),
                    resetsAt: sessionReset,
                    colorHex: accent
                ),
                MobileUsageMetric(
                    id: "\(id).weekly",
                    label: "Weekly",
                    presentation: .progress,
                    used: weeklyUsed,
                    limit: 100,
                    unit: MobileMetricUnit(kind: .percent),
                    resetsAt: weeklyReset,
                    colorHex: accent
                ),
                MobileUsageMetric(
                    id: "\(id).today",
                    label: "Today",
                    presentation: .values,
                    values: [MobileMetricValue(number: 4.18, unit: MobileMetricUnit(kind: .dollars), estimated: true)]
                ),
                MobileUsageMetric(
                    id: "\(id).last30",
                    label: "Last 30 Days",
                    presentation: .values,
                    values: [MobileMetricValue(number: 162.37, unit: MobileMetricUnit(kind: .dollars), estimated: true)]
                ),
            ]
        )
    }

    private static func makeHistory(now: Date) -> [MobileDailyTotal] {
        let calendar = Calendar.current
        return (0..<30).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let wave = Double((offset * 7 + 11) % 13) / 13
            return MobileDailyTotal(
                date: formatter.string(from: date),
                totalTokens: Int(1_400_000 + wave * 7_000_000),
                costUSD: 3.5 + wave * 21
            )
        }.reversed()
    }
}
