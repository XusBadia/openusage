import Foundation

/// How a surface orders the providers it lists.
///
/// The app's Today screen always uses `custom` — that list is the order someone dragged into place.
/// A widget can ask for one of the other two instead, so a Home Screen can lead with whatever is about
/// to run out without disturbing the app.
public enum MobileProviderSort: String, Codable, Hashable, Sendable, CaseIterable {
    /// The order chosen in the app.
    case custom
    /// Least headline capacity left first. A provider with no bounded meter sorts last.
    case lowestRemaining
    /// Nearest headline reset first. A provider with no reset date sorts last.
    case soonestReset
}

public extension MobileProviderDisplaySettings {
    /// Applies a sort to already-visible providers, keeping the chosen order as the tie-breaker so equal
    /// keys never shuffle between refreshes.
    func sortedProviders(
        _ providers: [ResolvedMobileProvider],
        by sort: MobileProviderSort
    ) -> [ResolvedMobileProvider] {
        guard sort != .custom else { return providers }
        let keyed = providers.enumerated().map { position, source in
            (position: position, source: source, key: sortKey(for: source, sort: sort))
        }
        return keyed.sorted { left, right in
            switch (left.key, right.key) {
            case let (lhs?, rhs?) where lhs != rhs: lhs < rhs
            case (nil, .some): false
            case (.some, nil): true
            default: left.position < right.position
            }
        }
        .map(\.source)
    }

    private func sortKey(for source: ResolvedMobileProvider, sort: MobileProviderSort) -> Double? {
        guard let headline = cardMetrics(for: source.provider).headline else { return nil }
        switch sort {
        case .custom: return nil
        case .lowestRemaining: return headline.remainingFraction
        case .soonestReset: return headline.resetsAt?.timeIntervalSinceReferenceDate
        }
    }
}
