import Foundation

/// One completed read of the synced folder plus the shared snapshot it produced.
public struct MobileSnapshotRefresh: Sendable {
    public var read: ICloudMobileReadResult
    public var snapshot: MobileSharedSnapshot

    public init(read: ICloudMobileReadResult, snapshot: MobileSharedSnapshot) {
        self.read = read
        self.snapshot = snapshot
    }
}

/// The single path from "what a Mac published" to "what this phone renders".
///
/// The app and both WidgetKit extensions call this, so a widget timeline refresh produces exactly the
/// values opening the app would, and whichever surface ran last leaves the App Group cache current for
/// the others.
public enum MobileSnapshotSync {
    public static func refresh(
        reader: any MobileSnapshotReading,
        store: MobileSharedSnapshotStore,
        now: Date = Date()
    ) async throws -> MobileSnapshotRefresh {
        let read = try await reader.load()
        let snapshot = MobileSharedSnapshot(
            cachedAt: now,
            providers: MobileUsageResolver.resolve(read.usageDocuments),
            dailyTotals: MobileHistoryAggregator.totals(from: read.historyDocuments)
        )
        try store.save(snapshot)
        return MobileSnapshotRefresh(read: read, snapshot: snapshot)
    }
}
