import Foundation

struct StreamScoreBreakdown: Hashable, Sendable {
    var episodeMatch: Double = 0
    var cached: Double = 0
    var resolution: Double = 0
    var source: Double = 0
    var codec: Double = 0
    var size: Double = 0
    var seeders: Double = 0
    var language: Double = 0
    var releaseGroup: Double = 0
    var addonPriority: Double = 0
    var penalties: Double = 0

    var total: Double {
        episodeMatch + cached + resolution + source + codec + size + seeders
            + language + releaseGroup + addonPriority + penalties
    }
}

struct StreamScoringOptions: Hashable, Sendable {
    var autoSelectEnabled: Bool = true
    var qualityBalance: QualityBalance = .balanced
    var preferredQuality: QualityPreference = .auto
    var preferCachedStreams: Bool = true
    var preferredAudio: AudioPreference = .japanese
    var preferredSubtitles: SubtitlePreference = .english
    var preferredReleaseGroups: [String] = []
    var blockedReleaseGroups: [String] = []
    var minimumSeedersForUncached: Int = 2
    var maximumEpisodeFileSizeBytes: Int64?
    var maximumMovieFileSizeBytes: Int64?
    var confidenceThreshold: Double = 0.88
    var debridAvailable: Bool = true

    init() {}

    init(preferences: UserPreferences, debridAvailable: Bool) {
        autoSelectEnabled = preferences.autoSelectBestStream
        qualityBalance = preferences.qualityBalance
        preferredQuality = preferences.preferredQuality
        preferCachedStreams = preferences.preferCachedStreams
        preferredAudio = preferences.preferredAudio
        preferredSubtitles = preferences.preferredSubtitles
        preferredReleaseGroups = preferences.preferredReleaseGroups
        blockedReleaseGroups = preferences.blockedReleaseGroups
        minimumSeedersForUncached = preferences.minimumSeedersForUncached
        maximumEpisodeFileSizeBytes = preferences.maximumEpisodeFileSizeBytes > 0
            ? preferences.maximumEpisodeFileSizeBytes
            : nil
        maximumMovieFileSizeBytes = preferences.maximumMovieFileSizeBytes > 0
            ? preferences.maximumMovieFileSizeBytes
            : nil
        confidenceThreshold = preferences.autoSelectConfidenceThreshold
        self.debridAvailable = debridAvailable
    }
}

struct ScoringContext: Hashable, Sendable {
    var episodeDurationMinutes: Int?
    var addonPriorities: [String: Int] = [:]
    var debridAvailable: Bool = true
    var isMovie: Bool = false
}

struct ScoreReason: Hashable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
        case positive
        case caution
        case negative
    }

    var id: String { text }
    let text: String
    let kind: Kind
}

struct ScoredStream: Identifiable, Sendable {
    var id: String { candidate.id }
    let candidate: StreamCandidate
    let breakdown: StreamScoreBreakdown
    let isAutoEligible: Bool
    let rejectionReasons: [String]

    var total: Double { breakdown.total }
}

struct AutoSelectDecision: Sendable {
    let candidate: StreamCandidate?
    let totalScore: Double
    let confidence: Double
    let scoreGapToSecondPlace: Double?
    let reasons: [ScoreReason]
    let shouldAutoPlay: Bool

    var reasonTexts: [String] { reasons.map(\.text) }
}

struct StreamScoringEngine: Sendable {
    let options: StreamScoringOptions

    init(options: StreamScoringOptions = StreamScoringOptions()) {
        self.options = options
    }

    func evaluate(_ candidate: StreamCandidate, context: ScoringContext) -> ScoredStream {
        let rejectionReasons = gates(candidate, context: context)
        var breakdown = StreamScoreBreakdown()
        breakdown.episodeMatch = 35 * clamped(candidate.episodeMatchConfidence)
        breakdown.cached = cachedScore(candidate)
        breakdown.resolution = resolutionScore(candidate.resolution)
        breakdown.source = sourceScore(candidate.source)
        breakdown.codec = codecScore(candidate.codec)
        breakdown.size = sizeScore(
            bytes: candidate.sizeBytes,
            durationMinutes: context.episodeDurationMinutes
        )
        breakdown.seeders = seederScore(candidate)
        let language = languageScores(candidate)
        breakdown.language = language.bonus
        breakdown.releaseGroup = releaseGroupScore(candidate)
        breakdown.addonPriority = addonPriorityScore(candidate, context: context)
        breakdown.penalties = language.penalty
        if isBlockedGroup(candidate) {
            breakdown.penalties -= 100
        }
        return ScoredStream(
            candidate: candidate,
            breakdown: breakdown,
            isAutoEligible: rejectionReasons.isEmpty,
            rejectionReasons: rejectionReasons
        )
    }

