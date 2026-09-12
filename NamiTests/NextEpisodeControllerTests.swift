import Foundation
import Testing
@testable import Nami

@MainActor
struct NextEpisodeControllerTests {
    private struct Setup {
        let controller: NextEpisodeController
        let http: MockHTTPClient
        let debrid: StubDebridService
        let defaults: UserDefaults
        let suite: String
    }

    private var anime: Anime { SampleCatalog.anime[0] }

    private func episode(_ number: Int, of anime: Anime? = nil) -> Episode {
        let target = anime ?? self.anime
        return Episode(
            id: "\(target.id)-\(number)",
            animeID: target.id,
            number: number,
            relativeNumber: number,
            seasonNumber: 1,
            durationMinutes: target.durationMinutes
        )
    }

    private static func streamsJSON(episode: Int, hash: String) -> Data {
        let padded = String(format: "%02d", episode)
        return Data("""
        {"streams":[{"title":"Sousou no Frieren - \(padded) [1080p] BluRay HEVC","infoHash":"\(hash)","sizeBytes":1400000000,"seeders":50}]}
        """.utf8)
    }

    private func makeSetup(
        streamsJSON: Data? = nil,
        latency: Duration = .zero,
        autoplay: Bool = true,
        cacheTTL: TimeInterval = 600
    ) async throws -> Setup {
        let suite = "next-episode-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let preferences = PreferencesStore(defaults: defaults)
        preferences.autoplayNextEpisode = autoplay

        let hash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let json = streamsJSON ?? Self.streamsJSON(episode: 8, hash: hash)
        let http = MockHTTPClient { _ in
            if latency > .zero {
                try await Task.sleep(for: latency)
            }
            return json
        }
        let debrid = StubDebridService()
        await debrid.configure(availability: [hash: .cached])

        let registry = AddonRegistry(
            persistence: InMemoryAddonPersistence(addons: [
                AddonFixtures.addon(id: "one", baseURL: testURL("https://one.example"), priority: 0),
            ])
        )
        let discovery = StreamDiscoveryService(
            addonManager: AddonManager(http: http),
            debrid: debrid
        )
        let resolver = SourceResolver(
            debrid: debrid,
            cache: ResolvedStreamCache(fileURL: nil),
            preferences: preferences
        )
        let controller = NextEpisodeController(
            discovery: discovery,
            streamPlayback: StreamPlaybackService(
                resolver: resolver,
                validator: StubStreamValidator()
            ),
            preferences: preferences,
            registry: registry,
            cacheTTL: cacheTTL
        )
        return Setup(
            controller: controller,
            http: http,
            debrid: debrid,
            defaults: defaults,
            suite: suite
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

    @Test func prefetchStartsOnlyPastThreshold() async throws {
        let setup = try await makeSetup()
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.controller.progressTick(anime: anime, episode: episode(7), currentTime: 1000, duration: 1440)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(setup.controller.preparedDecision == nil)
        #expect(setup.controller.nextEpisodeNumber == 8)
        #expect(await setup.http.requestCount == 0)

        setup.controller.progressTick(anime: anime, episode: episode(7), currentTime: 1100, duration: 1440)
        await waitUntil { setup.controller.preparedDecision != nil }

        #expect(setup.controller.preparedEpisodeNumber == 8)
        #expect(setup.controller.preparedDecision?.shouldAutoPlay == true)
        #expect(await setup.http.requestCount == 1)
    }

    @Test func countdownOverlayAppearsNearEnd() async throws {
        let setup = try await makeSetup()
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.controller.progressTick(anime: anime, episode: episode(7), currentTime: 1100, duration: 1440)
        await waitUntil { setup.controller.preparedDecision != nil }

        setup.controller.progressTick(anime: anime, episode: episode(7), currentTime: 1428, duration: 1440)
        #expect(setup.controller.overlay == .countdown(seconds: 10))

        setup.controller.progressTick(anime: anime, episode: episode(7), currentTime: 1432, duration: 1440)
        #expect(setup.controller.overlay == .countdown(seconds: 8))
    }

    @Test func playNowResolvesAndStartsNextEpisode() async throws {
        let setup = try await makeSetup()
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        var started: [(URL, Int)] = []
        setup.controller.startPlayback = { stream, _, episode in
            started.append((stream.url, episode.displayNumber))
        }

        setup.controller.progressTick(anime: anime, episode: episode(7), currentTime: 1100, duration: 1440)
        await waitUntil { setup.controller.preparedDecision != nil }
        setup.controller.progressTick(anime: anime, episode: episode(7), currentTime: 1432, duration: 1440)

        setup.controller.playNow()
        await waitUntil { started.count == 1 }

        #expect(started.first?.1 == 8)
        #expect(started.first?.0.absoluteString == "https://resolved.example/video.mp4")
        #expect(await setup.debrid.resolvedCandidateIDs.count == 1)
    }

    @Test func cancelHidesOverlayAndPreventsAutoplay() async throws {
        let setup = try await makeSetup()
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        var started: [(URL, Int)] = []
        setup.controller.startPlayback = { stream, _, episode in
            started.append((stream.url, episode.displayNumber))
        }

        setup.controller.progressTick(anime: anime, episode: episode(7), currentTime: 1100, duration: 1440)
        await waitUntil { setup.controller.preparedDecision != nil }
        setup.controller.progressTick(anime: anime, episode: episode(7), currentTime: 1432, duration: 1440)
        #expect(setup.controller.overlay != .hidden)

        setup.controller.cancelCountdown()
        #expect(setup.controller.overlay == .hidden)

        setup.controller.playbackEnded()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(started.isEmpty)
    }

    @Test func lowConfidenceShowsChooseSourceOverlay() async throws {
        let wrongEpisode = Self.streamsJSON(
            episode: 9,
            hash: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        )
        let setup = try await makeSetup(streamsJSON: wrongEpisode)
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.controller.progressTick(anime: anime, episode: episode(7), currentTime: 1100, duration: 1440)
        await waitUntil { setup.controller.preparedDecision != nil }
        #expect(setup.controller.preparedDecision?.shouldAutoPlay == false)

        setup.controller.progressTick(anime: anime, episode: episode(7), currentTime: 1432, duration: 1440)
        #expect(setup.controller.overlay == .readyToChoose)
        #expect(setup.controller.nextEpisodeRequest?.episodeNumber == 8)
        #expect(setup.controller.nextEpisodeRequest?.prefersManualSelection == true)
    }

    @Test func autoplayDisabledSkipsPrefetchAndOverlay() async throws {
        let setup = try await makeSetup(autoplay: false)
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.controller.progressTick(anime: anime, episode: episode(7), currentTime: 1432, duration: 1440)
        try? await Task.sleep(for: .milliseconds(80))

        #expect(setup.controller.preparedDecision == nil)
        #expect(setup.controller.overlay == .hidden)
        #expect(await setup.http.requestCount == 0)
    }

    @Test func switchingEpisodeCancelsPrefetch() async throws {
        let setup = try await makeSetup(latency: .milliseconds(300))
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.controller.progressTick(anime: anime, episode: episode(7), currentTime: 1100, duration: 1440)
        setup.controller.progressTick(anime: anime, episode: episode(3), currentTime: 100, duration: 1440)

        try? await Task.sleep(for: .milliseconds(500))

        #expect(setup.controller.preparedDecision == nil)
        #expect(setup.controller.nextEpisodeNumber == 4)
    }

    @Test func lastEpisodeHasNoNextEpisode() async throws {
        let movie = try #require(SampleCatalog.anime(withID: "11614"))
        let setup = try await makeSetup()
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.controller.progressTick(
            anime: movie,
            episode: episode(1, of: movie),
            currentTime: 1400,
            duration: 1440
        )
        try? await Task.sleep(for: .milliseconds(80))

        #expect(setup.controller.nextEpisodeNumber == nil)
        #expect(setup.controller.overlay == .hidden)
        #expect(setup.controller.preparedDecision == nil)
        #expect(await setup.http.requestCount == 0)
    }

    @Test func expiredCacheTriggersRefetch() async throws {
        let setup = try await makeSetup(cacheTTL: 0.01)
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.controller.progressTick(anime: anime, episode: episode(7), currentTime: 1100, duration: 1440)
        await waitUntil { setup.controller.preparedDecision != nil }

        try? await Task.sleep(for: .milliseconds(60))
        setup.controller.progressTick(anime: anime, episode: episode(7), currentTime: 1432, duration: 1440)

        await waitUntil { await setup.http.requestCount == 2 }
        #expect(await setup.http.requestCount == 2)
    }

    @Test func resetClearsEverything() async throws {
        let setup = try await makeSetup()
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.controller.progressTick(anime: anime, episode: episode(7), currentTime: 1100, duration: 1440)
        await waitUntil { setup.controller.preparedDecision != nil }

        setup.controller.reset()

        #expect(setup.controller.overlay == .hidden)
        #expect(setup.controller.nextEpisodeNumber == nil)
        #expect(setup.controller.preparedDecision == nil)
        #expect(!setup.controller.hasPreparedDecision)
    }
}
