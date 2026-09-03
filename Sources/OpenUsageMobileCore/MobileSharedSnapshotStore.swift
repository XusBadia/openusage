import Foundation

/// App-group persistence shared by the iOS app and WidgetKit extensions. Whichever surface refreshes
/// iCloud last updates the cache and notification state for the next one.
public struct MobileSharedSnapshotStore: Sendable {
    public static let snapshotKey = "openusage.mobile.sharedSnapshot.v1"
    public static let hideFinancialValuesKey = "openusage.mobile.hideFinancialValues.v1"
    public static let providerDisplaySettingsKey = "openusage.mobile.providerDisplaySettings.v1"
    public static let notificationSettingsKey = "openusage.mobile.notificationSettings.v1"
    static let quotaNotificationStateKey = "openusage.mobile.quotaNotificationState.v1"

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

    public var providerDisplaySettings: MobileProviderDisplaySettings {
        get {
            guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: Self.providerDisplaySettingsKey)
            else { return MobileProviderDisplaySettings() }
            return (try? Self.makeDecoder().decode(MobileProviderDisplaySettings.self, from: data))
                ?? MobileProviderDisplaySettings()
        }
        nonmutating set {
            let data = try? Self.makeEncoder().encode(newValue)
            UserDefaults(suiteName: suiteName)?.set(data, forKey: Self.providerDisplaySettingsKey)
        }
    }

    public var notificationSettings: MobileNotificationSettings {
        get {
            guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: Self.notificationSettingsKey)
            else { return MobileNotificationSettings() }
            return (try? Self.makeDecoder().decode(MobileNotificationSettings.self, from: data))
                ?? MobileNotificationSettings()
        }
        nonmutating set {
            let data = try? Self.makeEncoder().encode(newValue)
            UserDefaults(suiteName: suiteName)?.set(data, forKey: Self.notificationSettingsKey)
        }
    }

    var quotaNotificationState: MobileQuotaNotificationState {
        get {
            guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: Self.quotaNotificationStateKey)
            else { return MobileQuotaNotificationState() }
            return (try? Self.makeDecoder().decode(MobileQuotaNotificationState.self, from: data))
                ?? MobileQuotaNotificationState()
        }
        nonmutating set {
            let data = try? Self.makeEncoder().encode(newValue)
            UserDefaults(suiteName: suiteName)?.set(data, forKey: Self.quotaNotificationStateKey)
        }
    }

    public func resetQuotaNotificationState() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: Self.quotaNotificationStateKey)
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
