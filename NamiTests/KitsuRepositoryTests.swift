import Foundation
import Testing
@testable import Nami

private func kitsuPageResponse(_ request: URLRequest, pageOne: Data, pageTwo: Data) -> Data {
    let url = request.url?.absoluteString ?? ""
    if url.contains("page%5Boffset%5D=2") || url.contains("page[offset]=2") {
        return pageTwo
    }
    return pageOne
}

struct KitsuRepositoryTests {
    private func animeResponse(_ request: URLRequest, pageOne: Data, pageTwo: Data) -> Data {
        kitsuPageResponse(request, pageOne: pageOne, pageTwo: pageTwo)
    }

    @Test func popularBuildsExpectedRequest() async throws {
        let http = MockHTTPClient { _ in KitsuFixtures.animePageOneJSON }
        let repository = KitsuMediaRepository(
            client: KitsuClient(http: http),
            cache: MetadataCache(directory: nil)
        )

        let items = try await repository.popular(page: 0)
        #expect(items.count == 2)

        let request = try #require(await http.lastRequest)
        let url = request.url?.absoluteString ?? ""
        #expect(url.contains("/api/edge/anime"))
        #expect(url.contains("page%5Blimit%5D=20") || url.contains("page[limit]=20"))
        #expect(url.contains("page%5Boffset%5D=0") || url.contains("page[offset]=0"))
        #expect(url.contains("sort=popularityRank"))
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.api+json")
    }

    @Test func popularCachesResults() async throws {
        let http = MockHTTPClient { _ in KitsuFixtures.animePageOneJSON }
        let repository = KitsuMediaRepository(
            client: KitsuClient(http: http),
            cache: MetadataCache(directory: nil)
        )

        _ = try await repository.popular(page: 0)
        _ = try await repository.popular(page: 0)

        #expect(await http.requestCount == 1)
    }

    @Test func searchSendsTextFilter() async throws {
        let http = MockHTTPClient { _ in KitsuFixtures.animePageOneJSON }
        let repository = KitsuMediaRepository(
            client: KitsuClient(http: http),
            cache: MetadataCache(directory: nil)
        )

        _ = try await repository.search(query: "frieren", page: 0)

        let url = try #require(await http.lastRequest?.url?.absoluteString)
        #expect(url.contains("filter%5Btext%5D=frieren") || url.contains("filter[text]=frieren"))
    }

    @Test func discoverSendsFiltersAndSort() async throws {
        let http = MockHTTPClient { _ in KitsuFixtures.emptyCollectionJSON }
        let repository = KitsuMediaRepository(
            client: KitsuClient(http: http),
            cache: MetadataCache(directory: nil)
        )
        var filters = DiscoverFilters()
        filters.genre = "sci-fi"
        filters.year = 2024
        filters.status = .current
        filters.subtype = .tv
        filters.season = .fall
        filters.sort = .rating

        _ = try await repository.discover(query: nil, filters: filters, page: 1)

        let url = try #require(await http.lastRequest?.url?.absoluteString)
        #expect(url.contains("filter%5Bcategories%5D=sci-fi") || url.contains("filter[categories]=sci-fi"))
        #expect(url.contains("filter%5BseasonYear%5D=2024") || url.contains("filter[seasonYear]=2024"))
        #expect(url.contains("filter%5Bstatus%5D=current") || url.contains("filter[status]=current"))
        #expect(url.contains("filter%5Bsubtype%5D=TV") || url.contains("filter[subtype]=TV"))
        #expect(url.contains("filter%5Bseason%5D=fall") || url.contains("filter[season]=fall"))
        #expect(url.contains("sort=ratingRank"))
        #expect(url.contains("page%5Boffset%5D=20") || url.contains("page[offset]=20"))
    }

    @Test func detailsDecodeRelationsAndIdentity() async throws {
        let http = MockHTTPClient { _ in KitsuFixtures.animeDetailsJSON }
        let repository = KitsuMediaRepository(
            client: KitsuClient(http: http),
            cache: MetadataCache(directory: nil)
        )

        let details = try await repository.anime(id: "8671")
        #expect(details.anime.id == "8671")
        #expect(details.anime.identity.malID == 25777)
        #expect(details.relations.contains { $0.role == .prequel && $0.anime.id == "7442" })

        let url = try #require(await http.lastRequest?.url?.absoluteString)
        #expect(url.contains("include="))
        #expect(url.contains("mediaRelationships.destination"))
        #expect(url.contains("mappings"))
    }

    @Test func staleDetailsAreServedWhenRefreshFails() async throws {
        let cache = MetadataCache(directory: nil)
        let known = Anime(
            identity: MediaIdentity(kitsuID: "8671"),
            title: "Cached Show",
            subtype: .tv
        )
        await cache.store(
            .details(AnimeDetails(anime: known, relations: [])),
            for: "details:8671",
            ttl: -1
        )

        let failing = MockHTTPClient { _ in throw HTTPError.transport("offline") }
        let repository = KitsuMediaRepository(
            client: KitsuClient(http: failing),
            cache: cache
        )

        let details = try await repository.anime(id: "8671")
        #expect(details.anime.displayTitle == "Cached Show")
    }

