import Foundation
import OpenUsageMobileCore
import OSLog

struct ICloudMobileReadResult: Sendable {
    var usageDocuments: [MobileUsageDocument]
    var historyDocuments: [MobileUsageHistoryDocument]
    var invalidFileCount: Int
}

protocol MobileSnapshotReading: Sendable {
    func load() async throws -> ICloudMobileReadResult
}

enum ICloudMobileReaderError: Error, LocalizedError {
    case unavailable

    var errorDescription: String? {
        "iCloud Drive isn’t available. Check that this iPhone is signed in and iCloud Drive is on."
    }
}

actor ICloudMobileReader: MobileSnapshotReading {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "UsageCompanion", category: "iCloud")

    func load() async throws -> ICloudMobileReadResult {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            throw ICloudMobileReaderError.unavailable
        }

        let usageDirectory = container
            .appendingPathComponent("OpenUsage", isDirectory: true)
            .appendingPathComponent("Mobile", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        let historyDirectory = container
            .appendingPathComponent("OpenUsage", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)

        let usage: LoadResult<MobileUsageDocument> = loadDocuments(at: usageDirectory) { try $0.validate() }
        let history: LoadResult<MobileUsageHistoryDocument> = loadDocuments(at: historyDirectory) { try $0.validate() }
        return ICloudMobileReadResult(
            usageDocuments: usage.documents,
            historyDocuments: history.documents,
            invalidFileCount: usage.invalidCount + history.invalidCount
        )
    }

    private struct LoadResult<Document> {
        var documents: [Document]
        var invalidCount: Int
    }

    private func loadDocuments<Document: Decodable>(
        at directory: URL,
        validate: (Document) throws -> Void
    ) -> LoadResult<Document> {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return LoadResult(documents: [], invalidCount: 0)
        }
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "json" }
        } catch {
            logger.error("Could not enumerate a synced usage directory")
            return LoadResult(documents: [], invalidCount: 1)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var documents: [Document] = []
        var invalidCount = 0
        for url in urls {
            do {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                let document = try decoder.decode(Document.self, from: coordinatedRead(url))
                try validate(document)
                documents.append(document)
            } catch {
                invalidCount += 1
                logger.warning("Ignored an invalid synced usage file")
            }
        }
        return LoadResult(documents: documents, invalidCount: invalidCount)
    }

    private func coordinatedRead(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result { try Data(contentsOf: coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        return try result?.get() ?? { throw CocoaError(.fileReadUnknown) }()
    }
}
