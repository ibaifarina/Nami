import Foundation

struct EpisodeMatchResult: Hashable, Sendable {
    let confidence: Double
    let matchedEpisode: Int?
    let reasoning: [EpisodeMatchReason]

    static let safeForAutoSelectionThreshold = 0.70
    static let extremelyStrongThreshold = 0.95

    var isSafeForAutoSelection: Bool {
        confidence >= Self.safeForAutoSelectionThreshold
    }

    var isExtremelyStrong: Bool {
        confidence >= Self.extremelyStrongThreshold
    }
}

enum EpisodeMatchReason: String, Hashable, Sendable {
    case providerEpisodeMetadata
    case exactEpisodeNumber
    case seasonEpisode
    case absoluteNumbering
    case batchRange
    case batchUnknown
    case movieTitle
    case noEpisodeNumber
    case episodeMismatch
    case conflictingSeason
    case specialMismatch
    case specialMatch
    case extraContent
    case weakTitleMatch
    case titleMismatch
    case episodeCountMismatch

    var displayText: String {
        switch self {
        case .providerEpisodeMetadata: "Provider confirmed this episode"
        case .exactEpisodeNumber: "Exact episode match"
        case .seasonEpisode: "Season and episode match"
        case .absoluteNumbering: "Absolute episode numbering"
        case .batchRange: "Episode falls inside this batch"
        case .batchUnknown: "Batch contents could not be verified"
        case .movieTitle: "Title match for a movie"
        case .noEpisodeNumber: "No episode number in the release title"
        case .episodeMismatch: "Release is a different episode"
        case .conflictingSeason: "Season does not match"
        case .specialMismatch: "Release is a special"
        case .specialMatch: "Special episode match"
        case .extraContent: "Extra content such as a preview or creditless sequence"
        case .weakTitleMatch: "Title only partially matches"
        case .titleMismatch: "Release title does not match this anime"
        case .episodeCountMismatch: "Requested episode is beyond the known episode count"
        }
    }
}

struct EpisodeMatcher: Sendable {
    struct Context: Hashable, Sendable {
        let requestedEpisode: Int
        let requestedSeason: Int
        /// Absolute number across the grouped series, when known.
        let requestedAbsoluteEpisode: Int?
        let totalEpisodes: Int?
        let animeTitles: [String]
        let isMovie: Bool
        let requestedIsSpecial: Bool

        init(
            requestedEpisode: Int,
            requestedSeason: Int = 1,
            requestedAbsoluteEpisode: Int? = nil,
            totalEpisodes: Int? = nil,
            animeTitles: [String],
            isMovie: Bool = false,
            requestedIsSpecial: Bool = false
        ) {
            self.requestedEpisode = requestedEpisode
            self.requestedSeason = requestedSeason
            self.requestedAbsoluteEpisode = requestedAbsoluteEpisode
            self.totalEpisodes = totalEpisodes
            self.animeTitles = animeTitles
            self.isMovie = isMovie
            self.requestedIsSpecial = requestedIsSpecial
        }
    }

