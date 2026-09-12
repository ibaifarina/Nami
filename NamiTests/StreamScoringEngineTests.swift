import Foundation
import Testing
@testable import Nami

struct StreamScoringEngineTests {
    private func options(
        autoSelect: Bool = true,
        quality: QualityBalance = .balanced,
        preferredQuality: QualityPreference = .auto,
        preferCached: Bool = true,
        audio: AudioPreference = .any,
        subtitles: SubtitlePreference = .any,
        preferredGroups: [String] = [],
        blockedGroups: [String] = [],
        minSeeders: Int = 2,
        maxSize: Int64? = nil,
        maxMovieSize: Int64? = nil,
        threshold: Double = 0.88,
        debridAvailable: Bool = true
    ) -> StreamScoringOptions {
        var options = StreamScoringOptions()
        options.autoSelectEnabled = autoSelect
        options.qualityBalance = quality
        options.preferredQuality = preferredQuality
        options.preferCachedStreams = preferCached
        options.preferredAudio = audio
        options.preferredSubtitles = subtitles
        options.preferredReleaseGroups = preferredGroups
        options.blockedReleaseGroups = blockedGroups
        options.minimumSeedersForUncached = minSeeders
        options.maximumEpisodeFileSizeBytes = maxSize
        options.maximumMovieFileSizeBytes = maxMovieSize
        options.confidenceThreshold = threshold
        options.debridAvailable = debridAvailable
        return options
    }

    private func candidate(
        id: String,
        episodeConfidence: Double = 0.97,
        resolution: VideoResolution? = .p1080,
        codec: VideoCodec? = .hevc,
        source: ReleaseSource? = .bluRay,
        cached: Bool = true,
        sizeBytes: Int64? = 1_800_000_000,
        seeders: Int? = 20,
        group: String? = nil,
        audio: Set<String> = [],
        subtitles: Set<String> = [],
        addonPriority: Int = 0,
        isBatch: Bool = false,
        targetEpisode: Int? = 7,
        hasTorrentSource: Bool = true,
        directURL: String? = nil
    ) -> StreamCandidate {
        let hash = hasTorrentSource
            ? "aabbccddeeff00112233445566778899aabbccdd"
            : nil
        return StreamCandidate(
            id: id,
            addonID: "addon.p\(addonPriority)",
            addonName: "Addon \(addonPriority)",
            displayTitle: "Show - 07 [1080p]",
            rawTitle: "Show - 07 [1080p]",
            infoHash: hash,
            directURL: directURL.flatMap { URL(string: $0) },
            resolution: resolution,
            codec: codec,
            source: source,
            releaseGroup: group,
            sizeBytes: sizeBytes,
            seeders: seeders,
            audioLanguages: audio,
            subtitleLanguages: subtitles,
            parsedEpisode: ParsedEpisodeInfo(season: nil, episode: 7, isBatch: isBatch, isSpecial: false),
            isBatch: isBatch,
            debridStatus: cached ? .cached : .unknown,
            episodeMatchConfidence: episodeConfidence,
            targetEpisode: targetEpisode
        )
    }

    private var context: ScoringContext {
        ScoringContext(
            episodeDurationMinutes: 24,
            addonPriorities: [
                "addon.p0": 0,
                "addon.p1": 1,
                "addon.p2": 2,
                "addon.p3": 3,
                "addon.p4": 4,
            ],
            debridAvailable: true
        )
    }

    // MARK: - Required cases (§62)

    @Test func case1Cached1080pBeatsHugeUncached4K() {
        let engine = StreamScoringEngine(options: options())
        let a = candidate(
            id: "A",
            resolution: .p1080,
            codec: .hevc,
            source: .bluRay,
            cached: true,
            sizeBytes: 1_800_000_000,
            seeders: 20
        )
        let b = candidate(
            id: "B",
            resolution: .p2160,
            codec: .hevc,
            source: .bluRay,
            cached: false,
            sizeBytes: 12_000_000_000,
            seeders: 2
        )

        let decision = engine.selectBest([a, b], context: context)

        #expect(decision.candidate?.id == "A")
        #expect(decision.shouldAutoPlay)
    }

