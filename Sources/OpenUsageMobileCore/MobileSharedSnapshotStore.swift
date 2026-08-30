import Foundation

/// App-group persistence shared by the iOS app and WidgetKit extensions. The iOS app remains the only
/// iCloud reader; widgets consume this cache so timeline refreshes stay quick and deterministic.
public struct MobileSharedSnapshotStore: Sendable {
    public static let snapshotKey = "openusage.mobile.sharedSnapshot.v1"
    public static let hideFinancialValuesKey = "openusage.mobile.hideFinancialValues.v1"

    private let suiteName: String

    public init(suiteName: String) {
        self.suiteName = suiteName
    }

    public func load() -> MobileSharedSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: Self.snapshotKey)
        else { return nil }
        return try? Self.makeDecoder().decode(MobileSharedSnapshot.self, from: data)
    }

    public func save(_ snapshot: MobileSharedSnapshot) throws {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw MobileSharedSnapshotStoreError.unavailable
        }
        defaults.set(try Self.makeEncoder().encode(snapshot), forKey: Self.snapshotKey)
    }

    public var hidesFinancialValues: Bool {
        get { UserDefaults(suiteName: suiteName)?.bool(forKey: Self.hideFinancialValuesKey) ?? false }
        nonmutating set { UserDefaults(suiteName: suiteName)?.set(newValue, forKey: Self.hideFinancialValuesKey) }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum MobileSharedSnapshotStoreError: Error, LocalizedError, Sendable {
    case unavailable

    public var errorDescription: String? { "The shared widget container is unavailable." }
}
