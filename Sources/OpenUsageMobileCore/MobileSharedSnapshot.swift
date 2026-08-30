import Foundation

/// Compact app-group cache consumed by WidgetKit. The containing app is the only iCloud reader;
/// extensions render this last-known value and never pretend they refreshed a provider themselves.
public struct MobileSharedSnapshot: Codable, Hashable, Sendable {
    public var cachedAt: Date
    public var providers: [ResolvedMobileProvider]
    public var dailyTotals: [MobileDailyTotal]

    public init(
        cachedAt: Date,
        providers: [ResolvedMobileProvider],
        dailyTotals: [MobileDailyTotal]
    ) {
        self.cachedAt = cachedAt
        self.providers = providers
        self.dailyTotals = dailyTotals
    }
}
