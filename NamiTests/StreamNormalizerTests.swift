import Foundation
import Testing
@testable import Nami

struct StreamNormalizerTests {
    private let normalizer = StreamNormalizer()

    private func raw(
        title: String,
        infoHash: String? = nil,
        magnet: String? = "magnet:?xt=urn:btih:00112233445566778899aabbccddeeff00112233",
        url: String? = nil,
        size: Int64? = nil,
        seeders: Int? = nil,
        audio: String? = nil,
        subtitles: String? = nil,
        provider: String? = nil,
        addonID: String = "sample.sources",
        addonName: String = "Sample Sources"
    ) -> RawStreamResult {
        var metadata: [String: String] = [:]
        if let audio { metadata["audio"] = audio }
        if let subtitles { metadata["subtitles"] = subtitles }
        return RawStreamResult(
            addonID: addonID,
            addonName: addonName,
            displayTitle: title,
            rawTitle: title,
            infoHash: infoHash,
            magnetURI: magnet.flatMap { URL(string: $0) },
            directURL: url.flatMap { URL(string: $0) },
            sizeBytes: size,
            seeders: seeders,
            providerName: provider,
            providerMetadata: metadata
        )
    }

    @Test func mapsRawResultToCandidate() {
        let candidate = normalizer.normalize(
            raw(
                title: "[SubsPlease] Sousou no Frieren - 07 [1080p][HEVC].mkv",
                infoHash: "AABBCCDDEEFF00112233445566778899AABBCCDD",
                size: 1_450_000_000,
                seeders: 42
            )
        )

        #expect(candidate.id == "aabbccddeeff00112233445566778899aabbccdd")
        #expect(candidate.infoHash == "aabbccddeeff00112233445566778899aabbccdd")
        #expect(candidate.resolution == .p1080)
        #expect(candidate.codec == .hevc)
        #expect(candidate.releaseGroup == "SubsPlease")
        #expect(candidate.parsedEpisode?.episode == 7)
        #expect(candidate.isBatch == false)
        #expect(candidate.sizeBytes == 1_450_000_000)
        #expect(candidate.seeders == 42)
        #expect(candidate.sources.map(\.addonName) == ["Sample Sources"])
        #expect(candidate.episodeMatchConfidence == 0)
    }

    @Test func appliesEpisodeMatching() {
        let context = EpisodeMatcher.Context(
            requestedEpisode: 7,
            totalEpisodes: 28,
            animeTitles: ["Sousou no Frieren", "Frieren: Beyond Journey's End"]
        )

        let candidate = normalizer.normalize(
            raw(title: "[SubsPlease] Sousou no Frieren - 07 [1080p][HEVC].mkv"),
            matching: context
        )

        #expect(candidate.episodeMatchConfidence >= 0.95)
        #expect(candidate.parsedEpisode?.episode == 7)
    }

    @Test func marksBatchCandidates() {
        let candidate = normalizer.normalize(
            raw(title: "[Group] Sousou no Frieren 01-12 [1080p]")
        )

        #expect(candidate.isBatch)
        #expect(candidate.parsedEpisode?.isBatch == true)
        #expect(candidate.parsedEpisode?.episode == nil)
    }

    @Test func mergesLanguagesFromTitleAndProvider() {
        let candidate = normalizer.normalize(
            raw(
                title: "[Group] Show - 07 [1080p] Dual Audio",
                audio: "Japanese, English",
                subtitles: "English, Spanish"
            )
        )

        #expect(candidate.audioLanguages == ["japanese", "english"])
        #expect(candidate.subtitleLanguages == ["english", "spanish"])
    }

    @Test func fallsBackToDirectURLAsIdentity() {
        let candidate = normalizer.normalize(
            raw(title: "Direct stream", magnet: nil, url: "https://example.com/stream.mp4")
        )

        #expect(candidate.id == "https://example.com/stream.mp4")
        #expect(candidate.directURL?.absoluteString == "https://example.com/stream.mp4")
    }

    @Test func preservesProviderName() {
        let candidate = normalizer.normalize(
            raw(title: "Show - 07", provider: "Torrentio")
        )

        #expect(candidate.rawTitle == "Show - 07")
    }

    @Test func fallsBackToSizeFromTitle() {
        let candidate = normalizer.normalize(
            raw(title: "[SubsPlease] Sousou no Frieren - 07 [1080p][1.4 GB].mkv")
        )

        #expect(candidate.sizeBytes == 1_400_000_000)
    }

    @Test func addonProvidedSizeWinsOverTitle() {
        let candidate = normalizer.normalize(
            raw(title: "Show - 07 [1.4 GB]", size: 2_000_000_000)
        )

        #expect(candidate.sizeBytes == 2_000_000_000)
    }

    @Test func fallsBackToSeedersFromTitle() {
        let candidate = normalizer.normalize(
            raw(title: "Show - 07 1080p\n\u{1F464} 142 \u{1F4BE} 2.1 GB")
        )

        #expect(candidate.seeders == 142)
        #expect(candidate.sizeBytes == 2_100_000_000)
    }

    @Test func addonProvidedSeedersWinOverTitle() {
        let candidate = normalizer.normalize(
            raw(title: "Show - 07\n\u{1F464} 142", seeders: 12)
        )

        #expect(candidate.seeders == 12)
    }

    @Test func normalizesMultipleRawResults() {
        let context = EpisodeMatcher.Context(requestedEpisode: 7, animeTitles: ["Show"])
        let candidates = normalizer.normalize(
            [raw(title: "Show - 07"), raw(title: "Show - 08")],
            matching: context
        )

        #expect(candidates.count == 2)
        #expect(candidates[0].episodeMatchConfidence > candidates[1].episodeMatchConfidence)
    }
}
