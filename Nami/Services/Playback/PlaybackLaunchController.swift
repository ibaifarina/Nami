import Foundation
import Observation

/// Orchestrates playback launches from the catalog UI.
///
/// The built-in player is presented immediately and discovers the stream
/// behind its loading state. When no source can be selected confidently the
/// source picker is surfaced through `pickerRequest`.
@MainActor
@Observable
final class PlaybackLaunchController {
    private let preload: any StreamPreloading
    private let resolver: SourceResolver
    private let playback: PlaybackCoordinator

    private var launchTask: Task<Void, Never>?

    /// Set when the source picker should be presented. The owner presents a
    /// `StreamSelectionView` and calls `pickerDismissed()` afterwards.
    var pickerRequest: PlaybackRequest?

    init(
        preload: any StreamPreloading,
        resolver: SourceResolver,
        playback: PlaybackCoordinator
    ) {
        self.preload = preload
        self.resolver = resolver
        self.playback = playback
    }

    func play(_ request: PlaybackRequest) {
        launchTask?.cancel()
        launchTask = nil
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
        if playback.isAwaitingSource {
            playback.close()
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
            return
        }

        let result = await preload.streams(anime: request.anime, episode: request.episode)
        guard !Task.isCancelled, isCurrent(expectedGeneration) else { return }

        guard result.decision.shouldAutoPlay, let candidate = result.decision.candidate else {
            pickerRequest = manualRequest(for: request)
            return
        }

        do {
            let stream = try await resolver.resolve(
                candidate,
                anime: request.anime,
                episode: request.episode
            )
            guard !Task.isCancelled, isCurrent(expectedGeneration) else { return }
            playback.start(
                stream: stream,
                anime: request.anime,
                episode: request.episode,
                startAt: request.startPositionSeconds
            )
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, isCurrent(expectedGeneration) else { return }
            pickerRequest = manualRequest(for: request)
        }
    }

    /// The expected generation is nil when no built-in player was presented
    /// (external playback), in which case there is nothing to invalidate.
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
