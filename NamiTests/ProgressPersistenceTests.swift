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
            progressStore: progressStore,
            episodes: StubEpisodeRepository()
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
            progressStore: progressStore,
            episodes: StubEpisodeRepository()
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
            progressStore: progressStore,
            episodes: StubEpisodeRepository()
        )

        await model.load()

        #expect(model.continueWatching.count == 2)
        let frieren = model.continueWatching.first { $0.anime.id == "46474" }
        #expect(frieren?.progress.episodeNumber == 2)
        #expect(model.continueWatching.first { $0.anime.id == "46474" }?.id == "46474-2")
    }

    @Test func continueWatchingCollapsesSeasonsOfOneSeries() async throws {
        let season1 = try #require(SampleCatalog.anime(withID: "7442"))
        let season2 = try #require(SampleCatalog.anime(withID: "8671"))
        var media = StubMediaRepository()
        media.details = [
            season1.id: AnimeDetails(
                anime: season1,
                relations: [AnimeRelation(role: .sequel, anime: season2)]
            ),
            season2.id: AnimeDetails(
                anime: season2,
                relations: [AnimeRelation(role: .prequel, anime: season1)]
            ),
        ]
        let now = Date()
        let progressStore = InMemoryPlaybackProgressStore(items: [
            PlaybackProgress(
                animeID: season1.id,
                episodeNumber: 5,
                positionSeconds: 300,
                durationSeconds: 1400,
                updatedAt: now.addingTimeInterval(-600)
            ),
            PlaybackProgress(
                animeID: season2.id,
                episodeNumber: 1,
                positionSeconds: 120,
                durationSeconds: 1400,
                updatedAt: now
            ),
        ])
        let model = HomeViewModel(
            media: media,
            progressStore: progressStore,
            episodes: StubEpisodeRepository()
        )

        await model.load()

        #expect(model.continueWatching.count == 1)
        #expect(model.continueWatching.first?.anime.id == season2.id)
        #expect(model.continueWatching.first?.progress.episodeNumber == 1)
    }

    @Test func removeFromContinueWatchingClearsEverySeasonOfTheSeries() async throws {
        let season1 = try #require(SampleCatalog.anime(withID: "7442"))
        let season2 = try #require(SampleCatalog.anime(withID: "8671"))
        var media = StubMediaRepository()
        media.details = [
            season1.id: AnimeDetails(
                anime: season1,
                relations: [AnimeRelation(role: .sequel, anime: season2)]
            ),
            season2.id: AnimeDetails(
                anime: season2,
                relations: [AnimeRelation(role: .prequel, anime: season1)]
            ),
        ]
        let now = Date()
        let progressStore = InMemoryPlaybackProgressStore(items: [
            PlaybackProgress(
                animeID: season1.id,
                episodeNumber: 5,
                positionSeconds: 300,
                durationSeconds: 1400,
                updatedAt: now.addingTimeInterval(-600)
            ),
            PlaybackProgress(
                animeID: season2.id,
                episodeNumber: 1,
                positionSeconds: 120,
                durationSeconds: 1400,
                updatedAt: now
            ),
        ])
        let model = HomeViewModel(
            media: media,
            progressStore: progressStore,
            episodes: StubEpisodeRepository()
        )
        await model.load()
        let entry = try #require(model.continueWatching.first)

        await model.removeFromContinueWatching(entry)

        #expect(model.continueWatching.isEmpty)
        #expect(await progressStore.progress(forAnimeID: season1.id).isEmpty)
        #expect(await progressStore.progress(forAnimeID: season2.id).isEmpty)
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
            progressStore: progressStore,
            episodes: StubEpisodeRepository()
        )

        await model.load()

        #expect(model.continueWatching.count == 1)
        #expect(model.continueWatching.first?.anime.displayTitle == "Offline Show")
    }

    @Test func refreshContinueWatchingPicksUpProgressSavedAfterLoad() async {
        let progressStore = InMemoryPlaybackProgressStore()
        let model = HomeViewModel(
            media: StubMediaRepository(),
            progressStore: progressStore,
            episodes: StubEpisodeRepository()
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

    @Test func continueWatchingKeepsResolvedCardsDuringRefresh() async throws {
        var media = StubMediaRepository()
        media.requestDelay = .milliseconds(150)
        let episodes = StubEpisodeRepository(episodesByAnimeID: [
            "46474": [
                Episode(
                    id: "46474-5",
                    animeID: "46474",
                    number: 5,
                    relativeNumber: 5,
                    title: "The Journey Begins"
                ),
            ],
        ])
        let progressStore = InMemoryPlaybackProgressStore(items: [
            PlaybackProgress(
                animeID: "46474",
                episodeNumber: 5,
                positionSeconds: 100,
                durationSeconds: 1400,
                updatedAt: Date(),
                animeTitle: "Frieren"
            ),
        ])
        let model = HomeViewModel(
            media: media,
            progressStore: progressStore,
            episodes: episodes
        )
        await model.load()
        #expect(model.continueWatching.first?.episode?.title == "The Journey Begins")

        await progressStore.save(
            PlaybackProgress(
                animeID: "41370",
                episodeNumber: 3,
                positionSeconds: 200,
                durationSeconds: 1400,
                updatedAt: Date(),
                animeTitle: "Demon Slayer"
            )
        )
        let refresh = Task { await model.refreshContinueWatching() }
        try await Task.sleep(for: .milliseconds(50))
        // Mid-refresh the resolved Frieren card stays put. Snapshot
        // placeholders would have dropped its episode title.
        #expect(model.continueWatching.count == 1)
        #expect(model.continueWatching.first?.episode?.title == "The Journey Begins")

        await refresh.value
        #expect(model.continueWatching.count == 2)
    }

    @Test func continueWatchingResolvesShowsConcurrently() async {
        let tracker = MediaRequestTracker()
        var media = StubMediaRepository()
        media.requestDelay = .milliseconds(80)
        media.requestTracker = tracker
        let now = Date()
        let progressStore = InMemoryPlaybackProgressStore(
            items: ["46474", "7442", "41370", "12"].enumerated().map { offset, animeID in
                PlaybackProgress(
                    animeID: animeID,
                    episodeNumber: 1,
                    positionSeconds: 100,
                    durationSeconds: 1400,
                    updatedAt: now.addingTimeInterval(TimeInterval(-offset)),
                    animeTitle: "Show \(animeID)"
                )
            }
        )
        let model = HomeViewModel(
            media: media,
            progressStore: progressStore,
            episodes: StubEpisodeRepository()
        )

        await model.load()

        #expect(model.continueWatching.count == 4)
        #expect(await tracker.maxInFlight > 1)
    }

    @Test func continueWatchingCarriesEpisodeTitleAndSeason() async throws {
        let season1 = try #require(SampleCatalog.anime(withID: "7442"))
        let season2 = try #require(SampleCatalog.anime(withID: "8671"))
        var media = StubMediaRepository()
        media.details = [
            season1.id: AnimeDetails(
                anime: season1,
                relations: [AnimeRelation(role: .sequel, anime: season2)]
            ),
            season2.id: AnimeDetails(
                anime: season2,
                relations: [AnimeRelation(role: .prequel, anime: season1)]
            ),
        ]
        var episodes = StubEpisodeRepository()
        episodes.episodesByAnimeID = [
            season2.id: [
                Episode(
                    id: "\(season2.id)-4",
                    animeID: season2.id,
                    number: 4,
                    relativeNumber: 4,
                    title: "The Hero's Resolve"
                ),
            ],
        ]
        let progressStore = InMemoryPlaybackProgressStore(items: [
            PlaybackProgress(
                animeID: season2.id,
                episodeNumber: 4,
                positionSeconds: 1_038,
                durationSeconds: 1_440,
                updatedAt: Date()
            ),
        ])
        let model = HomeViewModel(
            media: media,
            progressStore: progressStore,
            episodes: episodes
        )

        await model.load()

        let entry = try #require(model.continueWatching.first)
        #expect(entry.anime.id == season2.id)
        #expect(entry.seasonNumber == 2)
        #expect(entry.episode?.title == "The Hero's Resolve")
    }
}
