import AppKit
import Foundation
import Testing
@testable import Nami

@MainActor
private final class MockPlayerEngine: PlayerEngine {
    var onStateChange: ((PlayerEngineState) -> Void)?
    var onTimeChange: ((Double, Double) -> Void)?
    var onTracksChange: (() -> Void)?

    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 600
    var volume: Double = 1
    var rate: Double = 1

    var loadError: PlayerError?
    private(set) var loadedURLs: [URL] = []
    private(set) var didStop = false
    private(set) var seekRequests: [Double] = []
    private(set) var selectedAudio: [String] = []
    private(set) var selectedSubtitles: [String?] = []
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    var audioTrackList: [MediaTrack] = []
    var subtitleTrackList: [MediaTrack] = []

    func load(_ stream: ResolvedStream) async throws {
        onStateChange?(.loading)
        if let loadError {
            onStateChange?(.failed(loadError.userMessage))
            throw loadError
        }
        loadedURLs.append(stream.url)
        onStateChange?(.ready)
        onTracksChange?()
    }

    func play() {
        isPlaying = true
        playCount += 1
        onStateChange?(.playing)
    }

    func pause() {
        isPlaying = false
        pauseCount += 1
        onStateChange?(.paused)
    }

    func stop() {
        isPlaying = false
        didStop = true
        onStateChange?(.idle)
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        seekRequests.append(seconds)
        onTimeChange?(seconds, duration)
    }

    func setVolume(_ volume: Double) {
        self.volume = volume
    }

    func setRate(_ rate: Double) {
        self.rate = rate
    }

    func audioTracks() -> [MediaTrack] { audioTrackList }
    func subtitleTracks() -> [MediaTrack] { subtitleTrackList }
    func selectAudioTrack(_ track: MediaTrack) { selectedAudio.append(track.id) }
    func selectSubtitleTrack(_ track: MediaTrack?) { selectedSubtitles.append(track?.id) }
    func makeVideoSurface() -> NSView { NSView() }
    func updateVideoSurface(_ view: NSView) {}

    func emitTime(_ time: Double) {
        currentTime = time
        onTimeChange?(time, duration)
    }

    func emitEnded() {
        isPlaying = false
        onStateChange?(.ended)
    }
}

@MainActor
private final class MockExternalPlayerOpener: ExternalPlayerOpening {
    var players: [ExternalPlayer] = []
    var openError: ExternalPlayerError?
    private(set) var openedURLs: [URL] = []
    private(set) var openedBundleIDs: [String] = []

    func detectedPlayers() -> [ExternalPlayer] { players }

    func open(_ url: URL, in player: ExternalPlayer) async throws {
        if let openError { throw openError }
        openedURLs.append(url)
        openedBundleIDs.append(player.bundleID)
    }
}

@MainActor
struct PlaybackCoordinatorTests {
    private struct Setup {
        let coordinator: PlaybackCoordinator
        let engine: MockPlayerEngine
        let store: InMemoryPlaybackProgressStore
        let library: StubLibraryRepository
        let preferences: PreferencesStore
        let defaults: UserDefaults
        let suiteName: String
    }

    private func makeSetup(
        audio: AudioPreference = .japanese,
        subtitles: SubtitlePreference = .english,
        externalPlayers: (any ExternalPlayerOpening)? = nil,
        library: StubLibraryRepository? = nil
    ) throws -> Setup {
        let suiteName = "playback-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let preferences = PreferencesStore(defaults: defaults)
        preferences.preferredAudio = audio
        preferences.preferredSubtitles = subtitles
        let store = InMemoryPlaybackProgressStore()
        let library = library ?? StubLibraryRepository()
        let engine = MockPlayerEngine()
        let coordinator = PlaybackCoordinator(
            engine: engine,
            progressStore: store,
            preferences: preferences,
            library: library,
            externalPlayers: externalPlayers ?? ExternalPlayerService()
        )
        return Setup(
            coordinator: coordinator,
            engine: engine,
            store: store,
            library: library,
            preferences: preferences,
            defaults: defaults,
            suiteName: suiteName
        )
    }

