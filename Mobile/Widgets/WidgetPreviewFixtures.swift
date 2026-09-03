import Foundation
import OpenUsageMobileCore

enum WidgetPreviewFixtures {
    static func provider(id: String = "claude", used: Double = 32) -> ResolvedMobileProvider {
        let provider = MobileProviderSnapshot(
            providerID: id,
            displayName: id.capitalized,
            plan: "Max",
            refreshedAt: Date().addingTimeInterval(-90),
            metrics: [
                MobileUsageMetric(
                    id: "\(id).session",
                    label: "Session",
                    presentation: .progress,
                    used: used,
                    limit: 100,
                    unit: MobileMetricUnit(kind: .percent),
                    resetsAt: Date().addingTimeInterval(2.5 * 3_600)
                ),
                MobileUsageMetric(
                    id: "\(id).weekly",
                    label: "Weekly",
                    presentation: .progress,
                    used: 0,
                    limit: 100,
                    unit: MobileMetricUnit(kind: .percent),
                    resetsAt: Date().addingTimeInterval(4.5 * 86_400)
                )
            ]
        )
        return ResolvedMobileProvider(
            provider: provider,
            deviceID: "preview",
            deviceName: "Studio Mac",
            documentUpdatedAt: .now
        )
    }

    static func providers() -> [ResolvedMobileProvider] {
        [provider(), provider(id: "codex", used: 71)]
    }
}
