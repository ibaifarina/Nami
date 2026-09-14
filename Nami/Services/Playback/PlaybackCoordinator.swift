import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class PlaybackCoordinator {
    enum State: Equatable {
        case idle
        case loading
        case playing
        case paused
        case ended
        case failed(String)
    }

    private struct Session {
        let anime: Anime
        let episode: Episode
        let stream: ResolvedStream
    }

    private let engineFactory: (PlaybackEngineKind) -> any PlayerEngine
    private var engine: any PlayerEngine
    private let progressStore: any PlaybackProgressStore
    private let preferences: PreferencesStore
    private let library: any LibraryRepository
    private let externalPlayers: any ExternalPlayerOpening
    private let completionService = PlaybackCompletionService()
    private var session: Session?
    private var lastProgressWrite = Date.distantPast
    private var lastSyncedLibraryProgress: Int?
    private var previousVolume: Double = 1
    private var hasCompletedSession = false
    private var hasAppliedAutomaticTrackSelection = false

    var onPlaybackTick: ((Anime, Episode, Double, Double) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onSessionClosed: (() -> Void)?
    /// Called after a progress snapshot has been persisted, so open screens can
    /// refresh watched state without polling the store.
    var onProgressSaved: ((PlaybackProgress) -> Void)?
    /// Called when a stream fails to load or play so callers can invalidate
    /// any cached source for the episode.
    var onStreamFailed: ((Anime, Episode) -> Void)?

    private(set) var engineKind: PlaybackEngineKind
    private(set) var engineGeneration = 0
    private(set) var presentationGeneration = 0
    private(set) var state: State = .idle
    private(set) var isPresenting = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var volume: Double = 1
    private(set) var isMuted = false
    private(set) var rate: Double = 1
    private(set) var title = ""
    private(set) var episodeLabel = ""
    private(set) var audioTracks: [MediaTrack] = []
    private(set) var subtitleTracks: [MediaTrack] = []
    private(set) var selectedAudioTrackID: String?
    private(set) var selectedSubtitleTrackID: String?

    init(
        engineKind: PlaybackEngineKind = .mpv,
        engineFactory: ((PlaybackEngineKind) -> any PlayerEngine)? = nil,
        engine: (any PlayerEngine)? = nil,
        progressStore: any PlaybackProgressStore,
        preferences: PreferencesStore,
        library: any LibraryRepository,
        externalPlayers: any ExternalPlayerOpening = ExternalPlayerService()
    ) {
        let factory = engineFactory ?? PlaybackEngineFactory.make
        self.engineKind = engineKind
        self.engineFactory = factory
        self.engine = engine ?? factory(engineKind)
        self.progressStore = progressStore
        self.preferences = preferences
        self.library = library
        self.externalPlayers = externalPlayers
        volume = self.engine.volume
        previousVolume = self.engine.volume

        bindEngineCallbacks()
    }

    private func bindEngineCallbacks() {
        engine.onStateChange = { [weak self] engineState in
            self?.engineStateChanged(engineState)
        }
        engine.onTimeChange = { [weak self] time, duration in
            self?.timeChanged(time, duration)
        }
        engine.onTracksChange = { [weak self] in
            self?.tracksChanged()
        }
    }

    private func unbindEngineCallbacks() {
        engine.onStateChange = nil
        engine.onTimeChange = nil
        engine.onTracksChange = nil
    }

    func selectEngine(_ kind: PlaybackEngineKind) {
        guard kind != engineKind else { return }
        let resume = session.map { ($0.stream, currentTime > 5 ? currentTime : nil) }
        engine.stop()
        engine.shutdown()
        unbindEngineCallbacks()
        engineKind = kind
        engine = engineFactory(kind)
        bindEngineCallbacks()
        engineGeneration += 1
        hasAppliedAutomaticTrackSelection = false
        volume = engine.volume
        previousVolume = engine.volume
        engine.setRate(rate)

        if let resume {
            state = .loading
            let (stream, startAt) = resume
            Task { [weak self] in
                await self?.begin(stream: stream, startAt: startAt)
            }
        }
    }

    func shutdown() {
        engine.shutdown()
    }

    var isPlaying: Bool {
        state == .playing
    }

    /// True while the player is visible but no stream has been resolved for it
    /// yet.
    var isAwaitingSource: Bool {
        isPresenting && session == nil
    }

    /// Whether playback will be handed off to a configured external player
    /// instead of the built-in one.
    var usesExternalPlayback: Bool {
        externalPlayer() != nil
    }

    var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    func start(stream: ResolvedStream, anime: Anime, episode: Episode, startAt: Double?) {
        guard let player = externalPlayer() else {
            startBuiltIn(stream: stream, anime: anime, episode: episode, startAt: startAt)
            return
        }
        if session != nil || isPresenting {
            close()
        }
        Task { [weak self] in
            await self?.openExternally(
                stream: stream,
                anime: anime,
                episode: episode,
                player: player,
                startAt: startAt
            )
        }
    }

    private func externalPlayer() -> ExternalPlayer? {
        guard let bundleID = preferences.externalPlayerBundleID, !bundleID.isEmpty else {
            return nil
        }
        return externalPlayers.detectedPlayers().first { $0.bundleID == bundleID }
    }

    private func openExternally(
        stream: ResolvedStream,
        anime: Anime,
        episode: Episode,
        player: ExternalPlayer,
        startAt: Double?
    ) async {
        do {
            try await externalPlayers.open(stream.url, in: player)
        } catch {
            AppLogger.playback.error(
                "Could not open \(player.bundleID, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            startBuiltIn(stream: stream, anime: anime, episode: episode, startAt: startAt)
        }
    }

    private func startBuiltIn(stream: ResolvedStream, anime: Anime, episode: Episode, startAt: Double?) {
        session = Session(anime: anime, episode: episode, stream: stream)
        title = anime.displayTitle(for: preferences.animeTitleLanguage)
        episodeLabel = String(localized: "Episode \(episode.displayNumber)")
        isPresenting = true
        state = .loading
        currentTime = 0
        duration = 0
        audioTracks = []
        subtitleTracks = []
        selectedAudioTrackID = nil
        selectedSubtitleTrackID = nil
        hasAppliedAutomaticTrackSelection = false
        lastProgressWrite = .distantPast
        lastSyncedLibraryProgress = nil
        hasCompletedSession = false
        presentationGeneration += 1

        Task { [weak self] in
            await self?.begin(stream: stream, startAt: startAt)
        }
    }

    /// Presents the built-in player in its loading state before a stream has
    /// been resolved. Callers resolve a source and then hand it to
    /// `start(stream:anime:episode:startAt:)`.
    func presentLoading(anime: Anime, episode: Episode) {
        if session != nil || isPresenting {
            close()
        }
        session = nil
        title = anime.displayTitle(for: preferences.animeTitleLanguage)
        episodeLabel = String(localized: "Episode \(episode.displayNumber)")
        isPresenting = true
        state = .loading
        currentTime = 0
        duration = 0
        audioTracks = []
        subtitleTracks = []
        selectedAudioTrackID = nil
        selectedSubtitleTrackID = nil
        hasAppliedAutomaticTrackSelection = false
        lastProgressWrite = .distantPast
        lastSyncedLibraryProgress = nil
        hasCompletedSession = false
        presentationGeneration += 1
    }

    func retry() {
        guard let session else { return }
        state = .loading
        let stream = session.stream
        let resumeAt = currentTime > 5 ? currentTime : nil
        Task { [weak self] in
            await self?.begin(stream: stream, startAt: resumeAt)
        }
    }

    func close() {
        writeProgress(force: true)
        engine.stop()
        session = nil
        isPresenting = false
        state = .idle
        currentTime = 0
        duration = 0
        audioTracks = []
        subtitleTracks = []
        selectedAudioTrackID = nil
        selectedSubtitleTrackID = nil
        hasAppliedAutomaticTrackSelection = false
        title = ""
        episodeLabel = ""
        lastSyncedLibraryProgress = nil
        hasCompletedSession = false
        presentationGeneration += 1
        onSessionClosed?()
    }

    func togglePlayPause() {
        switch state {
        case .playing:
            engine.pause()
        case .paused, .loading:
            engine.play()
        case .ended:
            engine.seek(to: 0)
            engine.play()
        case .idle, .failed:
            break
        }
    }

    func seek(to seconds: Double) {
        let clamped: Double
        if duration > 0 {
            clamped = min(max(seconds, 0), duration)
        } else {
            clamped = max(seconds, 0)
        }
        engine.seek(to: clamped)
        currentTime = clamped
        writeProgress(force: true)
    }

    func seek(by delta: Double) {
        seek(to: currentTime + delta)
    }

    func setVolume(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        volume = clamped
        isMuted = clamped == 0
        if clamped > 0 {
            previousVolume = clamped
        }
        engine.setVolume(isMuted ? 0 : clamped)
    }

    func toggleMute() {
        if isMuted {
            setVolume(previousVolume > 0 ? previousVolume : 0.5)
        } else {
            previousVolume = max(volume, 0.1)
            isMuted = true
            engine.setVolume(0)
        }
    }

    func setRate(_ value: Double) {
        rate = min(max(value, 0.5), 2)
        engine.setRate(rate)
    }

    func selectAudioTrack(_ track: MediaTrack) {
        selectedAudioTrackID = track.id
        engine.selectAudioTrack(track)
    }

    func selectSubtitleTrack(_ track: MediaTrack?) {
        selectedSubtitleTrackID = track?.id
        engine.selectSubtitleTrack(track)
    }

    func makeVideoSurface() -> NSView {
        engine.makeVideoSurface()
    }

    func updateVideoSurface(_ view: NSView) {
        engine.updateVideoSurface(view)
    }

    private func begin(stream: ResolvedStream, startAt: Double?) async {
        do {
            try await engine.load(stream)
            engine.setVolume(isMuted ? 0 : volume)
            engine.setRate(rate)
            engine.play()
            if let startAt, startAt > 5 {
                engine.seek(to: startAt)
                currentTime = startAt
            }
            state = .playing
            writeProgress(force: true)
        } catch is CancellationError {
            // The session was closed or the engine switched; no failure to report.
        } catch {
            guard let session else { return }
            state = .failed(Self.message(for: error))
            onStreamFailed?(session.anime, session.episode)
        }
    }

    private func engineStateChanged(_ engineState: PlayerEngineState) {
        switch engineState {
        case .idle:
            break
        case .loading:
            state = .loading
        case .ready:
            break
        case .playing:
            state = .playing
        case .paused:
            state = .paused
            writeProgress(force: true)
        case .ended:
            evaluateCompletion()
            state = .ended
            writeProgress(force: true)
            onPlaybackEnded?()
        case .failed(let message):
            state = .failed(message)
            writeProgress(force: true)
            if let session {
                onStreamFailed?(session.anime, session.episode)
            }
        }
    }

    private func timeChanged(_ time: Double, _ duration: Double) {
        if currentTime != time {
            currentTime = time
        }
        if duration > 0, duration != self.duration {
            self.duration = duration
        }
        if let session {
            onPlaybackTick?(session.anime, session.episode, time, self.duration)
        }
        evaluateCompletion()
        writeProgress(force: false)
    }

    private func evaluateCompletion() {
        guard !hasCompletedSession, duration > 0, session != nil else { return }
        guard completionService.isComplete(
            positionSeconds: currentTime,
            durationSeconds: duration
        ) else {
            return
        }
        hasCompletedSession = true
        writeProgress(force: true)
        seedNextEpisodeProgress()
    }

    private func tracksChanged() {
        audioTracks = engine.audioTracks()
        subtitleTracks = engine.subtitleTracks()
        applyAutomaticTrackSelectionIfNeeded()
    }

    /// Applies track preferences exactly once per loaded media file, as soon as
    /// the engine reports a usable track list. Later `track-list` events,
    /// including the ones caused by setting `aid`/`sid` and the ones following
    /// a manual choice, are left alone.
    private func applyAutomaticTrackSelectionIfNeeded() {
        guard !hasAppliedAutomaticTrackSelection else { return }
        guard !audioTracks.isEmpty || !subtitleTracks.isEmpty else { return }
        hasAppliedAutomaticTrackSelection = true

        let selection = PlaybackTrackSelector.select(
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks,
            preferences: preferences.preferences
        )
        if let audio = selection.audio {
            selectedAudioTrackID = audio.id
            engine.selectAudioTrack(audio)
        }
        selectedSubtitleTrackID = selection.subtitle?.id
        engine.selectSubtitleTrack(selection.subtitle)
    }

    private func writeProgress(force: Bool) {
        guard let session, duration > 0 else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastProgressWrite) >= 10 else { return }
        lastProgressWrite = now
        let progress = PlaybackProgress(
            animeID: session.anime.id,
            episodeID: session.episode.id,
            episodeNumber: session.episode.displayNumber,
            absoluteEpisodeNumber: session.episode.absoluteNumber,
            positionSeconds: currentTime,
            durationSeconds: duration,
            isCompleted: hasCompletedSession,
            updatedAt: now,
            animeTitle: session.anime.displayTitle(for: preferences.animeTitleLanguage),
            posterURL: session.anime.posterURL,
            bannerURL: session.anime.bannerURL,
            episodeCount: session.anime.episodeCount
        )
        syncLibrary(anime: session.anime, progress: progress)
        let store = progressStore
        Task { [weak self] in
            await store.save(progress)
            self?.onProgressSaved?(progress)
        }
    }

    /// Seeds the following episode as an unfinished, not-started record so the
    /// series stays in Continue Watching after the current episode completes.
    /// Completed episodes are filtered out of the shelf, so without a record
    /// for the next episode the show would simply disappear.
    private func seedNextEpisodeProgress() {
        guard let session else { return }
        let available = session.anime.episodesAvailable ?? 0
        let nextEpisodeNumber = session.episode.displayNumber + 1
        guard nextEpisodeNumber <= available else { return }

        let anime = session.anime
        let episode = session.episode
        let next = PlaybackProgress(
            animeID: anime.id,
            episodeID: "\(anime.id)-\(nextEpisodeNumber)",
            episodeNumber: nextEpisodeNumber,
            absoluteEpisodeNumber: episode.absoluteNumber.map { $0 + 1 },
            positionSeconds: 0,
            durationSeconds: duration,
            isCompleted: false,
            updatedAt: Date(),
            animeTitle: anime.displayTitle(for: preferences.animeTitleLanguage),
            posterURL: anime.posterURL,
            bannerURL: anime.bannerURL,
            episodeCount: anime.episodeCount
        )
        let store = progressStore
        Task { [weak self] in
            // Never clobber progress the viewer already has for that episode:
            // a partial watch or autoplay may have recorded it already.
            guard await store.progress(
                animeID: next.animeID,
                episodeNumber: nextEpisodeNumber
            ) == nil else {
                return
            }
            await store.save(next)
            self?.onProgressSaved?(next)
        }
    }

    /// Mirrors playback into the library so anything being watched shows up
    /// under `watching`, with its watched-episode count kept current. The
    /// repository preserves statuses the user picked explicitly.
    private func syncLibrary(anime: Anime, progress: PlaybackProgress) {
        let watchedCount = progress.watchedEpisodeCount
        guard lastSyncedLibraryProgress != watchedCount else { return }
        lastSyncedLibraryProgress = watchedCount
        let library = library
        Task {
            try? await library.addToWatching(anime: anime, progress: watchedCount)
        }
    }

    private static func message(for error: Error) -> String {
        if let playerError = error as? PlayerError {
            return playerError.userMessage
        }
        return error.localizedDescription
    }
}