    private let stream = ResolvedStream(
        url: testURL("https://cdn.example/video.mp4"),
        filename: "video.mp4",
        sizeBytes: 1_400_000_000,
        streamable: true,
        fileID: 2
    )

    private var anime: Anime { SampleCatalog.anime[0] }

    private func episode(_ number: Int) -> Episode {
        Episode(
            id: "\(anime.id)-\(number)",
            animeID: anime.id,
            number: number,
            relativeNumber: number,
            seasonNumber: 1,
            durationMinutes: anime.durationMinutes
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () async -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func startLoadsStreamAndPlays() async throws {
        let setup = try makeSetup()

        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: nil)

        await waitUntil { setup.coordinator.state == .playing }

        #expect(setup.coordinator.isPresenting)
        #expect(setup.engine.loadedURLs == [stream.url])
        #expect(setup.engine.playCount >= 1)
        #expect(setup.coordinator.episodeLabel == "Episode 7")
        #expect(setup.coordinator.title == anime.displayTitle)
    }

    @Test func resumeSeeksToSavedPosition() async throws {
        let setup = try makeSetup()

        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: 300)
        await waitUntil { setup.coordinator.state == .playing }

        #expect(setup.engine.seekRequests.contains(300))
        #expect(setup.coordinator.currentTime == 300)
    }

    @Test func shortStartPositionIsIgnored() async throws {
        let setup = try makeSetup()

        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: 3)
        await waitUntil { setup.coordinator.state == .playing }

