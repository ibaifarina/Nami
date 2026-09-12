import Foundation
import Testing
@testable import Nami

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

    @Test func usesBehaviorHintsFilenameWhenTitleIsMissing() async throws {
        let http = MockHTTPClient { _ in AddonFixtures.filenameOnlyStreamsJSON }
        let adapter = StremioAddonAdapter(
            descriptor: descriptor(namespaces: [.imdb]),
            supportedTypes: ["movie", "series", "anime"],
            http: http
        )
        let media = MediaIdentity(kitsuID: "46474", imdbID: "tt22248376")

        let results = try await adapter.streams(for: media, episode: episode)

        let first = try #require(results.first)
        #expect(
            first.rawTitle
                == "Frieren Beyond Journey's End - S01E01 (BD Remux 1080p AVC FLAC AAC) [Dual Audio] [PMR].mkv"
        )
        #expect(first.displayTitle == first.rawTitle)
        #expect(first.sizeBytes == 7_500_699_108)
        #expect(first.directURL?.absoluteString == "https://aiostreams.example/playback/abc123")
        #expect(first.providerName == "1080P  \u{26A1}  \u{2605}\u{2605}\u{2605}\u{2605}\u{2605}")
    }

    @Test func filenameOnlyStreamsPassEpisodeMatching() async throws {
        let http = MockHTTPClient { _ in AddonFixtures.filenameOnlyStreamsJSON }
        let adapter = StremioAddonAdapter(
            descriptor: descriptor(namespaces: [.imdb]),
            supportedTypes: ["movie", "series", "anime"],
            http: http
        )
        let media = MediaIdentity(kitsuID: "46474", imdbID: "tt22248376")
        let episode = Episode(id: "46474-1", animeID: "46474", number: 1)

        let results = try await adapter.streams(for: media, episode: episode)
        let raw = try #require(results.first)
        let candidate = StreamNormalizer().normalize(
            raw,
            matching: EpisodeMatcher.Context(
                requestedEpisode: 1,
                animeTitles: ["Frieren: Beyond Journey's End", "Sousou no Frieren"]
            )
        )

        #expect(candidate.episodeMatchConfidence >= EpisodeMatchResult.safeForAutoSelectionThreshold)
        #expect(candidate.parsedEpisode?.episode == 1)
    }

    @Test func usesSeriesTypeForIMDbIDsEvenWhenAnimeIsDeclared() async throws {
        let http = MockHTTPClient { _ in AddonFixtures.stremioStreamsJSON }
        let adapter = StremioAddonAdapter(
            descriptor: descriptor(namespaces: [.imdb, .kitsu]),
            supportedTypes: ["movie", "series", "anime"],
            http: http
        )
        let media = MediaIdentity(kitsuID: "999", imdbID: "tt1234567")

        _ = try await adapter.streams(for: media, episode: episode)

        let request = try #require(await http.lastRequest)
        #expect(request.url?.absoluteString == "https://stremio.example/stream/series/tt1234567:1:7.json")
    }

    @Test func fallsBackToKitsuWhenIMDbRouteHasNoStreams() async throws {
        let http = MockHTTPClient { request in
            if request.url?.path.contains("/stream/series/tt39287518:1:1.json") == true {
                return Data(#"{ "streams": [] }"#.utf8)
            }
            if request.url?.path.contains("/stream/anime/kitsu:49998:1.json") == true {
                return AddonFixtures.stremioStreamsJSON
            }
            throw HTTPError.transport("unexpected route")
        }
        let adapter = StremioAddonAdapter(
            descriptor: descriptor(namespaces: [.imdb, .kitsu]),
            supportedTypes: ["movie", "series", "anime"],
            http: http
        )
        let media = MediaIdentity(
            kitsuID: "49998",
            imdbID: "tt39287518"
        )
        let episode = Episode(id: "49998-1", animeID: "49998", number: 1)

        let results = try await adapter.streams(for: media, episode: episode)

        #expect(results.count == 2)
        #expect(await http.requestCount == 2)
        #expect(
            await http.lastRequest?.url?.absoluteString
                == "https://stremio.example/stream/anime/kitsu:49998:1.json"
        )
    }

    @Test func usesMovieTypeForMovies() async throws {
        let http = MockHTTPClient { _ in AddonFixtures.stremioStreamsJSON }
        let adapter = StremioAddonAdapter(
            descriptor: descriptor(namespaces: [.imdb]),
            supportedTypes: ["movie", "series"],
            http: http
        )
        let media = MediaIdentity(kitsuID: "999", imdbID: "tt1234567")

        _ = try await adapter.streams(for: media, episode: episode, isMovie: true)

        let request = try #require(await http.lastRequest)
        #expect(request.url?.absoluteString == "https://stremio.example/stream/movie/tt1234567.json")
    }

    @Test func streamTypeSelection() {
        #expect(
            StremioAddonAdapter.streamType(
                namespace: .imdb,
                isMovie: false,
                supportedTypes: ["movie", "series", "anime"]
            ) == "series"
        )
        #expect(
            StremioAddonAdapter.streamType(
                namespace: .kitsu,
                isMovie: false,
                supportedTypes: ["movie", "series", "anime"]
            ) == "anime"
        )
        #expect(
            StremioAddonAdapter.streamType(
                namespace: .mal,
                isMovie: false,
                supportedTypes: ["movie", "series"]
            ) == "series"
        )
        #expect(
            StremioAddonAdapter.streamType(
                namespace: .kitsu,
                isMovie: true,
                supportedTypes: ["movie", "series", "anime"]
            ) == "movie"
        )
        #expect(
            StremioAddonAdapter.streamType(
                namespace: .kitsu,
                isMovie: false,
                supportedTypes: ["anime"]
            ) == "anime"
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