    func match(
        _ candidate: ParsedRelease,
        providerEpisode: Int? = nil,
        providerSeason: Int? = nil,
        context: Context
    ) -> EpisodeMatchResult {
        if candidate.isExtra {
            return EpisodeMatchResult(
                confidence: 0.05,
                matchedEpisode: candidate.episode,
                reasoning: [.extraContent]
            )
        }

        if candidate.isSpecial != context.requestedIsSpecial {
            return EpisodeMatchResult(
                confidence: candidate.isSpecial ? 0.15 : 0.25,
                matchedEpisode: candidate.episode,
                reasoning: [.specialMismatch]
            )
        }

        if candidate.isSpecial && context.requestedIsSpecial {
            return EpisodeMatchResult(
                confidence: 0.85,
                matchedEpisode: candidate.episode ?? context.requestedEpisode,
                reasoning: [.specialMatch]
            )
        }

        var reasons: [EpisodeMatchReason] = []
        var confidence: Double
        var claimedEpisode = candidate.episode

        if let providerEpisode {
            claimedEpisode = providerEpisode
            reasons.append(.providerEpisodeMetadata)
            if providerEpisode == context.requestedEpisode {
                confidence = 0.97
                reasons.append(.exactEpisodeNumber)
            } else {
                confidence = 0.08
                reasons.append(.episodeMismatch)
            }
            if let providerSeason, providerSeason != context.requestedSeason {
                confidence = min(confidence, 0.3)
                reasons.append(.conflictingSeason)
            }
        } else if let episode = candidate.episode {
            if let season = candidate.season, season != context.requestedSeason {
                confidence = 0.25
                reasons.append(.conflictingSeason)
            } else if episode == context.requestedEpisode {
                if candidate.season != nil {
                    confidence = 0.97
                    reasons.append(.seasonEpisode)
                } else {
                    confidence = 0.95
                    reasons.append(.exactEpisodeNumber)
                    if context.requestedEpisode > 26 {
                        reasons.append(.absoluteNumbering)
                    }
                }
            } else if let absolute = context.requestedAbsoluteEpisode, episode == absolute {
                // Releases sometimes use absolute numbering ("Episode 28")
                // while the requested installment uses season-relative
                // numbering ("S02E03").
                confidence = 0.93
                reasons.append(.absoluteNumbering)
            } else {
                confidence = 0.08
                reasons.append(.episodeMismatch)
            }
        } else if candidate.isBatch {
            if let range = candidate.episodeRange, range.contains(context.requestedEpisode) {
                confidence = 0.84
                reasons.append(.batchRange)
            } else if candidate.episodeRange != nil {
                confidence = 0.08
                reasons.append(.episodeMismatch)
            } else {
                confidence = 0.4
                reasons.append(.batchUnknown)
            }
        } else if context.isMovie {
            confidence = 0.9
            reasons.append(.movieTitle)
        } else {
            confidence = 0.35
            reasons.append(.noEpisodeNumber)
        }

        if !context.animeTitles.isEmpty {
            let similarity = Self.titleSimilarity(
                candidateTitle: candidate.rawTitle,
                expectedTitles: context.animeTitles
            )
            if similarity >= 0.6 {
                // Title strongly agrees with the requested anime.
            } else if similarity >= 0.3 {
                confidence *= 0.85
                reasons.append(.weakTitleMatch)
            } else {
                confidence *= 0.55
                reasons.append(.titleMismatch)
            }
        }

        if let totalEpisodes = context.totalEpisodes, context.requestedEpisode > totalEpisodes {
            confidence = min(confidence, 0.55)
            reasons.append(.episodeCountMismatch)
        }

        let matchedEpisode = claimedEpisode
            ?? (confidence >= EpisodeMatchResult.safeForAutoSelectionThreshold ? context.requestedEpisode : nil)

        return EpisodeMatchResult(
            confidence: min(max(confidence, 0), 1),
            matchedEpisode: matchedEpisode,
            reasoning: reasons
        )
    }

    static func titleSimilarity(candidateTitle: String, expectedTitles: [String]) -> Double {
        let candidateTokens = ReleaseParser.titleTokens(for: candidateTitle)
        guard !candidateTokens.isEmpty else { return 0 }

        var best = 0.0
        for title in expectedTitles {
            let expectedTokens = ReleaseParser.titleTokens(for: title)
            guard !expectedTokens.isEmpty else { continue }
            let intersection = candidateTokens.intersection(expectedTokens).count
            let coverage = Double(intersection) / Double(expectedTokens.count)
            let precision = Double(intersection) / Double(candidateTokens.count)
            let union = candidateTokens.union(expectedTokens).count
            let jaccard = union > 0 ? Double(intersection) / Double(union) : 0
            best = max(best, max(coverage, max(jaccard, precision * 0.9)))
        }
        return best
    }
}
