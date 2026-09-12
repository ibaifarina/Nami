import AppKit
import Foundation
import Testing
@testable import Nami

@MainActor
private final class LaunchPlayerEngine: PlayerEngine {
    var onStateChange: ((PlayerEngineState) -> Void)?
    var onTimeChange: ((Double, Double) -> Void)?
    var onTracksChange: (() -> Void)?

    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 600
    var volume: Double = 1
    var rate: Double = 1

    private(set) var loadedURLs: [URL] = []
    private(set) var loadAttempts = 0
    var failuresBeforeSuccess = 0

    func load(_ stream: ResolvedStream) async throws {
        onStateChange?(.loading)
        loadAttempts += 1
        if loadAttempts <= failuresBeforeSuccess {
            throw PlayerError.failedToLoad("Simulated stream failure")
        }
        loadedURLs.append(stream.url)
        onStateChange?(.ready)
    }

    func play() {
        isPlaying = true
        onStateChange?(.playing)
    }

    func pause() {
        isPlaying = false
        onStateChange?(.paused)
    }

    func stop() {
        isPlaying = false
        onStateChange?(.idle)
    }

    func seek(to seconds: Double) {}
    func setVolume(_ volume: Double) { self.volume = volume }
    func setRate(_ rate: Double) { self.rate = rate }
    func audioTracks() -> [MediaTrack] { [] }
    func subtitleTracks() -> [MediaTrack] { [] }
    func selectAudioTrack(_ track: MediaTrack) {}
    func selectSubtitleTrack(_ track: MediaTrack?) {}
    func makeVideoSurface() -> NSView { NSView() }
    func updateVideoSurface(_ view: NSView) {}
}

@MainActor
private final class StubPreloader: StreamPreloading {
    var result: StreamDiscoveryResult
    var latency: Duration = .zero
    private(set) var prepareCallCount = 0
    private(set) var streamsCallCount = 0

    init(result: StreamDiscoveryResult) {
        self.result = result
    }

    func prepare(anime: Anime, episode: Episode) {
        prepareCallCount += 1
    }

    func streams(anime: Anime, episode: Episode) async -> StreamDiscoveryResult {
        streamsCallCount += 1
        if latency > .zero {
            try? await Task.sleep(for: latency)
        }
        return result
    }

    func clear() {}
}

private actor FailingDebridService: DebridService {
    private let error: DebridError

    init(error: DebridError = .itemNotReady) {
        self.error = error
    }

    func validateAccount() async throws -> DebridAccount {
        throw DebridError.notConfigured
    }

    func validateAccount(token: String) async throws -> DebridAccount {
        throw DebridError.notConfigured
    }

    func checkAvailability(_ candidates: [StreamCandidate]) async throws -> [DebridCheckResult] {
        []
    }

    func files(for candidate: StreamCandidate) async throws -> [DebridFileInfo] {
        throw error
    }

    func resolve(_ candidate: StreamCandidate, fileID: Int?) async throws -> ResolvedStream {
        throw error
    }
}

@MainActor
struct PlaybackLaunchControllerTests {
    private struct Setup {
        let controller: PlaybackLaunchController
        let playback: PlaybackCoordinator
        let engine: LaunchPlayerEngine
        let preloader: StubPreloader
        let defaults: UserDefaults
        let suite: String
    }

    private var anime: Anime { SampleCatalog.anime[0] }

    private var movie: Anime { SampleCatalog.anime[4] }

    private let multiFileHash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

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

    private func movieEpisode() -> Episode {
        Episode(
            id: "\(movie.id)-1",
            animeID: movie.id,
            number: 1,
            relativeNumber: 1,
            seasonNumber: 1,
            durationMinutes: movie.durationMinutes
        )
    }

    private func request(manual: Bool = false) -> PlaybackRequest {
        PlaybackRequest(
            anime: anime,
            episode: episode(7),
            prefersManualSelection: manual
        )
    }

