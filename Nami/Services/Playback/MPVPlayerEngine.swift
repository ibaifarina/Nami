import AppKit
import Foundation
import Libmpv
import OpenGL
import OpenGL.GL
import QuartzCore
import os

// MARK: - libmpv event model

struct MPVPropertyEvent: Sendable {
    enum Value: Sendable {
        case double(Double)
        case flag(Bool)
        case int64(Int64)
        case unavailable
    }

    let name: String
    let value: Value
}

enum MPVPlaybackEvent: Sendable {
    case fileLoaded
    case endFile(reason: Int32, errorCode: Int32)
    case shutdown
    case propertyChange(MPVPropertyEvent)
}

struct MPVTrackInfo: Sendable {
    let id: Int64
    let type: String
    let title: String?
    let language: String?
    let isDefault: Bool
    let isForced: Bool
}

// MARK: - Core

/// Owns the libmpv handle and its event loop. No app state is touched here;
/// every notification is delivered through `onEvent` on the main queue.
final class MPVPlayerCore: @unchecked Sendable {
    private static let observedProperties: [(name: String, format: mpv_format)] = [
        ("time-pos", MPV_FORMAT_DOUBLE),
        ("duration", MPV_FORMAT_DOUBLE),
        ("pause", MPV_FORMAT_FLAG),
        ("volume", MPV_FORMAT_DOUBLE),
        ("speed", MPV_FORMAT_DOUBLE),
        ("eof-reached", MPV_FORMAT_FLAG),
        ("track-list", MPV_FORMAT_NONE),
    ]

    let handle: OpaquePointer

    private let eventQueue = DispatchQueue(
        label: "com.auax.Nami.mpv.events",
        qos: .userInteractive
    )
    private let stopRequested = OSAllocatedUnfairLock(initialState: false)
    private let didShutdown = OSAllocatedUnfairLock(initialState: false)
    private var renderContext: OpaquePointer?
    private var onEvent: ((MPVPlaybackEvent) -> Void)?

    init?() {
        guard let handle = mpv_create() else { return nil }
        self.handle = handle

        let options: [(name: String, value: String)] = [
            ("config", "no"),
            ("terminal", "no"),
            ("input-default-bindings", "no"),
            ("input-vo-keyboard", "no"),
            ("osc", "no"),
            ("osd-level", "0"),
            ("vo", "libmpv"),
            ("hwdec", "auto-safe"),
            ("keep-open", "yes"),
            ("audio-display", "no"),
        ]
        for option in options {
            mpv_set_option_string(handle, option.name, option.value)
        }

        guard mpv_initialize(handle) >= 0 else {
            mpv_terminate_destroy(handle)
            return nil
        }
        for property in Self.observedProperties {
            mpv_observe_property(handle, 0, property.name, property.format)
        }
    }

    func start(onEvent: @escaping (MPVPlaybackEvent) -> Void) {
        self.onEvent = onEvent
        eventQueue.async { [weak self] in
            self?.pumpEvents()
        }
    }

    // MARK: Commands

    func loadFile(_ url: URL) {
        command(["loadfile", url.absoluteString, "replace"])
    }

    func stopPlayback() {
        command(["stop"])
    }

    func addSubtitle(url: URL) {
        command(["sub-add", url.absoluteString, "select"])
    }

    func setFlag(_ name: String, _ value: Bool) {
        var flag: Int32 = value ? 1 : 0
        mpv_set_property(handle, name, MPV_FORMAT_FLAG, &flag)
    }

    func setDouble(_ name: String, _ value: Double) {
        var double = value
        mpv_set_property(handle, name, MPV_FORMAT_DOUBLE, &double)
    }

    func setInt64(_ name: String, _ value: Int64) {
        var int = value
        mpv_set_property(handle, name, MPV_FORMAT_INT64, &int)
    }

    func setString(_ name: String, _ value: String) {
        mpv_set_property_string(handle, name, value)
    }

