import Foundation
import Testing
@testable import Nami

struct AddonManagerTests {
    private let media = MediaIdentity(kitsuID: "7442", malID: 16498)
    private let episode = Episode(id: "7442-7", animeID: "7442", number: 7)

    private func routingHandler() -> MockHTTPClient.Handler {
        { request in
            guard let host = request.url?.host else {
                throw HTTPError.transport("missing host")
            }
            let isManifest = request.url?.path.hasSuffix("manifest.json") == true
            switch host {
            case "slow.example":
                try await Task.sleep(for: .milliseconds(400))
                return isManifest ? AddonFixtures.genericManifestJSON : AddonFixtures.genericStreamsJSON
            case "fail.example":
                throw HTTPError.transport("boom")
            default:
                return isManifest ? AddonFixtures.genericManifestJSON : AddonFixtures.genericStreamsJSON
            }
        }
    }

    @Test func queriesAllEnabledAddons() async {
        let manager = AddonManager(http: MockHTTPClient(handler: routingHandler()))
        let addons = [
            AddonFixtures.addon(id: "a", baseURL: testURL("https://a.example"), priority: 0),
            AddonFixtures.addon(id: "b", baseURL: testURL("https://b.example"), priority: 1),
        ]

        let results = await manager.queryStreams(
            for: media,
            episode: episode,
            addons: addons,
            timeout: .seconds(2)
        )

        #expect(results.count == 2)
        #expect(results.map(\.addon.id) == ["a", "b"])
        #expect(results.allSatisfy { $0.streams.count == 3 })
    }

    @Test func isolatesFailuresAndTimeouts() async {
        let manager = AddonManager(
            http: MockHTTPClient(handler: routingHandler()),
            healthTimeout: .milliseconds(40)
        )
        let addons = [
            AddonFixtures.addon(id: "ok", baseURL: testURL("https://ok.example"), priority: 0),
            AddonFixtures.addon(id: "fail", baseURL: testURL("https://fail.example"), priority: 1),
            AddonFixtures.addon(id: "slow", baseURL: testURL("https://slow.example"), priority: 2),
        ]

        let results = await manager.queryStreams(
            for: media,
            episode: episode,
            addons: addons,
            timeout: .milliseconds(80)
        )

        #expect(results.count == 3)

        let ok = results.first { $0.addon.id == "ok" }
        #expect(ok?.streams.count == 3)

        let failed = results.first { $0.addon.id == "fail" }
        #expect(failed?.failureMessage != nil)

        let timedOut = results.first { $0.addon.id == "slow" }
        if case .timedOut = timedOut?.outcome {
        } else {
            Issue.record("Expected slow addon to time out")
        }
    }

    @Test func skipsDisabledAddons() async {
        let manager = AddonManager(http: MockHTTPClient(handler: routingHandler()))
        let addons = [
            AddonFixtures.addon(id: "on", baseURL: testURL("https://a.example"), priority: 0),
            AddonFixtures.addon(id: "off", baseURL: testURL("https://b.example"), priority: 1, isEnabled: false),
        ]

        let results = await manager.queryStreams(
            for: media,
            episode: episode,
            addons: addons,
            timeout: .seconds(2)
        )

        #expect(results.map(\.addon.id) == ["on"])
    }

    @Test func returnsEmptyForNoAddons() async {
        let manager = AddonManager(http: MockHTTPClient())

        let results = await manager.queryStreams(
            for: media,
            episode: episode,
            addons: [],
            timeout: .seconds(1)
        )

        #expect(results.isEmpty)
    }

    @Test func unsupportedProtocolFailsGracefully() async {
        let manager = AddonManager(http: MockHTTPClient(handler: routingHandler()))
        let addons = [
            AddonFixtures.addon(
                id: "generic",
                baseURL: testURL("https://g.example"),
                protocolType: .generic
            ),
        ]

        let results = await manager.queryStreams(
            for: media,
            episode: episode,
            addons: addons,
            timeout: .seconds(1)
        )

        #expect(results.count == 1)
        #expect(results.first?.failureMessage?.contains("not supported") == true)
    }

