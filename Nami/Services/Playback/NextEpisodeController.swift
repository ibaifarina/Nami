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
    private let resolver: SourceResolver
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
        resolver: SourceResolver,
        preferences: PreferencesStore,
        registry: AddonRegistry,
        prefetchFraction: Double = 0.75,
        prefetchRemainingSeconds: Double = 360,
        overlayLeadSeconds: Double = 15,
        countdownSeconds: Int = 10,
        cacheTTL: TimeInterval = 600
    ) {
        self.discovery = discovery
        self.resolver = resolver
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
            overlay = .hidden
            return
        }
        guard let nextEpisodeNumber, !autoplayCancelled else {
            overlay = .hidden
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
                    overlay = .countdown(seconds: countdown(for: remaining))
                } else {
                    overlay = .readyToChoose
                }
            } else if case .countdown = overlay {
                overlay = .hidden
            } else if case .readyToChoose = overlay {
                overlay = .hidden
            }
        } else if remaining <= overlayLeadSeconds, hasPrefetched {
            overlay = .preparing
        } else if remaining > overlayLeadSeconds {
            if case .preparing = overlay {
                overlay = .hidden
            }
        }

        if remaining <= 0.5 {
            advanceIfNeeded()
        }
    }

    func playbackEnded() {
        guard preferences.autoplayNextEpisode, !autoplayCancelled else {
            overlay = .hidden
            return
        }
        guard nextEpisodeNumber != nil else {
            overlay = .hidden
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
        overlay = .hidden
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
        overlay = .hidden
    }

    func dismissOverlay() {
        overlay = .hidden
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
                self.overlay = result.decision.shouldAutoPlay ? .countdown(seconds: self.countdownSeconds) : .readyToChoose
            }
        }
    }

    private func cancelPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
        prepared = nil
        preparedDecision = nil
        preparedEpisodeNumber = nil
        hasPrefetched = false
    }

    // MARK: - Advancing

    private func advanceIfNeeded() {
        guard !advanceInFlight else { return }
        guard let prepared, prepared.episodeNumber == nextEpisodeNumber else {
            if nextEpisodeNumber != nil, hasPrefetched {
                overlay = .preparing
            } else if nextEpisodeNumber != nil {
                overlay = .readyToChoose
            }
            return
        }
        guard let candidate = prepared.result.decision.candidate,
              prepared.result.decision.shouldAutoPlay else {
            overlay = .readyToChoose
            return
        }
        advanceInFlight = true
        overlay = .hidden

        Task { [weak self] in
            guard let self else { return }
            guard let anime = self.currentAnime, let episode = self.nextEpisode() else {
                self.advanceInFlight = false
                return
            }
            do {
                let stream = try await self.resolver.resolve(candidate, anime: anime, episode: episode)
                self.advanceInFlight = false
                self.startPlayback?(stream, anime, episode)
            } catch {
                self.advanceInFlight = false
                self.prepareError = (error as? DebridError)?.errorDescription
                    ?? error.localizedDescription
                self.overlay = .readyToChoose
            }
        }
    }

    private func resetForSession(anime: Anime, episode: Episode) {
        sessionToken = UUID()
        prefetchTask?.cancel()
        prefetchTask = nil
        prepared = nil
        preparedDecision = nil
        preparedEpisodeNumber = nil
        prepareError = nil
        overlay = .hidden
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
