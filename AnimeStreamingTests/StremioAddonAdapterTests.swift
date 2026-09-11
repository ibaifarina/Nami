import Foundation
import Testing
@testable import AnimeStreaming

struct StremioAddonAdapterTests {
    private func descriptor(
        namespaces: [AddonIDNamespace] = [.kitsu, .imdb],
        baseURL: String = "https://stremio.example"
    ) -> AddonDescriptor {
        AddonDescriptor(
            id: "org.example.stremio",
            name: "Example Stremio",
            version: "2.0.0",
            protocolType: .stremio,
            capabilities: [.streams],
            idNamespaces: namespaces,
            baseURL: testURL(baseURL),
            manifestURL: testURL("\(baseURL)/manifest.json")
        )
    }

    private let episode = Episode(id: "7442-7", animeID: "7442", number: 7)

    @Test func buildsAnimeURLAndNormalizesStreams() async throws {
        let http = MockHTTPClient { _ in AddonFixtures.stremioStreamsJSON }
        let adapter = StremioAddonAdapter(
            descriptor: descriptor(),
            supportedTypes: ["anime"],
            http: http
        )
        let media = MediaIdentity(kitsuID: "12345", anilistID: 52991)

        let results = try await adapter.streams(for: media, episode: episode)

        #expect(results.count == 2)
        let first = try #require(results.first)
        #expect(first.infoHash == "ddeeff001122")
        #expect(first.magnetURI?.absoluteString == "magnet:?xt=urn:btih:ddeeff001122")
        #expect(first.fileIndex == 2)
        #expect(first.sizeBytes == 1_400_000_000)
        #expect(first.providerName == "Torrentio")
        #expect(first.providerMetadata["bingeGroup"] == "show-1080")

        let direct = try #require(results.last)
        #expect(direct.directURL?.absoluteString == "https://example.com/a.mp4")

        let request = try #require(await http.lastRequest)
        #expect(request.url?.absoluteString == "https://stremio.example/stream/anime/kitsu:12345:7.json")
    }

    @Test func buildsSeriesURLWithSeasonOne() async throws {
        let http = MockHTTPClient { _ in AddonFixtures.stremioStreamsJSON }
        let adapter = StremioAddonAdapter(
            descriptor: descriptor(namespaces: [.imdb]),
            supportedTypes: ["series"],
            http: http
        )
        let media = MediaIdentity(kitsuID: "999", imdbID: "tt1234567")

        _ = try await adapter.streams(for: media, episode: episode)

        let request = try #require(await http.lastRequest)
        #expect(request.url?.absoluteString == "https://stremio.example/stream/series/tt1234567:1:7.json")
    }

    @Test func throwsWhenIDCannotBeResolved() async {
        let adapter = StremioAddonAdapter(
            descriptor: descriptor(namespaces: [.imdb]),
            supportedTypes: ["series"],
            http: MockHTTPClient()
        )
        let media = MediaIdentity(kitsuID: "999")

        do {
            _ = try await adapter.streams(for: media, episode: episode)
            Issue.record("Expected unresolvable ID error")
        } catch let error as AddonError {
            #expect(error == .unresolvableMediaID([.imdb]))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func resolveIDNormalizesIMDBPrefix() throws {
        let resolved = try StremioAddonAdapter.resolveID(
            for: MediaIdentity(kitsuID: "1", imdbID: "1234567"),
            namespaces: [.imdb]
        )
        #expect(resolved.value == "tt1234567")
        #expect(resolved.namespace == .imdb)
    }

    @Test func resolveIDPrefersDeclaredNamespaceOrder() throws {
        let resolved = try StremioAddonAdapter.resolveID(
            for: MediaIdentity(kitsuID: "99", malID: 5114, anilistID: 1),
            namespaces: [.kitsu, .mal]
        )
        #expect(resolved.value == "kitsu:99")
    }

    @Test func identifierFormats() {
        #expect(
            StremioAddonAdapter.identifier(
                id: "kitsu:1", type: "anime", episodeNumber: 7, seasonNumber: 2
            ) == "kitsu:1:7"
        )
        #expect(
            StremioAddonAdapter.identifier(
                id: "tt1", type: "series", episodeNumber: 7, seasonNumber: 2
            ) == "tt1:2:7"
        )
        #expect(
            StremioAddonAdapter.identifier(
                id: "tt1", type: "movie", episodeNumber: 1, seasonNumber: 1
            ) == "tt1"
        )
    }

    @Test func healthCheckReportsHealthy() async {
        let adapter = StremioAddonAdapter(
            descriptor: descriptor(),
            supportedTypes: ["anime"],
            http: MockHTTPClient { _ in AddonFixtures.stremioManifestJSON }
        )

        #expect(await adapter.healthCheck() == .healthy)
    }
}
