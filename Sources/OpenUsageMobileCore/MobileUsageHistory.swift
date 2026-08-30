import Foundation

/// Read-only mirror of the existing `openusage.history.v1/v2` documents. Keeping this in the mobile
/// module lets iOS consume today's sync format without pulling AppKit, provider clients, or credentials.
public struct MobileUsageHistoryDocument: Codable, Hashable, Identifiable, Sendable {
    public var schema: String
    public var deviceID: String
    public var deviceName: String
    public var updatedAt: Date
    public var providers: [String: MobileProviderUsageHistory]

    public var id: String { deviceID }

    public init(
        schema: String,
        deviceID: String,
        deviceName: String,
        updatedAt: Date,
        providers: [String: MobileProviderUsageHistory]
    ) {
        self.schema = schema
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.updatedAt = updatedAt
        self.providers = providers
    }

    private enum CodingKeys: String, CodingKey {
        case schema, deviceID, deviceName, updatedAt, providers
    }

    public func validate() throws {
        guard schema == "openusage.history.v1" || schema == "openusage.history.v2" else {
            throw MobileUsageHistoryError.unsupportedSchema
        }
        guard !deviceID.isEmpty, !deviceName.isEmpty else { throw MobileUsageHistoryError.invalidDevice }
        for (providerID, history) in providers {
            guard !providerID.isEmpty else { throw MobileUsageHistoryError.invalidProvider }
            var seen = Set<String>()
            for entry in history.series.daily {
                guard Self.isDayKey(entry.date), seen.insert(entry.date).inserted,
                      entry.totalTokens >= 0,
                      entry.costUSD.map({ $0.isFinite && $0 >= 0 }) ?? true
                else { throw MobileUsageHistoryError.invalidEntry }
            }
        }
    }

    public static func newestByDevice(_ documents: [Self]) -> [Self] {
        var newest: [String: Self] = [:]
        for document in documents where newest[document.deviceID]?.updatedAt ?? .distantPast < document.updatedAt {
            newest[document.deviceID] = document
        }
        return Array(newest.values)
    }

    private static func isDayKey(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }
}

public struct MobileProviderUsageHistory: Codable, Hashable, Sendable {
    public var series: MobileDailyUsageSeries

    public init(series: MobileDailyUsageSeries) {
        self.series = series
    }

    private enum CodingKeys: String, CodingKey { case series }
}

public struct MobileDailyUsageSeries: Codable, Hashable, Sendable {
    public var daily: [MobileDailyUsageEntry]

    public init(daily: [MobileDailyUsageEntry]) {
        self.daily = daily
    }
}

public struct MobileDailyUsageEntry: Codable, Hashable, Sendable {
    public var date: String
    public var totalTokens: Int
    public var costUSD: Double?

    public init(date: String, totalTokens: Int, costUSD: Double?) {
        self.date = date
        self.totalTokens = totalTokens
        self.costUSD = costUSD
    }
}

public struct MobileDailyTotal: Codable, Hashable, Identifiable, Sendable {
    public var date: String
    public var totalTokens: Int
    public var costUSD: Double?

    public var id: String { date }

    public init(date: String, totalTokens: Int, costUSD: Double?) {
        self.date = date
        self.totalTokens = totalTokens
        self.costUSD = costUSD
    }
}

public enum MobileHistoryAggregator {
    public static func totals(
        from input: [MobileUsageHistoryDocument],
        providerIDs: Set<String>? = nil
    ) -> [MobileDailyTotal] {
        let documents = MobileUsageHistoryDocument.newestByDevice(input)
        var totals: [String: (tokens: Int, cost: Double?)] = [:]
        for document in documents {
            for (providerID, history) in document.providers where providerIDs?.contains(providerID) ?? true {
                for entry in history.series.daily {
                    let existing = totals[entry.date] ?? (0, nil)
                    let cost = [existing.cost, entry.costUSD].compactMap { $0 }
                    totals[entry.date] = (
                        existing.tokens + entry.totalTokens,
                        cost.isEmpty ? nil : cost.reduce(0, +)
                    )
                }
            }
        }
        return totals.map { MobileDailyTotal(date: $0.key, totalTokens: $0.value.tokens, costUSD: $0.value.cost) }
            .sorted { $0.date < $1.date }
    }
}

public enum MobileUsageHistoryError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedSchema
    case invalidDevice
    case invalidProvider
    case invalidEntry

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema: "A Mac wrote a newer usage history format. Update the app."
        case .invalidDevice: "The synced Mac identity is invalid."
        case .invalidProvider: "The synced history provider is invalid."
        case .invalidEntry: "The synced history contains an invalid daily value."
        }
    }
}