        #expect(setup.engine.seekRequests.isEmpty)
    }

    @Test func pauseWritesProgress() async throws {
        let setup = try makeSetup()
        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: nil)
        await waitUntil { setup.coordinator.state == .playing }

        setup.engine.emitTime(120)
        setup.coordinator.togglePlayPause()

        await waitUntil { await setup.store.progress(animeID: anime.id, episodeNumber: 7) != nil }
        let saved = await setup.store.progress(animeID: anime.id, episodeNumber: 7)
        #expect(saved?.positionSeconds == 120)
        #expect(setup.coordinator.state == .paused)
    }

    @Test func seekWritesProgressImmediately() async throws {
        let setup = try makeSetup()
        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: nil)
        await waitUntil { setup.coordinator.state == .playing }

        setup.coordinator.seek(to: 200)

        await waitUntil { await setup.store.progress(animeID: anime.id, episodeNumber: 7) != nil }
        let saved = await setup.store.progress(animeID: anime.id, episodeNumber: 7)
        #expect(saved?.positionSeconds == 200)
    }

    @Test func closeStopsEngineHidesAndWritesProgress() async throws {
        let setup = try makeSetup()
        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: nil)
        await waitUntil { setup.coordinator.state == .playing }
        setup.engine.emitTime(90)

        setup.coordinator.close()

        #expect(!setup.coordinator.isPresenting)
        #expect(setup.coordinator.state == .idle)
        #expect(setup.engine.didStop)
        await waitUntil { await setup.store.progress(animeID: anime.id, episodeNumber: 7) != nil }
        let saved = await setup.store.progress(animeID: anime.id, episodeNumber: 7)
        #expect(saved?.positionSeconds == 90)
    }

    @Test func endedMarksStateAndWritesProgress() async throws {
        let setup = try makeSetup()
        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: nil)
        await waitUntil { setup.coordinator.state == .playing }
        setup.engine.emitTime(590)

        setup.engine.emitEnded()

        #expect(setup.coordinator.state == .ended)
        await waitUntil { await setup.store.progress(animeID: anime.id, episodeNumber: 7) != nil }
        let saved = await setup.store.progress(animeID: anime.id, episodeNumber: 7)
        #expect(saved?.positionSeconds == 590)
    }

    @Test func preferredTracksAreAutoSelected() async throws {
        let setup = try makeSetup(audio: .japanese, subtitles: .english)
        setup.engine.audioTrackList = [
            MediaTrack(id: "audio-0", kind: .audio, title: "Japanese", language: "ja"),
            MediaTrack(id: "audio-1", kind: .audio, title: "English", language: "en"),
        ]
        setup.engine.subtitleTrackList = [
            MediaTrack(id: "subtitle-0", kind: .subtitle, title: "English", language: "en"),
            MediaTrack(id: "subtitle-1", kind: .subtitle, title: "Spanish", language: "es"),
        ]

        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: nil)
        await waitUntil { setup.coordinator.selectedAudioTrackID != nil }

        #expect(setup.coordinator.selectedAudioTrackID == "audio-0")
        #expect(setup.coordinator.selectedSubtitleTrackID == "subtitle-0")
        #expect(setup.engine.selectedAudio == ["audio-0"])
        #expect(setup.engine.selectedSubtitles == ["subtitle-0"])
    }

    @Test func manualTrackSelectionOverridesPreference() async throws {
        let setup = try makeSetup(audio: .japanese)
        setup.engine.audioTrackList = [
            MediaTrack(id: "audio-0", kind: .audio, title: "Japanese", language: "ja"),
            MediaTrack(id: "audio-1", kind: .audio, title: "English", language: "en"),
        ]
        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: nil)
        await waitUntil { setup.coordinator.selectedAudioTrackID == "audio-0" }

        setup.coordinator.selectAudioTrack(setup.engine.audioTrackList[1])

        #expect(setup.coordinator.selectedAudioTrackID == "audio-1")
        #expect(setup.engine.selectedAudio == ["audio-0", "audio-1"])
    }

    @Test func loadFailureSetsFailedStateAndRetryRecovers() async throws {
        let setup = try makeSetup()
        setup.engine.loadError = .failedToLoad("MKV is not supported by the system player")

        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: nil)
        await waitUntil {
            if case .failed = setup.coordinator.state { return true }
            return false
        }

        if case .failed(let message) = setup.coordinator.state {
            #expect(message.contains("MKV"))
        } else {
            Issue.record("Expected failed state")
        }
        #expect(setup.coordinator.isPresenting)

        setup.coordinator.seek(to: 100)
        setup.engine.loadError = nil
        setup.coordinator.retry()
        await waitUntil { setup.coordinator.state == .playing }

        #expect(setup.engine.loadedURLs.count == 1)
        #expect(setup.engine.seekRequests.contains(100))
    }

    @Test func muteAndVolumeControl() async throws {
        let setup = try makeSetup()

        setup.coordinator.toggleMute()
        #expect(setup.coordinator.isMuted)
        #expect(setup.engine.volume == 0)

        setup.coordinator.toggleMute()
        #expect(!setup.coordinator.isMuted)
        #expect(setup.engine.volume > 0)

        setup.coordinator.setVolume(0.4)
        #expect(setup.coordinator.volume == 0.4)
        #expect(abs(setup.engine.volume - 0.4) < 0.001)
    }

    @Test func speedIsClampedAndApplied() async throws {
        let setup = try makeSetup()

        setup.coordinator.setRate(5)
        #expect(setup.coordinator.rate == 2)
        #expect(setup.engine.rate == 2)

        setup.coordinator.setRate(0.1)
        #expect(setup.coordinator.rate == 0.5)
    }

    @Test func completionMarksProgressCompletedOnce() async throws {
        let setup = try makeSetup()
        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: nil)
        await waitUntil { setup.coordinator.state == .playing }

        setup.engine.emitTime(590)
        await waitUntil {
            await setup.store.progress(animeID: anime.id, episodeNumber: 7)?.isCompleted == true
        }

        setup.engine.emitTime(595)

        let saved = await setup.store.progress(animeID: anime.id, episodeNumber: 7)
        #expect(saved?.isCompleted == true)
        #expect(saved?.episodeID == "\(anime.id)-7")
        #expect(saved?.animeTitle == anime.displayTitle)
    }

    @Test func completionSeedsNextEpisodeForContinueWatching() async throws {
        let setup = try makeSetup()
        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: nil)
        await waitUntil { setup.coordinator.state == .playing }

        setup.engine.emitTime(590)

        await waitUntil { await setup.store.progress(animeID: anime.id, episodeNumber: 8) != nil }
        let next = await setup.store.progress(animeID: anime.id, episodeNumber: 8)
        #expect(next?.isCompleted == false)
        #expect(next?.positionSeconds == 0)
        #expect(next?.episodeID == "\(anime.id)-8")
    }

    @Test func completionSkipsSeedOnFinalEpisode() async throws {
        let setup = try makeSetup()
        setup.coordinator.start(stream: stream, anime: anime, episode: episode(28), startAt: nil)
        await waitUntil { setup.coordinator.state == .playing }

        setup.engine.emitTime(590)

        await waitUntil {
            await setup.store.progress(animeID: anime.id, episodeNumber: 28)?.isCompleted == true
        }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await setup.store.progress(animeID: anime.id, episodeNumber: 29) == nil)
    }

    @Test func completionKeepsExistingNextEpisodeProgress() async throws {
        let setup = try makeSetup()
        await setup.store.save(
            PlaybackProgress(
                animeID: anime.id,
                episodeNumber: 8,
                positionSeconds: 300,
                durationSeconds: 600,
                updatedAt: Date().addingTimeInterval(-60)
            )
        )
        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: nil)
        await waitUntil { setup.coordinator.state == .playing }

        setup.engine.emitTime(590)

        await waitUntil {
            await setup.store.progress(animeID: anime.id, episodeNumber: 7)?.isCompleted == true
        }
        try? await Task.sleep(for: .milliseconds(50))
        let next = await setup.store.progress(animeID: anime.id, episodeNumber: 8)
        #expect(next?.positionSeconds == 300)
    }

    @Test func progressPersistenceNotifiesObserver() async throws {
        let setup = try makeSetup()
        var persisted: PlaybackProgress?
        setup.coordinator.onProgressSaved = { persisted = $0 }

        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: nil)
        await waitUntil { setup.coordinator.state == .playing }
        setup.engine.emitTime(120)

        await waitUntil { persisted != nil }
        #expect(persisted?.episodeNumber == 7)
        #expect(persisted?.positionSeconds == 120)
        #expect(persisted?.isCompleted == false)
    }

    @Test func shortPlaybackDoesNotMarkComplete() async throws {
        let setup = try makeSetup()
        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: nil)
        await waitUntil { setup.coordinator.state == .playing }

        setup.engine.emitTime(30)
        try? await Task.sleep(for: .milliseconds(70))

        let saved = await setup.store.progress(animeID: anime.id, episodeNumber: 7)
        #expect(saved?.isCompleted != true)
    }

    @Test func playbackAddsAnimeToWatchingLibrary() async throws {
        let setup = try makeSetup()
        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: nil)
        await waitUntil { setup.coordinator.state == .playing }
        setup.engine.emitTime(120)

        await waitUntil {
            guard let entry = try? await setup.library.entry(animeID: anime.id) else { return false }
            return entry.status == .watching
        }

        let entry = try await setup.library.entry(animeID: anime.id)
        #expect(entry?.status == .watching)
        #expect(entry?.progress == 6)
        #expect(entry?.anime.id == anime.id)
    }

    @Test func completionAdvancesLibraryProgress() async throws {
        let setup = try makeSetup()
        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: nil)
        await waitUntil { setup.coordinator.state == .playing }
        setup.engine.emitTime(590)

        await waitUntil {
            guard let entry = try? await setup.library.entry(animeID: anime.id) else { return false }
            return entry.progress == 7
        }

        let entry = try await setup.library.entry(animeID: anime.id)
        #expect(entry?.progress == 7)
    }

    @Test func playbackPreservesExplicitLibraryStatus() async throws {
        let completed = LibraryEntry(
            animeID: anime.id,
            status: .completed,
            progress: 12,
            updatedAt: Date(),
            anime: anime
        )
        let library = StubLibraryRepository(entries: [completed])
        let setup = try makeSetup(library: library)

        setup.coordinator.start(stream: stream, anime: anime, episode: episode(1), startAt: nil)
        await waitUntil { setup.coordinator.state == .playing }
        setup.engine.emitTime(30)
        await waitUntil { await setup.store.progress(animeID: anime.id, episodeNumber: 1) != nil }

        let entry = try await setup.library.entry(animeID: anime.id)
        #expect(entry?.status == .completed)
        #expect(entry?.progress == 12)
        #expect(entry?.updatedAt == completed.updatedAt)
    }

    @Test func playbackPromotesPlanToWatch() async throws {
        let planned = LibraryEntry(
            animeID: anime.id,
            status: .planToWatch,
            progress: 0,
            updatedAt: Date(),
            anime: anime
        )
        let library = StubLibraryRepository(entries: [planned])
        let setup = try makeSetup(library: library)

        setup.coordinator.start(stream: stream, anime: anime, episode: episode(3), startAt: nil)
        await waitUntil { setup.coordinator.state == .playing }
        setup.engine.emitTime(60)

        await waitUntil {
            guard let entry = try? await setup.library.entry(animeID: anime.id) else { return false }
            return entry.status == .watching
        }

        let entry = try await setup.library.entry(animeID: anime.id)
        #expect(entry?.status == .watching)
        #expect(entry?.progress == 2)
    }

    @Test func externalPlayerOpensStreamWithoutPresentingBuiltInPlayer() async throws {
        let player = ExternalPlayer(bundleID: "com.example.player", displayName: "Example Player")
        let opener = MockExternalPlayerOpener()
        opener.players = [player]
        let setup = try makeSetup(externalPlayers: opener)
        setup.preferences.externalPlayerBundleID = player.bundleID

        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: nil)

        await waitUntil { !opener.openedURLs.isEmpty }
        #expect(opener.openedURLs == [stream.url])
        #expect(opener.openedBundleIDs == [player.bundleID])
        #expect(!setup.coordinator.isPresenting)
        #expect(setup.engine.loadedURLs.isEmpty)
    }

    @Test func externalPlayerFailureFallsBackToBuiltInPlayer() async throws {
        let player = ExternalPlayer(bundleID: "com.example.player", displayName: "Example Player")
        let opener = MockExternalPlayerOpener()
        opener.players = [player]
        opener.openError = .notInstalled(player.displayName)
        let setup = try makeSetup(externalPlayers: opener)
        setup.preferences.externalPlayerBundleID = player.bundleID

        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: nil)

        await waitUntil { setup.coordinator.state == .playing }
        #expect(setup.coordinator.isPresenting)
        #expect(setup.engine.loadedURLs == [stream.url])
    }

    @Test func missingExternalPlayerFallsBackToBuiltInPlayer() async throws {
        let setup = try makeSetup(externalPlayers: MockExternalPlayerOpener())
        setup.preferences.externalPlayerBundleID = "com.example.uninstalled"

        setup.coordinator.start(stream: stream, anime: anime, episode: episode(7), startAt: nil)

        await waitUntil { setup.coordinator.state == .playing }
        #expect(setup.coordinator.isPresenting)
        #expect(setup.engine.loadedURLs == [stream.url])
    }
}

