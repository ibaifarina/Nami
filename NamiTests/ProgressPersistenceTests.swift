import Foundation
import Testing
@testable import Nami

struct SwiftDataPlaybackProgressStoreTests {
    @Test func roundTripSaveUpdateAndQueries() async throws {
        let container = try #require(SwiftDataStack.makeContainer(inMemory: true))
        let store = SwiftDataPlaybackProgressStore(modelContainer: container)

        let first = PlaybackProgress(
            animeID: "46474",
            episodeID: "46474-2",
            episodeNumber: 2,
            positionSeconds: 100,
            durationSeconds: 1400,
            updatedAt: Date().addingTimeInterval(-60),
            animeTitle: "Frieren",
            posterURL: URL(string: "https://media.kitsu.app/poster.jpg"),
            bannerURL: nil,
            episodeCount: 28
        )
        let second = PlaybackProgress(
            animeID: "7442",
            episodeNumber: 1,
            positionSeconds: 500,
            durationSeconds: 1400,
            updatedAt: Date()
        )
        await store.save(first)
        await store.save(second)

        let all = await store.allProgress(limit: 10)
        #expect(all.count == 2)
        #expect(all.first?.animeID == "7442")

        var updated = first
        updated.positionSeconds = 1200
        updated.isCompleted = true
        updated.updatedAt = Date()
        await store.save(updated)

        let loaded = await store.progress(animeID: "46474", episodeNumber: 2)
        #expect(loaded?.positionSeconds == 1200)
        #expect(loaded?.isCompleted == true)
        #expect(loaded?.episodeID == "46474-2")
        #expect(loaded?.animeTitle == "Frieren")
        #expect(loaded?.posterURL?.absoluteString == "https://media.kitsu.app/poster.jpg")
        #expect(loaded?.episodeCount == 28)

        let latest = await store.latestProgress(animeID: "46474")
        #expect(latest?.episodeNumber == 2)
        #expect(latest?.isCompleted == true)

        let limited = await store.allProgress(limit: 1)
        #expect(limited.count == 1)
    }

    @Test func progressForUnknownEpisodeIsNil() async throws {
        let container = try #require(SwiftDataStack.makeContainer(inMemory: true))
        let store = SwiftDataPlaybackProgressStore(modelContainer: container)

        #expect(await store.progress(animeID: "99", episodeNumber: 1) == nil)
        #expect(await store.latestProgress(animeID: "99") == nil)
    }

    @Test func historyIsScopedToAnimeAndRemovable() async throws {
        let container = try #require(SwiftDataStack.makeContainer(inMemory: true))
        let store = SwiftDataPlaybackProgressStore(modelContainer: container)

        await store.save(
            PlaybackProgress(
                animeID: "46474",
                episodeNumber: 1,
                positionSeconds: 100,
                durationSeconds: 1400,
                updatedAt: Date().addingTimeInterval(-120)
            )
        )
        await store.save(
            PlaybackProgress(
                animeID: "46474",
                episodeNumber: 2,
                positionSeconds: 200,
                durationSeconds: 1400,
                updatedAt: Date()
            )
        )
        await store.save(
            PlaybackProgress(
                animeID: "41370",
                episodeNumber: 1,
                positionSeconds: 300,
                durationSeconds: 1400,
                updatedAt: Date()
            )
        )

        let history = await store.progress(forAnimeID: "46474")
        #expect(history.map(\.episodeNumber) == [2, 1])

        await store.remove(animeID: "46474", episodeNumber: 2)
        #expect(await store.progress(animeID: "46474", episodeNumber: 2) == nil)
        #expect(await store.latestProgress(animeID: "46474")?.episodeNumber == 1)
        #expect(await store.allProgress(limit: 10).count == 2)
    }
}

