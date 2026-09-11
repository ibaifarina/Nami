import Foundation
import Testing
@testable import Nami

@MainActor
struct SourceResolverTests {
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

    private func candidate(_ id: String) -> StreamCandidate {
        StreamCandidate(
            id: id,
            addonID: "one",
            addonName: "One",
            displayTitle: "Sousou no Frieren - 07 [1080p] BluRay HEVC",
            infoHash: id,
            resolution: .p1080,
            codec: .hevc,
            source: .bluRay,
            sizeBytes: 1_400_000_000,
            seeders: 50,
            debridStatus: .cached,
            episodeMatchConfidence: 1
        )
    }

    private func makeResolver(
        debrid: StubDebridService,
        suite: String
    ) throws -> (SourceResolver, PreferencesStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: suite))
        let preferences = PreferencesStore(defaults: defaults)
        let resolver = SourceResolver(
            debrid: debrid,
            cache: ResolvedStreamCache(fileURL: nil),
            preferences: preferences
        )
        return (resolver, preferences, defaults)
    }

    @Test func resolveReusesCachedSourceForMatchingCandidate() async throws {
        let suite = "source-resolver-\(UUID().uuidString)"
        let debrid = StubDebridService()
        let (resolver, _, defaults) = try makeResolver(debrid: debrid, suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let candidate = candidate("aaaaaaaa")

        _ = try await resolver.resolve(candidate, anime: anime, episode: episode(7))
        let second = try await resolver.resolve(candidate, anime: anime, episode: episode(7))

        let resolvedIDs = await debrid.resolvedCandidateIDs
        #expect(second.url == testURL("https://resolved.example/video.mp4"))
        #expect(resolvedIDs == [candidate.id])
    }

    @Test func resolveResolvesAgainForDifferentCandidate() async throws {
        let suite = "source-resolver-\(UUID().uuidString)"
        let debrid = StubDebridService()
        let (resolver, _, defaults) = try makeResolver(debrid: debrid, suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        _ = try await resolver.resolve(candidate("aaaaaaaa"), anime: anime, episode: episode(7))
        _ = try await resolver.resolve(candidate("bbbbbbbb"), anime: anime, episode: episode(7))

        let resolvedIDs = await debrid.resolvedCandidateIDs
        #expect(resolvedIDs.count == 2)
    }

    @Test func disabledCachingBypassesStoreAndLookup() async throws {
        let suite = "source-resolver-\(UUID().uuidString)"
        let debrid = StubDebridService()
        let (resolver, preferences, defaults) = try makeResolver(debrid: debrid, suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        preferences.cacheResolvedSources = false
        let candidate = candidate("aaaaaaaa")

        _ = try await resolver.resolve(candidate, anime: anime, episode: episode(7))
        let cached = await resolver.cachedStream(anime: anime, episode: episode(7))
        _ = try await resolver.resolve(candidate, anime: anime, episode: episode(7))

        let resolvedIDs = await debrid.resolvedCandidateIDs
        #expect(cached == nil)
        #expect(resolvedIDs.count == 2)
    }

    @Test func resolveForwardsExplicitFileSelection() async throws {
        let suite = "source-resolver-\(UUID().uuidString)"
        let debrid = StubDebridService()
        let (resolver, _, defaults) = try makeResolver(debrid: debrid, suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        _ = try await resolver.resolve(
            candidate("aaaaaaaa"),
            anime: anime,
            episode: episode(7),
            fileID: 3
        )

        let fileIDs = await debrid.resolvedFileIDs
        #expect(fileIDs == [3])
    }

    @Test func resolveBypassesCacheWhenAnotherFileIsChosen() async throws {
        let suite = "source-resolver-\(UUID().uuidString)"
        let debrid = StubDebridService()
        let (resolver, _, defaults) = try makeResolver(debrid: debrid, suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let candidate = candidate("aaaaaaaa")

        _ = try await resolver.resolve(
            candidate,
            anime: anime,
            episode: episode(7),
            fileID: 1
        )
        _ = try await resolver.resolve(
            candidate,
            anime: anime,
            episode: episode(7),
            fileID: 2
        )

        let fileIDs = await debrid.resolvedFileIDs
        #expect(fileIDs == [1, 2])
    }

    @Test func invalidateForcesFreshResolution() async throws {
        let suite = "source-resolver-\(UUID().uuidString)"
        let debrid = StubDebridService()
        let (resolver, _, defaults) = try makeResolver(debrid: debrid, suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let candidate = candidate("aaaaaaaa")

        _ = try await resolver.resolve(candidate, anime: anime, episode: episode(7))
        await resolver.invalidate(anime: anime, episode: episode(7))
        _ = try await resolver.resolve(candidate, anime: anime, episode: episode(7))

        let resolvedIDs = await debrid.resolvedCandidateIDs
        #expect(resolvedIDs.count == 2)
    }
}
