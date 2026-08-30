import XCTest
@testable import OpenUsageMobileCore

final class MobileProviderDisplaySettingsTests: XCTestCase {
    func testAppliesSavedOrderVisibilityAndAppendsNewProviders() {
        let input = [
            resolvedProvider(id: "claude"),
            resolvedProvider(id: "codex"),
            resolvedProvider(id: "cursor"),
        ]
        let settings = MobileProviderDisplaySettings(
            providerOrder: ["codex", "claude"],
            hiddenProviderIDs: ["claude"]
        )

        XCTAssertEqual(
            settings.orderedProviders(from: input).map(\.provider.providerID),
            ["codex", "claude", "cursor"]
        )
        XCTAssertEqual(
            settings.visibleProviders(from: input).map(\.provider.providerID),
            ["codex", "cursor"]
        )
    }

    func testSharedStorePersistsDisplaySettings() {
        let suiteName = "OpenUsageMobileCoreTests.Display.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let store = MobileSharedSnapshotStore(suiteName: suiteName)
        let expected = MobileProviderDisplaySettings(
            providerOrder: ["cursor", "codex", "claude"],
            hiddenProviderIDs: ["codex"]
        )

        store.providerDisplaySettings = expected

        XCTAssertEqual(MobileSharedSnapshotStore(suiteName: suiteName).providerDisplaySettings, expected)
    }

    private func resolvedProvider(id: String) -> ResolvedMobileProvider {
        let provider = MobileProviderSnapshot(
            providerID: id,
            displayName: id.capitalized,
            refreshedAt: Date(timeIntervalSince1970: 100),
            metrics: [
                MobileUsageMetric(
                    id: "\(id).session",
                    label: "Session",
                    presentation: .progress,
                    used: 25,
                    limit: 100,
                    unit: MobileMetricUnit(kind: .percent)
                )
            ]
        )
        return ResolvedMobileProvider(
            provider: provider,
            deviceID: "mac",
            deviceName: "Mac",
            documentUpdatedAt: provider.refreshedAt
        )
    }
}
