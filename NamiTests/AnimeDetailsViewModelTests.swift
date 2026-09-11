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
}