    private func command(_ arguments: [String]) {
        var cArguments = arguments.map { argument -> UnsafePointer<CChar>? in
            strdup(argument).map { UnsafePointer($0) }
        }
        cArguments.append(nil)
        mpv_command(handle, &cArguments)
        for pointer in cArguments {
            if let pointer {
                free(UnsafeMutablePointer(mutating: pointer))
            }
        }
    }

    // MARK: Properties

    func getDouble(_ name: String) -> Double? {
        var value = Double()
        return mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value) >= 0 ? value : nil
    }

    func getInt64(_ name: String) -> Int64? {
        var value = Int64()
        return mpv_get_property(handle, name, MPV_FORMAT_INT64, &value) >= 0 ? value : nil
    }

    func getFlag(_ name: String) -> Bool? {
        var value: Int32 = 0
        return mpv_get_property(handle, name, MPV_FORMAT_FLAG, &value) >= 0 ? value != 0 : nil
    }

    func getString(_ name: String) -> String? {
        guard let cString = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(cString) }
        let value = String(cString: cString)
        return value.isEmpty ? nil : value
    }

    func readTracks() -> [MPVTrackInfo] {
        let count = getInt64("track-list/count") ?? 0
        guard count > 0 else { return [] }
        var tracks: [MPVTrackInfo] = []
        for index in 0..<count {
            let prefix = "track-list/\(index)"
            guard let type = getString("\(prefix)/type") else { continue }
            guard type == "audio" || type == "sub" else { continue }
            tracks.append(
                MPVTrackInfo(
                    id: getInt64("\(prefix)/id") ?? 0,
                    type: type,
                    title: getString("\(prefix)/title"),
                    language: getString("\(prefix)/lang"),
                    isDefault: getFlag("\(prefix)/default") ?? false,
                    isForced: getFlag("\(prefix)/forced") ?? false
                )
            )
        }
        return tracks
    }

    // MARK: Rendering

    @MainActor
    func attachRenderContext(to layer: MPVVideoLayer) -> Bool {
        if renderContext != nil { return true }
        CGLSetCurrentContext(layer.cglContext)
        defer { CGLSetCurrentContext(nil) }

        var initParams = mpv_opengl_init_params(
            get_proc_address: mpvGLGetProcAddress,
            get_proc_address_ctx: nil
        )
        let apiType = MPV_RENDER_API_TYPE_OPENGL.withCString { strdup($0) }
        defer { free(apiType) }

        return withUnsafeMutablePointer(to: &initParams) { initParamsPointer in
            var params = [
                mpv_render_param(
                    type: MPV_RENDER_PARAM_API_TYPE,
                    data: UnsafeMutableRawPointer(apiType)
                ),
                mpv_render_param(
                    type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS,
                    data: UnsafeMutableRawPointer(initParamsPointer)
                ),
                mpv_render_param(),
            ]
            var context: OpaquePointer?
            guard mpv_render_context_create(&context, handle, &params) >= 0, let context else {
                return false
            }
            renderContext = context
            mpv_render_context_set_update_callback(
                context,
                mpvRenderUpdateCallback,
                Unmanaged.passUnretained(layer).toOpaque()
            )
            return true
        }
    }

    /// Called from the layer's render queue; must not hop to the main actor.
    nonisolated func render(fbo: Int32, width: Int32, height: Int32) {
        guard let renderContext else { return }
        var fboDescription = mpv_opengl_fbo(
            fbo: fbo,
            w: width,
            h: height,
            internal_format: 0
        )
        var flip: CInt = 1
        withUnsafeMutablePointer(to: &fboDescription) { fboPointer in
            withUnsafeMutablePointer(to: &flip) { flipPointer in
                var params = [
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_OPENGL_FBO,
                        data: UnsafeMutableRawPointer(fboPointer)
                    ),
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_FLIP_Y,
                        data: UnsafeMutableRawPointer(flipPointer)
                    ),
                    mpv_render_param(),
                ]
                mpv_render_context_render(renderContext, &params)
            }
        }
    }

    /// Called from the layer's render queue; must not hop to the main actor.
    nonisolated func reportSwap() {
        guard let renderContext else { return }
        mpv_render_context_report_swap(renderContext)
    }

    @MainActor
    func destroyRenderContext() {
        guard let renderContext else { return }
        self.renderContext = nil
        mpv_render_context_set_update_callback(renderContext, nil, nil)
        mpv_render_context_free(renderContext)
    }

    @MainActor
    func shutdown(view: MPVVideoView?) {
        let alreadyShutDown = didShutdown.withLock { flag -> Bool in
            if flag { return true }
            flag = true
            return false
        }
        guard !alreadyShutDown else { return }

        stopRequested.withLock { $0 = true }
        mpv_wakeup(handle)
        eventQueue.sync {}

        view?.videoLayer.detach()
        CGLSetCurrentContext(view?.videoLayer.cglContext)
        destroyRenderContext()
        CGLSetCurrentContext(nil)
        mpv_terminate_destroy(handle)
    }

    // MARK: Event pump

    private func pumpEvents() {
        while true {
            if stopRequested.withLock({ $0 }) { break }
            guard let event = mpv_wait_event(handle, -1) else { continue }
            if stopRequested.withLock({ $0 }) { break }
            process(event.pointee)
        }
    }

    private func process(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let data = event.data else { return }
            let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
            let name = String(cString: property.name)
            let value: MPVPropertyEvent.Value
            switch property.format {
            case MPV_FORMAT_DOUBLE:
                value = property.data
                    .map { .double($0.assumingMemoryBound(to: Double.self).pointee) } ?? .unavailable
            case MPV_FORMAT_FLAG:
                value = property.data
                    .map { .flag($0.assumingMemoryBound(to: Int32.self).pointee != 0) } ?? .unavailable
            case MPV_FORMAT_INT64:
                value = property.data
                    .map { .int64($0.assumingMemoryBound(to: Int64.self).pointee) } ?? .unavailable
            default:
                value = .unavailable
            }
            onEvent?(.propertyChange(MPVPropertyEvent(name: name, value: value)))
        case MPV_EVENT_FILE_LOADED:
            onEvent?(.fileLoaded)
        case MPV_EVENT_END_FILE:
            guard let data = event.data else { return }
            let endFile = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
            onEvent?(.endFile(reason: Int32(endFile.reason.rawValue), errorCode: endFile.error))
        case MPV_EVENT_SHUTDOWN:
            onEvent?(.shutdown)
        default:
            break
        }
    }
}

