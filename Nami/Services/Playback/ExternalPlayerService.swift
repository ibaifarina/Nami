import AppKit

struct ExternalPlayer: Identifiable, Hashable, Sendable {
    let bundleID: String
    let displayName: String

    var id: String { bundleID }

    /// Common macOS video players, in the order they are offered in Settings.
    static let known: [ExternalPlayer] = [
        ExternalPlayer(bundleID: "org.videolan.vlc", displayName: "VLC"),
        ExternalPlayer(bundleID: "com.colliderli.iina", displayName: "IINA"),
        ExternalPlayer(bundleID: "io.mpv", displayName: "mpv"),
        ExternalPlayer(bundleID: "com.firecore.infuse", displayName: "Infuse"),
        ExternalPlayer(bundleID: "com.eltima.ElmediaPlayer", displayName: "Elmedia Player"),
        ExternalPlayer(bundleID: "com.movist.MovistPro", displayName: "Movist Pro"),
        ExternalPlayer(bundleID: "com.movist.Movist", displayName: "Movist"),
        ExternalPlayer(bundleID: "com.apple.QuickTimePlayerX", displayName: "QuickTime Player"),
    ]
}

enum ExternalPlayerError: LocalizedError, Equatable {
    case notInstalled(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let name):
            String(localized: "\(name) is no longer installed.")
        }
    }
}

@MainActor
protocol ExternalPlayerOpening {
    func detectedPlayers() -> [ExternalPlayer]
    func open(_ url: URL, in player: ExternalPlayer) async throws
}

@MainActor
struct ExternalPlayerService: ExternalPlayerOpening {
    func detectedPlayers() -> [ExternalPlayer] {
        ExternalPlayer.known.filter { applicationURL(for: $0) != nil }
    }

    func applicationURL(for player: ExternalPlayer) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID)
    }

    func icon(for player: ExternalPlayer) -> NSImage? {
        guard let url = applicationURL(for: player) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    func open(_ url: URL, in player: ExternalPlayer) async throws {
        guard let applicationURL = applicationURL(for: player) else {
            throw ExternalPlayerError.notInstalled(player.displayName)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.open(
            [url],
            withApplicationAt: applicationURL,
            configuration: configuration
        )
    }
}
