import AppKit
import Foundation

enum PlayerEngineState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case ended
    case failed(String)
}

enum PlayerError: Error, Equatable, Sendable {
    case notReady
    case timedOut
    case failedToLoad(String)

    var userMessage: String {
        switch self {
        case .notReady:
            "The video is not ready yet."
        case .timedOut:
            "The video took too long to load."
        case .failedToLoad(let detail):
            "This source could not be played. \(detail)"
        }
    }
}

@MainActor
protocol PlayerEngine: AnyObject {
    var onStateChange: ((PlayerEngineState) -> Void)? { get set }
    var onTimeChange: ((Double, Double) -> Void)? { get set }
    var onTracksChange: (() -> Void)? { get set }

    var isPlaying: Bool { get }
    var currentTime: Double { get }
    var duration: Double { get }
    var volume: Double { get }
    var rate: Double { get }

    func load(_ stream: ResolvedStream) async throws
    func play()
    func pause()
    func stop()
    func seek(to seconds: Double)
    func setVolume(_ volume: Double)
    func setRate(_ rate: Double)

    func audioTracks() -> [MediaTrack]
    func subtitleTracks() -> [MediaTrack]
    func selectAudioTrack(_ track: MediaTrack)
    func selectSubtitleTrack(_ track: MediaTrack?)
    func addExternalSubtitle(url: URL)

    func makeVideoSurface() -> NSView
    func updateVideoSurface(_ view: NSView)

    /// Releases the underlying player resources. Called when the app terminates.
    func shutdown()
}

extension PlayerEngine {
    func addExternalSubtitle(url: URL) {}
    func shutdown() {}
}

@MainActor
enum PlaybackEngineFactory {
    static func make(_ kind: PlaybackEngineKind) -> any PlayerEngine {
        switch kind {
        case .mpv:
            MPVPlayerEngine()
        case .avPlayer:
            AVPlayerEngine()
        }
    }
}
