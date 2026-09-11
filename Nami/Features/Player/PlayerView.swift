import AppKit
import SwiftUI

struct PlayerView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var controlsVisible = true
    @State private var controlsTracker = ControlsVisibilityTracker()
    @State private var nextSelectionRequest: PlaybackRequest?
    @FocusState private var isFocused: Bool

    private var playback: PlaybackCoordinator {
        environment.playback
    }

    private var nextEpisode: NextEpisodeController {
        environment.nextEpisode
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerSurface(playback: playback)
                .id(playback.engineGeneration)
                .ignoresSafeArea()
                .onTapGesture {
                    playback.togglePlayPause()
                }

            if case .failed(let message) = playback.state {
                errorOverlay(message)
            } else {
                if playback.state == .loading {
                    LoadingSpinner(size: 34, lineWidth: 3.5, tint: .white)
                }
                controlsOverlay
                nextEpisodeLayer
            }
        }
        .background(PlayerWindowChrome())
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            isFocused = true
            scheduleHide()
        }
        .onDisappear {
            controlsTracker.cancel()
            NSCursor.setHiddenUntilMouseMoves(false)
        }
        .sheet(item: $nextSelectionRequest) { request in
            StreamSelectionView(request: request, environment: environment)
        }
        .onContinuousHover { phase in
            guard case .active(let point) = phase, controlsTracker.registerMovement(point) else { return }
            revealControls()
        }
        .onKeyPress(.space) {
            playback.togglePlayPause()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            playback.seek(by: -10)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            playback.seek(by: 10)
            return .handled
        }
        .onKeyPress(.upArrow) {
            playback.setVolume(playback.volume + 0.05)
            return .handled
        }
        .onKeyPress(.downArrow) {
            playback.setVolume(playback.volume - 0.05)
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("f"), KeyEquivalent("F")]) { _ in
            toggleFullScreen()
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("m"), KeyEquivalent("M")]) { _ in
            playback.toggleMute()
            return .handled
        }
        .onKeyPress(.escape) {
            handleEscape()
            return .handled
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var nextEpisodeLayer: some View {
        if nextEpisode.overlay != .hidden, let episodeNumber = nextEpisode.nextEpisodeNumber {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    nextEpisodeCard(episodeNumber)
                }
            }
            .padding(Spacing.xl)
            .padding(.bottom, controlsVisible ? 64 : 0)
            .animation(.easeOut(duration: Motion.transition), value: nextEpisode.overlay)
        }
    }

    private func nextEpisodeCard(_ episodeNumber: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Next Episode")
                .font(AppFont.cardMeta)
                .foregroundStyle(.white.opacity(0.7))
            Text("Episode \(episodeNumber)")
                .font(AppFont.sectionTitle)
                .foregroundStyle(.white)

            switch nextEpisode.overlay {
            case .preparing:
                HStack(spacing: Spacing.xs) {
                    LoadingSpinner(size: 16, lineWidth: 2, tint: .white)
                    Text("Preparing next episode\u{2026}")
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Button("Cancel") {
                    nextEpisode.cancelCountdown()
                }
                .buttonStyle(GlassButtonStyle())

            case .countdown(let seconds):
                Text("Starting in \(seconds)\u{2026}")
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.white.opacity(0.8))
                HStack(spacing: Spacing.sm) {
                    Button("Play Now") {
                        nextEpisode.playNow()
                    }
                    .buttonStyle(BrandButtonStyle())
                    Button("Cancel") {
                        nextEpisode.cancelCountdown()
                    }
                    .buttonStyle(GlassButtonStyle())
                }

            case .readyToChoose:
                if let error = nextEpisode.prepareError {
                    Text(error)
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                } else {
                    Text("No confident automatic source for the next episode.")
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Spacing.sm) {
                    Button("Choose Source") {
                        nextEpisode.dismissOverlay()
                        nextSelectionRequest = nextEpisode.nextEpisodeRequest
                    }
                    .buttonStyle(BrandButtonStyle())
                    Button("Cancel") {
                        nextEpisode.cancelCountdown()
                    }
                    .buttonStyle(GlassButtonStyle())
                }

            case .hidden:
                EmptyView()
            }
        }
        .padding(Spacing.md)
        .frame(width: 300, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
    }

    private var controlsOverlay: some View {
        VStack {
            topBar
            Spacer()
            bottomBar
        }
        .padding(Spacing.lg)
        .background(
            LinearGradient(
                colors: [
                    .black.opacity(0.65),
                    .clear,
                    .clear,
                    .black.opacity(0.8),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .opacity(controlsVisible ? 1 : 0)
        .animation(.easeOut(duration: Motion.transition), value: controlsVisible)
        .allowsHitTesting(controlsVisible)
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Button {
                playback.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .hoverFeedback(scale: 1.15)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close player")

            VStack(alignment: .leading, spacing: 1) {
                Text(playback.title)
                    .font(AppFont.cardTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(playback.episodeLabel)
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
        }
    }

    private var bottomBar: some View {
        VStack(spacing: Spacing.xs) {
            PlayerScrubberView(playback: playback)

            HStack(spacing: Spacing.md) {
                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17))
                        .frame(width: 26)
                }
                .buttonStyle(.plain)
                .hoverFeedback(scale: 1.15)
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

                PlayerTimecodeView(playback: playback)

                Spacer()

                speedMenu
                audioMenu
                subtitleMenu
                volumeControl

                Button {
                    toggleFullScreen()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .hoverFeedback(scale: 1.15)
                .accessibilityLabel("Toggle fullscreen")
            }
            .foregroundStyle(.white)
        }
    }

    private var speedMenu: some View {
        Menu {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                Button(value == 1 ? "Normal" : String(format: "%g\u{00D7}", value)) {
                    playback.setRate(value)
                }
            }
        } label: {
            Label("Speed", systemImage: "gauge.with.dots.needle.67percent")
                .labelStyle(.iconOnly)
                .font(.system(size: 13))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .pointerStyle(.link)
        .accessibilityLabel(playback.rate == 1 ? "Playback speed" : String(format: "Playback speed %g\u{00D7}", playback.rate))
    }

    private var audioMenu: some View {
        Menu {
            ForEach(playback.audioTracks) { track in
                Button {
                    playback.selectAudioTrack(track)
                } label: {
                    if playback.selectedAudioTrackID == track.id {
                        Label(track.displayName, systemImage: "checkmark")
                    } else {
                        Text(track.displayName)
                    }
                }
            }
        } label: {
            Label("Audio", systemImage: "waveform")
                .labelStyle(.iconOnly)
                .font(.system(size: 13))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(playback.audioTracks.isEmpty)
        .pointerStyle(.link)
        .accessibilityLabel("Audio track")
    }

    private var subtitleMenu: some View {
        Menu {
            Button {
                playback.selectSubtitleTrack(nil)
            } label: {
                if playback.selectedSubtitleTrackID == nil {
                    Label("Off", systemImage: "checkmark")
                } else {
                    Text("Off")
                }
            }
            if !playback.subtitleTracks.isEmpty {
                Divider()
            }
            ForEach(playback.subtitleTracks) { track in
                Button {
                    playback.selectSubtitleTrack(track)
                } label: {
                    if playback.selectedSubtitleTrackID == track.id {
                        Label(track.displayName, systemImage: "checkmark")
                    } else {
                        Text(track.displayName)
                    }
                }
            }
        } label: {
            Label("Subtitles", systemImage: "captions.bubble")
                .labelStyle(.iconOnly)
                .font(.system(size: 13))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(playback.subtitleTracks.isEmpty && playback.selectedSubtitleTrackID == nil)
        .pointerStyle(.link)
        .accessibilityLabel("Subtitles")
    }

    private var volumeControl: some View {
        HStack(spacing: Spacing.xs) {
            Button {
                playback.toggleMute()
            } label: {
                Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .hoverFeedback(scale: 1.15)
            .accessibilityLabel(playback.isMuted ? "Unmute" : "Mute")

            Slider(
                value: Binding(
                    get: { playback.isMuted ? 0 : playback.volume },
                    set: { playback.setVolume($0) }
                ),
                in: 0...1
            )
            .frame(width: 90)
            .tint(.white)
            .accessibilityLabel("Volume")
        }
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
            Text(message)
                .font(AppFont.body)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            HStack(spacing: Spacing.sm) {
                Button("Try Again") {
                    playback.retry()
                }
                .buttonStyle(BrandButtonStyle())
                .hoverFeedback(scale: 1.03)
                Button("Close") {
                    playback.close()
                }
                .buttonStyle(GlassButtonStyle())
                .hoverFeedback(scale: 1.03)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Spacing.xl)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: Radius.hero))
    }

    // MARK: - Behavior

    private func revealControls() {
        if !controlsVisible {
            controlsVisible = true
        }
        scheduleHide()
    }

    private func scheduleHide() {
        controlsTracker.scheduleHide {
            if playback.isPlaying {
                controlsVisible = false
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }

    private func toggleFullScreen() {
        (NSApp.mainWindow ?? NSApp.keyWindow)?.toggleFullScreen(nil)
    }

    private func handleEscape() {
        if NSApp.keyWindow?.styleMask.contains(.fullScreen) == true {
            NSApp.keyWindow?.toggleFullScreen(nil)
        } else {
            playback.close()
        }
    }
}

/// Owns player-control visibility bookkeeping outside of SwiftUI state: hover
/// events arrive at pointer frequency, and writing to `@State` for each one
/// would invalidate the whole player body (including its video surface) on
/// every mouse move.
@MainActor
private final class ControlsVisibilityTracker {
    private var lastPoint: CGPoint = .zero
    private var hideTask: Task<Void, Never>?

    /// Returns true when the pointer moved far enough to count as activity.
    func registerMovement(_ point: CGPoint) -> Bool {
        guard abs(point.x - lastPoint.x) > 2 || abs(point.y - lastPoint.y) > 2 else {
            return false
        }
        lastPoint = point
        return true
    }

    /// (Re)schedules the auto-hide callback for when activity stops.
    func scheduleHide(after delay: Duration = .seconds(3), _ hide: @escaping @MainActor () -> Void) {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    func cancel() {
        hideTask?.cancel()
        hideTask = nil
    }
}

struct PlayerSurface: NSViewRepresentable {
    let playback: PlaybackCoordinator

    func makeNSView(context: Context) -> NSView {
        playback.makeVideoSurface()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        playback.updateVideoSurface(nsView)
    }
}

private struct PlayerWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> PlayerWindowChromeView {
        PlayerWindowChromeView()
    }

    func updateNSView(_ nsView: PlayerWindowChromeView, context: Context) {}
}

private final class PlayerWindowChromeView: NSView {
    private weak var chromeWindow: NSWindow?
    private var wasFullScreen = false
    private var savedTitle: String?
    private var savedTitleVisibility: NSWindow.TitleVisibility?
    private var savedTitlebarAppearsTransparent: Bool?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            restoreWindowChrome()
            return
        }
        hideWindowChrome(in: window)
    }

    private func hideWindowChrome(in window: NSWindow) {
        guard chromeWindow == nil else { return }
        chromeWindow = window
        wasFullScreen = window.styleMask.contains(.fullScreen)
        savedTitle = window.title
        savedTitleVisibility = window.titleVisibility
        savedTitlebarAppearsTransparent = window.titlebarAppearsTransparent
        window.title = "Nami"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
    }

    private func restoreWindowChrome() {
        guard let window = chromeWindow, let savedTitle else { return }
        window.title = savedTitle
        if let savedTitleVisibility {
            window.titleVisibility = savedTitleVisibility
        }
        if let savedTitlebarAppearsTransparent {
            window.titlebarAppearsTransparent = savedTitlebarAppearsTransparent
        }
        if !wasFullScreen, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        chromeWindow = nil
        self.savedTitle = nil
        savedTitleVisibility = nil
        savedTitlebarAppearsTransparent = nil
    }
}

private struct PlayerScrubberView: View {
    let playback: PlaybackCoordinator

    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        Slider(
            value: Binding(
                get: { isScrubbing ? scrubValue : playback.currentTime },
                set: { scrubValue = $0 }
            ),
            in: 0...max(playback.duration, 1),
            onEditingChanged: { editing in
                if editing {
                    isScrubbing = true
                    scrubValue = playback.currentTime
                } else {
                    playback.seek(to: scrubValue)
                    isScrubbing = false
                }
            }
        )
        .tint(.white)
        .accessibilityLabel("Playback position")
    }
}

private struct PlayerTimecodeView: View {
    let playback: PlaybackCoordinator

    var body: some View {
        Text("\(Timecode.format(playback.currentTime)) / \(Timecode.format(playback.duration))")
            .font(.system(.caption).monospacedDigit())
            .foregroundStyle(.white.opacity(0.85))
    }
}
