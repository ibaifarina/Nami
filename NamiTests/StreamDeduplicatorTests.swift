import Foundation
import Testing
@testable import Nami

struct StreamDeduplicatorTests {
    private let deduplicator = StreamDeduplicator()

    private func candidate(
        title: String,
        infoHash: String? = nil,
        magnet: String? = nil,
        url: String? = nil,
        resolution: VideoResolution? = nil,
        codec: VideoCodec? = nil,
        size: Int64? = nil,
        seeders: Int? = nil,
        episode: Int? = nil,
        isBatch: Bool = false,
        debridStatus: DebridAvailability = .unknown,
        addonID: String,
        addonName: String? = nil
    ) -> StreamCandidate {
        StreamCandidate(
            id: infoHash ?? url ?? title,
            addonID: addonID,
            addonName: addonName ?? addonID,
            displayTitle: title,
            rawTitle: title,
            infoHash: infoHash,
            magnetURI: magnet.flatMap { URL(string: $0) },
            directURL: url.flatMap { URL(string: $0) },
            resolution: resolution,
            codec: codec,
            sizeBytes: size,
            seeders: seeders,
            parsedEpisode: episode.map { ParsedEpisodeInfo(season: nil, episode: $0, isBatch: isBatch, isSpecial: false) },
            isBatch: isBatch,
            debridStatus: debridStatus
        )
    }

    @Test func mergesSameInfoHashAcrossAddons() {
        let first = candidate(
            title: "[Group] Frieren - 07 [1080p]",
            infoHash: "AABBCCDDEEFF0011",
            resolution: .p1080,
            size: 1_000,
            seeders: 5,
            episode: 7,
            addonID: "one",
            addonName: "Addon One"
        )
        let second = candidate(
            title: "[Group] Frieren - 07 [1080p]",
            infoHash: "aabbccddeeff0011",
            codec: .hevc,
            seeders: 20,
            episode: 7,
            addonID: "two",
            addonName: "Addon Two"
        )

        let outcome = deduplicator.deduplicate([first, second])

        #expect(outcome.candidates.count == 1)
        #expect(outcome.duplicateCount == 1)
        let merged = outcome.candidates[0]
        #expect(merged.sources.map(\.addonName) == ["Addon One", "Addon Two"])
        #expect(merged.resolution == .p1080)
        #expect(merged.codec == .hevc)
        #expect(merged.sizeBytes == 1_000)
        #expect(merged.seeders == 20)
    }

    @Test func mergesMagnetHashWithInfoHash() {
        let first = candidate(
            title: "Show - 07",
            infoHash: "ddeeff0011223344",
            episode: 7,
            addonID: "one"
        )
        let second = candidate(
            title: "Show - 07 [Torrent]",
            magnet: "magnet:?xt=urn:btih:DDEEFF0011223344&dn=Show",
            episode: 7,
            addonID: "two"
        )

        let outcome = deduplicator.deduplicate([first, second])

        #expect(outcome.candidates.count == 1)
        #expect(outcome.candidates[0].sources.count == 2)
    }

    @Test func mergesDirectURLsCaseInsensitively() {
        let first = candidate(title: "Direct A", url: "https://EXAMPLE.com/a.mp4", addonID: "one")
        let second = candidate(title: "Direct B", url: "https://example.com/a.mp4", addonID: "two")

        let outcome = deduplicator.deduplicate([first, second])

        #expect(outcome.candidates.count == 1)
    }

    @Test func mergesByTitleSizeAndEpisodeFallback() {
        let first = candidate(
            title: "[Group] Frieren - 07 [1080p]",
            size: 1_400_000_000,
            episode: 7,
            addonID: "one"
        )
        let second = candidate(
            title: "[Group] Frieren - 07 [1080p]",
            size: 1_400_000_000,
            episode: 7,
            addonID: "two"
        )

        let outcome = deduplicator.deduplicate([first, second])

        #expect(outcome.candidates.count == 1)
        #expect(outcome.candidates[0].sources.count == 2)
    }

    @Test func differentFallbackEpisodeIsNotDuplicate() {
        let first = candidate(title: "[Group] Frieren - 07 [1080p]", size: 1_400, episode: 7, addonID: "one")
        let second = candidate(title: "[Group] Frieren - 08 [1080p]", size: 1_400, episode: 8, addonID: "two")

        let outcome = deduplicator.deduplicate([first, second])

        #expect(outcome.candidates.count == 2)
        #expect(outcome.duplicateCount == 0)
    }

    @Test func differentFallbackSizeIsNotDuplicate() {
        let first = candidate(title: "[Group] Frieren - 07 [1080p]", size: 1_400, episode: 7, addonID: "one")
        let second = candidate(title: "[Group] Frieren - 07 [1080p]", size: 2_800, episode: 7, addonID: "two")

        let outcome = deduplicator.deduplicate([first, second])

        #expect(outcome.candidates.count == 2)
    }

    @Test func distinctCandidatesArePreservedInOrder() {
        let first = candidate(title: "A - 07", infoHash: "1111111111111111", addonID: "one")
        let second = candidate(title: "B - 07", infoHash: "2222222222222222", addonID: "one")
        let third = candidate(title: "C - 07", infoHash: "3333333333333333", addonID: "two")

        let outcome = deduplicator.deduplicate([first, second, third])

        #expect(outcome.candidates.map(\.rawTitle) == ["A - 07", "B - 07", "C - 07"])
        #expect(outcome.duplicateCount == 0)
    }

    @Test func mergePrefersCachedDebridStatusAndFillsDirectURL() {
        let first = candidate(
            title: "Show - 07",
            infoHash: "abcdefabcdefabcd",
            episode: 7,
            debridStatus: .unknown,
            addonID: "one"
        )
        let second = candidate(
            title: "Show - 07",
            infoHash: "abcdefabcdefabcd",
            url: "https://example.com/stream.mp4",
            episode: 7,
            debridStatus: .cached,
            addonID: "two"
        )

        let outcome = deduplicator.deduplicate([first, second])

        #expect(outcome.candidates.count == 1)
        #expect(outcome.candidates[0].debridStatus == .cached)
        #expect(outcome.candidates[0].directURL?.absoluteString == "https://example.com/stream.mp4")
    }

    @Test func ignoresInvalidHashesForDedupe() {
        let first = candidate(title: "Show - 07", infoHash: "xyz", addonID: "one")
        let second = candidate(title: "Show - 07", infoHash: "xyz", addonID: "two")

        let outcome = deduplicator.deduplicate([first, second])

        #expect(outcome.candidates.count == 1)
    }

    @Test func magnetHashExtraction() {
        #expect(
            StreamDeduplicator.hash(fromMagnet: "magnet:?xt=urn:btih:ABCDEF1234567890&dn=x")
                == "abcdef1234567890"
        )
        #expect(StreamDeduplicator.hash(fromMagnet: "magnet:?dn=x") == nil)
    }
}