    private func makeResult(autoPlay: Bool) -> StreamDiscoveryResult {
        let hash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let candidate = StreamCandidate(
            id: hash,
            addonID: "one",
            addonName: "One",
            displayTitle: "Sousou no Frieren - 07 [1080p] BluRay HEVC",
            infoHash: hash,
            resolution: .p1080,
            codec: .hevc,
            source: .bluRay,
            sizeBytes: 1_400_000_000,
            seeders: 50,
            debridStatus: .cached,
            episodeMatchConfidence: 1
        )
        var options = StreamScoringOptions()
        options.autoSelectEnabled = autoPlay
        let engine = StreamScoringEngine(options: options)
        let context = ScoringContext(
            episodeDurationMinutes: 24,
            addonPriorities: ["one": 0],
            debridAvailable: true
        )
        return StreamDiscoveryResult(
            decision: engine.selectBest([candidate], context: context),
            ranked: engine.rank([candidate], context: context),
            addonResults: [],
            debridAvailable: true
        )
    }

    private func makeSetup(
        result: StreamDiscoveryResult,
        latency: Duration = .zero,
        debrid: (any DebridService)? = nil,
        validator: (any StreamValidating)? = nil
    ) throws -> Setup {
        let suite = "launch-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let preferences = PreferencesStore(defaults: defaults)
        let engine = LaunchPlayerEngine()
        let playback = PlaybackCoordinator(
            engine: engine,
            progressStore: InMemoryPlaybackProgressStore(),
            preferences: preferences,
            library: StubLibraryRepository()
        )
        let preloader = StubPreloader(result: result)
        preloader.latency = latency
        let resolver = SourceResolver(
            debrid: debrid ?? StubDebridService(),
            cache: ResolvedStreamCache(fileURL: nil),
            preferences: preferences
        )
        let streamPlayback = StreamPlaybackService(
            resolver: resolver,
            validator: validator ?? StubStreamValidator()
        )
        let controller = PlaybackLaunchController(
            preload: preloader,
            resolver: resolver,
            streamPlayback: streamPlayback,
            playback: playback
        )
        return Setup(
            controller: controller,
            playback: playback,
            engine: engine,
            preloader: preloader,
            defaults: defaults,
            suite: suite
        )
    }

