import Foundation

public enum OpenUsageLocalClientError: Error, LocalizedError, Sendable {
    case unavailable
    case invalidResponse(Int)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "OpenUsage isn’t running, or its local API isn’t available."
        case .invalidResponse(let status):
            "OpenUsage’s local API returned HTTP \(status)."
        }
    }
}

public struct OpenUsageBridgePayload: Sendable {
    public var limits: OpenUsageLimitsEnvelope
    public var usage: [OpenUsageLegacySnapshot]

    public init(limits: OpenUsageLimitsEnvelope, usage: [OpenUsageLegacySnapshot]) {
        self.limits = limits
        self.usage = usage
    }
}

/// Reads the two stable, read-only loopback endpoints exposed by the official OpenUsage app.
/// Credentials and raw provider responses never cross this boundary.
public actor OpenUsageLocalClient {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    private let baseURL: URL
    private let fetch: Fetch
    private let decoder = JSONDecoder()

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:6736")!,
        fetch: Fetch? = nil
    ) {
        self.baseURL = baseURL
        self.fetch = fetch ?? { url in
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OpenUsageLocalClientError.unavailable
            }
            guard http.statusCode == 200 else {
                throw OpenUsageLocalClientError.invalidResponse(http.statusCode)
            }
            return data
        }
    }

    public func load() async throws -> OpenUsageBridgePayload {
        async let limitsData = fetch(baseURL.appending(path: "v1/limits"))
        async let usageData = fetch(baseURL.appending(path: "v1/usage"))
        do {
            return try await OpenUsageBridgePayload(
                limits: decoder.decode(OpenUsageLimitsEnvelope.self, from: limitsData),
                usage: decoder.decode([OpenUsageLegacySnapshot].self, from: usageData)
            )
        } catch let error as OpenUsageLocalClientError {
            throw error
        } catch {
            throw OpenUsageLocalClientError.unavailable
        }
    }
}
