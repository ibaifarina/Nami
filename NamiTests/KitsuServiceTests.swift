import Foundation
import Testing
@testable import Nami

struct MediaIdentityResolverTests {
    @Test func doesNotFetchWhenKitsuIsEnough() async {
        let http = MockHTTPClient { _ in
            throw HTTPError.transport("should not be called")
        }
        let resolver = MediaIdentityResolver(
            client: KitsuClient(http: http),
            cache: MetadataCache(directory: nil)
        )

        let resolved = await resolver.resolve(MediaIdentity(kitsuID: "8671"), for: [.kitsu])

        #expect(resolved.kitsuID == "8671")
        #expect(await http.requestCount == 0)
    }

    @Test func doesNotFetchWhenIDIsAlreadyKnown() async {
        let http = MockHTTPClient { _ in
            throw HTTPError.transport("should not be called")
        }
        let resolver = MediaIdentityResolver(
            client: KitsuClient(http: http),
            cache: MetadataCache(directory: nil)
        )

        let identity = MediaIdentity(kitsuID: "8671", malID: 25777)
        let resolved = await resolver.resolve(identity, for: [.mal])

        #expect(resolved.malID == 25777)
        #expect(await http.requestCount == 0)
    }

    @Test func resolvesMALAndAniListFromMappings() async {
        let http = MockHTTPClient { _ in KitsuFixtures.mappingsJSON }
        let resolver = MediaIdentityResolver(
            client: KitsuClient(http: http),
            cache: MetadataCache(directory: nil)
        )

        let resolved = await resolver.resolve(
            MediaIdentity(kitsuID: "8671"),
            for: [.mal, .anilist]
        )

        #expect(resolved.malID == 25777)
        #expect(resolved.anilistID == 20958)
        #expect(await http.requestCount == 1)
    }

    @Test func cachesResolvedMappings() async {
        let http = MockHTTPClient { _ in KitsuFixtures.mappingsJSON }
        let resolver = MediaIdentityResolver(
            client: KitsuClient(http: http),
            cache: MetadataCache(directory: nil)
        )

        _ = await resolver.resolve(MediaIdentity(kitsuID: "8671"), for: [.mal])
        _ = await resolver.resolve(MediaIdentity(kitsuID: "8671"), for: [.anilist])

        #expect(await http.requestCount == 1)
    }

    @Test func returnsOriginalIdentityWhenMappingsFail() async {
        let http = MockHTTPClient { _ in throw HTTPError.transport("offline") }
        let resolver = MediaIdentityResolver(
            client: KitsuClient(http: http),
            cache: MetadataCache(directory: nil)
        )

        let identity = MediaIdentity(kitsuID: "8671")
        let resolved = await resolver.resolve(identity, for: [.imdb])

        #expect(resolved.kitsuID == "8671")
        #expect(resolved.imdbID == nil)
    }
}

struct SeriesGroupingServiceTests {
    private func anime(
        id: String,
        title: String,
        subtype: AnimeSubtype = .tv,
        episodes: Int
    ) -> Anime {
        SampleCatalog.make(
            id: id,
            title: title,
            canonical: title,
            subtype: subtype,
            status: .finished,
            year: 2013,
            episodes: episodes,
            duration: 24
        )
    }

    private func details(
        _ anime: Anime,
        relations: [AnimeRelation]
    ) -> AnimeDetails {
        AnimeDetails(anime: anime, relations: relations)
    }

