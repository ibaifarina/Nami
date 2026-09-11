import Foundation
import Testing
@testable import Nami

@MainActor
struct StreamPreloadServiceTests {
    private struct Setup {
        let service: StreamPreloadService
        let http: MockHTTPClient
        let debrid: StubDebridService
        let defaults: UserDefaults
        let suite: String
    }

    private var anime: Anime { SampleCatalog.anime[0] }

    private func episode(_ number: Int) -> Episode {
        Episode(
            id: "\(anime.id)-\(number)",
            animeID: anime.id,
            number: number,
            relativeNumber: number,
            seasonNumber: 1,
            absoluteNumber: number,
            durationMinutes: anime.durationMinutes
        )
    }

    private static func streamsJSON(episode: Int, hash: String) -> Data {
        let padded = String(format: "%02d", episode)
        return Data("""
        {"streams":[{"title":"Sousou no Frieren - \(padded) [1080p] BluRay HEVC","infoHash":"\(hash)","sizeBytes":1400000000,"seeders":50}]}
        """.utf8)
    }

    private func makeSetup(
        latency: Duration = .zero,
        cacheTTL: TimeInterval = 300
    ) async throws -> Setup {
        let suite = "preload-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let preferences = PreferencesStore(defaults: defaults)
        let hash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let json = Self.streamsJSON(episode: 7, hash: hash)
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
        let service = StreamPreloadService(
            discovery: discovery,
            episodes: StubEpisodeRepository(),
            preferences: preferences,
            registry: registry,
            cacheTTL: cacheTTL
        )
        return Setup(
            service: service,
            http: http,
            debrid: debrid,
            defaults: defaults,
            suite: suite
        )
    }

    @Test func prepareCachesDiscoveryForLaterPlayback() async throws {
        let setup = try await makeSetup()
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.service.prepare(anime: anime, episode: episode(7))
        let first = await setup.service.streams(anime: anime, episode: episode(7))

        #expect(first.decision.shouldAutoPlay)
        #expect(await setup.http.requestCount == 1)

        let second = await setup.service.streams(anime: anime, episode: episode(7))
        #expect(await setup.http.requestCount == 1)
        #expect(second.decision.candidate?.id == first.decision.candidate?.id)
    }

    @Test func concurrentRequestsShareOneDiscovery() async throws {
        let setup = try await makeSetup(latency: .milliseconds(100))
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        let service = setup.service
        let targetAnime = anime
        let targetEpisode = episode(7)
        let first = Task { await service.streams(anime: targetAnime, episode: targetEpisode) }
        let second = Task { await service.streams(anime: targetAnime, episode: targetEpisode) }
        let firstResult = await first.value
        let secondResult = await second.value

        #expect(await setup.http.requestCount == 1)
        #expect(firstResult.decision.candidate?.id == secondResult.decision.candidate?.id)
    }

    @Test func expiredCacheIsRefetched() async throws {
        let setup = try await makeSetup(cacheTTL: 0.01)
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        _ = await setup.service.streams(anime: anime, episode: episode(7))
        try? await Task.sleep(for: .milliseconds(60))
        _ = await setup.service.streams(anime: anime, episode: episode(7))

        #expect(await setup.http.requestCount == 2)
    }

    @Test func clearForcesRefetch() async throws {
        let setup = try await makeSetup()
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        _ = await setup.service.streams(anime: anime, episode: episode(7))
        setup.service.clear()
        _ = await setup.service.streams(anime: anime, episode: episode(7))

        #expect(await setup.http.requestCount == 2)
    }
}
