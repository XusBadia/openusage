import Foundation
import OpenUsageMobileCore
@testable import OpenUsageMobileBridgeCore
import XCTest

final class OpenUsageBridgeMapperTests: XCTestCase {
    func testMapsProviderOrderProgressBalancesAndErrors() throws {
        let limits = Data(#"""
        {
          "schema":"openusage.limits.v1",
          "generatedAt":"2026-09-01T22:30:12.570Z",
          "providers":{
            "claude":{
              "displayName":"Claude",
              "plan":"Max 5x",
              "fetchedAt":"2026-09-01T22:25:21.874Z",
              "stale":false,
              "resources":{
                "session":{"kind":"consumption","unit":"percent","used":42,"limit":100},
                "credits":{"kind":"balance","unit":"credits","available":12}
              }
            },
            "grok":{
              "displayName":"Grok",
              "plan":"SuperGrok",
              "fetchedAt":"2026-09-01T22:25:21.000Z",
              "stale":false,
              "resources":{}
            }
          },
          "errors":[{"providerId":"grok","message":"refresh failed"}]
        }
        """#.utf8)
        let usage = Data(#"""
        [
          {
            "providerId":"grok",
            "displayName":"Grok",
            "plan":"SuperGrok",
            "fetchedAt":"2026-09-01T22:25:21.000Z",
            "lines":[]
          },
          {
            "providerId":"claude",
            "displayName":"Claude",
            "plan":"Max 5x",
            "fetchedAt":"2026-09-01T22:25:21.874Z",
            "lines":[{
              "type":"progress",
              "label":"Session",
              "used":42,
              "limit":100,
              "format":{"kind":"percent"},
              "resetsAt":"2026-09-02T03:25:21.000Z",
              "periodDurationMs":18000000,
              "color":"#22C55E"
            }]
          }
        ]
        """#.utf8)
        let decoder = JSONDecoder()
        let payload = OpenUsageBridgePayload(
            limits: try decoder.decode(OpenUsageLimitsEnvelope.self, from: limits),
            usage: try decoder.decode([OpenUsageLegacySnapshot].self, from: usage)
        )

        let document = try OpenUsageBridgeMapper.makeDocument(
            payload: payload,
            deviceID: "mac-1",
            deviceName: "Test Mac",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(document.providerOrder, ["grok", "claude"])
        XCTAssertEqual(document.providers["grok"]?.status, .unavailable)
        XCTAssertEqual(document.providers["claude"]?.status, .available)
        XCTAssertEqual(document.providers["claude"]?.metrics.map(\.id), ["claude.session", "claude.credits"])
        let remainingFraction = try XCTUnwrap(document.providers["claude"]?.metrics[0].remainingFraction)
        XCTAssertEqual(remainingFraction, 0.58, accuracy: 0.0001)
        XCTAssertEqual(document.providers["claude"]?.metrics[1].values.first?.number, 12)
        XCTAssertEqual(document.providers["claude"]?.metrics[1].values.first?.unit.kind, .count)
        XCTAssertNoThrow(try document.validate())
    }

    func testPublisherWritesStatusAndMirrorsCompatibleHistory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenUsageBridgeTests-\(UUID().uuidString)", isDirectory: true)
        let container = root.appendingPathComponent("container", isDirectory: true)
        let source = root.appendingPathComponent("history", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let status = MobileUsageDocument(
            deviceID: "mac-1",
            deviceName: "Test Mac",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            providerOrder: [],
            providers: [:]
        )
        let history = MobileUsageHistoryDocument(
            schema: "openusage.history.v1",
            deviceID: "mac-1",
            deviceName: "Test Mac",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            providers: [
                "claude": MobileProviderUsageHistory(
                    series: MobileDailyUsageSeries(daily: [
                        MobileDailyUsageEntry(date: "2026-09-01", totalTokens: 42, costUSD: 0.12)
                    ])
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(history).write(to: source.appendingPathComponent("mac-1.json"))

        let publisher = MobileBridgePublisher(containerURL: container)
        try await publisher.publish(status)
        let mirrored = try await publisher.mirrorHistory(from: source)

        XCTAssertEqual(mirrored, 1)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: container.appendingPathComponent("OpenUsage/Mobile/v1/mac-1.json").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: container.appendingPathComponent("OpenUsage/History/v1/mac-1.json").path
        ))
    }
}
