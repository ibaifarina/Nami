import Foundation
import Observation

/// Tracks the active intro/outro/recap interval during playback so the player
/// can offer a skip button.
///
/// Timings are fetched lazily from AniSkip once the media duration is known.
/// Missing MAL IDs, absent skip data, and network failures are all treated as
/// "no button" rather than playback errors.
@MainActor
@Observable
final class SkipIntroController {
    private let skipTimes: AniSkipService
    private let identityResolver: MediaIdentityResolver?
    private let preferences: PreferencesStore

    private var sessionToken = UUID()
    private var lastAnimeID: String?
    private var lastEpisodeNumber: Int?
    private var lastTime: Double = 0
    private var hasRequested = false
    private var intervals: [SkipInterval] = []
    private var fetchTask: Task<Void, Never>?

    /// The interval the playhead is currently inside, if any.
    private(set) var activeInterval: SkipInterval?

    /// Called with the target position when the user taps the skip button.
    var onSkip: ((Double) -> Void)?

    init(
        skipTimes: AniSkipService,
        identityResolver: MediaIdentityResolver? = nil,
        preferences: PreferencesStore
    ) {
        self.skipTimes = skipTimes
        self.identityResolver = identityResolver
        self.preferences = preferences
    }

    func progressTick(anime: Anime, episode: Episode, currentTime: Double, duration: Double) {
        if lastAnimeID != anime.id || lastEpisodeNumber != episode.displayNumber {
            resetForSession(anime: anime, episode: episode)
        }
        lastTime = currentTime

        guard preferences.skipIntroEnabled else {
            setActive(nil)
            return
        }
        if !hasRequested, duration.isFinite, duration > 0 {
            startFetch(anime: anime, episode: episode, duration: duration)
        }
        updateActive()
    }

    /// Jumps past the active interval. Does nothing when no interval is active.
    func skip() {
        guard let activeInterval else { return }
        setActive(nil)
        onSkip?(activeInterval.endSeconds)
    }

    func reset() {
        sessionToken = UUID()
        fetchTask?.cancel()
        fetchTask = nil
        intervals = []
        hasRequested = false
        lastAnimeID = nil
        lastEpisodeNumber = nil
        lastTime = 0
        setActive(nil)
    }

    private func resetForSession(anime: Anime, episode: Episode) {
        sessionToken = UUID()
        fetchTask?.cancel()
        fetchTask = nil
        intervals = []
        hasRequested = false
        lastAnimeID = anime.id
        lastEpisodeNumber = episode.displayNumber
        lastTime = 0
        setActive(nil)
    }

    private func startFetch(anime: Anime, episode: Episode, duration: Double) {
        hasRequested = true
        let identity = anime.identity
        let episodeNumber = episode.displayNumber
        let resolver = identityResolver
        let token = sessionToken
        fetchTask = Task { [weak self] in
            var malID = identity.malID
            if malID == nil, let resolver {
                malID = await resolver.resolve(identity, for: [.mal]).malID
            }
            guard !Task.isCancelled, let self, let malID else { return }
            let fetched = await self.skipTimes.intervals(
                malID: malID,
                episodeNumber: episodeNumber,
                episodeLengthSeconds: duration
            )
            guard !Task.isCancelled, token == self.sessionToken else { return }
            self.intervals = fetched.sorted { $0.startSeconds < $1.startSeconds }
            self.updateActive()
        }
    }

    private func updateActive() {
        setActive(intervals.first { $0.contains(lastTime) })
    }

    /// Assigns only on an actual change so `@Observable` does not invalidate
    /// the player on every time tick.
    private func setActive(_ interval: SkipInterval?) {
        guard activeInterval != interval else { return }
        activeInterval = interval
    }
}
