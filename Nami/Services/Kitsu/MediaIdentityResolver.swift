import Foundation

/// Resolves optional interoperability IDs (MAL, AniList, ...) lazily from
/// Kitsu mappings. Addons that support Kitsu never trigger a lookup.
actor MediaIdentityResolver {
    private let client: KitsuClient
    private let cache: MetadataCache

    init(
        client: KitsuClient = KitsuClient(),
        cache: MetadataCache = MetadataCache()
    ) {
        self.client = client
        self.cache = cache
    }

    func resolve(
        _ identity: MediaIdentity,
        for namespaces: [AddonIDNamespace]
    ) async -> MediaIdentity {
        guard namespaces.contains(where: { Self.isMissing($0, in: identity) }) else {
            return identity
        }
        let key = "mappings:\(identity.kitsuID)"
        if case .identity(let cached)? = await cache.payload(for: key) {
            return identity.merging(cached)
        }
        do {
            let first = try await client.page(
                path: "anime/\(identity.kitsuID)/mappings",
                queryItems: [
                    URLQueryItem(name: "page[limit]", value: String(KitsuPagination.pageLimit)),
                ],
                as: KitsuMappingAttributes.self
            )
            let resources = try await KitsuPagination.collect(
                first: first,
                client: client,
                expectedCount: first.totalCount
            )
            guard
                let resolved = KitsuMapping.identities(
                    from: resources,
                    kitsuID: identity.kitsuID
                )
            else {
                return identity
            }
            await cache.store(.identity(resolved), for: key, ttl: CacheTTL.mappings)
            return identity.merging(resolved)
        } catch {
            if case .identity(let stale)? = await cache.stalePayload(for: key) {
                return identity.merging(stale)
            }
            return identity
        }
    }

    static func isMissing(_ namespace: AddonIDNamespace, in identity: MediaIdentity) -> Bool {
        switch namespace {
        case .kitsu: false
        case .mal: identity.malID == nil
        case .anilist: identity.anilistID == nil
        case .imdb: identity.imdbID == nil
        case .tmdb: identity.tmdbID == nil
        }
    }
}
