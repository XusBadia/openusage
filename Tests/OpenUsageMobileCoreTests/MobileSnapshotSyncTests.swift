import XCTest
@testable import OpenUsageMobileCore

final class MobileSnapshotSyncTests: XCTestCase {
    func testRefreshResolvesDocumentsAndLeavesTheCacheCurrentForEverySurface() async throws {
        let suiteName = "OpenUsageMobileCoreTests.Sync.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let store = MobileSharedSnapshotStore(suiteName: suiteName)
        let reader = StubReader(result: ICloudMobileReadResult(
            usageDocuments: [document(deviceID: "mac-a", used: 28)],
            historyDocuments: [],
            invalidFileCount: 0
        ))

        let refresh = try await MobileSnapshotSync.refresh(
            reader: reader,
            store: store,
            now: Date(timeIntervalSince1970: 500)
        )

        XCTAssertEqual(refresh.snapshot.providers.map(\.provider.providerID), ["claude"])
        XCTAssertEqual(refresh.snapshot.cachedAt, Date(timeIntervalSince1970: 500))
        // The widget extension runs this too, so whichever surface refreshed last must leave the shared
        // cache readable by the others.
        let cached = MobileSharedSnapshotStore(suiteName: suiteName).load()
        XCTAssertEqual(cached, refresh.snapshot)
    }

    func testAFailedReadLeavesTheCachedSnapshotAlone() async throws {
        let suiteName = "OpenUsageMobileCoreTests.Sync.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let store = MobileSharedSnapshotStore(suiteName: suiteName)
        let good = try await MobileSnapshotSync.refresh(
            reader: StubReader(result: ICloudMobileReadResult(
                usageDocuments: [document(deviceID: "mac-a", used: 28)],
                historyDocuments: [],
                invalidFileCount: 0
            )),
            store: store,
            // Whole seconds: the cache round-trips dates as ISO 8601, which drops fractions.
            now: Date(timeIntervalSince1970: 500)
        )

        do {
            _ = try await MobileSnapshotSync.refresh(reader: StubReader(error: ICloudMobileReaderError.unavailable), store: store)
            XCTFail("a failed read must surface instead of writing an empty snapshot")
        } catch {
            XCTAssertEqual(store.load(), good.snapshot)
        }
    }

    private func document(deviceID: String, used: Double) -> MobileUsageDocument {
        MobileUsageDocument(
            deviceID: deviceID,
            deviceName: "Studio",
            updatedAt: Date(timeIntervalSince1970: 100),
            providerOrder: ["claude"],
            providers: [
                "claude": MobileProviderSnapshot(
                    providerID: "claude",
                    displayName: "Claude",
                    refreshedAt: Date(timeIntervalSince1970: 100),
                    metrics: [
                        MobileUsageMetric(
                            id: "claude.session",
                            label: "Session",
                            presentation: .progress,
                            used: used,
                            limit: 100,
                            unit: MobileMetricUnit(kind: .percent)
                        )
                    ]
                )
            ]
        )
    }
}

private struct StubReader: MobileSnapshotReading {
    var result: ICloudMobileReadResult?
    var error: (any Error)?

    init(result: ICloudMobileReadResult) {
        self.result = result
    }

    init(error: any Error) {
        self.error = error
    }

    func load() async throws -> ICloudMobileReadResult {
        if let error { throw error }
        return result!
    }
}
