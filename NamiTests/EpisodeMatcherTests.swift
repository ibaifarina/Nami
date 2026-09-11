import Foundation
import Testing
@testable import Nami

struct EpisodeMatcherTests {
    private let matcher = EpisodeMatcher()

    private func context(
        episode: Int,
        titles: [String] = ["Sousou no Frieren", "Frieren: Beyond Journey's End"],
        season: Int = 1,
        absoluteEpisode: Int? = nil,
        totalEpisodes: Int? = nil,
        isMovie: Bool = false,
        requestedIsSpecial: Bool = false
    ) -> EpisodeMatcher.Context {
        EpisodeMatcher.Context(
            requestedEpisode: episode,
            requestedSeason: season,
            requestedAbsoluteEpisode: absoluteEpisode,
            totalEpisodes: totalEpisodes,
            animeTitles: titles,
            isMovie: isMovie,
            requestedIsSpecial: requestedIsSpecial
        )
    }

    @Test func exactEpisodeIsExtremelyStrong() {
        let parsed = ReleaseParser.parse("[SubsPlease] Sousou no Frieren - 07 [1080p]")
        let result = matcher.match(parsed, context: context(episode: 7))

        #expect(result.confidence >= 0.95)
        #expect(result.isExtremelyStrong)
        #expect(result.matchedEpisode == 7)
        #expect(result.reasoning.contains(.exactEpisodeNumber))
    }

    @Test func abbreviatedTitleStillMatches() {
        let parsed = ReleaseParser.parse("Frieren - 07 [1080p]")
        let result = matcher.match(parsed, context: context(episode: 7))

        #expect(result.isSafeForAutoSelection)
        #expect(result.matchedEpisode == 7)
    }

    @Test func seasonEpisodeMatches() {
        let parsed = ReleaseParser.parse("[Group] Sousou no Frieren S01E07 [1080p]")
        let result = matcher.match(parsed, context: context(episode: 7))

        #expect(result.confidence >= 0.95)
        #expect(result.reasoning.contains(.seasonEpisode))
    }

    @Test func absoluteNumberingMatches() {
        let parsed = ReleaseParser.parse("[Group] ONE PIECE - 1100 [1080p]")
        let result = matcher.match(parsed, context: context(episode: 1100, titles: ["One Piece"]))

        #expect(result.confidence >= 0.95)
        #expect(result.reasoning.contains(.absoluteNumbering))
    }

    @Test func wrongEpisodeIsUnsafe() {
        let parsed = ReleaseParser.parse("[SubsPlease] Sousou no Frieren - 08 [1080p]")
        let result = matcher.match(parsed, context: context(episode: 7))

        #expect(result.confidence < 0.20)
        #expect(!result.isSafeForAutoSelection)
        #expect(result.matchedEpisode == 8)
        #expect(result.reasoning.contains(.episodeMismatch))
    }

    @Test func seasonMismatchIsUnsafe() {
        let parsed = ReleaseParser.parse("[Group] Sousou no Frieren S02E07 [1080p]")
        let result = matcher.match(parsed, context: context(episode: 7, season: 1))

        #expect(result.confidence < 0.30)
        #expect(result.reasoning.contains(.conflictingSeason))
    }

    @Test func batchRangeContainingEpisodeIsGood() {
        let parsed = ReleaseParser.parse("[Group] Sousou no Frieren 01-12 [1080p]")
        let result = matcher.match(parsed, context: context(episode: 7))

        #expect(result.confidence >= 0.80)
        #expect(result.confidence < 0.95)
        #expect(result.matchedEpisode == 7)
        #expect(result.reasoning.contains(.batchRange))
    }

    @Test func batchRangeExcludingEpisodeIsUnsafe() {
        let parsed = ReleaseParser.parse("[Group] Sousou no Frieren 01-12 [1080p]")
        let result = matcher.match(parsed, context: context(episode: 20))

        #expect(result.confidence < 0.20)
        #expect(result.reasoning.contains(.episodeMismatch))
    }

    @Test func unknownBatchIsUnsafe() {
        let parsed = ReleaseParser.parse("[Group] Sousou no Frieren Batch [1080p]")
        let result = matcher.match(parsed, context: context(episode: 7))

        #expect(result.confidence < 0.70)
        #expect(result.reasoning.contains(.batchUnknown))
    }

    @Test func specialIsUnsafeForRegularEpisode() {
        let parsed = ReleaseParser.parse("[Group] Sousou no Frieren OVA [1080p]")
        let result = matcher.match(parsed, context: context(episode: 7))

        #expect(result.confidence < 0.20)
        #expect(result.reasoning.contains(.specialMismatch))
    }

    @Test func specialMatchesWhenRequested() {
        let parsed = ReleaseParser.parse("[Group] Sousou no Frieren OVA [1080p]")
        let result = matcher.match(parsed, context: context(episode: 1, requestedIsSpecial: true))

        #expect(result.confidence >= 0.8)
        #expect(result.reasoning.contains(.specialMatch))
    }