    @Test func staleListsAreServedWhenRefreshFails() async throws {
        let cache = MetadataCache(directory: nil)
        await cache.store(
            .animeList([SampleCatalog.anime[0]]),
            for: "popular:0",
            ttl: -1
        )

        let failing = MockHTTPClient { _ in throw HTTPError.transport("offline") }
        let repository = KitsuMediaRepository(
            client: KitsuClient(http: failing),
            cache: cache
        )

        let items = try await repository.popular(page: 0)
        #expect(items.count == 1)
    }

    @Test func httpErrorsMapToCatalogErrors() async {
        let notFound = MockHTTPClient {
            _ in throw HTTPError.httpStatus(code: 404, body: nil)
        }
        let repository = KitsuMediaRepository(
            client: KitsuClient(http: notFound),
            cache: MetadataCache(directory: nil)
        )

        await #expect(throws: CatalogError.notFound) {
            try await repository.anime(id: "missing")
        }
    }

    @Test func episodeRepositoryPaginatesAndSorts() async throws {
        let http = MockHTTPClient { request in
            self.animeResponse(
                request,
                pageOne: KitsuFixtures.episodePageOneJSON,
                pageTwo: KitsuFixtures.episodePageTwoJSON
            )
        }
        let repository = KitsuEpisodeRepository(
            client: KitsuClient(http: http),
            cache: MetadataCache(directory: nil)
        )

        let episodes = try await repository.episodes(forAnimeID: "7442")
        #expect(episodes.count == 3)
        #expect(episodes.map(\.number) == [1, 2, 3])
        #expect(await http.requestCount == 2)
    }

    @Test func episodeRepositoryCachesForCompletedShows() async throws {
        let http = MockHTTPClient { request in
            self.animeResponse(
                request,
                pageOne: KitsuFixtures.episodePageOneJSON,
                pageTwo: KitsuFixtures.episodePageTwoJSON
            )
        }
        let repository = KitsuEpisodeRepository(
            client: KitsuClient(http: http),
            cache: MetadataCache(directory: nil)
        )

        _ = try await repository.episodes(forAnimeID: "7442", isAiring: false)
        _ = try await repository.episodes(forAnimeID: "7442", isAiring: false)
        #expect(await http.requestCount == 2)

        _ = try await repository.episodes(forAnimeID: "7442", isAiring: true)
        #expect(await http.requestCount == 2)
    }
}

struct KitsuPaginationTests {
    @Test func collectsUntilExpectedCountIsReached() async throws {
        let http = MockHTTPClient { request in
            kitsuPageResponse(
                request,
                pageOne: KitsuFixtures.episodePageOneJSON,
                pageTwo: KitsuFixtures.episodePageTwoJSON
            )
        }
        let client = KitsuClient(http: http)
        let first = try await client.page(
            path: "anime/7442/episodes",
            queryItems: [URLQueryItem(name: "page[limit]", value: "2")],
            as: KitsuEpisodeAttributes.self
        )

        let collected = try await KitsuPagination.collect(
            first: first,
            client: client,
            expectedCount: first.totalCount
        )
        #expect(collected.count == 3)
        #expect(await http.requestCount == 2)
    }

    @Test func respectsMaxPageGuard() async throws {
        let http = MockHTTPClient { _ in KitsuFixtures.episodePageOneJSON }
        let client = KitsuClient(http: http)
        let first = try await client.page(
            path: "anime/7442/episodes",
            queryItems: [URLQueryItem(name: "page[limit]", value: "2")],
            as: KitsuEpisodeAttributes.self
        )

        let collected = try await KitsuPagination.collect(
            first: first,
            client: client,
            expectedCount: nil,
            maxPages: 3
        )
        #expect(collected.count == 6)
        #expect(await http.requestCount == 3)
    }

    @Test func rejectsNonKitsuPaginationHosts() async {
        let http = MockHTTPClient { _ in KitsuFixtures.episodePageTwoJSON }
        let client = KitsuClient(http: http)

        await #expect(throws: CatalogError.server("Kitsu returned an unexpected pagination link.")) {
            try await client.document(
                url: testURL("https://evil.example/anime"),
                as: JSONAPIDocument<
                    [JSONAPIResource<KitsuAnimeAttributes>],
                    KitsuIncludedResource
                >.self
            )
        }
    }

    @Test func isKitsuURLValidatesHosts() {
        #expect(KitsuClient.isKitsuURL(testURL("https://kitsu.io/api/edge/anime")))
        #expect(KitsuClient.isKitsuURL(testURL("https://media.kitsu.app/image.jpg")) == false)
        #expect(!KitsuClient.isKitsuURL(testURL("https://kitsu.io.evil.example/anime")))
        #expect(!KitsuClient.isKitsuURL(testURL("https://evil.example/kitsu.io")))
    }
}
