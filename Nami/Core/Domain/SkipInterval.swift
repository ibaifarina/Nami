import Foundation

/// A single intro/outro/recap interval within an episode, in seconds from the
/// start of the media.
struct SkipInterval: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case opening = "op"
        case ending = "ed"
        case recap
        case mixedOpening = "mixed-op"
        case mixedEnding = "mixed-ed"
    }

    let kind: Kind
    let startSeconds: Double
    let endSeconds: Double

    var id: String { "\(kind.rawValue)-\(startSeconds)-\(endSeconds)" }

    var durationSeconds: Double { max(0, endSeconds - startSeconds) }

    /// Label for the skip button shown while this interval is playing.
    var buttonTitle: String {
        switch kind {
        case .opening, .mixedOpening: String(localized: "Skip Intro")
        case .ending, .mixedEnding: String(localized: "Skip Outro")
        case .recap: String(localized: "Skip Recap")
        }
    }

    func contains(_ time: Double) -> Bool {
        time >= startSeconds && time < endSeconds
    }
}
