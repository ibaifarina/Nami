import Foundation
import Testing
@testable import Nami

struct IMDbResolverTests {
    private static let tvmazeHit = Data("""
    { "externals": { "imdb": "tt2560140" } }
    """.utf8)

    private static let tvmazeMiss = Data("""
    { "externals": { "imdb": null } }
    """.utf8)

    private static let cinemetaFrieren = Data("""
    {
      "metas": [
        {
          "id": "tt34754926",
          "type": "series",
          "name": "Frieren: Beyond Journey's End Original Mini-Anime - Magic of ??",
          "releaseInfo": "2023-2026"
        },
        {
          "id": "tt22248376",
          "type": "series",
          "name": "Frieren: Beyond Journey's End",
          "releaseInfo": "2023-"
        },
        {
          "id": "tt99999999",
          "type": "series",
          "name": "Parade's End",
          "releaseInfo": "2012"
        }
      ]
    }
    """.utf8)

    private func resolver(http: MockHTTPClient) -> IMDbResolver {
        IMDbResolver(http: http, cache: MetadataCache(directory: nil))
    }

    @Test func resolvesExactIMDbFromTVmazeLookup() async {
        let http = MockHTTPClient { request in
            #expect(request.url?.host == "api.tvmaze.com")
            #expect(request.url?.query?.contains("thetvdb=267440") == true)
            return Self.tvmazeHit
        }

        let result = await resolver(http: http).imdbID(
            kitsuID: "7442",
            theTVDBID: "267440",
            context: .init()
        )

        #expect(result == "tt2560140")
        #expect(await http.requestCount == 1)
    }

    @Test func fallsBackToRankedCinemetaSearch() async {
        let http = MockHTTPClient { request in
            switch request.url?.host {
            case "api.tvmaze.com":
                return Self.tvmazeMiss
            case "v3-cinemeta.strem.io":
                #expect(request.url?.path.contains("/catalog/series/top/") == true)
                return Self.cinemetaFrieren
            default:
                throw HTTPError.transport("unexpected host")
            }
        }

        let result = await resolver(http: http).imdbID(
            kitsuID: "46474",
            theTVDBID: "111",
            context: .init(
                titles: ["Frieren: Beyond Journey's End", "Sousou no Frieren"],
                year: 2023,
                isMovie: false
            )
        )

        #expect(result == "tt22248376")
    }

    @Test func searchesMoviesUnderTheMovieCatalog() async {
        let http = MockHTTPClient { request in
            guard request.url?.host == "v3-cinemeta.strem.io" else {
                return Data("{}".utf8)
            }
            #expect(request.url?.path.contains("/catalog/movie/top/") == true)
            return Data("""
            { "metas": [
                { "id": "tt5311514", "name": "Your Name.", "releaseInfo": "2016" },
                { "id": "tt1954577", "name": "What Is Your Name?", "releaseInfo": "1953" }
            ] }
            """.utf8)
        }

        let result = await resolver(http: http).imdbID(
            kitsuID: "11614",
            theTVDBID: nil,
            context: .init(titles: ["Your Name.", "Kimi no Na wa."], year: 2016, isMovie: true)
        )

        #expect(result == "tt5311514")
    }

    @Test func cachesResolvedIdentifiers() async {
        let http = MockHTTPClient { _ in Self.tvmazeHit }
        let resolver = resolver(http: http)

        _ = await resolver.imdbID(kitsuID: "7442", theTVDBID: "267440", context: .init())
        _ = await resolver.imdbID(kitsuID: "7442", theTVDBID: "267440", context: .init())

        #expect(await http.requestCount == 1)
    }

    @Test func cachesMissesForUnresolvedAnime() async {
        let http = MockHTTPClient { request in
            switch request.url?.host {
            case "api.tvmaze.com":
                return Self.tvmazeMiss
            case "v3-cinemeta.strem.io":
                return Data("""
                { "metas": [
                    { "id": "tt0100000", "name": "Totally Different Show", "releaseInfo": "1998" }
                ] }
                """.utf8)
            default:
                throw HTTPError.transport("unexpected host")
            }
        }
        let resolver = resolver(http: http)

        let first = await resolver.imdbID(
            kitsuID: "999",
            theTVDBID: "1",
            context: .init(titles: ["Unknown Show"], year: 2024, isMovie: false)
        )
        let second = await resolver.imdbID(
            kitsuID: "999",
            theTVDBID: "1",
            context: .init(titles: ["Unknown Show"], year: 2024, isMovie: false)
        )

        #expect(first == nil)
        #expect(second == nil)
        // One TVmaze request and one Cinemeta request, then cached.
        #expect(await http.requestCount == 2)
    }

    @Test func validatesIMDbIdentifiers() {
        #expect(IMDbResolver.validated("tt2560140") == "tt2560140")
        #expect(IMDbResolver.validated("TT2560140") == "tt2560140")
        #expect(IMDbResolver.validated(" 2560140 ") == nil)
        #expect(IMDbResolver.validated("ttabc") == nil)
        #expect(IMDbResolver.validated(nil) == nil)
    }

    @Test func matchScorePrefersExactTitleWithMatchingYear() {
        let exact = IMDbResolver.matchScore(
            candidate: "Frieren: Beyond Journey's End",
            releaseInfo: "2023-",
            titles: ["Frieren: Beyond Journey's End"],
            year: 2023
        )
        let prefix = IMDbResolver.matchScore(
            candidate: "Frieren: Beyond Journey's End Original Mini-Anime",
            releaseInfo: "2023-2026",
            titles: ["Frieren: Beyond Journey's End"],
            year: 2023
        )
        let wrongYear = IMDbResolver.matchScore(
            candidate: "Frieren: Beyond Journey's End",
            releaseInfo: "1990-",
            titles: ["Frieren: Beyond Journey's End"],
            year: 2023
        )

        #expect(exact > prefix)
        #expect(exact > wrongYear)
    }
}
