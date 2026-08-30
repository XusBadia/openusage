import Foundation
import OpenUsageMobileCore

protocol MobileUsageFileStoring: Sendable {
    func write(_ document: MobileUsageDocument) async throws
    func delete(deviceID: String) async throws
}

/// Writes the opt-in, sanitized mobile snapshot beside (not inside) the existing history schema.
/// Separate folders let older Mac builds keep reading history without seeing an unknown document type.
actor ICloudMobileUsageFileStore: MobileUsageFileStoring {
    private let encoder: JSONEncoder

    init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func write(_ document: MobileUsageDocument) async throws {
        try document.validate()
        let directory = try mobileDirectory(create: true)
        let url = directory.appendingPathComponent(document.deviceID).appendingPathExtension("json")
        try coordinatedWrite(encoder.encode(document), to: url)
    }

    func delete(deviceID: String) async throws {
        let directory = try mobileDirectory(create: false)
        let url = directory.appendingPathComponent(deviceID).appendingPathExtension("json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var coordinationError: NSError?
        var operationError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { coordinatedURL in
            do { try FileManager.default.removeItem(at: coordinatedURL) }
            catch { operationError = error }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
    }

    private func mobileDirectory(create: Bool) throws -> URL {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            throw ICloudUsageSyncError.unavailable
        }
        let directory = container
            .appendingPathComponent("OpenUsage", isDirectory: true)
            .appendingPathComponent("Mobile", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
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
