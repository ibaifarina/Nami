import Foundation
import Testing
@testable import Nami

/// Live verification against the public Kitsu API. Disabled by default; run
/// with the `LIVE_KITSU=1` environment variable when validating the schema.
struct LiveKitsuCheck {
    private var isEnabled: Bool {
        ProcessInfo.processInfo.environment["LIVE_KITSU"] == "1"
    }

    @Test func publicCatalogEndpoints() async throws {
        guard isEnabled else { return }
        let repository = KitsuMediaRepository(cache: MetadataCache(directory: nil))

        let popular = try await repository.popular(page: 0)
        #expect(!popular.isEmpty)
        #expect(popular.allSatisfy { !$0.id.isEmpty })

        let topRated = try await repository.topRated(page: 0)
        #expect(!topRated.isEmpty)

        let airing = try await repository.currentlyAiring(page: 0)
        #expect(!airing.isEmpty)
        #expect(airing.allSatisfy { $0.status == .current })

        let upcoming = try await repository.upcoming(page: 0)
        #expect(!upcoming.isEmpty)

        let recent = try await repository.recentlyReleased(page: 0)
        #expect(!recent.isEmpty)

        let search = try await repository.search(query: "frieren", page: 0)
        #expect(!search.isEmpty)
    }

    @Test func detailsRelationsAndMappings() async throws {
        guard isEnabled else { return }
        let repository = KitsuMediaRepository(cache: MetadataCache(directory: nil))

        let details = try await repository.anime(id: "7442")
        #expect(details.anime.id == "7442")
        #expect(details.anime.episodeCount == 25)
        #expect(!details.anime.genres.isEmpty)
        #expect(details.relations.contains { $0.role == .sequel })

        let resolver = MediaIdentityResolver(cache: MetadataCache(directory: nil))
        let identity = await resolver.resolve(
            details.anime.identity,
            for: [.mal, .anilist]
        )
        #expect(identity.malID != nil)
    }

    @Test func episodesPaginateLive() async throws {
        guard isEnabled else { return }
        let repository = KitsuEpisodeRepository(cache: MetadataCache(directory: nil))

        let episodes = try await repository.episodes(forAnimeID: "7442")
        #expect(episodes.count == 25)
        #expect(episodes.map(\.number) == Array(1...25))
        #expect(episodes.first?.title != nil)
        #expect(episodes.first?.seasonNumber == 1)
    }
}
