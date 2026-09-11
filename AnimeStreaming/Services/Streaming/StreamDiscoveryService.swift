import Foundation

struct StreamDiscoveryResult: Sendable {
    let decision: AutoSelectDecision
    let ranked: [ScoredStream]
    let addonResults: [AddonQueryResult]
    let debridAvailable: Bool

    var failedAddons: [AddonQueryResult] {
        addonResults.filter { $0.failureMessage != nil }
    }
}

actor StreamDiscoveryService {
    struct Request: Sendable {
        let media: MediaIdentity
        let episode: Episode
        let animeTitles: [String]
        let totalEpisodes: Int?
        let durationMinutes: Int?
        let isMovie: Bool
        let isSpecial: Bool
        let addons: [InstalledAddon]
        let options: StreamScoringOptions

        init(
            media: MediaIdentity,
            episode: Episode,
            animeTitles: [String],
            totalEpisodes: Int?,
            durationMinutes: Int?,
            isMovie: Bool = false,
            isSpecial: Bool = false,
            addons: [InstalledAddon],
            options: StreamScoringOptions
        ) {
            self.media = media
            self.episode = episode
            self.animeTitles = animeTitles
            self.totalEpisodes = totalEpisodes
            self.durationMinutes = durationMinutes
            self.isMovie = isMovie
            self.isSpecial = isSpecial
            self.addons = addons
            self.options = options
        }
    }

    private let addonManager: AddonManager
    private let debrid: (any DebridService)?
    private let normalizer = StreamNormalizer()
    private let deduplicator = StreamDeduplicator()

    init(addonManager: AddonManager, debrid: (any DebridService)?) {
        self.addonManager = addonManager
        self.debrid = debrid
    }

    func discover(_ request: Request) async -> StreamDiscoveryResult {
        let addonResults = await addonManager.queryStreams(
            for: request.media,
            episode: request.episode,
            addons: request.addons
        )

        let matchContext = EpisodeMatcher.Context(
            requestedEpisode: request.episode.displayNumber,
            requestedSeason: request.episode.seasonNumber ?? 1,
            requestedAbsoluteEpisode: request.episode.absoluteNumber,
            totalEpisodes: request.totalEpisodes,
            animeTitles: request.animeTitles,
            isMovie: request.isMovie,
            requestedIsSpecial: request.isSpecial
        )
        let raws = addonResults.flatMap(\.streams)
        let normalized = normalizer.normalize(raws, matching: matchContext)
        let deduplicated = deduplicator.deduplicate(normalized).candidates
        var candidates = deduplicated

        var debridAvailable = false
        if let debrid {
            do {
                let checks = try await debrid.checkAvailability(candidates)
                let availabilityByID = Dictionary(
                    checks.map { ($0.candidateID, $0.availability) },
                    uniquingKeysWith: { first, _ in first }
                )
                for index in candidates.indices {
                    if let availability = availabilityByID[candidates[index].id] {
                        candidates[index].debridStatus = availability
                    }
                }
                debridAvailable = true
            } catch let error as DebridError where error == .notConfigured {
                debridAvailable = false
            } catch {
                // The service is configured but failed (outage, rate limit, ...).
                // Keep torrent candidates available; availability stays unknown.
                debridAvailable = true
            }
        }

        let priorities = Dictionary(
            request.addons.map { ($0.id, $0.priority) },
            uniquingKeysWith: { first, _ in first }
        )
        var options = request.options
        options.debridAvailable = debridAvailable
        let scoringContext = ScoringContext(
            episodeDurationMinutes: request.durationMinutes,
            addonPriorities: priorities,
            debridAvailable: debridAvailable
        )
        let engine = StreamScoringEngine(options: options)
        return StreamDiscoveryResult(
            decision: engine.selectBest(candidates, context: scoringContext),
            ranked: engine.rank(candidates, context: scoringContext),
            addonResults: addonResults,
            debridAvailable: debridAvailable
        )
    }
}
