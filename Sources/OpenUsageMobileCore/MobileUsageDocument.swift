import Foundation

/// A presentation-neutral, privacy-filtered snapshot written by a Mac for mobile clients.
///
/// The mobile wire format deliberately does not reuse `ProviderSnapshot`. Provider snapshots may
/// contain raw notices, account-scoped history, or future Mac-only fields. This contract contains only
/// the numeric usage state that a person explicitly chose to share with their own devices.
public struct MobileUsageDocument: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchema = "openusage.mobile.v1"

    public var schema: String
    public var deviceID: String
    public var deviceName: String
    public var updatedAt: Date
    public var providerOrder: [String]
    public var providers: [String: MobileProviderSnapshot]

    public var id: String { deviceID }

    public init(
        schema: String = Self.currentSchema,
        deviceID: String,
        deviceName: String,
        updatedAt: Date,
        providerOrder: [String],
        providers: [String: MobileProviderSnapshot]
    ) {
        self.schema = schema
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.updatedAt = updatedAt
        self.providerOrder = providerOrder
        self.providers = providers
    }

    public func validate() throws {
        guard schema == Self.currentSchema else { throw MobileUsageDocumentError.unsupportedSchema }
        try Self.validateIdentifier(deviceID, error: .invalidDevice)
        try Self.validateText(deviceName, maximumLength: 120, error: .invalidDevice)

        guard Set(providerOrder).count == providerOrder.count,
              Set(providerOrder).isSubset(of: Set(providers.keys))
        else { throw MobileUsageDocumentError.invalidProviderOrder }

        for (providerID, provider) in providers {
            guard providerID == provider.providerID,
                  providerID.range(
                    of: #"^[a-z0-9][a-z0-9-]*(?:@[a-f0-9]{8})?$"#,
                    options: .regularExpression
                  ) != nil
            else { throw MobileUsageDocumentError.invalidProvider(providerID) }
            try provider.validate()
        }
    }

    public static func newestByDevice(_ documents: [MobileUsageDocument]) -> [MobileUsageDocument] {
        var newest: [String: MobileUsageDocument] = [:]
        for document in documents {
            if let existing = newest[document.deviceID], existing.updatedAt >= document.updatedAt { continue }
            newest[document.deviceID] = document
        }
        return newest.values.sorted {
            if $0.updatedAt == $1.updatedAt { return $0.deviceID < $1.deviceID }
            return $0.updatedAt > $1.updatedAt
        }
    }

    fileprivate static func validateIdentifier(
        _ value: String,
        error: MobileUsageDocumentError
    ) throws {
        guard !value.isEmpty, value.count <= 128,
              value.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              !value.contains("/"), !value.contains("\\")
        else { throw error }
    }

    fileprivate static func validateText(
        _ value: String,
        maximumLength: Int,
        error: MobileUsageDocumentError
    ) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.count <= maximumLength,
              value.rangeOfCharacter(from: .controlCharacters) == nil
        else { throw error }
    }
}

public struct MobileProviderSnapshot: Codable, Hashable, Identifiable, Sendable {
    public var providerID: String
    public var displayName: String
    public var plan: String?
    public var refreshedAt: Date
    public var status: MobileProviderStatus
    public var metrics: [MobileUsageMetric]

    public var id: String { providerID }

    public init(
        providerID: String,
        displayName: String,
        plan: String? = nil,
        refreshedAt: Date,
        status: MobileProviderStatus = .available,
        metrics: [MobileUsageMetric]
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.plan = plan
        self.refreshedAt = refreshedAt
        self.status = status
        self.metrics = metrics
    }

    public var primaryMetric: MobileUsageMetric? {
        metrics.first(where: { $0.presentation == .progress }) ?? metrics.first
    }

    fileprivate func validate() throws {
        try MobileUsageDocument.validateText(
            displayName,
            maximumLength: 80,
            error: .invalidProvider(providerID)
        )
        if let plan {
            try MobileUsageDocument.validateText(plan, maximumLength: 80, error: .invalidPlan(providerID))
        }
        guard Set(metrics.map(\.id)).count == metrics.count else {
            throw MobileUsageDocumentError.duplicateMetric(providerID)
        }
        for metric in metrics { try metric.validate(providerID: providerID) }
    }
}

public enum MobileProviderStatus: String, Codable, Hashable, Sendable {
    case available
    case attention
    case unavailable
}

