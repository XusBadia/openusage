import XCTest
import OpenUsageMobileCore
@testable import OpenUsage

@MainActor
final class MobileUsageDocumentBuilderTests: XCTestCase {
    func testBuilderExportsOnlySanitizedNumericMetrics() async throws {
        let runtime = MobileSnapshotRuntime()
        let defaults = makeDefaults()
        let store = WidgetDataStore(
            registry: WidgetRegistry(providers: [runtime.provider], descriptors: runtime.widgetDescriptors),
            providers: [runtime],
            cache: ProviderSnapshotCache(userDefaults: defaults, storageKey: "snapshots"),
            defaults: defaults
        )

        await store.refreshAll(force: true)
        let document = store.localMobileUsageDocument(
            deviceID: "mac-a",
            deviceName: "Studio",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        try document.validate()

        let provider = try XCTUnwrap(document.providers["claude@deadbeef"])
        XCTAssertEqual(provider.displayName, "Claude")
        XCTAssertEqual(provider.status, .attention)
        XCTAssertEqual(provider.plan, "Max")
        XCTAssertEqual(provider.metrics.count, 5)
        XCTAssertEqual(provider.metrics.first?.remainingFraction, 0.76)
        let weekly = try XCTUnwrap(provider.metrics.first { $0.id == "claude@deadbeef.weekly" })
        XCTAssertEqual(weekly.remainingFraction, 1)
        XCTAssertEqual(weekly.resetsAt, Date(timeIntervalSince1970: 7_200))
        // A registered descriptor names the metric, and the id is derived from that name so a phone's
        // saved metric order survives the Mac publishing one more line.
        XCTAssertEqual(provider.metrics.map(\.label), ["Session", "Weekly", "Today", "Quota 4", "Usage 5"])
        XCTAssertEqual(
            provider.metrics.map(\.id),
            [
                "claude@deadbeef.session",
                "claude@deadbeef.weekly",
                "claude@deadbeef.today",
                "claude@deadbeef.quota-4",
                "claude@deadbeef.usage-5"
            ]
        )

        store.providerErrors["claude@deadbeef"] = "token-expired:user@example.com"
        let failed = store.localMobileUsageDocument(deviceID: "mac-a", deviceName: "Studio")
        XCTAssertEqual(failed.providers["claude@deadbeef"]?.status, .unavailable)

        let encoded = try JSONEncoder().encode(failed)
        let payload = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(payload.contains("user@example.com"))
        XCTAssertFalse(payload.contains("Acme Research"))
        XCTAssertFalse(payload.contains("raw provider response"))
        XCTAssertFalse(payload.contains("soft account warning"))
        XCTAssertFalse(payload.contains("private-model-name"))
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "OpenUsageTests.MobileBuilder.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

@MainActor
private final class MobileSnapshotRuntime: ProviderRuntime {
    let provider = Provider(
        id: "claude@deadbeef",
        displayName: "Claude · user@example.com · Acme Research",
        icon: .providerMark("claude")
    )
    var widgetDescriptors: [WidgetDescriptor] {
        [
            .percent(id: "\(provider.id).session", provider: provider, title: "Session"),
            .percent(id: "\(provider.id).weekly", provider: provider, title: "Weekly"),
        ]
            + WidgetDescriptor.spendTiles(provider: provider)
    }

    func refresh() async -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: "claude@deadbeef",
            displayName: "Claude · user@example.com · Acme Research",
            plan: "Max",
            lines: [
                .progress(
                    label: "Session",
                    used: 24,
                    limit: 100,
                    format: .percent,
                    resetsAt: Date(timeIntervalSince1970: 3_600),
                    colorHex: "#D97757"
                ),
                .progress(
                    label: "Weekly",
                    used: 0,
                    limit: 100,
                    format: .percent,
                    resetsAt: Date(timeIntervalSince1970: 7_200),
                    periodDurationMs: MetricPeriod.weekMs,
                    colorHex: "#D97757"
                ),
                .values(
                    label: "Today",
                    values: [MetricValue(number: 1_250_000, kind: .count, label: "user@example.com")],
                    modelBreakdown: ModelUsageBreakdown(
                        totalTokens: 1_250_000,
                        totalCostUSD: 2.4,
                        models: [ModelUsageEntry(model: "private-model-name", totalTokens: 1_250_000, costUSD: nil)],
                        sourceNote: "local logs"
                    )
                ),
                .progress(
                    label: "private-model-name",
                    used: 10,
                    limit: 100,
                    format: .percent
                ),
                .values(
                    label: "Acme Research",
                    values: [MetricValue(number: 2.4, kind: .dollars)]
                ),
                .text(label: "Notice", value: "raw provider response"),
            ],
            refreshedAt: Date(timeIntervalSince1970: 100),
            warning: "soft account warning"
        )
    }

    func hasLocalCredentials() async -> Bool { true }
}
