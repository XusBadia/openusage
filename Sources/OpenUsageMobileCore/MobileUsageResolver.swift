import Foundation

/// A provider snapshot paired with the Mac that produced it. Mobile surfaces use this type so the
/// provenance and age can never drift away from the number being shown.
public struct ResolvedMobileProvider: Codable, Hashable, Identifiable, Sendable {
    public var provider: MobileProviderSnapshot
    public var deviceID: String
    public var deviceName: String
    public var documentUpdatedAt: Date

    public var id: String { provider.providerID }

    public init(
        provider: MobileProviderSnapshot,
        deviceID: String,
        deviceName: String,
        documentUpdatedAt: Date
    ) {
        self.provider = provider
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.documentUpdatedAt = documentUpdatedAt
    }
}

public enum MobileUsageResolver {
    /// Picks the newest valid snapshot independently for each provider, then applies the most recent
    /// producing Mac's stable order. Cards therefore stay put while still following the freshest data.
    public static func resolve(_ input: [MobileUsageDocument]) -> [ResolvedMobileProvider] {
        let documents = MobileUsageDocument.newestByDevice(input)
        var newest: [String: ResolvedMobileProvider] = [:]

        for document in documents {
            for (providerID, provider) in document.providers {
                let candidate = ResolvedMobileProvider(
                    provider: provider,
                    deviceID: document.deviceID,
                    deviceName: document.deviceName,
                    documentUpdatedAt: document.updatedAt
                )
                guard let existing = newest[providerID] else {
                    newest[providerID] = candidate
                    continue
                }
                if provider.refreshedAt > existing.provider.refreshedAt
                    || (provider.refreshedAt == existing.provider.refreshedAt
                        && document.updatedAt > existing.documentUpdatedAt)
                    || (provider.refreshedAt == existing.provider.refreshedAt
                        && document.updatedAt == existing.documentUpdatedAt
                        && document.deviceID < existing.deviceID)
                {
                    newest[providerID] = candidate
                }
            }
        }

        let order = documents
            .sorted {
                if $0.updatedAt == $1.updatedAt { return $0.deviceID < $1.deviceID }
                return $0.updatedAt > $1.updatedAt
            }
            .flatMap(\.providerOrder)
            .uniqued()
        let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })

        return newest.values.sorted { lhs, rhs in
            let left = positions[lhs.provider.providerID] ?? Int.max
            let right = positions[rhs.provider.providerID] ?? Int.max
            if left != right { return left < right }
            return lhs.provider.displayName.localizedCaseInsensitiveCompare(rhs.provider.displayName) == .orderedAscending
        }
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
