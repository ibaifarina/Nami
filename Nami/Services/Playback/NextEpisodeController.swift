import Foundation
import Observation

@MainActor
@Observable
final class NextEpisodeController {
    enum Overlay: Equatable {
        case hidden
        case preparing
        case countdown(seconds: Int)
        case readyToChoose
    }

    private struct PreparedDecision {
        let episodeNumber: Int
        let result: StreamDiscoveryResult
        let createdAt: Date
    }

    private let discovery: StreamDiscoveryService
    private let streamPlayback: any StreamPlaybackProviding
    private let preferences: PreferencesStore
    private let registry: AddonRegistry

    private let prefetchFraction: Double
    private let prefetchRemainingSeconds: Double
    private let overlayLeadSeconds: Double
    private let countdownSeconds: Int
    private let cacheTTL: TimeInterval

    var startPlayback: ((ResolvedStream, Anime, Episode) -> Void)?

    private(set) var overlay: Overlay = .hidden
    private(set) var nextEpisodeNumber: Int?
    private(set) var preparedDecision: AutoSelectDecision?
    private(set) var preparedEpisodeNumber: Int?
    private(set) var prepareError: String?

    private var currentAnime: Anime?
    private var currentEpisode: Episode?
    private var lastAnimeID: String?
    private var lastEpisodeNumber: Int?
    private var prepared: PreparedDecision?
    private var prefetchTask: Task<Void, Never>?
    private var sessionToken = UUID()
    private var hasPrefetched = false
    private var autoplayCancelled = false
    private var advanceInFlight = false

    init(
        discovery: StreamDiscoveryService,
        streamPlayback: any StreamPlaybackProviding,
        preferences: PreferencesStore,
        registry: AddonRegistry,
        prefetchFraction: Double = 0.75,
        prefetchRemainingSeconds: Double = 360,
        overlayLeadSeconds: Double = 15,
        countdownSeconds: Int = 10,
        cacheTTL: TimeInterval = 600
    ) {
        self.discovery = discovery
        self.streamPlayback = streamPlayback
        self.preferences = preferences
        self.registry = registry
        self.prefetchFraction = prefetchFraction
        self.prefetchRemainingSeconds = prefetchRemainingSeconds
        self.overlayLeadSeconds = overlayLeadSeconds
        self.countdownSeconds = countdownSeconds
        self.cacheTTL = cacheTTL
    }

    var isPreparing: Bool {
        if case .preparing = overlay { return true }
        return false
    }

    var isAdvancing: Bool { advanceInFlight }

    var nextEpisodeRequest: PlaybackRequest? {
        guard let currentAnime, let episode = nextEpisode() else { return nil }
        return PlaybackRequest(
            anime: currentAnime,
            episode: episode,
            prefersManualSelection: true
        )
    }

    var hasPreparedDecision: Bool {
        prepared != nil && prepared?.episodeNumber == nextEpisodeNumber
    }

    // MARK: - Playback events

    func progressTick(anime: Anime, episode: Episode, currentTime: Double, duration: Double) {
        if lastAnimeID != anime.id || lastEpisodeNumber != episode.displayNumber {
            resetForSession(anime: anime, episode: episode)
            lastAnimeID = anime.id
            lastEpisodeNumber = episode.displayNumber
        }
        guard duration > 0 else { return }

        guard preferences.autoplayNextEpisode else {
            cancelPrefetch()
            setOverlay(.hidden)
            return
        }
        guard let nextEpisodeNumber, !autoplayCancelled else {
            setOverlay(.hidden)
            return
        }

        let remaining = duration - currentTime
        let fraction = currentTime / duration

        if !hasPrefetched, fraction >= prefetchFraction || remaining <= prefetchRemainingSeconds {
            startPrefetch(anime: anime, episodeNumber: nextEpisodeNumber)
        }

        if let prepared, prepared.episodeNumber == nextEpisodeNumber {
            if Date().timeIntervalSince(prepared.createdAt) > cacheTTL {
                self.prepared = nil
                preparedDecision = nil
                preparedEpisodeNumber = nil
                hasPrefetched = false
                if fraction >= prefetchFraction || remaining <= prefetchRemainingSeconds {
                    startPrefetch(anime: anime, episodeNumber: nextEpisodeNumber)
                }
            } else if remaining <= overlayLeadSeconds {
                if prepared.result.decision.shouldAutoPlay {
                    setOverlay(.countdown(seconds: countdown(for: remaining)))
                } else {
                    setOverlay(.readyToChoose)
                }
            } else if case .countdown = overlay {
                setOverlay(.hidden)
            } else if case .readyToChoose = overlay {
                setOverlay(.hidden)
            }
        } else if remaining <= overlayLeadSeconds, hasPrefetched {
            setOverlay(.preparing)
        } else if remaining > overlayLeadSeconds {
            if case .preparing = overlay {
                setOverlay(.hidden)
            }
        }

        if remaining <= 0.5 {
            advanceIfNeeded()
        }
    }

    func playbackEnded() {
        guard preferences.autoplayNextEpisode, !autoplayCancelled else {
            setOverlay(.hidden)
            return
        }
        guard nextEpisodeNumber != nil else {
            setOverlay(.hidden)
            return
        }
        advanceIfNeeded()
    }

    func reset() {
        sessionToken = UUID()
        prefetchTask?.cancel()
        prefetchTask = nil
        prepared = nil
        preparedDecision = nil
        preparedEpisodeNumber = nil
        prepareError = nil
        setOverlay(.hidden)
        hasPrefetched = false
        autoplayCancelled = false
        advanceInFlight = false
        currentAnime = nil
        currentEpisode = nil
        nextEpisodeNumber = nil
        lastAnimeID = nil
        lastEpisodeNumber = nil
    }