    @Test func buildsSequentialSeasonsFromPrequelSequelRelations() async throws {
        let season1 = anime(id: "1", title: "Attack on Titan", episodes: 25)
        let season2 = anime(id: "2", title: "Attack on Titan Season 2", episodes: 12)
        let season3 = anime(id: "3", title: "Attack on Titan Season 3", episodes: 12)
        let sideStory = anime(id: "9", title: "AoT OVA", subtype: .ova, episodes: 3)
        let movie = anime(id: "10", title: "AoT Movie", subtype: .movie, episodes: 1)

        var repository = StubMediaRepository()
        repository.details = [
            "1": details(season1, relations: [AnimeRelation(role: .sequel, anime: season2)]),
            "2": details(season2, relations: [
                AnimeRelation(role: .prequel, anime: season1),
                AnimeRelation(role: .sequel, anime: season3),
                AnimeRelation(role: .sideStory, anime: sideStory),
            ]),
            "3": details(season3, relations: [
                AnimeRelation(role: .prequel, anime: season2),
                AnimeRelation(role: .alternativeVersion, anime: movie),
            ]),
        ]

        let service = SeriesGroupingService(repository: repository)
        let season2Details = try #require(repository.details["2"])
        let series = await service.series(for: season2, details: season2Details)

        #expect(series.installments.map(\.anime.id) == ["1", "2", "3"])
        #expect(series.installments.map(\.displayName) == ["Season 1", "Season 2", "Season 3"])
        #expect(series.installments.map(\.absoluteEpisodeOffset) == [0, 25, 37])
        #expect(series.rootAnime.id == "1")

        #expect(series.related.contains { $0.anime.id == "9" })
        #expect(series.related.contains { $0.anime.id == "10" })
        #expect(!series.installments.contains { $0.anime.id == "9" })
        #expect(!series.installments.contains { $0.anime.id == "10" })

        let second = try #require(series.installments.count > 1 ? series.installments[1] : nil)
        let absolute = second.absoluteNumber(forEpisodeNumber: 3)
        #expect(absolute == 28)
    }

    @Test func completeChainDoesNotIncludeNonTVEntries() async throws {
        let season1 = anime(id: "1", title: "Show", episodes: 12)
        let movieSequel = anime(id: "2", title: "Show Movie", subtype: .movie, episodes: 1)

        var repository = StubMediaRepository()
        repository.details = [
            "1": details(season1, relations: [AnimeRelation(role: .sequel, anime: movieSequel)]),
        ]

        let service = SeriesGroupingService(repository: repository)
        let season1Details = try #require(repository.details["1"])
        let series = await service.series(for: season1, details: season1Details)

        #expect(series.installments.count == 1)
        #expect(series.installments.first?.anime.id == "1")
        #expect(series.related.contains { $0.anime.id == "2" })
    }

    @Test func missingPrequelUsesTitleSeasonNumberForDisplay() async throws {
        let season2 = anime(id: "2", title: "Show Season 2", episodes: 12)
        let season3 = anime(id: "3", title: "Show Season 3", episodes: 12)

        var repository = StubMediaRepository()
        repository.details = [
            "2": details(season2, relations: [AnimeRelation(role: .sequel, anime: season3)]),
            "3": details(season3, relations: [AnimeRelation(role: .prequel, anime: season2)]),
        ]

        let service = SeriesGroupingService(repository: repository)
        let season2Details = try #require(repository.details["2"])
        let series = await service.series(for: season2, details: season2Details)

        #expect(series.installments.map(\.displayName) == ["Season 2", "Season 3"])
    }

    @Test func finalSeasonTitleIsPreserved() async throws {
        let season1 = anime(id: "1", title: "Show", episodes: 12)
        let finalSeason = anime(id: "2", title: "Show: The Final Season", episodes: 16)

        var repository = StubMediaRepository()
        repository.details = [
            "1": details(season1, relations: [AnimeRelation(role: .sequel, anime: finalSeason)]),
        ]

        let service = SeriesGroupingService(repository: repository)
        let season1Details = try #require(repository.details["1"])
        let series = await service.series(for: season1, details: season1Details)

        #expect(series.installments.map(\.displayName) == ["Season 1", "Final Season"])
    }

    @Test func standaloneAnimeReturnsSingleInstallment() async {
        let standalone = anime(id: "1", title: "Standalone", episodes: 12)
        let repository = StubMediaRepository()

        let service = SeriesGroupingService(repository: repository)
        let series = await service.series(
            for: standalone,
            details: details(standalone, relations: [])
        )

        #expect(series.installments.count == 1)
        #expect(series.related.isEmpty)
        #expect(series.installments.first?.displayName == "Season 1")
    }

    @Test func seasonNumberExtraction() {
        #expect(SeriesGroupingService.seasonNumber(inTitle: "Show 2nd Season") == 2)
        #expect(SeriesGroupingService.seasonNumber(inTitle: "Show Season 3") == 3)
        #expect(SeriesGroupingService.seasonNumber(inTitle: "Show: Final Season") == nil)
        #expect(SeriesGroupingService.seasonNumber(inTitle: "Show") == nil)
    }
}