    @Test func case2BetterQualityWinsWhenBothCached() {
        let engine = StreamScoringEngine(options: options())
        let a = candidate(id: "A", resolution: .p720, codec: .avc, source: .webRip)
        let b = candidate(id: "B", resolution: .p1080, codec: .hevc, source: .bluRay)

        let decision = engine.selectBest([a, b], context: context)

        #expect(decision.candidate?.id == "B")
    }

    @Test func case3WrongEpisodeIsNeverSelected() {
        let engine = StreamScoringEngine(options: options())
        let a = candidate(
            id: "A",
            episodeConfidence: 0.08,
            resolution: .p1080,
            source: .bluRay,
            cached: true
        )
        let b = candidate(
            id: "B",
            episodeConfidence: 0.97,
            resolution: .p1080,
            source: .webDL,
            cached: true
        )

        let decision = engine.selectBest([a, b], context: context)
        let ranked = engine.rank([a, b], context: context)

        #expect(decision.candidate?.id == "B")
        #expect(ranked.first(where: { $0.candidate.id == "A" })?.isAutoEligible == false)
    }

    @Test func case4CachedBeatsUncachedHighSeeders() {
        let engine = StreamScoringEngine(options: options())
        let a = candidate(
            id: "A",
            resolution: .p1080,
            codec: .hevc,
            source: .webDL,
            cached: false,
            seeders: 500
        )
        let b = candidate(
            id: "B",
            resolution: .p1080,
            codec: .hevc,
            source: .webDL,
            cached: true,
            seeders: 2
        )

        let decision = engine.selectBest([a, b], context: context)

        #expect(decision.candidate?.id == "B")
    }

    @Test func case5HighEpisodeConfidenceWinsByLargeMargin() {
        let engine = StreamScoringEngine(options: options())
        let a = candidate(id: "A", episodeConfidence: 0.98)
        let b = candidate(id: "B", episodeConfidence: 0.76)

        let decision = engine.selectBest([a, b], context: context)
        let aScore = engine.evaluate(a, context: context).total
        let bScore = engine.evaluate(b, context: context).total

        #expect(decision.candidate?.id == "A")
        #expect(aScore - bScore > 5)
    }

    @Test func case6AmbiguousUncertainCandidatesDoNotAutoPlay() {
        let engine = StreamScoringEngine(options: options())
        let a = candidate(id: "A", episodeConfidence: 0.74, sizeBytes: 1_400_000_000)
        let b = candidate(id: "B", episodeConfidence: 0.72, sizeBytes: 1_500_000_000)

        let decision = engine.selectBest([a, b], context: context)

        #expect(!decision.shouldAutoPlay)
        #expect(decision.confidence < 0.88)
    }

    // MARK: - Gates

    @Test func camAndTSArePenalized() {
        let engine = StreamScoringEngine(options: options())
        let cam = candidate(id: "CAM", source: .cam)
        let ts = candidate(id: "TS", source: .ts)
        let web = candidate(id: "WEB", source: .webDL)

        let decision = engine.selectBest([cam, ts, web], context: context)

        #expect(decision.candidate?.id == "WEB")
        #expect(engine.evaluate(cam, context: context).breakdown.source == -50)
    }

    @Test func blockedGroupIsNeverAutoEligible() {
        let engine = StreamScoringEngine(options: options(blockedGroups: ["BadGroup"]))
        let blocked = candidate(id: "A", group: "BadGroup")
        let good = candidate(id: "B", group: "GoodGroup")

        let decision = engine.selectBest([blocked, good], context: context)
        let ranked = engine.rank([blocked, good], context: context)

        #expect(decision.candidate?.id == "B")
        let blockedScored = ranked.first { $0.candidate.id == "A" }
        #expect(blockedScored?.isAutoEligible == false)
        #expect(blockedScored?.breakdown.penalties == -100)
    }

    @Test func preferredGroupGetsBonus() {
        let engine = StreamScoringEngine(options: options(preferredGroups: ["SubsPlease"]))
        let preferred = candidate(id: "A", group: "SubsPlease")

        #expect(engine.evaluate(preferred, context: context).breakdown.releaseGroup == 6)
    }

