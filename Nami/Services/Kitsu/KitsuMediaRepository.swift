import Foundation

/// Kitsu-backed implementation of the canonical media repository.
actor KitsuMediaRepository: MediaRepository {
    private let client: KitsuClient
    private let cache: MetadataCache

    init(
        client: KitsuClient = KitsuClient(),
        cache: MetadataCache = MetadataCache()
    ) {
        self.client = client
        self.cache = cache
    }

    func anime(id: String) async throws -> AnimeDetails {
        let key = "details:\(id)"
        if case .details(let cached)? = await cache.payload(for: key) {
            return cached
        }
        do {
            let document: JSONAPIDocument<
                JSONAPIResource<KitsuAnimeAttributes>,
                KitsuIncludedResource
            > = try await client.document(
                path: "anime/\(id)",
                queryItems: [
                    URLQueryItem(
                        name: "include",
                        value: "categories,mediaRelationships.destination,mappings"
                    ),
                ],
                as: JSONAPIDocument<
                    JSONAPIResource<KitsuAnimeAttributes>,
                    KitsuIncludedResource
                >.self
            )
            let details = Self.makeDetails(
                from: document.data,
                included: document.included ?? []
            )
            await cache.store(.details(details), for: key, ttl: CacheTTL.details)
            return details
        } catch {
            if case .details(let stale)? = await cache.stalePayload(for: key) {
                return stale
            }
            throw CatalogError.map(error)
        }
    }

    func search(query: String, page: Int) async throws -> [Anime] {
        try await discover(query: query, filters: DiscoverFilters(), page: page)
    }

    func popular(page: Int) async throws -> [Anime] {
        try await list(
            path: "anime",
            queryItems: pageQueryItems(
                page: page,
                extra: [URLQueryItem(name: "sort", value: "popularityRank")]
            ),
            key: "popular:\(page)",
            ttl: CacheTTL.list
        )
    }

    func topRated(page: Int) async throws -> [Anime] {
        try await list(
            path: "anime",
            queryItems: pageQueryItems(
                page: page,
                extra: [URLQueryItem(name: "sort", value: "ratingRank")]
            ),
            key: "top-rated:\(page)",
            ttl: CacheTTL.list
        )
    }

    func currentlyAiring(page: Int) async throws -> [Anime] {
        try await list(
            path: "anime",
            queryItems: pageQueryItems(
                page: page,
                extra: [
                    URLQueryItem(name: "filter[status]", value: AnimeStatus.current.rawValue),
                    URLQueryItem(name: "sort", value: "popularityRank"),
                ]
            ),
            key: "airing:\(page)",
            ttl: CacheTTL.list
        )
    }

    func upcoming(page: Int) async throws -> [Anime] {
        try await list(
            path: "anime",
            queryItems: pageQueryItems(
                page: page,
                extra: [
                    URLQueryItem(name: "filter[status]", value: AnimeStatus.upcoming.rawValue),
                    URLQueryItem(name: "sort", value: "startDate"),
                ]
            ),
            key: "upcoming:\(page)",
            ttl: CacheTTL.list
        )
    }

    func recentlyReleased(page: Int) async throws -> [Anime] {
        try await list(
            path: "anime",
            queryItems: pageQueryItems(
                page: page,
                extra: [
                    URLQueryItem(name: "filter[status]", value: AnimeStatus.finished.rawValue),
                    URLQueryItem(name: "sort", value: "-startDate"),
                ]
            ),
            key: "recent:\(page)",
            ttl: CacheTTL.list
        )
    }

    func discover(query: String?, filters: DiscoverFilters, page: Int) async throws -> [Anime] {
        var extra: [URLQueryItem] = []
        let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedQuery.isEmpty {
            extra.append(URLQueryItem(name: "filter[text]", value: trimmedQuery))
        }
        if let genre = filters.genre, !genre.isEmpty {
            extra.append(URLQueryItem(name: "filter[categories]", value: genre))
        }
        if let season = filters.season {
            extra.append(URLQueryItem(name: "filter[season]", value: season.rawValue))
        }
        if let year = filters.year {
            extra.append(URLQueryItem(name: "filter[seasonYear]", value: String(year)))
        }
        if let status = filters.status {
            extra.append(URLQueryItem(name: "filter[status]", value: status.rawValue))
        }
        if let subtype = filters.subtype {
            extra.append(URLQueryItem(name: "filter[subtype]", value: subtype.rawValue))
        }
        extra.append(URLQueryItem(name: "sort", value: filters.sort.kitsuSort))

        let key = "discover:\(trimmedQuery.lowercased()):\(filters.cacheKey):\(page)"
        let ttl = trimmedQuery.isEmpty ? CacheTTL.list : CacheTTL.search
        return try await list(
            path: "anime",
            queryItems: pageQueryItems(page: page, extra: extra),
            key: key,
            ttl: ttl
        )
    }

    // MARK: - Details mapping

    static func makeDetails(
        from resource: JSONAPIResource<KitsuAnimeAttributes>,
        included: [KitsuIncludedResource]
    ) -> AnimeDetails {
        var anime = KitsuMapping.anime(resource)

        let genres = included.compactMap { item -> String? in
            guard case .category(let category) = item else { return nil }
            return KitsuMapping.cleaned(category.attributes.title)
        }
        if !genres.isEmpty {
            anime = anime.with(genres: genres)
        }

        let mappings = included.compactMap { item -> JSONAPIResource<KitsuMappingAttributes>? in
            guard case .mapping(let mapping) = item else { return nil }
            return mapping
        }
        if let resolved = KitsuMapping.identities(from: mappings, kitsuID: resource.id) {
            anime = anime.with(identity: anime.identity.merging(resolved))
        }

        let animeByID = Dictionary(
            included.compactMap { item -> (String, Anime)? in
                guard case .anime(let resource) = item else { return nil }
                return (resource.id, KitsuMapping.anime(resource))
            },
            uniquingKeysWith: { first, _ in first }
        )

        var relations: [AnimeRelation] = []
        var seen = Set<String>([resource.id])
        for item in included {
            guard case .mediaRelationship(let relationship) = item else { continue }
            guard
                let role = KitsuMapping.relationRole(relationship.attributes.role),
                let destination = relationship.relationships?["destination"]?.data?.first,
                destination.type == "anime",
                destination.id != resource.id,
                seen.insert(destination.id).inserted,
                let target = animeByID[destination.id]
            else {
                continue
            }
            relations.append(AnimeRelation(role: role, anime: target))
        }

        return AnimeDetails(anime: anime, relations: relations)
    }

    // MARK: - List fetching

    private func list(
        path: String,
        queryItems: [URLQueryItem],
        key: String,
        ttl: TimeInterval
    ) async throws -> [Anime] {
        if case .animeList(let cached)? = await cache.payload(for: key) {
            return cached
        }
        do {
            let page = try await client.page(
                path: path,
                queryItems: queryItems,
                as: KitsuAnimeAttributes.self
            )
            let items = page.resources
                .filter { $0.attributes.nsfw != true }
                .map(KitsuMapping.anime)
            await cache.store(.animeList(items), for: key, ttl: ttl)
            return items
        } catch {
            if case .animeList(let stale)? = await cache.stalePayload(for: key) {
                return stale
            }
            throw CatalogError.map(error)
        }
    }

    /// Kitsu's `page[offset]` returns the first page again whenever a
    /// `filter[...]` is present, which stalls paging. `page[number]` with
    /// `page[size]` paginates correctly for both filtered and plain lists.
    private func pageQueryItems(page: Int, extra: [URLQueryItem]) -> [URLQueryItem] {
        [
            URLQueryItem(
                name: "page[size]",
                value: String(KitsuPagination.pageLimit)
            ),
            URLQueryItem(
                name: "page[number]",
                value: String(max(page, 0) + 1)
            ),
        ] + extra
    }
}