public struct MobileUsageMetric: Codable, Hashable, Identifiable, Sendable {
    public enum Presentation: String, Codable, Hashable, Sendable {
        case progress
        case values
    }

    public var id: String
    public var label: String
    public var presentation: Presentation
    public var used: Double?
    public var limit: Double?
    public var unit: MobileMetricUnit?
    public var values: [MobileMetricValue]
    public var resetsAt: Date?
    public var periodDurationMilliseconds: Int?
    public var expiriesAt: [Date]
    public var colorHex: String?

    public init(
        id: String,
        label: String,
        presentation: Presentation,
        used: Double? = nil,
        limit: Double? = nil,
        unit: MobileMetricUnit? = nil,
        values: [MobileMetricValue] = [],
        resetsAt: Date? = nil,
        periodDurationMilliseconds: Int? = nil,
        expiriesAt: [Date] = [],
        colorHex: String? = nil
    ) {
        self.id = id
        self.label = label
        self.presentation = presentation
        self.used = used
        self.limit = limit
        self.unit = unit
        self.values = values
        self.resetsAt = resetsAt
        self.periodDurationMilliseconds = periodDurationMilliseconds
        self.expiriesAt = expiriesAt
        self.colorHex = colorHex
    }

    /// Remaining bounded capacity in the 0...1 range. `nil` for unbounded value rows.
    public var remainingFraction: Double? {
        guard presentation == .progress, let used, let limit, limit > 0 else { return nil }
        return max(0, min(1, 1 - used / limit))
    }

    fileprivate func validate(providerID: String) throws {
        try MobileUsageDocument.validateIdentifier(id, error: .invalidMetric(providerID))
        try MobileUsageDocument.validateText(label, maximumLength: 80, error: .invalidMetric(providerID))
        if let colorHex, colorHex.range(of: #"^#[A-Fa-f0-9]{6}$"#, options: .regularExpression) == nil {
            throw MobileUsageDocumentError.invalidMetric(providerID)
        }
        guard values.allSatisfy(\.isValid),
              periodDurationMilliseconds.map({ $0 > 0 }) ?? true
        else { throw MobileUsageDocumentError.invalidMetric(providerID) }

        switch presentation {
        case .progress:
            guard let used, used.isFinite, used >= 0,
                  let limit, limit.isFinite, limit > 0,
                  unit != nil, values.isEmpty
            else { throw MobileUsageDocumentError.invalidMetric(providerID) }
        case .values:
            guard used == nil, limit == nil, unit == nil, !values.isEmpty
            else { throw MobileUsageDocumentError.invalidMetric(providerID) }
        }
    }
}

public struct MobileMetricUnit: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case percent
        case dollars
        case count
    }

    public var kind: Kind
    public var suffix: String?

    public init(kind: Kind, suffix: String? = nil) {
        self.kind = kind
        self.suffix = suffix
    }
}

public struct MobileMetricValue: Codable, Hashable, Sendable {
    public var number: Double
    public var unit: MobileMetricUnit
    public var label: String?
    public var estimated: Bool

    public init(number: Double, unit: MobileMetricUnit, label: String? = nil, estimated: Bool = false) {
        self.number = number
        self.unit = unit
        self.label = label
        self.estimated = estimated
    }

    fileprivate var isValid: Bool {
        number.isFinite && number >= 0
            && (label?.rangeOfCharacter(from: .controlCharacters) == nil)
            && (label?.count ?? 0) <= 40
            && (unit.suffix?.rangeOfCharacter(from: .controlCharacters) == nil)
            && (unit.suffix?.count ?? 0) <= 20
    }
}

public enum MobileUsageDocumentError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedSchema
    case invalidDevice
    case invalidProviderOrder
    case invalidProvider(String)
    case invalidPlan(String)
    case duplicateMetric(String)
    case invalidMetric(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema: "A Mac wrote a newer mobile usage format. Update the app."
        case .invalidDevice: "The synced Mac identity is invalid."
        case .invalidProviderOrder: "The synced provider order is invalid."
        case .invalidProvider: "The synced provider is invalid."
        case .invalidPlan: "The synced plan is invalid."
        case .duplicateMetric: "The synced provider contains a metric more than once."
        case .invalidMetric: "The synced provider contains an invalid metric."
        }
    }
}