    private func makeTwoCandidateResult() -> (result: StreamDiscoveryResult, first: StreamCandidate, second: StreamCandidate) {
        let firstHash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let secondHash = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        let first = StreamCandidate(
            id: firstHash,
            addonID: "one",
            addonName: "One",
            displayTitle: "Sousou no Frieren - 07 [1080p] BluRay HEVC",
            infoHash: firstHash,
            resolution: .p1080,
            codec: .hevc,
            source: .bluRay,
            sizeBytes: 1_400_000_000,
            seeders: 50,
            debridStatus: .cached,
            episodeMatchConfidence: 1
        )
        let second = StreamCandidate(
            id: secondHash,
            addonID: "one",
            addonName: "One",
            displayTitle: "Sousou no Frieren - 07 [720p] WEB-DL AVC",
            infoHash: secondHash,
            resolution: .p720,
            codec: .avc,
            source: .webDL,
            sizeBytes: 700_000_000,
            seeders: 30,
            debridStatus: .cached,
            episodeMatchConfidence: 1
        )
        let options = StreamScoringOptions()
        let engine = StreamScoringEngine(options: options)
        let context = ScoringContext(
            episodeDurationMinutes: 24,
            addonPriorities: ["one": 0],
            debridAvailable: true
        )
        return (
            StreamDiscoveryResult(
                decision: engine.selectBest([first, second], context: context),
                ranked: engine.rank([first, second], context: context),
                addonResults: [],
                debridAvailable: true
            ),
            first,
            second
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

    @Test func playPresentsPlayerAndStartsResolvedStream() async throws {
        let setup = try makeSetup(result: makeResult(autoPlay: true))
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.controller.play(request())
        await waitUntil { setup.playback.state == .playing }

        #expect(setup.playback.isPresenting)
        #expect(setup.engine.loadedURLs == [testURL("https://resolved.example/video.mp4")])
        #expect(setup.controller.pickerRequest == nil)
        #expect(setup.preloader.streamsCallCount == 1)
    }

    @Test func movieWithMultipleFilesPresentsPickerInsteadOfGuessing() async throws {
        let debrid = StubDebridService()
        await debrid.configure(files: [
            multiFileHash: [
                DebridFileInfo(id: 1, path: "/Your Name Part 1.mkv", bytes: 1_000_000, selected: false),
                DebridFileInfo(id: 2, path: "/Your Name Part 2.mkv", bytes: 2_000_000, selected: false),
            ],
        ])
        let setup = try makeSetup(result: makeResult(autoPlay: true), debrid: debrid)
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.controller.play(PlaybackRequest(anime: movie, episode: movieEpisode()))
        await waitUntil { setup.controller.pickerRequest != nil }

        #expect(setup.controller.pickerRequest?.prefersManualSelection == false)
        #expect(setup.playback.isAwaitingSource)
        #expect(setup.engine.loadedURLs.isEmpty)
        let resolvedIDs = await debrid.resolvedCandidateIDs
        #expect(resolvedIDs.isEmpty)
    }

    @Test func movieWithSingleFileStillAutoPlays() async throws {
        let debrid = StubDebridService()
        await debrid.configure(files: [
            multiFileHash: [
                DebridFileInfo(id: 1, path: "/Your Name.mkv", bytes: 2_000_000, selected: false),
            ],
        ])
        let setup = try makeSetup(result: makeResult(autoPlay: true), debrid: debrid)
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.controller.play(PlaybackRequest(anime: movie, episode: movieEpisode()))
        await waitUntil { setup.playback.state == .playing }

        #expect(setup.controller.pickerRequest == nil)
        #expect(setup.engine.loadedURLs == [testURL("https://resolved.example/video.mp4")])
    }

    @Test func lowConfidencePresentsSourcePickerOverPlayer() async throws {
        let setup = try makeSetup(result: makeResult(autoPlay: false))
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.controller.play(request())
        await waitUntil { setup.controller.pickerRequest != nil }

        #expect(setup.controller.pickerRequest?.prefersManualSelection == true)
        #expect(setup.playback.isPresenting)
        #expect(setup.playback.isAwaitingSource)
        #expect(setup.engine.loadedURLs.isEmpty)
    }

    @Test func manualPlayPresentsPickerWithoutPlayer() async throws {
        let setup = try makeSetup(result: makeResult(autoPlay: true))
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.controller.play(request(manual: true))

        #expect(setup.controller.pickerRequest?.prefersManualSelection == true)
        #expect(!setup.playback.isPresenting)
        #expect(setup.preloader.streamsCallCount == 0)
    }

    @Test func pickerDismissalClosesPendingPlayer() async throws {
        let setup = try makeSetup(result: makeResult(autoPlay: false))
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.controller.play(request())
        await waitUntil { setup.controller.pickerRequest != nil }

        setup.controller.pickerDismissed()

        #expect(!setup.playback.isPresenting)
        #expect(setup.playback.state == .idle)
    }

    @Test func closingPlayerWhileResolvingCancelsLaunch() async throws {
        let setup = try makeSetup(result: makeResult(autoPlay: true), latency: .milliseconds(200))
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.controller.play(request())
        #expect(setup.playback.isPresenting)

        setup.playback.close()
        try? await Task.sleep(for: .milliseconds(400))

        #expect(setup.playback.state == .idle)
        #expect(setup.engine.loadedURLs.isEmpty)
        #expect(setup.controller.pickerRequest == nil)
    }

    @Test func replayReusesCachedSourceWithoutDiscovery() async throws {
        let setup = try makeSetup(result: makeResult(autoPlay: true))
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.controller.play(request())
        await waitUntil { setup.playback.state == .playing }
        setup.playback.close()

        setup.controller.play(request())
        await waitUntil { setup.engine.loadedURLs.count == 2 }

        #expect(setup.preloader.streamsCallCount == 1)
        #expect(setup.engine.loadedURLs == [
            testURL("https://resolved.example/video.mp4"),
            testURL("https://resolved.example/video.mp4"),
        ])
    }