struct LocalLibraryRepositoryTests {
    @Test func addUpdateAndRemoveEntries() async throws {
        let repository = LocalLibraryRepository(persistence: InMemoryLibraryPersistence())
        let anime = SampleCatalog.anime[0]

        let first = try await repository.update(anime: anime, status: .watching, progress: 3)
        #expect(first.animeID == anime.id)
        #expect(first.status == .watching)
        #expect(first.progress == 3)

        _ = try await repository.update(anime: anime, status: .completed, progress: nil)
        let updated = try await repository.entry(animeID: anime.id)
        #expect(updated?.status == .completed)
        #expect(updated?.progress == 3)

        let all = try await repository.entries()
        #expect(all.count == 1)

        try await repository.remove(animeID: anime.id)
        let removed = try await repository.entry(animeID: anime.id)
        let empty = try await repository.entries()
        #expect(removed == nil)
        #expect(empty.isEmpty)
    }

    @Test func addToWatchingCreatesRefreshesAndPromotesEntries() async throws {
        let repository = LocalLibraryRepository(persistence: InMemoryLibraryPersistence())
        let anime = SampleCatalog.anime[0]

        try await repository.addToWatching(anime: anime, progress: 4)
        var entry = try await repository.entry(animeID: anime.id)
        #expect(entry?.status == .watching)
        #expect(entry?.progress == 4)

        _ = try await repository.update(anime: anime, status: .planToWatch, progress: 8)
        try await repository.addToWatching(anime: anime, progress: 5)
        entry = try await repository.entry(animeID: anime.id)
        #expect(entry?.status == .watching)
        #expect(entry?.progress == 5)

        try await repository.addToWatching(anime: anime, progress: nil)
        entry = try await repository.entry(animeID: anime.id)
        #expect(entry?.status == .watching)
        #expect(entry?.progress == 5)
    }

    @Test func addToWatchingPreservesExplicitStatuses() async throws {
        let repository = LocalLibraryRepository(persistence: InMemoryLibraryPersistence())
        let statuses: [LibraryStatus] = [.completed, .favorites, .onHold, .dropped]

        for (index, status) in statuses.enumerated() {
            let anime = SampleCatalog.anime[index]
            _ = try await repository.update(anime: anime, status: status, progress: 12)

            try await repository.addToWatching(anime: anime, progress: 2)

            let entry = try await repository.entry(animeID: anime.id)
            #expect(entry?.status == status)
            #expect(entry?.progress == 12)
        }
    }

    @Test func entriesSortByMostRecentlyUpdated() async throws {
        let older = LibraryEntry(
            animeID: SampleCatalog.anime[0].id,
            status: .watching,
            progress: 0,
            updatedAt: Date().addingTimeInterval(-100),
            anime: SampleCatalog.anime[0]
        )
        let newer = LibraryEntry(
            animeID: SampleCatalog.anime[1].id,
            status: .watching,
            progress: 0,
            updatedAt: Date(),
            anime: SampleCatalog.anime[1]
        )
        let repository = LocalLibraryRepository(
            persistence: InMemoryLibraryPersistence(entries: [older, newer])
        )

        let entries = try await repository.entries()
        #expect(entries.first?.animeID == SampleCatalog.anime[1].id)
    }

    @Test func persistenceRoundTripsAcrossInstances() async throws {
        let suite = "library-test-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let persistence = UserDefaultsLibraryPersistence(suiteName: suite)
        let first = LocalLibraryRepository(persistence: persistence)
        _ = try await first.update(anime: SampleCatalog.anime[0], status: .favorites, progress: 5)

        let second = LocalLibraryRepository(
            persistence: UserDefaultsLibraryPersistence(suiteName: suite)
        )
        let entry = try await second.entry(animeID: SampleCatalog.anime[0].id)
        #expect(entry?.status == .favorites)
        #expect(entry?.progress == 5)
        #expect(entry?.anime.displayTitle == SampleCatalog.anime[0].displayTitle)
    }
}