    // MARK: - User actions

    func playNow() {
        guard hasPreparedDecision else { return }
        advanceIfNeeded()
    }

    func cancelCountdown() {
        autoplayCancelled = true
        setOverlay(.hidden)
    }

    func dismissOverlay() {
        setOverlay(.hidden)
    }

    // MARK: - Prefetch

    private func startPrefetch(anime: Anime, episodeNumber: Int) {
        guard !hasPrefetched else { return }
        guard !registry.enabledAddons.isEmpty else { return }
        guard let episode = nextEpisode(matching: episodeNumber) else { return }
        hasPrefetched = true
        prepareError = nil

        let token = sessionToken
        let options = StreamScoringOptions(
            preferences: preferences.preferences,
            debridAvailable: true
        )
        let request = StreamDiscoveryService.Request(
            anime: anime,
            episode: episode,
            addons: registry.enabledAddons,
            options: options
        )

        prefetchTask = Task { [weak self] in
            let result = await self?.discovery.discover(request)
            guard let self, !Task.isCancelled, token == self.sessionToken, let result else { return }
            self.prepared = PreparedDecision(
                episodeNumber: episodeNumber,
                result: result,
                createdAt: Date()
            )
            self.preparedDecision = result.decision
            self.preparedEpisodeNumber = episodeNumber
            if self.overlay == .preparing {
                self.setOverlay(
                    result.decision.shouldAutoPlay ? .countdown(seconds: self.countdownSeconds) : .readyToChoose
                )
            }
        }
    }

    private func cancelPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
        if prepared != nil {
            prepared = nil
        }
        if preparedDecision != nil {
            preparedDecision = nil
        }
        if preparedEpisodeNumber != nil {
            preparedEpisodeNumber = nil
        }
        if hasPrefetched {
            hasPrefetched = false
        }
    }

    /// Assigns only on an actual change: the progress tick runs several times a
    /// second and `@Observable` notifies on every set, even for equal values.
    private func setOverlay(_ newOverlay: Overlay) {
        guard overlay != newOverlay else { return }
        overlay = newOverlay
    }

    // MARK: - Advancing

    private func advanceIfNeeded() {
        guard !advanceInFlight else { return }
        guard let prepared, prepared.episodeNumber == nextEpisodeNumber else {
            if nextEpisodeNumber != nil, hasPrefetched {
                setOverlay(.preparing)
            } else if nextEpisodeNumber != nil {
                setOverlay(.readyToChoose)
            }
            return
        }
        guard let candidate = prepared.result.decision.candidate,
              prepared.result.decision.shouldAutoPlay else {
            setOverlay(.readyToChoose)
            return
        }
        advanceInFlight = true
        setOverlay(.hidden)

        Task { [weak self] in
            guard let self else { return }
            guard let anime = self.currentAnime, let episode = self.nextEpisode() else {
                self.advanceInFlight = false
                return
            }
            for next in self.candidateChain(primary: candidate, result: prepared.result) {
                switch await self.streamPlayback.stream(for: next, anime: anime, episode: episode) {
                case .ready(let stream):
                    self.advanceInFlight = false
                    self.startPlayback?(stream, anime, episode)
                    return
                case .unavailable:
                    continue
                case .blocked(let error):
                    self.advanceInFlight = false
                    self.prepareError = error?.errorDescription
                        ?? String(localized: "Real-Debrid is unavailable right now.")
                    self.setOverlay(.readyToChoose)
                    return
                }
            }
            self.advanceInFlight = false
            self.prepareError = String(localized: "No playable source was found for the next episode.")
            self.setOverlay(.readyToChoose)
        }
    }

    private func candidateChain(
        primary: StreamCandidate,
        result: StreamDiscoveryResult
    ) -> [StreamCandidate] {
        var chain = [primary]
        for scored in result.ranked
        where scored.isAutoEligible && scored.candidate.id != primary.id {
            chain.append(scored.candidate)
        }
        return chain
    }

    private func resetForSession(anime: Anime, episode: Episode) {
        sessionToken = UUID()
        prefetchTask?.cancel()
        prefetchTask = nil
        prepared = nil
        preparedDecision = nil
        preparedEpisodeNumber = nil
        prepareError = nil
        setOverlay(.hidden)
        hasPrefetched = false
        autoplayCancelled = false
        advanceInFlight = false
        currentAnime = anime
        currentEpisode = episode
        let available = anime.episodesAvailable ?? 0
        nextEpisodeNumber = episode.number + 1 <= available ? episode.number + 1 : nil
    }

    private func nextEpisode() -> Episode? {
        guard let nextEpisodeNumber else { return nil }
        return nextEpisode(matching: nextEpisodeNumber)
    }

    private func nextEpisode(matching number: Int) -> Episode? {
        guard let anime = currentAnime, let currentEpisode else { return nil }
        return Episode(
            id: "\(anime.id)-\(number)",
            animeID: anime.id,
            number: number,
            relativeNumber: number,
            seasonNumber: currentEpisode.seasonNumber,
            absoluteNumber: currentEpisode.absoluteNumber.map { $0 + (number - currentEpisode.number) },
            durationMinutes: anime.durationMinutes
        )
    }

    private func countdown(for remaining: Double) -> Int {
        max(0, min(countdownSeconds, Int(ceil(remaining))))
    }
}
