import Foundation
import OpenUsageMobileCore

public struct OpenUsageLimitsEnvelope: Decodable, Sendable {
    public var schema: String
    public var generatedAt: String
    public var providers: [String: OpenUsageLimitProvider]
    public var errors: [OpenUsageLimitError]
}

public struct OpenUsageLimitProvider: Decodable, Sendable {
    public var displayName: String
    public var plan: String?
    public var fetchedAt: String
    public var stale: Bool
    public var resources: [String: OpenUsageLimitResource]
}

public struct OpenUsageLimitResource: Decodable, Sendable {
    public var kind: String
    public var unit: String
    public var used: Double?
    public var available: Double?
    public var limit: Double?
    public var resetsAt: String?
    public var windowSeconds: Double?
    public var expiresAt: [String]?
    public var estimated: Bool?
}

public struct OpenUsageLimitError: Decodable, Sendable {
    public var providerID: String
    public var message: String

    private enum CodingKeys: String, CodingKey {
        case providerID = "providerId"
        case message
    }
}

public struct OpenUsageLegacySnapshot: Decodable, Sendable {
    public var providerID: String
    public var displayName: String
    public var plan: String?
    public var lines: [OpenUsageLegacyLine]
    public var fetchedAt: String

    private enum CodingKeys: String, CodingKey {
        case providerID = "providerId"
        case displayName, plan, lines, fetchedAt
    }
}

public struct OpenUsageLegacyLine: Decodable, Sendable {
    public struct Format: Decodable, Sendable {
        public var kind: String
        public var suffix: String?
    }

    public var type: String
    public var label: String
    public var used: Double?
    public var limit: Double?
    public var format: Format?
    public var resetsAt: String?
    public var periodDurationMs: Int?
    public var color: String?
}

public enum OpenUsageBridgeMapper {
    public static func makeDocument(
        payload: OpenUsageBridgePayload,
        deviceID: String,
        deviceName: String,
        updatedAt: Date = Date()
    ) throws -> MobileUsageDocument {
        guard payload.limits.schema == "openusage.limits.v1" else {
            throw MobileUsageDocumentError.unsupportedSchema
        }

        let legacyByID = Dictionary(uniqueKeysWithValues: payload.usage.map { ($0.providerID, $0) })
        let errorIDs = Set(payload.limits.errors.map(\.providerID))
        let requestedOrder = payload.usage.map(\.providerID)
            + payload.limits.providers.keys.sorted()
        var seenProviders = Set<String>()
        let providerOrder = requestedOrder.filter {
            payload.limits.providers[$0] != nil && seenProviders.insert($0).inserted
        }

        var providers: [String: MobileProviderSnapshot] = [:]
        for providerID in providerOrder {
            guard let source = payload.limits.providers[providerID] else { continue }
            let legacy = legacyByID[providerID]
            var metrics = legacy?.lines.compactMap {
                progressMetric(providerID: providerID, line: $0)
            } ?? []
            var usedMetricIDs = Set(metrics.map(\.id))

            for (resourceKey, resource) in source.resources.sorted(by: { $0.key < $1.key }) {
                let label = humanized(resourceKey)
                let metricID = uniqueMetricID(
                    "\(providerID).\(slug(label))",
                    providerID: providerID,
                    resourceKey: resourceKey,
                    used: &usedMetricIDs
                )

                if resource.kind == "consumption", let used = resource.used, let limit = resource.limit, limit > 0 {
                    let resourceSlug = slug(label).replacingOccurrences(of: "-limit", with: "")
                    let alreadyPublished = metrics.contains {
                        $0.presentation == .progress
                            && slug($0.label).replacingOccurrences(of: "-limit", with: "") == resourceSlug
                    }
                    guard !alreadyPublished else { continue }
                    metrics.append(MobileUsageMetric(
                        id: metricID,
                        label: label,
                        presentation: .progress,
                        used: max(0, used),
                        limit: limit,
                        unit: mobileUnit(resource.unit),
                        resetsAt: parseDate(resource.resetsAt),
                        periodDurationMilliseconds: resource.windowSeconds.map { Int($0 * 1_000) }
                    ))
                    continue
                }

                let number = resource.kind == "balance" ? resource.available : resource.used
                guard let number, number.isFinite, number >= 0 else { continue }
                metrics.append(MobileUsageMetric(
                    id: metricID,
                    label: label,
                    presentation: .values,
                    values: [MobileMetricValue(
                        number: number,
                        unit: mobileUnit(resource.unit),
                        estimated: resource.estimated ?? false
                    )],
                    expiriesAt: (resource.expiresAt ?? []).compactMap(parseDate)
                ))
            }

            let status: MobileProviderStatus = if errorIDs.contains(providerID) {
                .unavailable
            } else if source.stale {
                .attention
            } else {
                .available
            }
            providers[providerID] = MobileProviderSnapshot(
                providerID: providerID,
                displayName: source.displayName,
                plan: source.plan,
                refreshedAt: parseDate(source.fetchedAt) ?? updatedAt,
                status: status,
                metrics: metrics
            )
        }

        let document = MobileUsageDocument(
            deviceID: deviceID,
            deviceName: deviceName,
            updatedAt: updatedAt,
            providerOrder: providerOrder,
            providers: providers
        )
        try document.validate()
        return document
    }

    private static func progressMetric(
        providerID: String,
        line: OpenUsageLegacyLine
    ) -> MobileUsageMetric? {
        guard line.type == "progress",
              let used = line.used, used.isFinite,
              let limit = line.limit, limit.isFinite, limit > 0,
              let format = line.format
        else { return nil }
        let label = safeLabel(line.label)
        return MobileUsageMetric(
            id: "\(providerID).\(slug(label))",
            label: label,
            presentation: .progress,
            used: max(0, used),
            limit: limit,
            unit: mobileUnit(format.kind, suffix: format.suffix),
            resetsAt: parseDate(line.resetsAt),
            periodDurationMilliseconds: line.periodDurationMs,
            colorHex: validColor(line.color)
        )
    }

    private static func mobileUnit(_ raw: String, suffix: String? = nil) -> MobileMetricUnit {
        switch raw.lowercased() {
        case "percent": MobileMetricUnit(kind: .percent)
        case "dollars", "usd": MobileMetricUnit(kind: .dollars)
        default: MobileMetricUnit(kind: .count, suffix: safeSuffix(suffix ?? raw))
        }
    }

    private static func humanized(_ value: String) -> String {
        let withSpaces = value
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "[-_]", with: " ")
        return withSpaces.split(separator: " ").map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    private static func slug(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func uniqueMetricID(
        _ candidate: String,
        providerID: String,
        resourceKey: String,
        used: inout Set<String>
    ) -> String {
        var result = candidate == "\(providerID)." ? "\(providerID).\(slug(resourceKey))" : candidate
        var attempt = 2
        while !used.insert(result).inserted {
            result = "\(candidate)-\(attempt)"
            attempt += 1
        }
        return result
    }

    private static func safeLabel(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 80,
              cleaned.rangeOfCharacter(from: .controlCharacters) == nil
        else { return "Usage" }
        return cleaned
    }

    private static func safeSuffix(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 20,
              cleaned.rangeOfCharacter(from: .controlCharacters) == nil
        else { return nil }
        return cleaned
    }

    private static func validColor(_ value: String?) -> String? {
        guard let value,
              value.range(of: #"^#[A-Fa-f0-9]{6}$"#, options: .regularExpression) != nil
        else { return nil }
        return value
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}