    @Test func resolvesIMDbForAddonsThatRequireIt() async {
        let http = MockHTTPClient { request in
            switch request.url?.host {
            case "kitsu.io":
                return KitsuFixtures.mappingsJSON
            case "api.tvmaze.com":
                return Data("""
                { "externals": { "imdb": "tt2560140" } }
                """.utf8)
            case "stremio.example":
                return AddonFixtures.stremioStreamsJSON
            default:
                throw HTTPError.transport("unexpected host \(request.url?.host ?? "nil")")
            }
        }
        let resolver = MediaIdentityResolver(
            client: KitsuClient(http: http),
            cache: MetadataCache(directory: nil),
            imdbResolver: IMDbResolver(http: http, cache: MetadataCache(directory: nil))
        )
        let manager = AddonManager(http: http, identityResolver: resolver)
        let addon = InstalledAddon(
            id: "com.stremio.thepiratebay.plus",
            name: "ThePirateBay+",
            manifestURL: testURL("https://stremio.example/manifest.json"),
            baseURL: testURL("https://stremio.example"),
            protocolType: .stremio,
            priority: 0,
            idNamespaces: [.imdb],
            supportedTypes: ["movie", "series"]
        )

        let results = await manager.queryStreams(
            for: MediaIdentity(kitsuID: "7442"),
            episode: Episode(id: "7442-7", animeID: "7442", number: 7),
            titles: ["Attack on Titan"],
            year: 2013,
            addons: [addon],
            timeout: .seconds(2)
        )

        #expect(results.first?.streams.count == 2)
        #expect(
            await http.lastRequest?.url?.absoluteString
                == "https://stremio.example/stream/series/tt2560140:1:7.json"
        )
    }

    @Test func fallsBackToDefaultNamespacesForStaleInstalls() async {
        let http = MockHTTPClient { request in
            switch request.url?.host {
            case "kitsu.io":
                return KitsuFixtures.mappingsJSON
            case "api.tvmaze.com":
                return Data("""
                { "externals": { "imdb": "tt2560140" } }
                """.utf8)
            case "stremio.example":
                return AddonFixtures.stremioStreamsJSON
            default:
                throw HTTPError.transport("unexpected host \(request.url?.host ?? "nil")")
            }
        }
        let resolver = MediaIdentityResolver(
            client: KitsuClient(http: http),
            cache: MetadataCache(directory: nil),
            imdbResolver: IMDbResolver(http: http, cache: MetadataCache(directory: nil))
        )
        let manager = AddonManager(http: http, identityResolver: resolver)
        let addon = InstalledAddon(
            id: "stale.stremio.addon",
            name: "Stale Stremio",
            manifestURL: testURL("https://stremio.example/manifest.json"),
            baseURL: testURL("https://stremio.example"),
            protocolType: .stremio,
            priority: 0,
            idNamespaces: [],
            supportedTypes: ["movie", "series"]
        )

        let results = await manager.queryStreams(
            for: MediaIdentity(kitsuID: "7442"),
            episode: Episode(id: "7442-7", animeID: "7442", number: 7),
            titles: ["Attack on Titan"],
            addons: [addon],
            timeout: .seconds(2)
        )

        #expect(results.first?.streams.count == 2)
        #expect(
            await http.lastRequest?.url?.absoluteString
                == "https://stremio.example/stream/series/tt2560140:1:7.json"
        )
    }

    @Test func effectiveNamespacesFallBackByProtocol() {
        let stremio = AddonFixtures.addon(
            id: "s",
            baseURL: testURL("https://s.example"),
            protocolType: .stremio,
            idNamespaces: []
        )
        let generic = AddonFixtures.addon(
            id: "g",
            baseURL: testURL("https://g.example"),
            idNamespaces: []
        )
        let animeStream = AddonFixtures.addon(
            id: "a",
            baseURL: testURL("https://a.example"),
            idNamespaces: []
        )

        #expect(AddonManager.effectiveNamespaces(for: stremio) == [.imdb, .kitsu])
        #expect(AddonManager.effectiveNamespaces(for: generic) == [.kitsu, .mal, .anilist])
        #expect(AddonManager.effectiveNamespaces(for: animeStream) == [.kitsu, .mal, .anilist])
    }

    @Test func healthCheckReportsStatus() async {
        let manager = AddonManager(
            http: MockHTTPClient(handler: routingHandler()),
            healthTimeout: .milliseconds(50)
        )
        let healthy = AddonFixtures.addon(id: "ok", baseURL: testURL("https://ok.example"))
        let failing = AddonFixtures.addon(id: "fail", baseURL: testURL("https://fail.example"))
        let slow = AddonFixtures.addon(id: "slow", baseURL: testURL("https://slow.example"))

        #expect(await manager.healthCheck(healthy) == .healthy)
        #expect(await manager.healthCheck(failing) == .failing)
        #expect(await manager.healthCheck(slow) == .failing)
    }

    @Test func healthCheckFailsForUnsupportedAdapter() async {
        let manager = AddonManager(http: MockHTTPClient())
        let addon = AddonFixtures.addon(
            id: "generic",
            baseURL: testURL("https://g.example"),
            protocolType: .generic
        )

        #expect(await manager.healthCheck(addon) == .failing)
    }

    @Test func healthCheckAllReportsEveryEnabledAddon() async {
        let manager = AddonManager(
            http: MockHTTPClient(handler: routingHandler()),
            healthTimeout: .milliseconds(50)
        )
        let addons = [
            AddonFixtures.addon(id: "ok", baseURL: testURL("https://ok.example"), priority: 0),
            AddonFixtures.addon(id: "fail", baseURL: testURL("https://fail.example"), priority: 1),
            AddonFixtures.addon(id: "slow", baseURL: testURL("https://slow.example"), priority: 2),
        ]

        let results = await manager.healthCheckAll(addons)

        #expect(results.count == 3)
        #expect(results["ok"] == .healthy)
        #expect(results["fail"] == .failing)
        #expect(results["slow"] == .failing)
    }

    @Test func healthCheckAllSkipsDisabledAddons() async {
        let manager = AddonManager(http: MockHTTPClient(handler: routingHandler()))
        let addons = [
            AddonFixtures.addon(id: "on", baseURL: testURL("https://ok.example"), priority: 0),
            AddonFixtures.addon(
                id: "off",
                baseURL: testURL("https://fail.example"),
                priority: 1,
                isEnabled: false
            ),
        ]

        let results = await manager.healthCheckAll(addons)

        #expect(results.count == 1)
        #expect(results["on"] == .healthy)
    }

    @Test func healthCheckAllHandlesEmptyInput() async {
        let manager = AddonManager(http: MockHTTPClient())
        let results = await manager.healthCheckAll([])
        #expect(results.isEmpty)
    }

    @Test func makeAdapterRequiresStreamsPathForGeneric() {
        let withPath = AddonFixtures.addon(id: "a", baseURL: testURL("https://a.example"))
        let withoutPath = AddonFixtures.addon(
            id: "b",
            baseURL: testURL("https://b.example"),
            streamsPath: ""
        )

        #expect(AddonManager.makeAdapter(for: withPath, http: MockHTTPClient()) != nil)
        #expect(AddonManager.makeAdapter(for: withoutPath, http: MockHTTPClient()) == nil)
    }
}
