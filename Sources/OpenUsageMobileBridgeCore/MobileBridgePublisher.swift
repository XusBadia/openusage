import Foundation
import OpenUsageMobileCore

public enum MobileBridgePublisherError: Error, LocalizedError, Sendable {
    case iCloudUnavailable

    public var errorDescription: String? {
        "The companion’s iCloud container isn’t available. Check iCloud Drive and the bridge signature."
    }
}

/// Writes the bridge's sanitized status document and mirrors compatible history documents into the
/// iCloud Documents container shared with the TestFlight app and its widgets.
public actor MobileBridgePublisher {
    private let containerURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(containerURL: URL) {
        self.containerURL = containerURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func publish(_ document: MobileUsageDocument) throws {
        try document.validate()
        let directory = containerURL
            .appendingPathComponent("OpenUsage", isDirectory: true)
            .appendingPathComponent("Mobile", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try coordinatedWrite(
            encoder.encode(document),
            to: directory.appendingPathComponent(document.deviceID).appendingPathExtension("json")
        )
    }

    /// Returns the number of valid official OpenUsage history files mirrored. A missing source is a
    /// normal state when history sync is off in the Mac app, so it is not an error.
    public func mirrorHistory(from sourceDirectory: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: sourceDirectory.path) else { return 0 }
        let destination = containerURL
            .appendingPathComponent("OpenUsage", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let sources = try FileManager.default.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }
        var count = 0
        for source in sources {
            let document = try decoder.decode(MobileUsageHistoryDocument.self, from: coordinatedRead(source))
            try document.validate()
            try coordinatedWrite(
                encoder.encode(document),
                to: destination.appendingPathComponent(document.deviceID).appendingPathExtension("json")
            )
            count += 1
        }
        return count
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

    private func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var operationError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do { try data.write(to: coordinatedURL, options: .atomic) }
            catch { operationError = error }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
    }
}