    func rank(_ candidates: [StreamCandidate], context: ScoringContext) -> [ScoredStream] {
        candidates
            .map { evaluate($0, context: context) }
            .sorted { lhs, rhs in
                if lhs.isAutoEligible != rhs.isAutoEligible { return lhs.isAutoEligible }
                if lhs.total != rhs.total { return lhs.total > rhs.total }
                return lhs.candidate.id < rhs.candidate.id
            }
    }

    func selectBest(_ candidates: [StreamCandidate], context: ScoringContext) -> AutoSelectDecision {
        let ranked = rank(candidates, context: context)
        let eligible = ranked.filter(\.isAutoEligible)
        guard let top = eligible.first else {
            return AutoSelectDecision(
                candidate: nil,
                totalScore: 0,
                confidence: 0,
                scoreGapToSecondPlace: nil,
                reasons: [],
                shouldAutoPlay: false
            )
        }
        let second = eligible.dropFirst().first
        let gap = second.map { top.total - $0.total }
        let confidence = confidenceScore(top: top, second: second)
        let reasons = reasons(for: top)
        let shouldAutoPlay = options.autoSelectEnabled
            && confidence >= options.confidenceThreshold
        return AutoSelectDecision(
            candidate: top.candidate,
            totalScore: top.total,
            confidence: confidence,
            scoreGapToSecondPlace: gap,
            reasons: reasons,
            shouldAutoPlay: shouldAutoPlay
        )
    }

    // MARK: - Gates

    private func gates(_ candidate: StreamCandidate, context: ScoringContext) -> [String] {
        var reasons: [String] = []
        if candidate.episodeMatchConfidence < EpisodeMatchResult.safeForAutoSelectionThreshold {
            reasons.append("Episode match is too uncertain")
        }
        if !hasPlayableSource(candidate) {
            reasons.append("No playable source")
        }
        if !context.debridAvailable && candidate.directURL == nil {
            reasons.append("Real-Debrid isn't connected")
        }
        if let maximum = maximumFileSizeBytes(for: context),
           let size = candidate.sizeBytes,
           size > maximum {
            reasons.append("File is larger than your size limit")
        }
        if candidate.debridStatus != .cached,
           options.preferCachedStreams,
           let seeders = candidate.seeders,
           seeders < options.minimumSeedersForUncached {
            reasons.append("Not enough seeders for an uncached stream")
        }
        if candidate.isBatch && candidate.targetEpisode == nil {
            reasons.append("Batch could not be matched to this episode")
        }
        if isBlockedGroup(candidate) {
            reasons.append("Release group is blocked")
        }
        return reasons
    }

    private func hasPlayableSource(_ candidate: StreamCandidate) -> Bool {
        candidate.infoHash != nil
            || candidate.magnetURI != nil
            || candidate.directURL != nil
    }

    private func maximumFileSizeBytes(for context: ScoringContext) -> Int64? {
        context.isMovie ? options.maximumMovieFileSizeBytes : options.maximumEpisodeFileSizeBytes
    }

    // MARK: - Weights

    private func cachedScore(_ candidate: StreamCandidate) -> Double {
        guard candidate.debridStatus == .cached else { return 0 }
        return options.preferCachedStreams ? 30 : 15
    }

    func resolutionScore(_ resolution: VideoResolution?) -> Double {
        switch options.preferredQuality {
        case .auto:
            switch resolution {
            case .p2160: 17
            case .p1080: 20
            case .p720: 10
            case .p480: 2
            case nil: 0
            }
        case .p2160:
            switch resolution {
            case .p2160: 20
            case .p1080: 13
            case .p720: 5
            case .p480: 1
            case nil: 0
            }
        case .p1080:
            switch resolution {
            case .p2160: 14
            case .p1080: 20
            case .p720: 8
            case .p480: 2
            case nil: 0
            }
        case .p720:
            switch resolution {
            case .p2160: 8
            case .p1080: 14
            case .p720: 20
            case .p480: 12
            case nil: 0
            }
        }
    }

