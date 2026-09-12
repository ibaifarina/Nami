import Foundation

/// Context used to resolve identifiers that are not derived from Kitsu
/// mappings alone (currently IMDb, which needs a title search fallback).
struct AddonIdentityContext: Sendable {
    var titles: [String]
    var year: Int?
    var isMovie: Bool

    init(titles: [String] = [], year: Int? = nil, isMovie: Bool = false) {
        self.titles = titles
        self.year = year
        self.isMovie = isMovie
    }
}

/// Resolves optional interoperability IDs (MAL, AniList, ...) lazily from
/// Kitsu mappings. Addons that support Kitsu never trigger a lookup.
///
/// Kitsu rarely exposes IMDb IDs, so addons that only accept IMDb are
/// supported through an additional `IMDbResolver` pass when configured.
actor MediaIdentityResolver {
    private let client: KitsuClient
    private let cache: MetadataCache
    private let imdbResolver: IMDbResolver?

    init(
        client: KitsuClient = KitsuClient(),
        cache: MetadataCache = MetadataCache(),
        imdbResolver: IMDbResolver? = nil
    ) {
        self.client = client
        self.cache = cache
        self.imdbResolver = imdbResolver
    }

    func resolve(
        _ identity: MediaIdentity,
        for namespaces: [AddonIDNamespace],
        context: AddonIdentityContext = AddonIdentityContext()
    ) async -> MediaIdentity {
        guard namespaces.contains(where: { Self.isMissing($0, in: identity) }) else {
            return identity
        }
        let key = "mappings:\(identity.kitsuID)"
        var mappings: [JSONAPIResource<KitsuMappingAttributes>] = []
        var resolved = identity
        var didStoreMappings = false

        if case .identity(let cached)? = await cache.payload(for: key) {
            resolved = identity.merging(cached)
        } else {
            do {
                let first = try await client.page(
                    path: "anime/\(identity.kitsuID)/mappings",
                    queryItems: [
                        URLQueryItem(name: "page[limit]", value: String(KitsuPagination.pageLimit)),
                    ],
                    as: KitsuMappingAttributes.self
                )
                mappings = try await KitsuPagination.collect(
                    first: first,
                    client: client,
                    expectedCount: first.totalCount
                )
                if let merged = KitsuMapping.identities(
                    from: mappings,
                    kitsuID: identity.kitsuID
                ) {
                    resolved = identity.merging(merged)
                    await cache.store(
                        .identity(resolved),
                        for: key,
                        ttl: CacheTTL.mappings
                    )
                    didStoreMappings = true
                }
            } catch {
                if case .identity(let stale)? = await cache.stalePayload(for: key) {
                    resolved = identity.merging(stale)
                }
            }
        }

        guard namespaces.contains(.imdb), resolved.imdbID == nil, let imdbResolver else {
            return resolved
        }
        let theTVDBID = KitsuMapping.theTVDBID(from: mappings)
        guard
            let imdbID = await imdbResolver.imdbID(
                kitsuID: identity.kitsuID,
                theTVDBID: theTVDBID,
                context: IMDbResolver.Context(
                    titles: context.titles,
                    year: context.year,
                    isMovie: context.isMovie
                )
            )
        else {
            return resolved
        }
        resolved.imdbID = imdbID
        if didStoreMappings {
            await cache.store(.identity(resolved), for: key, ttl: CacheTTL.mappings)
        }
        return resolved
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
