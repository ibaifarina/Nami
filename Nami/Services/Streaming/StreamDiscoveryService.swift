import Foundation

struct StreamDiscoveryResult: Sendable {
    let decision: AutoSelectDecision
    let ranked: [ScoredStream]
    let addonResults: [AddonQueryResult]
    let debridAvailable: Bool

    var failedAddons: [AddonQueryResult] {
        addonResults.filter { $0.failureMessage != nil }
    }

    static let empty = StreamDiscoveryResult(
        decision: AutoSelectDecision(
            candidate: nil,
            totalScore: 0,
            confidence: 0,
            scoreGapToSecondPlace: nil,
            reasons: [],
            shouldAutoPlay: false
        ),
        ranked: [],
        addonResults: [],
        debridAvailable: false
    )
}

/// One snapshot of a running discovery. Partial snapshots are emitted as each
/// addon answers (debrid cache status is still unknown); exactly one snapshot
/// is marked final.
struct StreamDiscoveryEvent: Sendable {
    let result: StreamDiscoveryResult
    let isFinal: Bool
}

actor StreamDiscoveryService {
    struct Request: Sendable {
        let media: MediaIdentity
        let episode: Episode
        let animeTitles: [String]
        let premiereYear: Int?
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
            premiereYear: Int? = nil,
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
            self.premiereYear = premiereYear
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
    private let profileStore: ParsingProfileStore?
    private let normalizer = StreamNormalizer()
    private let deduplicator = StreamDeduplicator()

    init(
        addonManager: AddonManager,
        debrid: (any DebridService)?,
        profileStore: ParsingProfileStore? = nil
    ) {
        self.addonManager = addonManager
        self.debrid = debrid
        self.profileStore = profileStore
    }

    /// Runs a discovery to completion and returns the final snapshot.
    /// Consumers that want partial results should use `discoverStream`.
    func discover(_ request: Request) async -> StreamDiscoveryResult {
        var latest: StreamDiscoveryResult?
        for await event in discoverStream(request) {
            latest = event.result
            if event.isFinal { break }
        }
        return latest ?? .empty
    }

    /// Streams discovery snapshots in addon completion order, followed by one
    /// final snapshot after debrid availability has been probed. Consumers may
    /// stop iterating early (for example once a confident source is found),
    /// which cancels the remaining addon requests.
    func discoverStream(_ request: Request) -> AsyncStream<StreamDiscoveryEvent> {
        AsyncStream { continuation in
            let task = Task {
                await self.run(request) { event in
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func run(
        _ request: Request,
        emit: @escaping @Sendable (StreamDiscoveryEvent) -> Void
    ) async {
        let matchContext = EpisodeMatcher.Context(
            requestedEpisode: request.episode.displayNumber,
            requestedSeason: request.episode.seasonNumber ?? 1,
            requestedAbsoluteEpisode: request.episode.absoluteNumber,
            totalEpisodes: request.totalEpisodes,
            animeTitles: request.animeTitles,
            isMovie: request.isMovie,
            requestedIsSpecial: request.isSpecial
        )
        let priorities = Dictionary(
            request.addons.map { ($0.id, $0.priority) },
            uniquingKeysWith: { first, _ in first }
        )
        let options = request.options
        let enabled = request.addons
            .filter(\.isEnabled)
            .sorted { $0.priority < $1.priority }
        let contentKind: StreamContentKind = request.isMovie ? .movie : .episode
        let profiles = await loadProfiles(for: enabled, kind: contentKind)

        var addonResults: [AddonQueryResult] = []
        var candidates: [StreamCandidate] = []
        var candidateIndexByKey: [String: Int] = [:]

        if !enabled.isEmpty {
            let manager = addonManager
            await withTaskGroup(of: AddonQueryResult.self) { group in
                for addon in enabled {
                    group.addTask {
                        await manager.query(
                            addon: addon,
                            for: request.media,
                            episode: request.episode,
                            titles: request.animeTitles,
                            year: request.premiereYear,
                            isMovie: request.isMovie
                        )
                    }
                }
                for await result in group {
                    if Task.isCancelled {
                        group.cancelAll()
                        return
                    }
                    addonResults.append(result)
                    let profile = profiles[result.addon.id]
                    Self.merge(
                        result.streams,
                        into: &candidates,
                        indexByKey: &candidateIndexByKey,
                        normalizer: normalizer,
                        deduplicator: deduplicator,
                        matchContext: matchContext,
                        profile: profile
                    )
                    if let profile {
                        await self.recordCoverage(
                            result.streams,
                            profile: profile,
                            addon: result.addon,
                            kind: contentKind
                        )
                    }
                    emit(
                        StreamDiscoveryEvent(
                            result: makeResult(
                                candidates: candidates,
                                addonResults: addonResults,
                                options: options,
                                priorities: priorities,
                                durationMinutes: request.durationMinutes,
                                isMovie: request.isMovie,
                                debridAvailable: options.debridAvailable
                            ),
                            isFinal: false
                        )
                    )
                }
            }
        }

        guard !Task.isCancelled else { return }

        let debridAvailable = await probeDebrid(
            &candidates,
            options: options,
            durationMinutes: request.durationMinutes,
            priorities: priorities,
            isMovie: request.isMovie
        )
        emit(
            StreamDiscoveryEvent(
                result: makeResult(
                    candidates: candidates,
                    addonResults: addonResults,
                    options: options,
                    priorities: priorities,
                    durationMinutes: request.durationMinutes,
                    isMovie: request.isMovie,
                    debridAvailable: debridAvailable
                ),
                isFinal: true
            )
        )
    }

    /// Normalizes one addon's streams and merges them into the running
    /// candidate set, combining duplicates that another addon already found.
    private static func merge(
        _ streams: [RawStreamResult],
        into candidates: inout [StreamCandidate],
        indexByKey: inout [String: Int],
        normalizer: StreamNormalizer,
        deduplicator: StreamDeduplicator,
        matchContext: EpisodeMatcher.Context,
        profile: ContentParsingProfile?
    ) {
        guard !streams.isEmpty else { return }
        let normalized = normalizer.normalize(
            streams,
            matching: matchContext,
            profile: profile
        )
        for candidate in deduplicator.deduplicate(normalized).candidates {
            guard let key = StreamDeduplicator.dedupeKey(for: candidate) else {
                candidates.append(candidate)
                continue
            }
            if let index = indexByKey[key], candidates.indices.contains(index) {
                candidates[index] = StreamDeduplicator.merge(candidates[index], candidate)
            } else {
                indexByKey[key] = candidates.count
                candidates.append(candidate)
            }
        }
    }

    /// Loads the calibrated parsing profile of every addon once per discovery.
    /// Does not touch the network.
    private func loadProfiles(
        for addons: [InstalledAddon],
        kind: StreamContentKind
    ) async -> [String: ContentParsingProfile] {
        guard let profileStore else { return [:] }
        var result: [String: ContentParsingProfile] = [:]
        for addon in addons {
            let fingerprint = AddonFingerprint(
                addonID: addon.id,
                manifestURL: addon.manifestURL
            )
            if let profile = await profileStore.contentProfile(for: kind, fingerprint: fingerprint) {
                result[addon.id] = profile
            }
        }
        return result
    }

    /// Feeds playback-time parse coverage back to the store so a profile that
    /// stops matching the addon's output can eventually be marked stale.
    private func recordCoverage(
        _ streams: [RawStreamResult],
        profile: ContentParsingProfile,
        addon: InstalledAddon,
        kind: StreamContentKind
    ) async {
        guard let profileStore, streams.count >= 3 else { return }
        let parser = ProfileStreamParser()
        var total = 0
        var matched = 0
        for raw in streams {
            let fields = raw.profileFields
            guard !fields.isEmpty else { continue }
            total += 1
            if !parser.parse(fields: fields, profile: profile).isEmpty {
                matched += 1
            }
        }
        guard total >= 3 else { return }
        let fingerprint = AddonFingerprint(addonID: addon.id, manifestURL: addon.manifestURL)
        await profileStore.recordObservation(
            fingerprint: fingerprint,
            kind: kind,
            matched: matched,
            total: total
        )
    }

    private func makeResult(
        candidates: [StreamCandidate],
        addonResults: [AddonQueryResult],
        options: StreamScoringOptions,
        priorities: [String: Int],
        durationMinutes: Int?,
        isMovie: Bool,
        debridAvailable: Bool
    ) -> StreamDiscoveryResult {
        var options = options
        options.debridAvailable = debridAvailable
        let context = ScoringContext(
            episodeDurationMinutes: durationMinutes,
            addonPriorities: priorities,
            debridAvailable: debridAvailable,
            isMovie: isMovie
        )
        let engine = StreamScoringEngine(options: options)
        return StreamDiscoveryResult(
            decision: engine.selectBest(candidates, context: context),
            ranked: engine.rank(candidates, context: context),
            addonResults: addonResults,
            debridAvailable: debridAvailable
        )
    }

    private func probeDebrid(
        _ candidates: inout [StreamCandidate],
        options: StreamScoringOptions,
        durationMinutes: Int?,
        priorities: [String: Int],
        isMovie: Bool
    ) async -> Bool {
        guard let debrid else { return false }
        do {
            // Availability probes are rate limited, so probe the most
            // promising candidates first instead of raw addon order.
            let rankingContext = ScoringContext(
                episodeDurationMinutes: durationMinutes,
                addonPriorities: priorities,
                debridAvailable: true,
                isMovie: isMovie
            )
            let probeOrder = StreamScoringEngine(options: options)
                .rank(candidates, context: rankingContext)
                .map(\.candidate)
            let checks = try await debrid.checkAvailability(probeOrder)
            let availabilityByID = Dictionary(
                checks.map { ($0.candidateID, $0.availability) },
                uniquingKeysWith: { first, _ in first }
            )
            for index in candidates.indices {
                if let availability = availabilityByID[candidates[index].id] {
                    candidates[index].debridStatus = availability
                }
            }
            return true
        } catch let error as DebridError where error == .notConfigured {
            return false
        } catch {
            // The service is configured but failed (outage, rate limit, ...).
            // Keep torrent candidates available; availability stays unknown.
            return true
        }
    }
}

extension StreamDiscoveryService.Request {
    init(
        anime: Anime,
        episode: Episode,
        addons: [InstalledAddon],
        options: StreamScoringOptions
    ) {
        self.init(
            media: anime.identity,
            episode: episode,
            animeTitles: [anime.englishTitle, anime.romajiTitle, anime.japaneseTitle, anime.title]
                .compactMap { $0 },
            premiereYear: anime.startYear,
            totalEpisodes: anime.episodesAvailable,
            durationMinutes: anime.durationMinutes,
            isMovie: anime.subtype?.isMovie ?? false,
            isSpecial: anime.subtype == .special,
            addons: addons,
            options: options
        )
    }
}
