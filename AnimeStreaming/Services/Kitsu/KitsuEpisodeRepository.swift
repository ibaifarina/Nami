import Foundation

/// Kitsu-backed episode repository with proper pagination and caching.
actor KitsuEpisodeRepository: EpisodeRepository {
    private let client: KitsuClient
    private let cache: MetadataCache

    init(
        client: KitsuClient = KitsuClient(),
        cache: MetadataCache = MetadataCache()
    ) {
        self.client = client
        self.cache = cache
    }

    func episodes(forAnimeID id: String) async throws -> [Episode] {
        try await fetch(id: id, ttl: CacheTTL.episodes)
    }

    func episodes(forAnimeID id: String, isAiring: Bool) async throws -> [Episode] {
        try await fetch(id: id, ttl: isAiring ? CacheTTL.airingEpisodes : CacheTTL.episodes)
    }

    private func fetch(id: String, ttl: TimeInterval) async throws -> [Episode] {
        let key = "episodes:\(id)"
        if case .episodes(let cached)? = await cache.payload(for: key) {
            return cached
        }
        do {
            let first = try await client.page(
                path: "anime/\(id)/episodes",
                queryItems: [
                    URLQueryItem(name: "page[limit]", value: String(KitsuPagination.pageLimit)),
                    URLQueryItem(name: "sort", value: "number"),
                ],
                as: KitsuEpisodeAttributes.self
            )
            let resources = try await KitsuPagination.collect(
                first: first,
                client: client,
                expectedCount: first.totalCount
            )
            var seen = Set<String>()
            let episodes = resources
                .compactMap { KitsuMapping.episode($0, animeID: id) }
                .filter { seen.insert($0.id).inserted }
                .sorted { lhs, rhs in
                    if lhs.number != rhs.number { return lhs.number < rhs.number }
                    return lhs.id < rhs.id
                }
            await cache.store(.episodes(episodes), for: key, ttl: ttl)
            return episodes
        } catch {
            if case .episodes(let stale)? = await cache.stalePayload(for: key) {
                return stale
            }
            throw CatalogError.map(error)
        }
    }
}