    @Test func extraContentIsRejected() {
        let parsed = ReleaseParser.parse("[Group] Sousou no Frieren NCOP [1080p]")
        let result = matcher.match(parsed, context: context(episode: 7))

        #expect(result.confidence <= 0.05)
        #expect(result.reasoning.contains(.extraContent))
    }

    @Test func providerEpisodeMetadataWins() {
        let parsed = ReleaseParser.parse("[Group] Frieren [1080p]")
        let result = matcher.match(parsed, providerEpisode: 7, context: context(episode: 7))

        #expect(result.confidence >= 0.95)
        #expect(result.matchedEpisode == 7)
        #expect(result.reasoning.contains(.providerEpisodeMetadata))
    }

    @Test func providerEpisodeMismatchIsUnsafe() {
        let parsed = ReleaseParser.parse("[Group] Frieren [1080p]")
        let result = matcher.match(parsed, providerEpisode: 9, context: context(episode: 7))

        #expect(result.confidence < 0.20)
        #expect(result.reasoning.contains(.episodeMismatch))
    }

    @Test func movieWithoutEpisodeNumberMatchesByTitle() {
        let parsed = ReleaseParser.parse("[Group] Your Name. [1080p]")
        let result = matcher.match(
            parsed,
            context: context(episode: 1, titles: ["Your Name."], isMovie: true)
        )

        #expect(result.confidence >= 0.85)
        #expect(result.reasoning.contains(.movieTitle))
    }

    @Test func missingEpisodeNumberIsUnsafe() {
        let parsed = ReleaseParser.parse("[Group] Frieren [1080p]")
        let result = matcher.match(parsed, context: context(episode: 7))

        #expect(result.confidence < 0.70)
        #expect(result.reasoning.contains(.noEpisodeNumber))
    }

    @Test func titleMismatchLowersConfidence() {
        let parsed = ReleaseParser.parse("[Group] Bocchi the Rock! - 07 [1080p]")
        let result = matcher.match(parsed, context: context(episode: 7))

        #expect(result.confidence < 0.70)
        #expect(!result.isSafeForAutoSelection)
        #expect(result.reasoning.contains(.titleMismatch))
    }

    @Test func episodeBeyondKnownCountIsUnsafe() {
        let parsed = ReleaseParser.parse("[Group] Sousou no Frieren - 15 [1080p]")
        let result = matcher.match(
            parsed,
            context: context(episode: 15, totalEpisodes: 12)
        )

        #expect(result.confidence <= 0.55)
        #expect(!result.isSafeForAutoSelection)
        #expect(result.reasoning.contains(.episodeCountMismatch))
    }

    @Test func titleSimilarityScores() {
        #expect(
            EpisodeMatcher.titleSimilarity(
                candidateTitle: "Sousou no Frieren - 07 [1080p]",
                expectedTitles: ["Sousou no Frieren"]
            ) >= 0.9
        )
        #expect(
            EpisodeMatcher.titleSimilarity(
                candidateTitle: "Bocchi the Rock - 07",
                expectedTitles: ["Sousou no Frieren"]
            ) < 0.3
        )
    }

    @Test func absoluteReleaseMatchesSeasonRelativeRequest() {
        let parsed = ReleaseParser.parse("[Group] Shingeki no Kyojin - 28 [1080p]")
        let result = matcher.match(
            parsed,
            context: context(
                episode: 3,
                titles: ["Shingeki no Kyojin", "Attack on Titan"],
                season: 2,
                absoluteEpisode: 28
            )
        )

        #expect(result.isSafeForAutoSelection)
        #expect(result.matchedEpisode == 28)
        #expect(result.reasoning.contains(.absoluteNumbering))
    }

    @Test func absoluteMismatchRemainsUnsafe() {
        let parsed = ReleaseParser.parse("[Group] Shingeki no Kyojin - 27 [1080p]")
        let result = matcher.match(
            parsed,
            context: context(
                episode: 3,
                titles: ["Shingeki no Kyojin", "Attack on Titan"],
                season: 2,
                absoluteEpisode: 28
            )
        )

        #expect(!result.isSafeForAutoSelection)
        #expect(result.reasoning.contains(.episodeMismatch))
    }

    @Test func seasonRelativeReleaseStillWins() {
        let parsed = ReleaseParser.parse("[Group] Shingeki no Kyojin S02E03 [1080p]")
        let result = matcher.match(
            parsed,
            context: context(
                episode: 3,
                titles: ["Shingeki no Kyojin", "Attack on Titan"],
                season: 2,
                absoluteEpisode: 28
            )
        )

        #expect(result.confidence >= 0.95)
        #expect(result.reasoning.contains(.seasonEpisode))
        #expect(!result.reasoning.contains(.absoluteNumbering))
    }
}