    func sourceScore(_ source: ReleaseSource?) -> Double {
        switch source {
        case .bluRay: 10
        case .webDL: 9
        case .webRip: 7
        case .hdtv: 4
        case .dvd: 1
        case .cam: -50
        case .ts: -50
        case nil: 0
        }
    }

    func codecScore(_ codec: VideoCodec?) -> Double {
        switch codec {
        case .hevc: 4
        case .av1: 3
        case .avc: 2
        case nil: 0
        }
    }

    func seederScore(_ candidate: StreamCandidate) -> Double {
        guard candidate.debridStatus != .cached else { return 0 }
        guard let seeders = candidate.seeders, seeders > 0 else { return 0 }
        return min(10, log2(Double(seeders) + 1) * 1.5)
    }

    func sizeScore(bytes: Int64?, durationMinutes: Int?) -> Double {
        guard let bytes, bytes > 0 else { return 0 }
        let minutes = max(durationMinutes ?? 24, 1)
        let megabytesPerMinute = Double(bytes) / 1_000_000.0 / Double(minutes)
        let bands = sizeBands(for: options.qualityBalance)
        if megabytesPerMinute < bands.minimum {
            return -8
        }
        if megabytesPerMinute < bands.idealLow {
            let progress = (megabytesPerMinute - bands.minimum) / (bands.idealLow - bands.minimum)
            return 2 + 4 * progress
        }
        if megabytesPerMinute <= bands.idealHigh {
            return 8
        }
        if megabytesPerMinute <= bands.maximum {
            let progress = (megabytesPerMinute - bands.idealHigh) / (bands.maximum - bands.idealHigh)
            return max(-5, 8 - 13 * progress)
        }
        return -15
    }

    private struct SizeBands {
        let minimum: Double
        let idealLow: Double
        let idealHigh: Double
        let maximum: Double
    }

    private func sizeBands(for balance: QualityBalance) -> SizeBands {
        switch balance {
        case .dataSaver:
            SizeBands(minimum: 5, idealLow: 8, idealHigh: 25, maximum: 50)
        case .balanced:
            SizeBands(minimum: 8, idealLow: 12, idealHigh: 65, maximum: 170)
        case .best:
            SizeBands(minimum: 12, idealLow: 30, idealHigh: 170, maximum: 500)
        }
    }

    private func languageScores(_ candidate: StreamCandidate) -> (bonus: Double, penalty: Double) {
        var bonus = 0.0
        var penalty = 0.0

        if let token = options.preferredAudio.languageToken {
            if !candidate.audioLanguages.isEmpty {
                if candidate.audioLanguages.contains(token) {
                    bonus += 4
                } else {
                    penalty -= 10
                }
            }
        }
        if let token = options.preferredSubtitles.languageToken {
            if !candidate.subtitleLanguages.isEmpty {
                if candidate.subtitleLanguages.contains(token) {
                    bonus += 4
                } else {
                    penalty -= 6
                }
            }
        }
        return (bonus, penalty)
    }

    private func releaseGroupScore(_ candidate: StreamCandidate) -> Double {
        guard let group = candidate.releaseGroup?.lowercased(), !group.isEmpty else { return 0 }
        if options.preferredReleaseGroups.contains(where: { $0.lowercased() == group }) {
            return 6
        }
        return 0
    }

    private func isBlockedGroup(_ candidate: StreamCandidate) -> Bool {
        guard let group = candidate.releaseGroup?.lowercased(), !group.isEmpty else { return false }
        return options.blockedReleaseGroups.contains { $0.lowercased() == group }
    }

    private func addonPriorityScore(_ candidate: StreamCandidate, context: ScoringContext) -> Double {
        let priority = context.addonPriorities[candidate.addonID] ?? 4
        return Double(max(0, min(4, 4 - priority)))
    }

    // MARK: - Confidence