    @Test func deadTorrentIsIneligibleWhenNotCached() {
        let engine = StreamScoringEngine(options: options(minSeeders: 2))
        let dead = candidate(id: "dead", cached: false, seeders: 0)
        let healthy = candidate(id: "healthy", cached: false, seeders: 50)

        let ranked = engine.rank([dead, healthy], context: context)

        #expect(ranked.first { $0.candidate.id == "dead" }?.isAutoEligible == false)
        #expect(ranked.first { $0.candidate.id == "healthy" }?.isAutoEligible == true)
    }

    @Test func unknownSeedersAreNotTreatedAsZero() {
        let engine = StreamScoringEngine(options: options(minSeeders: 2))
        let unknown = candidate(id: "unknown", cached: false, seeders: nil)

        #expect(engine.evaluate(unknown, context: context).isAutoEligible)
    }

    @Test func maximumFileSizeGate() {
        let engine = StreamScoringEngine(options: options(maxSize: 2_000_000_000))
        let huge = candidate(id: "huge", sizeBytes: 5_000_000_000)
        let fine = candidate(id: "fine", sizeBytes: 1_500_000_000)

        let ranked = engine.rank([huge, fine], context: context)

        #expect(ranked.first { $0.candidate.id == "huge" }?.isAutoEligible == false)
        #expect(ranked.first { $0.candidate.id == "fine" }?.isAutoEligible == true)
    }

    @Test func movieFileSizeGateUsesMovieLimit() {
        let engine = StreamScoringEngine(
            options: options(maxSize: 5_000_000_000, maxMovieSize: 20_000_000_000)
        )
        let huge = candidate(id: "huge", sizeBytes: 25_000_000_000)
        let fine = candidate(id: "fine", sizeBytes: 15_000_000_000)
        let movieContext = ScoringContext(
            episodeDurationMinutes: 110,
            addonPriorities: [:],
            debridAvailable: true,
            isMovie: true
        )

        let ranked = engine.rank([huge, fine], context: movieContext)

        #expect(ranked.first { $0.candidate.id == "huge" }?.isAutoEligible == false)
        #expect(ranked.first { $0.candidate.id == "fine" }?.isAutoEligible == true)
    }

    @Test func torrentCandidatesIneligibleWithoutDebrid() {
        let offlineContext = ScoringContext(
            episodeDurationMinutes: 24,
            addonPriorities: [:],
            debridAvailable: false
        )
        let engine = StreamScoringEngine(options: options())
        let torrent = candidate(id: "torrent")
        let direct = candidate(
            id: "direct",
            hasTorrentSource: false,
            directURL: "https://cdn.example/video.mp4"
        )

        let ranked = engine.rank([torrent, direct], context: offlineContext)

        #expect(ranked.first { $0.candidate.id == "torrent" }?.isAutoEligible == false)
        #expect(ranked.first { $0.candidate.id == "direct" }?.isAutoEligible == true)
    }

    @Test func batchWithoutTargetEpisodeIsIneligible() {
        let engine = StreamScoringEngine(options: options())
        let batch = candidate(id: "batch", isBatch: true, targetEpisode: nil)

        #expect(engine.evaluate(batch, context: context).isAutoEligible == false)
    }

    @Test func sourceLessCandidateIsIneligible() {
        let engine = StreamScoringEngine(options: options())
        let empty = candidate(id: "empty", hasTorrentSource: false)

        #expect(engine.evaluate(empty, context: context).isAutoEligible == false)
    }

    // MARK: - Weights

    @Test func seedersUseLogScaleAndStopAtTen() {
        let engine = StreamScoringEngine(options: options())
        let one = candidate(id: "one", cached: false, seeders: 1)
        let hundred = candidate(id: "hundred", cached: false, seeders: 100)
        let huge = candidate(id: "huge", cached: false, seeders: 100_000)
        let cached = candidate(id: "cached", cached: true, seeders: 100_000)

        let oneScore = engine.seederScore(one)
        let hundredScore = engine.seederScore(hundred)
        let hugeScore = engine.seederScore(huge)

        #expect(oneScore < hundredScore)
        #expect(hugeScore <= 10)
        #expect(hundredScore <= hugeScore)
        #expect(engine.seederScore(cached) == 0)
    }

