import XCTest
import OpenUsageMobileCore
@testable import OpenUsage

@MainActor
final class MobileUsageDocumentBuilderTests: XCTestCase {
    func testBuilderExportsOnlySanitizedNumericMetrics() async throws {
        let runtime = MobileSnapshotRuntime()
        let defaults = makeDefaults()
        let store = WidgetDataStore(
            registry: WidgetRegistry(providers: [runtime.provider], descriptors: []),
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
        XCTAssertEqual(provider.metrics.count, 4)
        XCTAssertEqual(provider.metrics.first?.remainingFraction, 0.76)
        XCTAssertEqual(provider.metrics[2].label, "Quota 3")
        XCTAssertEqual(provider.metrics[3].label, "Usage 4")

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
    let widgetDescriptors: [WidgetDescriptor] = []

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