    @Test func resolveFailureFallsBackToPicker() async throws {
        let setup = try makeSetup(
            result: makeResult(autoPlay: true),
            debrid: FailingDebridService()
        )
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.controller.play(request())
        await waitUntil { setup.controller.pickerRequest != nil }

        #expect(setup.playback.isPresenting)
        #expect(setup.playback.isAwaitingSource)
        #expect(setup.engine.loadedURLs.isEmpty)
    }

    @Test func invalidPreferredStreamFallsBackToNextCandidate() async throws {
        let (result, first, second) = makeTwoCandidateResult()
        let firstURL = testURL("https://resolved.example/first.mp4")
        let secondURL = testURL("https://resolved.example/second.mp4")
        let debrid = StubDebridService()
        await debrid.configure(resolveURLs: [first.id: firstURL, second.id: secondURL])
        let validator = StubStreamValidator()
        await validator.setVerdict(
            .candidateInvalid(StreamValidationIssue(kind: .infringing)),
            for: firstURL
        )
        let setup = try makeSetup(result: result, debrid: debrid, validator: validator)
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.controller.play(request())
        await waitUntil { setup.playback.state == .playing }

        #expect(setup.controller.pickerRequest == nil)
        #expect(setup.engine.loadedURLs == [secondURL])
    }

    @Test func playbackFailureTransparentlyFallsBackToNextCandidate() async throws {
        let (result, first, second) = makeTwoCandidateResult()
        let firstURL = testURL("https://resolved.example/first.mp4")
        let secondURL = testURL("https://resolved.example/second.mp4")
        let debrid = StubDebridService()
        await debrid.configure(resolveURLs: [first.id: firstURL, second.id: secondURL])
        let setup = try makeSetup(result: result, debrid: debrid)
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        setup.engine.failuresBeforeSuccess = 1
        setup.playback.onStreamFailed = { [weak controller = setup.controller] anime, episode in
            controller?.streamFailed(anime: anime, episode: episode)
        }

        setup.controller.play(request())
        await waitUntil { setup.engine.loadedURLs == [secondURL] }

        #expect(setup.controller.pickerRequest == nil)
        #expect(setup.engine.loadAttempts == 2)
    }

    @Test func cachedPlaybackFailureRecoversWithFreshSource() async throws {
        let setup = try makeSetup(result: makeResult(autoPlay: true))
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        setup.playback.onStreamFailed = { [weak controller = setup.controller] anime, episode in
            controller?.streamFailed(anime: anime, episode: episode)
        }

        setup.controller.play(request())
        await waitUntil { setup.playback.state == .playing }
        setup.playback.close()

        // The next load fails, which must invalidate the cached source and
        // resolve a fresh one without surfacing an error.
        setup.engine.failuresBeforeSuccess = 2
        setup.controller.play(request())
        await waitUntil { setup.playback.state == .playing && setup.engine.loadAttempts == 3 }

        #expect(setup.controller.pickerRequest == nil)
        #expect(setup.engine.loadedURLs.count == 2)
        #expect(setup.preloader.streamsCallCount == 2)
    }

    @Test func accountErrorStopsFallbackAndShowsPicker() async throws {
        let (result, _, _) = makeTwoCandidateResult()
        let setup = try makeSetup(
            result: result,
            debrid: FailingDebridService(error: .accountLocked)
        )
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.controller.play(request())
        await waitUntil { setup.controller.pickerRequest != nil }

        #expect(setup.playback.isPresenting)
        #expect(setup.engine.loadedURLs.isEmpty)
    }
}