struct PlaybackProgressStoreTests {
    @Test func savesAndUpdatesProgress() async {
        let store = InMemoryPlaybackProgressStore()
        let first = PlaybackProgress(
            animeID: "anime-1",
            episodeNumber: 2,
            positionSeconds: 30,
            durationSeconds: 1_400,
            updatedAt: Date()
        )

        await store.save(first)
        let loaded = await store.progress(animeID: "anime-1", episodeNumber: 2)
        #expect(loaded?.positionSeconds == 30)

        var updated = first
        updated.positionSeconds = 90
        updated.updatedAt = Date().addingTimeInterval(5)
        await store.save(updated)

        let all = await store.allProgress(limit: 10)
        #expect(all.count == 1)
        #expect(all.first?.positionSeconds == 90)

        let latest = await store.latestProgress(animeID: "anime-1")
        #expect(latest?.positionSeconds == 90)
    }

    @Test func watchedEpisodeCountTracksCompletedEpisodes() {
        let inProgress = PlaybackProgress(
            animeID: "anime-1",
            episodeNumber: 7,
            positionSeconds: 300,
            durationSeconds: 1_400,
            updatedAt: Date()
        )
        #expect(inProgress.watchedEpisodeCount == 6)

        let firstEpisode = PlaybackProgress(
            animeID: "anime-1",
            episodeNumber: 1,
            positionSeconds: 60,
            durationSeconds: 1_400,
            updatedAt: Date()
        )
        #expect(firstEpisode.watchedEpisodeCount == 0)

        var completed = inProgress
        completed.isCompleted = true
        #expect(completed.watchedEpisodeCount == 7)
    }
}
