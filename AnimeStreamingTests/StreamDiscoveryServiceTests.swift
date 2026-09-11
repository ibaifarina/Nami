import Foundation
import Testing
@testable import AnimeStreaming

struct StreamDiscoveryServiceTests {
    private let media = MediaIdentity(kitsuID: "46474", malID: 52991)
    private let episode = Episode(id: "46474-7", animeID: "46474", number: 7, durationMinutes: 24)

    private func streamsJSON(_ streams: [(title: String, hash: String?)]) -> Data {
        let items = streams.map { stream -> String in
            var fields = ["\"title\":\"\(stream.title)\"", "\"sizeBytes\":1400000000", "\"seeders\":50"]
            if let hash = stream.hash {
                fields.append("\"infoHash\":\"\(hash)\"")
            } else {
                fields.append("\"url\":\"https://cdn.example/video.mp4\"")
            }
            return "{\(fields.joined(separator: ","))}"
        }
        return Data("{\"streams\":[\(items.joined(separator: ","))]}".utf8)
    }

    private func request(
        addons: [InstalledAddon],
        options: StreamScoringOptions = StreamScoringOptions(),
        titles: [String] = ["Sousou no Frieren", "Frieren: Beyond Journey's End"]
    ) -> StreamDiscoveryService.Request {
        StreamDiscoveryService.Request(
            media: media,
            episode: episode,
            animeTitles: titles,
            totalEpisodes: 28,
            durationMinutes: 24,
            addons: addons,
            options: options
        )
    }

    @Test func pipelineNormalizesDeduplicatesAndScores() async {
        let hashA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let hashB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

        let http = MockHTTPClient { request in
            switch request.url?.host {
            case "one.example":
                return self.streamsJSON([
                    ("Sousou no Frieren - 07 [1080p] BluRay HEVC", hashA),
                    ("Sousou no Frieren - 07 [720p] WEBRip AVC", hashB),
                ])
            case "two.example":
                return self.streamsJSON([
                    ("[Group] Sousou no Frieren - 07 [1080p][HEVC][BluRay]", hashA),
                ])
            default:
                throw HTTPError.transport("unexpected host")
            }
        }

        let debrid = StubDebridService()
        await debrid.configure(availability: [hashA: .cached, hashB: .notCached])

        let service = StreamDiscoveryService(
            addonManager: AddonManager(http: http),
            debrid: debrid
        )
        let result = await service.discover(
            request(addons: [
                AddonFixtures.addon(id: "one", baseURL: testURL("https://one.example"), priority: 0),
                AddonFixtures.addon(id: "two", baseURL: testURL("https://two.example"), priority: 1),
            ])
        )

        #expect(result.decision.shouldAutoPlay)
        #expect(result.decision.candidate?.id == hashA)
        #expect(result.decision.candidate?.debridStatus == .cached)

        let top = result.ranked.first
        #expect(top?.candidate.id == hashA)
        #expect(top?.candidate.sources.count == 2)
        #expect(result.ranked.count == 2)
    }

    @Test func failingAddonDoesNotBreakOtherResults() async {
        let hash = "cccccccccccccccccccccccccccccccccccccccc"

        let http = MockHTTPClient { request in
            switch request.url?.host {
            case "one.example":
                return self.streamsJSON([("Sousou no Frieren - 07 [1080p] BluRay HEVC", hash)])
            case "fail.example":
                throw HTTPError.transport("boom")
            default:
                throw HTTPError.transport("unexpected host")
            }
        }

        let service = StreamDiscoveryService(
            addonManager: AddonManager(http: http),
            debrid: StubDebridService()
        )
        let result = await service.discover(
            request(addons: [
                AddonFixtures.addon(id: "one", baseURL: testURL("https://one.example"), priority: 0),
                AddonFixtures.addon(id: "fail", baseURL: testURL("https://fail.example"), priority: 1),
            ])
        )

        #expect(result.ranked.count == 1)
        #expect(result.failedAddons.count == 1)
        #expect(result.decision.candidate?.id == hash)
    }

    @Test func withoutDebridTorrentCandidatesAreIneligible() async {
        let hash = "dddddddddddddddddddddddddddddddddddddddd"

        let http = MockHTTPClient { _ in
            self.streamsJSON([
                ("Sousou no Frieren - 07 [1080p] BluRay HEVC", hash),
                ("Sousou no Frieren - 07 [720p] WEB mp4", nil),
            ])
        }

        let service = StreamDiscoveryService(
            addonManager: AddonManager(http: http),
            debrid: nil
        )
        let result = await service.discover(
            request(addons: [
                AddonFixtures.addon(id: "one", baseURL: testURL("https://one.example"), priority: 0),
            ])
        )

        #expect(result.debridAvailable == false)
        #expect(result.decision.candidate?.directURL != nil)
        let torrent = result.ranked.first { $0.candidate.infoHash != nil }
        #expect(torrent?.isAutoEligible == false)
        #expect(torrent?.rejectionReasons.contains("Real-Debrid isn't connected") == true)
    }

    @Test func unconfiguredDebridMarksCandidatesUnknown() async {
        let hash = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        let http = MockHTTPClient { _ in
            self.streamsJSON([("Sousou no Frieren - 07 [1080p] BluRay HEVC", hash)])
        }
        let debrid = StubDebridService()
        await debrid.configure(checkError: .notConfigured)

        let service = StreamDiscoveryService(
            addonManager: AddonManager(http: http),
            debrid: debrid
        )
        let result = await service.discover(
            request(addons: [
                AddonFixtures.addon(id: "one", baseURL: testURL("https://one.example"), priority: 0),
            ])
        )

        #expect(result.debridAvailable == false)
        #expect(result.ranked.first?.candidate.debridStatus == .unknown)
    }

    @Test func noAddonsYieldsEmptyResult() async {
        let service = StreamDiscoveryService(
            addonManager: AddonManager(http: MockHTTPClient()),
            debrid: nil
        )
        let result = await service.discover(request(addons: []))

        #expect(result.ranked.isEmpty)
        #expect(result.decision.candidate == nil)
        #expect(!result.decision.shouldAutoPlay)
    }
}