    private func confidenceScore(top: ScoredStream, second: ScoredStream?) -> Double {
        var value = clamped(top.candidate.episodeMatchConfidence)

        let metadataFields = [
            top.candidate.resolution != nil,
            top.candidate.codec != nil,
            top.candidate.source != nil,
            top.candidate.sizeBytes != nil,
        ]
        value += 0.06 * (Double(metadataFields.filter { $0 }.count) / 4.0)

        if top.candidate.debridStatus == .cached {
            value += 0.05
        }
        if let second {
            let gap = top.total - second.total
            let ratio = gap / max(abs(top.total), 1)
            value += min(0.08, max(0, ratio) * 0.2)
        } else {
            value += 0.03
        }
        if top.candidate.debridStatus != .cached,
           let seeders = top.candidate.seeders,
           seeders < options.minimumSeedersForUncached {
            value -= 0.15
        }
        if hasLanguageMismatch(top.candidate) {
            value -= 0.2
        }
        return clamped(value)
    }

    private func hasLanguageMismatch(_ candidate: StreamCandidate) -> Bool {
        if let token = options.preferredAudio.languageToken,
           !candidate.audioLanguages.isEmpty,
           !candidate.audioLanguages.contains(token) {
            return true
        }
        if let token = options.preferredSubtitles.languageToken,
           !candidate.subtitleLanguages.isEmpty,
           !candidate.subtitleLanguages.contains(token) {
            return true
        }
        return false
    }

    // MARK: - Reasons

    private func reasons(for scored: ScoredStream) -> [ScoreReason] {
        let candidate = scored.candidate
        let breakdown = scored.breakdown
        var reasons: [ScoreReason] = []

        let percent = Int((candidate.episodeMatchConfidence * 100).rounded())
        if candidate.episodeMatchConfidence >= EpisodeMatchResult.extremelyStrongThreshold {
            reasons.append(ScoreReason(text: "Exact episode match", kind: .positive))
        } else if candidate.episodeMatchConfidence >= EpisodeMatchResult.safeForAutoSelectionThreshold {
            reasons.append(ScoreReason(text: "Episode match confidence \(percent)%", kind: .positive))
        } else {
            reasons.append(ScoreReason(text: "Uncertain episode match (\(percent)%)", kind: .caution))
        }

        if candidate.debridStatus == .cached {
            reasons.append(ScoreReason(text: "Cached on Real-Debrid", kind: .positive))
        }

        if let resolution = candidate.resolution {
            reasons.append(
                ScoreReason(
                    text: "\(resolution.label) quality",
                    kind: breakdown.resolution >= 15 ? .positive : .caution
                )
            )
        }
        if let source = candidate.source {
            let kind: ScoreReason.Kind = source == .cam || source == .ts ? .negative : .positive
            reasons.append(ScoreReason(text: "\(source.label) source", kind: kind))
        }
        if let codec = candidate.codec {
            reasons.append(ScoreReason(text: "\(codec.label) codec", kind: .positive))
        }
        if let size = candidate.sizeBytes {
            let text = "File size \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
            reasons.append(
                ScoreReason(text: text, kind: breakdown.size < 0 ? .caution : .positive)
            )
        }
        if candidate.debridStatus != .cached, let seeders = candidate.seeders {
            reasons.append(
                ScoreReason(
                    text: "\(seeders) seeders",
                    kind: seeders >= options.minimumSeedersForUncached ? .positive : .caution
                )
            )
        }
        if breakdown.language > 0 {
            reasons.append(ScoreReason(text: "Preferred language available", kind: .positive))
        }
        if breakdown.releaseGroup > 0, let group = candidate.releaseGroup {
            reasons.append(ScoreReason(text: "Preferred group \(group)", kind: .positive))
        }
        if breakdown.penalties < 0, let group = candidate.releaseGroup, isBlockedGroup(candidate) {
            reasons.append(ScoreReason(text: "Blocked group \(group)", kind: .negative))
        }
        if candidate.isBatch, candidate.targetEpisode != nil {
            reasons.append(ScoreReason(text: "Batch contains this episode", kind: .caution))
        }
        return reasons
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

extension AudioPreference {
    var languageToken: String? {
        self == .any ? nil : rawValue
    }
}

extension SubtitlePreference {
    var languageToken: String? {
        self == .any ? nil : rawValue
    }
}