// MARK: - C callbacks

private func mpvGLGetProcAddress(
    _ context: UnsafeMutableRawPointer?,
    _ name: UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    let symbol = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
    guard let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString) else {
        return nil
    }
    return CFBundleGetFunctionPointerForName(bundle, symbol)
}

private func mpvRenderUpdateCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let layer = Unmanaged<MPVVideoLayer>.fromOpaque(context).takeUnretainedValue()
    layer.requestFrame()
}

// MARK: - Video surface

/// Renders libmpv through a `CAOpenGLLayer` so OpenGL work runs on a dedicated
/// queue instead of the main thread. Drawing video on the main thread starves
/// SwiftUI's event loop, which makes control animations and cursor-driven UI
/// (showing the controls) feel sluggish.
final class MPVVideoLayer: CAOpenGLLayer, @unchecked Sendable {
    var render: (@Sendable (Int32, Int32, Int32) -> Void)?
    var didPresent: (@Sendable () -> Void)?

    let cglPixelFormat: CGLPixelFormatObj
    let cglContext: CGLContextObj

    private let renderQueue = DispatchQueue(label: "com.auax.Nami.mpv.gl", qos: .userInteractive)
    private let displayLock = NSRecursiveLock()
    private let needsFrame = OSAllocatedUnfairLock(initialState: false)
    /// CA can hand back a zero FBO on the first draw; keep the last valid one.
    private var lastFBO: GLint = 1

