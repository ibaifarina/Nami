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

    private let engine: any PlayerEngine
    private let progressStore: any PlaybackProgressStore
    private let preferences: PreferencesStore
    private let completionService = PlaybackCompletionService()
    private var session: Session?
    private var lastProgressWrite = Date.distantPast
    private var previousVolume: Double = 1
    private var hasCompletedSession = false

    var onPlaybackTick: ((Anime, Episode, Double, Double) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onSessionClosed: (() -> Void)?

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
        engine: any PlayerEngine = AVPlayerEngine(),
        progressStore: any PlaybackProgressStore,
        preferences: PreferencesStore
    ) {
        self.engine = engine
        self.progressStore = progressStore
        self.preferences = preferences
        volume = engine.volume
        previousVolume = engine.volume

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

    var isPlaying: Bool {
        state == .playing
    }

    var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    func start(stream: ResolvedStream, anime: Anime, episode: Episode, startAt: Double?) {
        session = Session(anime: anime, episode: episode, stream: stream)
        title = anime.displayTitle
        episodeLabel = "Episode \(episode.displayNumber)"
        isPresenting = true
        state = .loading
        currentTime = 0
        duration = 0
        audioTracks = []
        subtitleTracks = []
        selectedAudioTrackID = nil
        selectedSubtitleTrackID = nil
        lastProgressWrite = .distantPast
        hasCompletedSession = false

        Task { [weak self] in
            await self?.begin(stream: stream, startAt: startAt)
        }
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
        title = ""
        episodeLabel = ""
        hasCompletedSession = false
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
        } catch {
            state = .failed(Self.message(for: error))
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
        }
    }

    private func timeChanged(_ time: Double, _ duration: Double) {
        currentTime = time
        if duration > 0 {
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
    }

    private func tracksChanged() {
        audioTracks = engine.audioTracks()
        subtitleTracks = engine.subtitleTracks()
        applyPreferredTracks()
    }

    private func applyPreferredTracks() {
        if selectedAudioTrackID == nil, let match = preferredAudioTrack() {
            selectedAudioTrackID = match.id
            engine.selectAudioTrack(match)
        }
        if selectedSubtitleTrackID == nil, let match = preferredSubtitleTrack() {
            selectedSubtitleTrackID = match.id
            engine.selectSubtitleTrack(match)
        }
    }

    private func preferredAudioTrack() -> MediaTrack? {
        guard let token = preferences.preferredAudio.languageToken else {
            return audioTracks.first { $0.isDefault } ?? audioTracks.first
        }
        let tokens = Self.preferenceTokens(for: token)
        return audioTracks.first { matches(track: $0, tokens: tokens) }
            ?? audioTracks.first { $0.isDefault }
    }

    private func preferredSubtitleTrack() -> MediaTrack? {
        guard let token = preferences.preferredSubtitles.languageToken else {
            return subtitleTracks.first { $0.isDefault }
        }
        let tokens = Self.preferenceTokens(for: token)
        return subtitleTracks.first { matches(track: $0, tokens: tokens) }
    }

    private func matches(track: MediaTrack, tokens: Set<String>) -> Bool {
        var haystack = Set<String>()
        if let language = track.language?.lowercased() {
            haystack.insert(language)
        }
        haystack.insert(track.title.lowercased())
        return !haystack.isDisjoint(with: tokens)
    }

    private static func preferenceTokens(for token: String) -> Set<String> {
        switch token {
        case "japanese": ["japanese", "ja", "jpn"]
        case "english": ["english", "en", "eng"]
        case "spanish": ["spanish", "es", "spa"]
        default: [token]
        }
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
            animeTitle: session.anime.displayTitle,
            posterURL: session.anime.posterURL,
            bannerURL: session.anime.bannerURL,
            episodeCount: session.anime.episodeCount
        )
        let store = progressStore
        Task {
            await store.save(progress)
        }
    }

    private static func message(for error: Error) -> String {
        if let playerError = error as? PlayerError {
            return playerError.userMessage
        }
        return error.localizedDescription
    }
}