    @Test func resolutionPreferenceChangesRanking() {
        let fourK = candidate(id: "4k", resolution: .p2160)
        let fullHD = candidate(id: "1080", resolution: .p1080)

        let autoEngine = StreamScoringEngine(options: options(preferredQuality: .auto))
        #expect(autoEngine.selectBest([fourK, fullHD], context: context).candidate?.id == "1080")

        let fourKEngine = StreamScoringEngine(options: options(preferredQuality: .p2160))
        #expect(fourKEngine.selectBest([fourK, fullHD], context: context).candidate?.id == "4k")
    }

    @Test func sizeHeuristicScalesWithDurationAndQualityMode() {
        let balanced = StreamScoringEngine(options: options(quality: .balanced))
        let dataSaver = StreamScoringEngine(options: options(quality: .dataSaver))

        let normal = balanced.sizeScore(bytes: 400_000_000, durationMinutes: 24, codec: nil)
        let tiny = balanced.sizeScore(bytes: 50_000_000, durationMinutes: 24, codec: nil)
        let enormous = balanced.sizeScore(bytes: 12_000_000_000, durationMinutes: 24, codec: nil)

        #expect(normal == 8)
        #expect(tiny < 0)
        #expect(enormous < 0)
        #expect(dataSaver.sizeScore(bytes: 400_000_000, durationMinutes: 24, codec: nil) == 8)

        let longEpisode = balanced.sizeScore(bytes: 1_200_000_000, durationMinutes: 90, codec: nil)
        #expect(longEpisode == 8)
    }

    @Test func languagePreferencesRewardMatchesAndPenalizeMismatches() {
        let engine = StreamScoringEngine(options: options(audio: .japanese, subtitles: .english))
        let matching = candidate(id: "match", audio: ["japanese", "english"], subtitles: ["english"])
        let wrong = candidate(id: "wrong", audio: ["english"], subtitles: ["spanish"])
        let unknown = candidate(id: "unknown")

        let matchingScore = engine.evaluate(matching, context: context)
        let wrongScore = engine.evaluate(wrong, context: context)
        let unknownScore = engine.evaluate(unknown, context: context)

        #expect(matchingScore.breakdown.language == 8)
        #expect(wrongScore.breakdown.penalties == -16)
        #expect(unknownScore.breakdown.language == 0)
        #expect(unknownScore.breakdown.penalties == 0)

        let matchingDecision = engine.selectBest([matching, wrong], context: context)
        #expect(matchingDecision.candidate?.id == "match")
    }

    @Test func addonPriorityAddsUpToFourPoints() {
        let engine = StreamScoringEngine(options: options())
        let first = candidate(id: "first", addonPriority: 0)
        let fourth = candidate(id: "fourth", addonPriority: 3)
        let beyond = candidate(id: "beyond", addonPriority: 7)

        #expect(engine.evaluate(first, context: context).breakdown.addonPriority == 4)
        #expect(engine.evaluate(fourth, context: context).breakdown.addonPriority == 1)
        #expect(engine.evaluate(beyond, context: context).breakdown.addonPriority == 0)
    }

    @Test func autoSelectDisabledNeverAutoPlays() {
        let engine = StreamScoringEngine(options: options(autoSelect: false))
        let great = candidate(id: "great")

        let decision = engine.selectBest([great], context: context)

        #expect(!decision.shouldAutoPlay)
        #expect(decision.candidate?.id == "great")
    }

    @Test func decisionExplainsWhyAStreamWasChosen() {
        let engine = StreamScoringEngine(options: options(audio: .japanese))
        let best = candidate(id: "best", audio: ["japanese"], subtitles: ["english"])

        let decision = engine.selectBest([best], context: context)

        #expect(decision.reasons.contains { $0.text.contains("Cached") })
        #expect(decision.reasons.contains { $0.text.contains("1080p") })
        #expect(decision.reasons.contains { $0.text.contains("Preferred language") })
        #expect(decision.scoreGapToSecondPlace == nil)
    }
}
