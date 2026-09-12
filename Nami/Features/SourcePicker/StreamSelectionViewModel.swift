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

    /// A source that contains several video files and therefore needs an
    /// explicit file choice from the user before it can be resolved.
    var pendingFileCandidate: StreamCandidate?
    var pendingFiles: [DebridFileInfo] = []

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

    var isMovie: Bool {
        request.anime.subtype?.isMovie ?? false
    }

    var isChoosingFile: Bool {
        pendingFileCandidate != nil
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

        let result = await environment.streamPreload.streams(anime: anime, episode: episode)

        decision = result.decision
        ranked = result.ranked
        addonResults = result.addonResults
        debridAvailable = result.debridAvailable

        if !request.prefersManualSelection,
           result.decision.shouldAutoPlay,
           let candidate = result.decision.candidate {
            if await offerFileSelection(for: candidate) {
                phase = .picker
            } else {
                await resolve(candidate, episode: episode)
            }
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
        if await offerFileSelection(for: scored.candidate) { return }
        await resolve(scored.candidate, episode: effectiveEpisode)
    }

    /// Resolves the pending candidate with the file the user picked.
    func chooseFile(_ file: DebridFileInfo) async {
        guard let candidate = pendingFileCandidate else { return }
        pendingFileCandidate = nil
        pendingFiles = []
        await resolve(candidate, episode: effectiveEpisode, fileID: file.id)
    }

    func cancelFileSelection() {
        pendingFileCandidate = nil
        pendingFiles = []
    }

    /// Movies are occasionally packaged as several files (split parts or
    /// per-episode files). When that happens the user has to pick the file
    /// instead of letting automatic selection guess.
    private func offerFileSelection(for candidate: StreamCandidate) async -> Bool {
        guard isMovie else { return false }
        resolvingCandidateID = candidate.id
        defer { resolvingCandidateID = nil }
        guard let files = try? await environment.sourceResolver.files(for: candidate) else {
            return false
        }
        let playable = TorrentFileSelector.playableFiles(from: files)
        guard playable.count > 1 else { return false }
        pendingFileCandidate = candidate
        pendingFiles = playable
        return true
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

    private func resolve(_ candidate: StreamCandidate, episode: Episode, fileID: Int? = nil) async {
        resolvingCandidateID = candidate.id
        defer { resolvingCandidateID = nil }

        // The validated lookup skips cached-known-bad sources and reuses a
        // stream that the detail page already prefetched.
        switch await environment.streamPlayback.stream(
            for: candidate,
            fileID: fileID,
            anime: request.anime,
            episode: episode
        ) {
        case .ready(let stream):
            start(stream, episode: episode)
        case .unavailable:
            phase = .failed("This source is no longer available. Pick another one.")
        case .blocked(let error):
            phase = .failed(
                error?.errorDescription ?? "Real-Debrid is unavailable right now."
            )
        }
    }

    private func start(_ stream: ResolvedStream, episode: Episode) {
        environment.playback.start(
            stream: stream,
            anime: request.anime,
            episode: episode,
            startAt: request.startPositionSeconds
        )
        phase = .started
    }
}
