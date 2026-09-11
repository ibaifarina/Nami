import Foundation

/// A single decoded Kitsu collection page.
struct KitsuPage<Attributes: Decodable & Sendable>: Sendable {
    let resources: [JSONAPIResource<Attributes>]
    let included: [KitsuIncludedResource]
    let nextURL: URL?
    let totalCount: Int?
}

extension KitsuClient {
    func page<Attributes: Decodable & Sendable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        as type: Attributes.Type
    ) async throws -> KitsuPage<Attributes> {
        let document: JSONAPIDocument<[JSONAPIResource<Attributes>], KitsuIncludedResource> =
            try await document(path: path, queryItems: queryItems, as: JSONAPIDocument<
                [JSONAPIResource<Attributes>],
                KitsuIncludedResource
            >.self)
        return KitsuPage(
            resources: document.data,
            included: document.included ?? [],
            nextURL: document.links?.next,
            totalCount: document.meta?.count
        )
    }

    func page<Attributes: Decodable & Sendable>(
        url: URL,
        as type: Attributes.Type
    ) async throws -> KitsuPage<Attributes> {
        let document: JSONAPIDocument<[JSONAPIResource<Attributes>], KitsuIncludedResource> =
            try await document(url: url, as: JSONAPIDocument<
                [JSONAPIResource<Attributes>],
                KitsuIncludedResource
            >.self)
        return KitsuPage(
            resources: document.data,
            included: document.included ?? [],
            nextURL: document.links?.next,
            totalCount: document.meta?.count
        )
    }
}

/// Walks Kitsu pagination safely.
enum KitsuPagination {
    /// Maximum pages followed for a single logical request. Kitsu pages hold
    /// at most 20 resources, so this caps a request at 1,000 resources.
    static let defaultMaxPages = 50

    /// Collects resources across pages until the API reports no next page,
    /// the expected count is reached, or the page cap is hit.
    static func collect<Attributes: Decodable & Sendable>(
        first: KitsuPage<Attributes>,
        client: KitsuClient,
        expectedCount: Int? = nil,
        maxPages: Int = defaultMaxPages
    ) async throws -> [JSONAPIResource<Attributes>] {
        var collected = first.resources
        var nextURL = first.nextURL
        var pages = 1

        while let url = nextURL, pages < maxPages {
            if let expectedCount, collected.count >= expectedCount { break }
            try Task.checkCancellation()
            let page = try await client.page(url: url, as: Attributes.self)
            guard !page.resources.isEmpty else { break }
            collected.append(contentsOf: page.resources)
            nextURL = page.nextURL
            pages += 1
        }
        return collected
    }

    /// Page size used by the app. Kitsu caps page sizes at 20.
    static let pageLimit = 20
}
