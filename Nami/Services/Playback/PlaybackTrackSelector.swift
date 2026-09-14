import Foundation

/// Chooses the best audio and subtitle tracks of an already loaded media file
/// according to `UserPreferences`.
///
/// Selection happens only after libmpv exposes the file's real track list, and
/// it is purely about tracks: it never influences source ranking, source
/// fallback, or stream scoring, and it never reads the release name. Language
/// comes from the track's own metadata, falling back to the track title when
/// exactly one language is named there.
///
/// The functions are deterministic and side-effect free so they can be unit
/// tested without launching a player.
enum PlaybackTrackSelector {

    struct Selection: Equatable, Sendable {
        let audio: MediaTrack?
        let subtitle: MediaTrack?
    }

    static func select(
        audioTracks: [MediaTrack],
        subtitleTracks: [MediaTrack],
        preferences: UserPreferences
    ) -> Selection {
        Selection(
            audio: selectAudio(from: audioTracks, preference: preferences.preferredAudio),
            subtitle: selectSubtitle(from: subtitleTracks, preference: preferences.preferredSubtitles)
        )
    }

    // MARK: - Language

    /// Canonical language code of a track.
    ///
    /// Real container metadata (`lang`) always wins. The title is only used as
    /// a fallback when it names exactly one language; ambiguous or empty titles
    /// stay unknown.
    static func language(of track: MediaTrack) -> String? {
        if let raw = track.language, let code = LanguageDetector.canonicalCode(forToken: raw) {
            return code
        }
        let detected = LanguageDetector.languages(in: track.title)
        return detected.count == 1 ? detected.first : nil
    }

    // MARK: - Audio

    /// Audio selection order:
    /// 1. The preferred language, best `AudioKind` first.
    /// 2. Japanese, when the preference is a different language.
    /// 3. The mpv-default normal track, then the best normal track.
    /// 4. Audio description / commentary only as a last resort.
    static func selectAudio(
        from tracks: [MediaTrack],
        preference: AudioPreference
    ) -> MediaTrack? {
        guard !tracks.isEmpty else { return nil }
        if let code = preference.languageCode {
            if let match = bestAudio(in: tracks, language: code) {
                return match
            }
            if code != "ja", let japanese = bestAudio(in: tracks, language: "ja") {
                return japanese
            }
        }
        return fallbackAudio(in: tracks)
    }

    private static func bestAudio(in tracks: [MediaTrack], language code: String) -> MediaTrack? {
        indexed(tracks)
            .filter { language(of: $0.track) == code }
            .sorted(by: audioPreferred)
            .first?
            .track
    }

    private static func fallbackAudio(in tracks: [MediaTrack]) -> MediaTrack? {
        let normal = indexed(tracks).filter { isNormalAudio($0.track) }
        if let match = normal.filter(\.track.isDefault).sorted(by: audioPreferred).first {
            return match.track
        }
        if let match = normal.sorted(by: audioPreferred).first {
            return match.track
        }
        return indexed(tracks).sorted(by: audioPreferred).first?.track
    }

    private static func isNormalAudio(_ track: MediaTrack) -> Bool {
        let kind = TrackTypeDetector.audioType(title: track.title).kind
        return kind == .main || kind == .unknown
    }

    private static func audioPreferred(_ lhs: OrderedTrack, _ rhs: OrderedTrack) -> Bool {
        let lhsPriority = TrackTypeDetector.audioType(title: lhs.track.title).kind.playbackSelectionPriority
        let rhsPriority = TrackTypeDetector.audioType(title: rhs.track.title).kind.playbackSelectionPriority
        if lhsPriority != rhsPriority {
            return lhsPriority > rhsPriority
        }
        if lhs.track.isDefault != rhs.track.isDefault {
            return lhs.track.isDefault
        }
        return lhs.order < rhs.order
    }

    // MARK: - Subtitles

    /// Subtitle selection order:
    /// 1. The preferred language, best `SubtitleKind` first.
    /// 2. English, when the preference is a different language.
    /// 3. The mpv-default full/SDH/unknown track, then any full/SDH/unknown.
    /// 4. Partial/special-purpose tracks as a last resort, never commentary.
    ///
    /// A `nil` result means no suitable track exists and subtitles should stay
    /// off rather than enabling something the viewer did not ask for.
    static func selectSubtitle(
        from tracks: [MediaTrack],
        preference: SubtitlePreference
    ) -> MediaTrack? {
        guard !tracks.isEmpty else { return nil }
        if let code = preference.languageCode {
            if let match = bestSubtitle(in: tracks, language: code) {
                return match
            }
            if code != "en", let english = bestSubtitle(in: tracks, language: "en") {
                return english
            }
        }
        return fallbackSubtitle(in: tracks)
    }

    private static func bestSubtitle(in tracks: [MediaTrack], language code: String) -> MediaTrack? {
        indexed(tracks)
            .filter { language(of: $0.track) == code }
            .filter { subtitleKind(of: $0.track) != .commentary }
            .sorted(by: subtitlePreferred)
            .first?
            .track
    }

    private static func fallbackSubtitle(in tracks: [MediaTrack]) -> MediaTrack? {
        let dialogue = indexed(tracks).filter { subtitleKind(of: $0.track).isFullDialogueTrack }
        if let match = dialogue.filter(\.track.isDefault).sorted(by: subtitlePreferred).first {
            return match.track
        }
        if let match = dialogue.sorted(by: subtitlePreferred).first {
            return match.track
        }
        return indexed(tracks)
            .filter { subtitleKind(of: $0.track) != .commentary }
            .sorted(by: subtitlePreferred)
            .first?
            .track
    }

    private static func subtitleKind(of track: MediaTrack) -> TrackTypeDetector.SubtitleKind {
        TrackTypeDetector.subtitleType(
            title: track.title,
            forcedFlag: track.isForced
        ).kind
    }

    private static func subtitlePreferred(_ lhs: OrderedTrack, _ rhs: OrderedTrack) -> Bool {
        let lhsPriority = subtitleKind(of: lhs.track).dialogueSelectionPriority
        let rhsPriority = subtitleKind(of: rhs.track).dialogueSelectionPriority
        if lhsPriority != rhsPriority {
            return lhsPriority > rhsPriority
        }
        if lhs.track.isDefault != rhs.track.isDefault {
            return lhs.track.isDefault
        }
        return lhs.order < rhs.order
    }

    // MARK: - Helpers

    /// Track order is the final tie-breaker, matching the order libmpv reports.
    private struct OrderedTrack {
        let track: MediaTrack
        let order: Int
    }

    private static func indexed(_ tracks: [MediaTrack]) -> [OrderedTrack] {
        tracks.enumerated().map { OrderedTrack(track: $0.element, order: $0.offset) }
    }
}
