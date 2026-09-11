import Foundation
import Observation

struct PlaybackRequest: Identifiable {
    let anime: Anime
    let episode: Episode
    var prefersManualSelection: Bool = false
    var startPositionSeconds: Double? = nil

    var id: String { "\(anime.id)-\(episode.id)" }
    var episodeNumber: Int { episode.displayNumber }

    init(
        anime: Anime,
        episode: Episode,
        prefersManualSelection: Bool = false,
        startPositionSeconds: Double? = nil
    ) {
        self.anime = anime
        self.episode = episode
        self.prefersManualSelection = prefersManualSelection
        self.startPositionSeconds = startPositionSeconds
    }

    /// Convenience for callers that only know an episode number. Episode
    /// metadata is completed by the source picker when available.
    init(
        anime: Anime,
        episodeNumber: Int,
        prefersManualSelection: Bool = false,
        startPositionSeconds: Double? = nil
    ) {
        self.init(
            anime: anime,
            episode: Episode(
                id: "\(anime.id)-\(episodeNumber)",
                animeID: anime.id,
                number: episodeNumber,
                durationMinutes: anime.durationMinutes
            ),
            prefersManualSelection: prefersManualSelection,
            startPositionSeconds: startPositionSeconds
        )
    }
}

@MainActor
@Observable
final class StreamSelectionViewModel {
    enum Phase: Equatable {
        case loading
        case picker
        case started
        case failed(String)
    }

    let request: PlaybackRequest
    private let environment: AppEnvironment

    var phase: Phase = .loading
    var decision: AutoSelectDecision?
    var ranked: [ScoredStream] = []
    var addonResults: [AddonQueryResult] = []
    var resolvingCandidateID: String?
    var debridAvailable = false

    /// The episode used for stream discovery, enriched with real Kitsu
    /// metadata (season/absolute numbering) when available.
    private(set) var effectiveEpisode: Episode

    init(request: PlaybackRequest, environment: AppEnvironment) {
        self.request = request
        self.environment = environment
        effectiveEpisode = request.episode
    }

    var showDebugInfo: Bool {
        environment.preferences.showStreamScoringDebugInfo
    }

    var eligibleStreams: [ScoredStream] {
        ranked.filter(\.isAutoEligible)
    }

    var rejectedStreams: [ScoredStream] {
        ranked.filter { !$0.isAutoEligible }
    }

    var bestMatch: ScoredStream? {
        eligibleStreams.first
    }

    var otherStreams: [ScoredStream] {
        Array(eligibleStreams.dropFirst())
    }

    var hasAnyCandidates: Bool {
        !ranked.isEmpty
    }

    var enabledAddonCount: Int {
        environment.addons.enabledAddons.count
    }

    var addonFailureMessages: [String] {
        addonResults.compactMap(\.failureMessage)
    }

    func start() async {
        phase = .loading
        decision = nil
        ranked = []
        addonResults = []

        let anime = request.anime
        var episode = request.episode
        if episode.absoluteNumber == nil, let resolved = await resolveEpisodeMetadata(episode) {
            episode = resolved
        }
        effectiveEpisode = episode
        let options = StreamScoringOptions(
            preferences: environment.preferences.preferences,
            debridAvailable: environment.debridAuth.isConnected
        )
        let titles = [anime.englishTitle, anime.romajiTitle, anime.japaneseTitle, anime.title]
            .compactMap { $0 }

        let result = await environment.streamDiscovery.discover(
            StreamDiscoveryService.Request(
                media: anime.identity,
                episode: episode,
                animeTitles: titles,
                totalEpisodes: anime.episodesAvailable,
                durationMinutes: anime.durationMinutes,
                isMovie: anime.subtype?.isMovie ?? false,
                isSpecial: anime.subtype == .special,
                addons: environment.addons.enabledAddons,
                options: options
            )
        )

        decision = result.decision
        ranked = result.ranked
        addonResults = result.addonResults
        debridAvailable = result.debridAvailable

        if !request.prefersManualSelection,
           result.decision.shouldAutoPlay,
           let candidate = result.decision.candidate {
            await resolve(candidate, episode: episode)
        } else {
            phase = .picker
        }
    }

    func showPicker() {
        if phase != .loading {
            phase = .picker
        }
    }

    func choose(_ scored: ScoredStream) async {
        await resolve(scored.candidate, episode: effectiveEpisode)
    }

    func retry() async {
        await start()
    }

    /// If the caller only knew an episode number, look up the real Kitsu
    /// episode so streaming gets season/absolute numbering.
    private func resolveEpisodeMetadata(_ episode: Episode) async -> Episode? {
        guard
            let episodes = try? await environment.episodes.episodes(
                forAnimeID: request.anime.id,
                isAiring: request.anime.status?.isAiring ?? false
            )
        else {
            return nil
        }
        return episodes.first { $0.number == episode.number || $0.displayNumber == episode.number }
    }

    private func resolve(_ candidate: StreamCandidate, episode: Episode) async {
        resolvingCandidateID = candidate.id
        defer { resolvingCandidateID = nil }
        do {
            let stream = try await environment.debrid.resolve(candidate)
            environment.playback.start(
                stream: stream,
                anime: request.anime,
                episode: episode,
                startAt: request.startPositionSeconds
            )
            phase = .started
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        if let debridError = error as? DebridError {
            return debridError.errorDescription ?? "The stream could not be resolved."
        }
        return error.localizedDescription
    }
}
