import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.auax.Nami"

    static let kitsu = Logger(subsystem: subsystem, category: "Kitsu")
    static let addons = Logger(subsystem: subsystem, category: "Addons")
    static let streaming = Logger(subsystem: subsystem, category: "Streaming")
    static let debrid = Logger(subsystem: subsystem, category: "Debrid")
    static let playback = Logger(subsystem: subsystem, category: "Playback")
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    static let ui = Logger(subsystem: subsystem, category: "UI")
}