    override init() {
        let pixelFormat = Self.makePixelFormat()
        cglPixelFormat = pixelFormat
        cglContext = Self.makeContext(pixelFormat: pixelFormat)
        super.init()
        configureLayer()
    }

    override init(layer: Any) {
        if let previous = layer as? MPVVideoLayer {
            cglPixelFormat = previous.cglPixelFormat
            cglContext = previous.cglContext
        } else {
            let pixelFormat = Self.makePixelFormat()
            cglPixelFormat = pixelFormat
            cglContext = Self.makeContext(pixelFormat: pixelFormat)
        }
        super.init(layer: layer)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureLayer() {
        autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backgroundColor = NSColor.black.cgColor
        contentsGravity = .resizeAspect
        isAsynchronous = false
    }

    /// Schedules a draw off the main thread. Safe to call from any thread.
    func requestFrame() {
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.needsFrame.withLock { $0 = true }
            self.display()
        }
    }

    /// Drains the render queue and stops drawing so the engine can safely
    /// destroy the mpv render context.
    func detach() {
        renderQueue.sync {
            render = nil
            didPresent = nil
            needsFrame.withLock { $0 = false }
        }
    }

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        cglPixelFormat
    }

    override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj {
        cglContext
    }

    override func canDraw(
        inCGLContext ctx: CGLContextObj,
        pixelFormat pf: CGLPixelFormatObj,
        forLayerTime t: CFTimeInterval,
        displayTime ts: UnsafePointer<CVTimeStamp>?
    ) -> Bool {
        needsFrame.withLock { $0 }
    }

    override func draw(
        inCGLContext ctx: CGLContextObj,
        pixelFormat pf: CGLPixelFormatObj,
        forLayerTime t: CFTimeInterval,
        displayTime ts: UnsafePointer<CVTimeStamp>?
    ) {
        needsFrame.withLock { $0 = false }
        var fbo: GLint = 0
        glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &fbo)
        if fbo != 0 {
            lastFBO = fbo
        }
        var viewport = [GLint](repeating: 0, count: 4)
        glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)
        render?(Int32(lastFBO), Int32(viewport[2]), Int32(viewport[3]))
        glFlush()
        didPresent?()
    }

    override func display() {
        displayLock.lock()
        defer { displayLock.unlock() }
        if Thread.isMainThread {
            super.display()
        } else {
            // Off-main draws need an explicit transaction and flush, otherwise
            // the frame is not committed.
            CATransaction.begin()
            super.display()
            CATransaction.commit()
        }
        CATransaction.flush()
    }

    private static func makePixelFormat() -> CGLPixelFormatObj {
        let profiles: [CGLOpenGLProfile] = [kCGLOGLPVersion_3_2_Core, kCGLOGLPVersion_Legacy]
        for profile in profiles {
            var attributes: [CGLPixelFormatAttribute] = [
                kCGLPFAOpenGLProfile,
                CGLPixelFormatAttribute(profile.rawValue),
                kCGLPFAAccelerated,
                kCGLPFADoubleBuffer,
                kCGLPFAColorSize,
                CGLPixelFormatAttribute(32),
                kCGLPFAAllowOfflineRenderers,
                CGLPixelFormatAttribute(0),
            ]
            var pixelFormat: CGLPixelFormatObj?
            var count: GLint = 0
            if CGLChoosePixelFormat(&attributes, &pixelFormat, &count) == kCGLNoError, let pixelFormat {
                return pixelFormat
            }
        }
        fatalError("Unable to create an OpenGL pixel format for video playback")
    }

    private static func makeContext(pixelFormat: CGLPixelFormatObj) -> CGLContextObj {
        var context: CGLContextObj?
        guard CGLCreateContext(pixelFormat, nil, &context) == kCGLNoError, let context else {
            fatalError("Unable to create an OpenGL context for video playback")
        }
        var swapInterval: GLint = 1
        CGLSetParameter(context, kCGLCPSwapInterval, &swapInterval)
        CGLEnable(context, kCGLCEMPEngine)
        return context
    }
}

