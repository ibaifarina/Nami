import Foundation
import Testing
@testable import Nami

@MainActor
struct SkipIntroControllerTests {
    private struct Setup {
        let controller: SkipIntroController
        let preferences: PreferencesStore
        let http: MockHTTPClient
        let defaults: UserDefaults
    }

    private var skipTimesJSON: Data {
        Data("""
        {
          "found": true,
          "results": [
            { "interval": { "startTime": 10, "endTime": 100 }, "skipType": "op" },
            { "interval": { "startTime": 1300, "endTime": 1400 }, "skipType": "ed" }
          ]
        }
        """.utf8)
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

    private func makeSetup(
        http: MockHTTPClient? = nil,
        identityResolver: MediaIdentityResolver? = nil,
        skipIntroEnabled: Bool = true
    ) throws -> Setup {
        let suite = "skip-intro-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let preferences = PreferencesStore(defaults: defaults)
        preferences.skipIntroEnabled = skipIntroEnabled
        let times = skipTimesJSON
        let client = http ?? MockHTTPClient { _ in times }
        let controller = SkipIntroController(
            skipTimes: AniSkipService(http: client),
            identityResolver: identityResolver,
            preferences: preferences
        )
        return Setup(controller: controller, preferences: preferences, http: client, defaults: defaults)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func showsOpeningIntervalDuringPlayback() async throws {
        let setup = try makeSetup()
        let anime = self.anime
        let episode = episode(7)

        setup.controller.progressTick(anime: anime, episode: episode, currentTime: 5, duration: 1440)
        await waitUntil {
            setup.controller.progressTick(anime: anime, episode: episode, currentTime: 50, duration: 1440)
            return setup.controller.activeInterval != nil
        }

        #expect(setup.controller.activeInterval?.kind == .opening)
        #expect(setup.controller.activeInterval?.endSeconds == 100)
    }

    @Test func hidesButtonOutsideIntervals() async throws {
        let setup = try makeSetup()
        let anime = self.anime
        let episode = episode(7)

        setup.controller.progressTick(anime: anime, episode: episode, currentTime: 5, duration: 1440)
        await waitUntil {
            setup.controller.progressTick(anime: anime, episode: episode, currentTime: 50, duration: 1440)
            return setup.controller.activeInterval != nil
        }

        setup.controller.progressTick(anime: anime, episode: episode, currentTime: 500, duration: 1440)

        #expect(setup.controller.activeInterval == nil)
    }

    @Test func skipJumpsToIntervalEndAndHidesButton() async throws {
        let setup = try makeSetup()
        var target: Double?
        setup.controller.onSkip = { target = $0 }
        let anime = self.anime
        let episode = episode(7)

        setup.controller.progressTick(anime: anime, episode: episode, currentTime: 5, duration: 1440)
        await waitUntil {
            setup.controller.progressTick(anime: anime, episode: episode, currentTime: 50, duration: 1440)
            return setup.controller.activeInterval != nil
        }

        setup.controller.skip()

        #expect(target == 100)
        #expect(setup.controller.activeInterval == nil)
    }

    @Test func switchingEpisodeClearsActiveInterval() async throws {
        let setup = try makeSetup()
        let anime = self.anime

        setup.controller.progressTick(anime: anime, episode: episode(7), currentTime: 5, duration: 1440)
        await waitUntil {
            setup.controller.progressTick(anime: anime, episode: episode(7), currentTime: 50, duration: 1440)
            return setup.controller.activeInterval != nil
        }

        setup.controller.progressTick(anime: anime, episode: episode(8), currentTime: 50, duration: 1440)

        #expect(setup.controller.activeInterval == nil)
    }

    @Test func resetClearsActiveInterval() async throws {
        let setup = try makeSetup()
        let anime = self.anime
        let episode = episode(7)

        setup.controller.progressTick(anime: anime, episode: episode, currentTime: 5, duration: 1440)
        await waitUntil {
            setup.controller.progressTick(anime: anime, episode: episode, currentTime: 50, duration: 1440)
            return setup.controller.activeInterval != nil
        }

        setup.controller.reset()

        #expect(setup.controller.activeInterval == nil)
    }

    @Test func disabledPreferenceSuppressesButton() async throws {
        let setup = try makeSetup(skipIntroEnabled: false)
        let anime = self.anime
        let episode = episode(7)

        setup.controller.progressTick(anime: anime, episode: episode, currentTime: 50, duration: 1440)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(setup.controller.activeInterval == nil)
        #expect(await setup.http.requestCount == 0)
    }

    @Test func resolvesMALIDFromKitsuMappingsWhenMissing() async throws {
        let times = skipTimesJSON
        let http = MockHTTPClient { request in
            if request.url?.host() == "api.aniskip.com" {
                return times
            }
            return KitsuFixtures.mappingsJSON
        }
        let resolver = MediaIdentityResolver(
            client: KitsuClient(http: http),
            cache: MetadataCache(directory: nil)
        )
        let setup = try makeSetup(http: http, identityResolver: resolver)
        let anime = SampleCatalog.make(
            id: "8671",
            title: "Attack on Titan Season 2",
            subtype: .tv,
            status: .finished,
            episodes: 12,
            duration: 24
        )
        let episode = episode(1, of: anime)

        setup.controller.progressTick(anime: anime, episode: episode, currentTime: 5, duration: 1440)
        await waitUntil {
            setup.controller.progressTick(anime: anime, episode: episode, currentTime: 50, duration: 1440)
            return setup.controller.activeInterval != nil
        }

        #expect(setup.controller.activeInterval?.kind == .opening)
        let request = try #require(await setup.http.lastRequest)
        #expect(request.url?.path() == "/v2/skip-times/25777/1")
    }
}
