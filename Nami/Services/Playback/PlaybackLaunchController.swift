import Foundation
import Observation

/// Orchestrates playback launches from the catalog UI.
///
/// The built-in player is presented immediately and discovers the stream
/// behind its loading state. Candidates are resolved and validated in
/// preference order, and a stream that fails during playback is replaced by
/// the next preferred candidate without surfacing Real-Debrid errors. When no
/// source can be selected confidently the source picker is surfaced through
/// `pickerRequest`.
@MainActor
@Observable
final class PlaybackLaunchController {
    private struct ActiveSession {
        let request: PlaybackRequest
        let current: StreamCandidate?
        let remaining: [StreamCandidate]
        let expectedGeneration: Int?
    }

    private let preload: any StreamPreloading
    private let resolver: SourceResolver
    private let streamPlayback: any StreamPlaybackProviding
    private let playback: PlaybackCoordinator

    private var launchTask: Task<Void, Never>?
    private var fallbackTask: Task<Void, Never>?
    private var activeSession: ActiveSession?

    /// Set when the source picker should be presented. The owner presents a
    /// `StreamSelectionView` and calls `pickerDismissed()` afterwards.
    var pickerRequest: PlaybackRequest?

    init(
        preload: any StreamPreloading,
        resolver: SourceResolver,
        streamPlayback: any StreamPlaybackProviding,
        playback: PlaybackCoordinator
    ) {
        self.preload = preload
        self.resolver = resolver
        self.streamPlayback = streamPlayback
        self.playback = playback
    }

    func play(_ request: PlaybackRequest) {
        launchTask?.cancel()
        launchTask = nil
        fallbackTask?.cancel()
        fallbackTask = nil
        activeSession = nil
        pickerRequest = nil

        if request.prefersManualSelection {
            pickerRequest = request
            return
        }

        var expectedGeneration: Int?
        if !playback.usesExternalPlayback {
            playback.presentLoading(anime: request.anime, episode: request.episode)
            expectedGeneration = playback.presentationGeneration
        }

        launchTask = Task { [weak self] in
            await self?.resolve(request, expectedGeneration: expectedGeneration)
        }
    }

    /// Called when the source picker closes. A player that is still waiting
    /// for a source is dismissed with it.
    func pickerDismissed() {
        activeSession = nil
        fallbackTask?.cancel()
        fallbackTask = nil
        if playback.isAwaitingSource {
            playback.close()
        }
    }

    /// Called by the playback coordinator when a stream fails to load or play.
    /// Invalidates the candidate and, when possible, transparently moves on to
    /// the next preferred source.
    func streamFailed(anime: Anime, episode: Episode) {
        guard fallbackTask == nil else { return }
        guard
            let session = activeSession,
            session.request.anime.id == anime.id,
            session.request.episode.id == episode.id
                || session.request.episode.displayNumber == episode.displayNumber
        else {
            return
        }
        guard isCurrent(session.expectedGeneration) else {
            activeSession = nil
            return
        }

        if let current = session.current {
            streamPlayback.markPlaybackFailed(for: current, anime: anime, episode: episode)
        }
        let remaining = session.remaining
        activeSession = nil

        fallbackTask = Task { [weak self] in
            guard let self else { return }
            await self.resolver.invalidate(anime: anime, episode: episode)
            // Hide the player's error state while the next source is prepared.
            var generation = session.expectedGeneration
            if !self.playback.usesExternalPlayback {
                self.playback.presentLoading(anime: anime, episode: episode)
                generation = self.playback.presentationGeneration
            }
            if remaining.isEmpty, session.current == nil {
                // The session started from the persistent cache; discover and
                // validate sources again from scratch.
                await self.resolve(session.request, expectedGeneration: generation)
            } else if !remaining.isEmpty {
                await self.startFirstAvailable(
                    remaining,
                    request: session.request,
                    expectedGeneration: generation
                )
            }
            self.fallbackTask = nil
        }
    }

    private func resolve(_ request: PlaybackRequest, expectedGeneration: Int?) async {
        if let cached = await resolver.cachedStream(anime: request.anime, episode: request.episode) {
            guard !Task.isCancelled, isCurrent(expectedGeneration) else { return }
            playback.start(
                stream: cached,
                anime: request.anime,
                episode: request.episode,
                startAt: request.startPositionSeconds
            )
            activeSession = ActiveSession(
                request: request,
                current: nil,
                remaining: [],
                expectedGeneration: captureGeneration()
            )
            return
        }

        let result = await preload.streams(anime: request.anime, episode: request.episode)
        guard !Task.isCancelled, isCurrent(expectedGeneration) else { return }

        guard result.decision.shouldAutoPlay, let candidate = result.decision.candidate else {
            pickerRequest = manualRequest(for: request)
            return
        }

        // Movie releases are occasionally packaged as several files. Hand the
        // choice back to the user instead of guessing which part to play.
        // Auto-selection stays enabled so the picker can jump straight to the
        // file list for the best source.
        if request.anime.subtype?.isMovie == true,
           let files = try? await resolver.files(for: candidate),
           TorrentFileSelector.playableFiles(from: files).count > 1 {
            guard !Task.isCancelled, isCurrent(expectedGeneration) else { return }
            pickerRequest = PlaybackRequest(
                anime: request.anime,
                episode: request.episode,
                startPositionSeconds: request.startPositionSeconds
            )
            return
        }

        await startFirstAvailable(
            candidateChain(primary: candidate, result: result),
            request: request,
            expectedGeneration: expectedGeneration
        )
    }

    /// Resolves candidates in preference order and starts the first usable
    /// one. Prefetched validations make each hop nearly instantaneous.
    private func startFirstAvailable(
        _ candidates: [StreamCandidate],
        request: PlaybackRequest,
        expectedGeneration: Int?
    ) async {
        for (index, candidate) in candidates.enumerated() {
            guard !Task.isCancelled, isCurrent(expectedGeneration) else { return }
            let lookup = await streamPlayback.stream(
                for: candidate,
                anime: request.anime,
                episode: request.episode
            )
            guard !Task.isCancelled, isCurrent(expectedGeneration) else { return }
            switch lookup {
            case .ready(let stream):
                playback.start(
                    stream: stream,
                    anime: request.anime,
                    episode: request.episode,
                    startAt: request.startPositionSeconds
                )
                activeSession = ActiveSession(
                    request: request,
                    current: candidate,
                    remaining: Array(candidates.dropFirst(index + 1)),
                    expectedGeneration: captureGeneration()
                )
                return
            case .unavailable:
                continue
            case .blocked:
                pickerRequest = manualRequest(for: request)
                return
            }
        }
        pickerRequest = manualRequest(for: request)
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

    /// The generation is nil when no built-in player was presented (external
    /// playback), in which case there is nothing to invalidate.
    private func captureGeneration() -> Int? {
        playback.isPresenting ? playback.presentationGeneration : nil
    }

    private func isCurrent(_ expectedGeneration: Int?) -> Bool {
        guard let expectedGeneration else { return true }
        return playback.isPresenting && playback.presentationGeneration == expectedGeneration
    }

    private func manualRequest(for request: PlaybackRequest) -> PlaybackRequest {
        PlaybackRequest(
            anime: request.anime,
            episode: request.episode,
            prefersManualSelection: true,
            startPositionSeconds: request.startPositionSeconds
        )
    }
}
