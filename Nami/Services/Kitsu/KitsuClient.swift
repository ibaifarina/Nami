import Foundation

/// Small JSON:API client for the public Kitsu API.
///
/// Public metadata requests do not require authentication. The client reuses
/// the app-wide `HTTPClient` abstraction and simply decodes JSON:API
/// documents.
struct KitsuClient: Sendable {
    static let baseURL = URL(string: "https://kitsu.io/api/edge")!

    private let http: any HTTPClient
    private let timeout: TimeInterval
    private let maxResponseBytes: Int

    init(
        http: any HTTPClient = URLSessionHTTPClient(),
        timeout: TimeInterval = 20,
        maxResponseBytes: Int = 8_000_000
    ) {
        self.http = http
        self.timeout = timeout
        self.maxResponseBytes = maxResponseBytes
    }

    /// Fetches a document at a path relative to the Kitsu API root.
    func document<Data: Decodable & Sendable, Included: Decodable & Sendable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        as type: JSONAPIDocument<Data, Included>.Type
    ) async throws -> JSONAPIDocument<Data, Included> {
        let url = try Self.makeURL(path: path, queryItems: queryItems)
        return try await document(url: url, as: type)
    }

    /// Fetches a document from an absolute URL (used to follow pagination
    /// links). Only Kitsu hosts are accepted.
    func document<Data: Decodable & Sendable, Included: Decodable & Sendable>(
        url: URL,
        as type: JSONAPIDocument<Data, Included>.Type
    ) async throws -> JSONAPIDocument<Data, Included> {
        guard Self.isKitsuURL(url) else {
            throw CatalogError.server(String(localized: "Kitsu returned an unexpected pagination link."))
        }
        let request = RequestBuilder(
            url: url,
            headers: ["Accept": "application/vnd.api+json"],
            timeout: timeout
        ).build()
        do {
            return try await http.send(request, as: type, maxBytes: maxResponseBytes)
        } catch {
            throw CatalogError.map(error)
        }
    }

    static func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard
            var components = URLComponents(
                url: baseURL.appending(path: trimmed),
                resolvingAgainstBaseURL: false
            )
        else {
            throw CatalogError.server(String(localized: "Could not build a Kitsu request URL."))
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw CatalogError.server(String(localized: "Could not build a Kitsu request URL."))
        }
        return url
    }

    static func isKitsuURL(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return host == "kitsu.io" || host.hasSuffix(".kitsu.io") || host == "kitsu.app"
    }
}
