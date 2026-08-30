import XCTest
@testable import OpenUsageMobileCore

final class MobileUsageDocumentTests: XCTestCase {
    func testDocumentRoundTripsAndValidates() throws {
        let document = makeDocument(deviceID: "mac-a", refreshedAt: Date(timeIntervalSince1970: 100))
        try document.validate()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MobileUsageDocument.self, from: encoder.encode(document))

        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.providers["claude"]?.primaryMetric?.remainingFraction, 0.72)
    }

    func testResolverUsesNewestProviderWithoutReorderingCards() throws {
        var older = makeDocument(deviceID: "mac-a", refreshedAt: Date(timeIntervalSince1970: 100))
        older.providerOrder = ["claude", "codex"]
        older.providers["codex"] = provider(id: "codex", refreshedAt: Date(timeIntervalSince1970: 100))

        var newer = makeDocument(deviceID: "mac-b", refreshedAt: Date(timeIntervalSince1970: 200))
        newer.providers["claude"]?.metrics[0].used = 64

        let resolved = MobileUsageResolver.resolve([older, newer])

        XCTAssertEqual(resolved.map(\.provider.providerID), ["claude", "codex"])
        XCTAssertEqual(resolved.first?.deviceName, "mac-b")
        XCTAssertEqual(resolved.first?.provider.primaryMetric?.remainingFraction, 0.36)
    }

    func testRejectsRawControlCharactersAndNonFiniteValues() {
        var invalidName = makeDocument(deviceID: "mac-a", refreshedAt: .now)
        invalidName.providers["claude"]?.displayName = "Claude\u{0000}"
        XCTAssertThrowsError(try invalidName.validate())

        var invalidValue = makeDocument(deviceID: "mac-a", refreshedAt: .now)
        invalidValue.providers["claude"]?.metrics[0].used = .infinity
        XCTAssertThrowsError(try invalidValue.validate())
    }

    private func makeDocument(deviceID: String, refreshedAt: Date) -> MobileUsageDocument {
        MobileUsageDocument(
            deviceID: deviceID,
            deviceName: deviceID,
            updatedAt: refreshedAt,
            providerOrder: ["claude"],
            providers: ["claude": provider(id: "claude", refreshedAt: refreshedAt)]
        )
    }

    private func provider(id: String, refreshedAt: Date) -> MobileProviderSnapshot {
        MobileProviderSnapshot(
            providerID: id,
            displayName: id.capitalized,
            plan: "Pro",
            refreshedAt: refreshedAt,
            metrics: [
                MobileUsageMetric(
                    id: "\(id).session",
                    label: "Session",
                    presentation: .progress,
                    used: 28,
                    limit: 100,
                    unit: MobileMetricUnit(kind: .percent),
                    resetsAt: refreshedAt.addingTimeInterval(3_600),
                    colorHex: "#D97757"
                )
            ]
        )
    }
}