@MainActor
struct HomeViewModelTests {
    @Test func continueWatchingExcludesCompletedEpisodes() async {
        let progressStore = InMemoryPlaybackProgressStore(items: [
            PlaybackProgress(
                animeID: "46474",
                episodeNumber: 7,
                positionSeconds: 100,
                durationSeconds: 1400,
                updatedAt: Date()
            ),
            PlaybackProgress(
                animeID: "41370",
                episodeNumber: 3,
                positionSeconds: 1300,
                durationSeconds: 1400,
                isCompleted: true,
                updatedAt: Date()
            ),
        ])
        let model = HomeViewModel(
            media: StubMediaRepository(),
            progressStore: progressStore
        )

        await model.load()

        #expect(model.continueWatching.count == 1)
        #expect(model.continueWatching.first?.anime.id == "46474")
        #expect(model.continueWatching.first?.progress.episodeNumber == 7)
    }

    @Test func continueWatchingIsEmptyWhenEverythingCompleted() async {
        let progressStore = InMemoryPlaybackProgressStore(items: [
            PlaybackProgress(
                animeID: "46474",
                episodeNumber: 28,
                positionSeconds: 1400,
                durationSeconds: 1400,
                isCompleted: true,
                updatedAt: Date()
            ),
        ])
        let model = HomeViewModel(
            media: StubMediaRepository(),
            progressStore: progressStore
        )

        await model.load()

        #expect(model.continueWatching.isEmpty)
    }

    @Test func continueWatchingKeepsLatestEpisodePerShow() async {
        let now = Date()
        let progressStore = InMemoryPlaybackProgressStore(items: [
            PlaybackProgress(
                animeID: "46474",
                episodeNumber: 1,
                positionSeconds: 300,
                durationSeconds: 1400,
                updatedAt: now.addingTimeInterval(-600)
            ),
            PlaybackProgress(
                animeID: "46474",
                episodeNumber: 2,
                positionSeconds: 200,
                durationSeconds: 1400,
                updatedAt: now.addingTimeInterval(-300)
            ),
            PlaybackProgress(
                animeID: "41370",
                episodeNumber: 3,
                positionSeconds: 100,
                durationSeconds: 1400,
                updatedAt: now.addingTimeInterval(-100)
            ),
        ])
        let model = HomeViewModel(
            media: StubMediaRepository(),
            progressStore: progressStore
        )

        await model.load()

        #expect(model.continueWatching.count == 2)
        let frieren = model.continueWatching.first { $0.anime.id == "46474" }
        #expect(frieren?.progress.episodeNumber == 2)
        #expect(model.continueWatching.first { $0.anime.id == "46474" }?.id == "46474-2")
    }

    @Test func continueWatchingFallsBackToSnapshotWhenMediaUnavailable() async {
        let progressStore = InMemoryPlaybackProgressStore(items: [
            PlaybackProgress(
                animeID: "unknown-anime",
                episodeNumber: 4,
                positionSeconds: 200,
                durationSeconds: 1400,
                updatedAt: Date(),
                animeTitle: "Offline Show",
                posterURL: URL(string: "https://media.kitsu.app/offline.jpg")
            ),
        ])
        let model = HomeViewModel(
            media: StubMediaRepository(),
            progressStore: progressStore
        )

        await model.load()

        #expect(model.continueWatching.count == 1)
        #expect(model.continueWatching.first?.anime.displayTitle == "Offline Show")
    }

    @Test func refreshContinueWatchingPicksUpProgressSavedAfterLoad() async {
        let progressStore = InMemoryPlaybackProgressStore()
        let model = HomeViewModel(
            media: StubMediaRepository(),
            progressStore: progressStore
        )

        await model.load()
        #expect(model.continueWatching.isEmpty)

        await progressStore.save(
            PlaybackProgress(
                animeID: "46474",
                episodeNumber: 3,
                positionSeconds: 420,
                durationSeconds: 1400,
                updatedAt: Date(),
                animeTitle: "Frieren"
            )
        )
        await model.refreshContinueWatching()

        #expect(model.continueWatching.count == 1)
        #expect(model.continueWatching.first?.anime.id == "46474")
        #expect(model.continueWatching.first?.progress.episodeNumber == 3)
    }
}