/// Hosts `MPVVideoLayer` as its backing layer.
final class MPVVideoView: NSView {
    let videoLayer: MPVVideoLayer

    override init(frame frameRect: NSRect) {
        videoLayer = MPVVideoLayer()
        super.init(frame: frameRect)
        wantsLayer = true
        layer = videoLayer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        videoLayer.contentsScale = window.backingScaleFactor
        videoLayer.requestFrame()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        videoLayer.contentsScale = window?.backingScaleFactor ?? 2
        videoLayer.requestFrame()
    }
}

// MARK: - Engine

@MainActor
final class MPVPlayerEngine: PlayerEngine {
    var onStateChange: ((PlayerEngineState) -> Void)?
    var onTimeChange: ((Double, Double) -> Void)?
    var onTracksChange: (() -> Void)?

    private var core: MPVPlayerCore?
    private var videoView: MPVVideoView?
    private var state: PlayerEngineState = .idle
    private var loadContinuation: CheckedContinuation<Void, Error>?
    private var loadTimeoutTask: Task<Void, Never>?
    private var isLoaded = false
    private var didReachEOF = false
    private var durationValue: Double = 0
    private var currentTimeValue: Double = 0
    private var lastEmittedTime: Double = 0
    private var volumeValue: Double = 1
    private var rateValue: Double = 1
    private var audioTrackList: [MediaTrack] = []
    private var subtitleTrackList: [MediaTrack] = []
    private nonisolated(unsafe) var terminateObserver: NSObjectProtocol?

