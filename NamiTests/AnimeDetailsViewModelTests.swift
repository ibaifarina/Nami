import Foundation
import Testing
@testable import Nami

@MainActor
struct AnimeDetailsViewModelTests {
    private func makeModel(
        progressStore: InMemoryPlaybackProgressStore = InMemoryPlaybackProgressStore()
    ) -> AnimeDetailsViewModel {
        AnimeDetailsViewModel(
            animeID: "46474",
            media: StubMediaRepository(),
            episodeRepository: StubEpisodeRepository(
                episodesByAnimeID: [
                    "46474": SampleCatalog.episodes(forAnimeID: "46474", count: 3),
                ]
            ),
            progressStore: progressStore,
            library: StubLibraryRepository()
        )
    }

    @Test func loadsWatchedEpisodesFromProgressHistory() async {
        let store = InMemoryPlaybackProgressStore(items: [
            PlaybackProgress(
                animeID: "46474",
                episodeNumber: 1,
                positionSeconds: 0,
                durationSeconds: 0,
                isCompleted: true,
                updatedAt: Date().addingTimeInterval(-300)
            ),
            PlaybackProgress(
                animeID: "46474",
                episodeNumber: 2,
                positionSeconds: 100,
                durationSeconds: 1400,
                updatedAt: Date()
            ),
        ])
        let model = makeModel(progressStore: store)

        await model.load()

        #expect(model.watchedEpisodeNumbers == [1])
        #expect(model.progress?.episodeNumber == 2)
        #expect(model.isWatched(model.episodes[0]))
        #expect(!model.isWatched(model.episodes[1]))
    }

    @Test func togglingEpisodeWatchedMarksAndClearsProgress() async throws {
        let store = InMemoryPlaybackProgressStore()
        let model = makeModel(progressStore: store)

        await model.load()
        let episode = try #require(model.episodes.first)

        #expect(!model.isWatched(episode))

        await model.toggleEpisodeWatched(episode)
        #expect(model.isWatched(episode))
        #expect(await store.progress(animeID: "46474", episodeNumber: 1)?.isCompleted == true)

        await model.toggleEpisodeWatched(episode)
        #expect(!model.isWatched(episode))
        #expect(await store.progress(animeID: "46474", episodeNumber: 1) == nil)
    }

    @Test func markingOldEpisodeWatchedKeepsInProgressResumeTarget() async throws {
        let store = InMemoryPlaybackProgressStore(items: [
            PlaybackProgress(
                animeID: "46474",
                episodeNumber: 3,
                positionSeconds: 400,
                durationSeconds: 1400,
                updatedAt: Date()
            ),
        ])
        let model = makeModel(progressStore: store)

        await model.load()
        let episodeOne = try #require(model.episodes.first)

        await model.markEpisodeWatched(episodeOne)

        #expect(model.isWatched(episodeOne))
        #expect(model.progress?.episodeNumber == 3)
    }

    @Test func markingInProgressEpisodeUnwatchedClearsResumeTarget() async throws {
        let store = InMemoryPlaybackProgressStore(items: [
            PlaybackProgress(
                animeID: "46474",
                episodeNumber: 1,
                positionSeconds: 400,
                durationSeconds: 1400,
                updatedAt: Date()
            ),
        ])
        let model = makeModel(progressStore: store)

        await model.load()
        let episodeOne = try #require(model.episodes.first)
        #expect(model.progress?.episodeNumber == 1)

        await model.markEpisodeUnwatched(episodeOne)

        #expect(model.progress == nil)
    }

    @Test func movieInsideSequentialChainIsNotReplacedBySeasons() async {
        let movie = SampleCatalog.make(
            id: "48323", title: "Chainsaw Man: Reze-hen",
            subtype: .movie, status: .finished, year: 2025, episodes: 1, duration: 100
        )
        let season1 = SampleCatalog.make(
            id: "43806", title: "Chainsaw Man",
            subtype: .tv, status: .finished, year: 2022, episodes: 12, duration: 24
        )
        let season2 = SampleCatalog.make(
            id: "50406", title: "Chainsaw Man: Shikaku-hen",
            subtype: .tv, status: .tba, year: 2026, episodes: nil, duration: 24
        )

        var media = StubMediaRepository()
        media.details = [
            movie.id: AnimeDetails(anime: movie, relations: [
                AnimeRelation(role: .prequel, anime: season1),
                AnimeRelation(role: .sequel, anime: season2),
            ]),
            season1.id: AnimeDetails(anime: season1, relations: [
                AnimeRelation(role: .sequel, anime: movie),
            ]),
            season2.id: AnimeDetails(anime: season2, relations: [
                AnimeRelation(role: .prequel, anime: movie),
            ]),
        ]

        let model = AnimeDetailsViewModel(
            animeID: movie.id,
            media: media,
            episodeRepository: StubEpisodeRepository(
                episodesByAnimeID: [movie.id: SampleCatalog.episodes(forAnimeID: movie.id, count: 1)]
            ),
            progressStore: InMemoryPlaybackProgressStore(),
            library: StubLibraryRepository()
        )

        await model.load()

        #expect(model.selectedAnime?.id == movie.id)
        #expect(model.isMovie)
        #expect(model.availableInstallments.map(\.anime.id) == [movie.id])
        #expect(model.related.map(\.anime.id).contains(season1.id))
        #expect(model.related.map(\.anime.id).contains(season2.id))
    }

    @Test func currentEpisodeAdvancesPastWatchedEpisodes() async {
        let store = InMemoryPlaybackProgressStore(items: [
            PlaybackProgress(
                animeID: "46474",
                episodeNumber: 1,
                positionSeconds: 0,
                durationSeconds: 0,
                isCompleted: true,
                updatedAt: Date().addingTimeInterval(-60)
            ),
            PlaybackProgress(
                animeID: "46474",
                episodeNumber: 2,
                positionSeconds: 0,
                durationSeconds: 0,
                isCompleted: true,
                updatedAt: Date()
            ),
        ])
        let model = makeModel(progressStore: store)

        await model.load()

        #expect(model.currentEpisode?.displayNumber == 3)
        #expect(model.primaryEpisode?.displayNumber == 3)
        #expect(model.primaryActionTitle == "Play Episode 3")
    }

    @Test func refreshLocalContextPicksUpCompletedPlayback() async throws {
        let store = InMemoryPlaybackProgressStore()
        let model = makeModel(progressStore: store)

        await model.load()
        let episodeOne = try #require(model.episodes.first)
        #expect(!model.isWatched(episodeOne))
        #expect(!model.hasWatchHistory)
        #expect(model.currentEpisode?.displayNumber == 1)

        await store.save(
            PlaybackProgress(
                animeID: "46474",
                episodeID: episodeOne.id,
                episodeNumber: episodeOne.displayNumber,
                positionSeconds: 0,
                durationSeconds: 1400,
                isCompleted: true,
                updatedAt: Date()
            )
        )

        await model.refreshLocalContext()

        #expect(model.isWatched(episodeOne))
        #expect(model.hasWatchHistory)
        #expect(model.currentEpisode?.displayNumber == 2)
    }
}
