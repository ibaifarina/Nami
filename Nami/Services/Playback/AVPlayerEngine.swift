import AppKit
import AVFoundation
import Foundation

@MainActor
final class AVPlayerEngine: PlayerEngine {
    var onStateChange: ((PlayerEngineState) -> Void)?
    var onTimeChange: ((Double, Double) -> Void)?
    var onTracksChange: (() -> Void)?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var audioGroup: AVMediaSelectionGroup?
    private var subtitleGroup: AVMediaSelectionGroup?
    private var audioOptions: [String: AVMediaSelectionOption] = [:]
    private var subtitleOptions: [String: AVMediaSelectionOption] = [:]
    private var defaultAudioID: String?
    private var defaultSubtitleID: String?
    private var isLoaded = false

    init() {
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in
                self?.handleTimeUpdate(seconds: seconds)
            }
        }
    }

    var isPlaying: Bool {
        player.timeControlStatus == .playing
    }

    var currentTime: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? max(0, seconds) : 0
    }

    var duration: Double {
        guard let seconds = player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 else {
            return 0
        }
        return seconds
    }

    var volume: Double {
        Double(player.volume)
    }

    var rate: Double = 1

    func load(_ stream: ResolvedStream) async throws {
        stop()
        onStateChange?(.loading)

        let item = AVPlayerItem(url: stream.url)
        item.preferredForwardBufferDuration = 5
        player.replaceCurrentItem(with: item)

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleEnded()
            }
        }

        for _ in 0..<200 {
            switch item.status {
            case .readyToPlay:
                isLoaded = true
                await loadTracks(for: item)
                onStateChange?(.ready)
                return
            case .failed:
                let detail = item.error?.localizedDescription ?? "Unknown playback error"
                onStateChange?(.failed(detail))
                throw PlayerError.failedToLoad(detail)
            default:
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        onStateChange?(.failed("Timed out"))
        throw PlayerError.timedOut
    }

    func play() {
        player.play()
        if rate != 1 {
            player.rate = Float(rate)
        }
        onStateChange?(.playing)
    }

    func pause() {
        player.pause()
        onStateChange?(.paused)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        audioGroup = nil
        subtitleGroup = nil
        audioOptions = [:]
        subtitleOptions = [:]
        defaultAudioID = nil
        defaultSubtitleID = nil
        isLoaded = false
        onStateChange?(.idle)
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setVolume(_ volume: Double) {
        player.volume = Float(min(max(volume, 0), 1))
    }

    func setRate(_ rate: Double) {
        self.rate = min(max(rate, 0.5), 2)
        if isPlaying {
            player.rate = Float(self.rate)
        }
    }

    func audioTracks() -> [MediaTrack] {
        guard let audioGroup else { return [] }
        return audioGroup.options.enumerated().map { index, option in
            MediaTrack(
                id: "audio-\(index)",
                kind: .audio,
                title: option.displayName,
                language: option.extendedLanguageTag,
                isDefault: "audio-\(index)" == defaultAudioID
            )
        }
    }

    func subtitleTracks() -> [MediaTrack] {
        guard let subtitleGroup else { return [] }
        return subtitleGroup.options.enumerated().map { index, option in
            MediaTrack(
                id: "subtitle-\(index)",
                kind: .subtitle,
                title: option.displayName,
                language: option.extendedLanguageTag,
                isDefault: "subtitle-\(index)" == defaultSubtitleID,
                isForced: option.hasMediaCharacteristic(.containsOnlyForcedSubtitles)
            )
        }
    }

    func selectAudioTrack(_ track: MediaTrack) {
        guard
            let group = audioGroup,
            let option = audioOptions[track.id],
            let item = player.currentItem
        else {
            return
        }
        item.select(option, in: group)
    }

    func selectSubtitleTrack(_ track: MediaTrack?) {
        guard let group = subtitleGroup, let item = player.currentItem else { return }
        if let track, let option = subtitleOptions[track.id] {
            item.select(option, in: group)
        } else {
            item.select(nil, in: group)
        }
    }

    func makeVideoSurface() -> NSView {
        let view = PlayerLayerView()
        view.player = player
        return view
    }

    func updateVideoSurface(_ view: NSView) {
        (view as? PlayerLayerView)?.player = player
    }

    private func loadTracks(for item: AVPlayerItem) async {
        audioGroup = try? await item.asset.loadMediaSelectionGroup(for: .audible)
        subtitleGroup = try? await item.asset.loadMediaSelectionGroup(for: .legible)

        audioOptions = [:]
        subtitleOptions = [:]
        defaultAudioID = nil
        defaultSubtitleID = nil

        if let audioGroup {
            for (index, option) in audioGroup.options.enumerated() {
                let id = "audio-\(index)"
                audioOptions[id] = option
                if item.currentMediaSelection.selectedMediaOption(in: audioGroup) == option {
                    defaultAudioID = id
                }
            }
        }
        if let subtitleGroup {
            for (index, option) in subtitleGroup.options.enumerated() {
                let id = "subtitle-\(index)"
                subtitleOptions[id] = option
                if item.currentMediaSelection.selectedMediaOption(in: subtitleGroup) == option {
                    defaultSubtitleID = id
                }
            }
        }
        onTracksChange?()
    }

    private func handleTimeUpdate(seconds: Double) {
        onTimeChange?(max(0, seconds), duration)
    }

    private func handleEnded() {
        player.pause()
        onStateChange?(.ended)
    }
}

final class PlayerLayerView: NSView {
    override func makeBackingLayer() -> CALayer {
        AVPlayerLayer()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        (layer as? AVPlayerLayer)?.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        (layer as? AVPlayerLayer)?.videoGravity = .resizeAspect
    }

    var player: AVPlayer? {
        get { (layer as? AVPlayerLayer)?.player }
        set { (layer as? AVPlayerLayer)?.player = newValue }
    }
}