    init() {
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.shutdown()
            }
        }
    }

    deinit {
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
        }
    }

    // MARK: PlayerEngine

    var isPlaying: Bool { state == .playing }

    var currentTime: Double { currentTimeValue }

    var duration: Double { durationValue }

    var volume: Double { volumeValue }

    var rate: Double { rateValue }

    func load(_ stream: ResolvedStream) async throws {
        guard let core = ensureCore() else {
            let error = PlayerError.failedToLoad("The MPV playback engine could not be initialized.")
            emit(.failed(error.userMessage))
            throw error
        }

        failPendingLoad(with: CancellationError())
        core.stopPlayback()
        isLoaded = false
        didReachEOF = false
        durationValue = 0
        currentTimeValue = 0
        lastEmittedTime = 0
        emit(.loading)
        core.loadFile(stream.url)

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    loadContinuation = continuation
                    loadTimeoutTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(20))
                        guard !Task.isCancelled else { return }
                        self?.timeoutPendingLoad()
                    }
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.failPendingLoad(with: CancellationError())
                }
            }
        } catch {
            if error is CancellationError {
                throw error
            }
            emit(.failed(Self.message(for: error)))
            throw error
        }

        refreshTracks()
        emit(.ready)
    }

    func play() {
        guard let core else { return }
        core.setFlag("pause", false)
        didReachEOF = false
        if isLoaded {
            emit(.playing)
        }
    }

    func pause() {
        guard let core else { return }
        core.setFlag("pause", true)
        if isLoaded {
            emit(.paused)
        }
    }

    func stop() {
        failPendingLoad(with: CancellationError())
        core?.stopPlayback()
        isLoaded = false
        didReachEOF = false
        currentTimeValue = 0
        durationValue = 0
        emit(.idle)
    }

    func seek(to seconds: Double) {
        guard let core else { return }
        let target = max(0, seconds)
        core.setDouble("time-pos", target)
        didReachEOF = false
        currentTimeValue = target
        lastEmittedTime = target
        onTimeChange?(target, durationValue)
    }

    func setVolume(_ volume: Double) {
        let clamped = min(max(volume, 0), 1)
        volumeValue = clamped
        core?.setDouble("volume", clamped * 100)
    }

    func setRate(_ rate: Double) {
        let clamped = min(max(rate, 0.5), 2)
        rateValue = clamped
        core?.setDouble("speed", clamped)
    }

    func audioTracks() -> [MediaTrack] {
        audioTrackList
    }

    func subtitleTracks() -> [MediaTrack] {
        subtitleTrackList
    }

    func selectAudioTrack(_ track: MediaTrack) {
        guard let id = Self.trackID(from: track.id) else { return }
        core?.setInt64("aid", id)
    }

    func selectSubtitleTrack(_ track: MediaTrack?) {
        guard let core else { return }
        if let track, let id = Self.trackID(from: track.id) {
            core.setInt64("sid", id)
        } else {
            core.setString("sid", "no")
        }
    }

    func addExternalSubtitle(url: URL) {
        core?.addSubtitle(url: url)
    }

    func makeVideoSurface() -> NSView {
        ensureVideoView()
    }

    func updateVideoSurface(_ view: NSView) {
        guard let view = view as? MPVVideoView, let core = ensureCore() else { return }
        let isNewSurface = videoView !== view
        videoView = view
        configure(videoLayer: view.videoLayer, core: core)
        if core.attachRenderContext(to: view.videoLayer), isNewSurface {
            view.videoLayer.requestFrame()
        }
    }

    func shutdown() {
        failPendingLoad(with: CancellationError())
        let view = videoView
        videoView = nil
        view?.videoLayer.detach()
        core?.shutdown(view: view)
        core = nil
        isLoaded = false
        didReachEOF = false
        emit(.idle)
    }

    // MARK: Wiring

    private func ensureCore() -> MPVPlayerCore? {
        if let core { return core }
        guard let core = MPVPlayerCore() else { return nil }
        core.start { [weak self] event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.handle(event)
                }
            }
        }
        self.core = core
        return core
    }

    private func ensureVideoView() -> MPVVideoView {
        if let videoView { return videoView }
        let view = MPVVideoView(frame: .zero)
        videoView = view
        if let core = ensureCore() {
            configure(videoLayer: view.videoLayer, core: core)
            _ = core.attachRenderContext(to: view.videoLayer)
        }
        return view
    }

    private func configure(videoLayer: MPVVideoLayer, core: MPVPlayerCore) {
        if videoLayer.render == nil {
            videoLayer.render = { [weak core] fbo, width, height in
                core?.render(fbo: fbo, width: width, height: height)
            }
        }
        if videoLayer.didPresent == nil {
            videoLayer.didPresent = { [weak core] in
                core?.reportSwap()
            }
        }
    }

    // MARK: Events

    private func handle(_ event: MPVPlaybackEvent) {
        switch event {
        case .fileLoaded:
            handleFileLoaded()
        case .endFile(let reason, let errorCode):
            handleEndFile(reason: reason, errorCode: errorCode)
        case .propertyChange(let property):
            handleProperty(property)
        case .shutdown:
            break
        }
    }

    private func handleFileLoaded() {
        loadTimeoutTask?.cancel()
        loadTimeoutTask = nil
        isLoaded = true
        didReachEOF = false
        if let duration = core?.getDouble("duration"), duration.isFinite, duration > 0 {
            durationValue = duration
        }
        resumePendingLoad(with: nil)
        refreshTracks()
    }

    private func handleEndFile(reason: Int32, errorCode: Int32) {
        let isError = reason == Int32(MPV_END_FILE_REASON_ERROR.rawValue) || errorCode < 0
        if loadContinuation != nil {
            // Stale stop/redirect events for a previous file are expected while a
            // new load is in flight; only a genuine error should fail the load.
            guard isError else { return }
            resumePendingLoad(with: PlayerError.failedToLoad(Self.message(forMPVError: errorCode)))
            return
        }
        if isError {
            isLoaded = false
            emit(.failed(Self.message(forMPVError: errorCode)))
            return
        }
        if !didReachEOF, reason == Int32(MPV_END_FILE_REASON_EOF.rawValue) {
            didReachEOF = true
            onTimeChange?(durationValue, durationValue)
            emit(.ended)
        }
    }

    private func handleProperty(_ property: MPVPropertyEvent) {
        switch property.name {
        case "time-pos":
            guard case .double(let seconds) = property.value, seconds.isFinite else { return }
            currentTimeValue = max(0, seconds)
            if abs(currentTimeValue - lastEmittedTime) >= 0.2 {
                lastEmittedTime = currentTimeValue
                onTimeChange?(currentTimeValue, durationValue)
            }
        case "duration":
            guard case .double(let seconds) = property.value, seconds.isFinite, seconds > 0 else {
                return
            }
            durationValue = seconds
        case "pause":
            guard case .flag(let paused) = property.value, isLoaded, !didReachEOF else { return }
            emit(paused ? .paused : .playing)
        case "volume":
            guard case .double(let value) = property.value else { return }
            volumeValue = min(max(value / 100, 0), 1)
        case "speed":
            guard case .double(let value) = property.value, value > 0 else { return }
            rateValue = value
        case "eof-reached":
            guard case .flag(let reached) = property.value, reached, !didReachEOF else { return }
            didReachEOF = true
            onTimeChange?(durationValue, durationValue)
            emit(.ended)
        case "track-list":
            refreshTracks()
        default:
            break
        }
    }

    // MARK: Load bookkeeping

    private func timeoutPendingLoad() {
        loadTimeoutTask = nil
        failPendingLoad(with: PlayerError.timedOut)
    }

    private func failPendingLoad(with error: Error) {
        loadTimeoutTask?.cancel()
        loadTimeoutTask = nil
        guard let continuation = loadContinuation else { return }
        loadContinuation = nil
        continuation.resume(throwing: error)
    }

    private func resumePendingLoad(with error: Error?) {
        loadTimeoutTask?.cancel()
        loadTimeoutTask = nil
        guard let continuation = loadContinuation else { return }
        loadContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    // MARK: Tracks

    private func refreshTracks() {
        guard let core else { return }
        let infos = core.readTracks()
        audioTrackList = infos.filter { $0.type == "audio" }.map(Self.mediaTrack(from:))
        subtitleTrackList = infos.filter { $0.type == "sub" }.map(Self.mediaTrack(from:))
        onTracksChange?()
    }

    private static func mediaTrack(from info: MPVTrackInfo) -> MediaTrack {
        let kind: MediaTrack.Kind = info.type == "audio" ? .audio : .subtitle
        let fallback = kind == .audio ? "Audio \(info.id)" : "Subtitle \(info.id)"
        let title = info.title ?? languageName(info.language) ?? fallback
        return MediaTrack(
            id: "\(kind.rawValue)-\(info.id)",
            kind: kind,
            title: title,
            language: info.language,
            isDefault: info.isDefault,
            isForced: info.isForced
        )
    }

    private static func languageName(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        return Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }

    private static func trackID(from identifier: String) -> Int64? {
        identifier.split(separator: "-").last.flatMap { Int64($0) }
    }

    // MARK: State

    private func emit(_ newState: PlayerEngineState) {
        state = newState
        onStateChange?(newState)
    }

    private static func message(for error: Error) -> String {
        if let playerError = error as? PlayerError {
            return playerError.userMessage
        }
        return error.localizedDescription
    }

    private static func message(forMPVError code: Int32) -> String {
        guard code < 0, let description = mpv_error_string(code) else {
            return "The video could not be loaded."
        }
        return String(cString: description)
    }
}
