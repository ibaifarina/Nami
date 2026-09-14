import Foundation

/// Classifies media tracks by their semantic purpose.
///
/// This does NOT detect the language of a track.
/// Language detection/normalization belongs to `LanguageDetector`.
///
/// Typical subtitle examples:
///
/// - "English Full"          -> .full
/// - "English SDH"           -> .sdh
/// - "English Forced"        -> .forced
/// - "English Signs & Songs" -> .signsAndSongs
/// - "Karaoke / Lyrics"      -> .lyrics
///
/// Typical audio examples:
///
/// - "Japanese"              -> .main
/// - "English Commentary"    -> .commentary
/// - "English Audio Description" -> .descriptive
enum TrackTypeDetector {

    // MARK: - Confidence

    enum Confidence: Int, Hashable, Sendable {
        case unknown = 0
        case inferred = 1
        case explicit = 2
    }

    // MARK: - Subtitle

    enum SubtitleKind: String, Hashable, Sendable {
        /// Normal/full dialogue subtitles.
        case full

        /// SDH / CC / hearing-impaired captions.
        case sdh

        /// Forced subtitles, usually only foreign dialogue.
        case forced

        /// Signs, songs, on-screen text, etc.
        case signsAndSongs

        /// Karaoke / lyrics-only track.
        case lyrics

        /// Commentary subtitle track.
        case commentary

        /// Nami cannot determine the type.
        ///
        /// This is still treated as a good candidate because many
        /// normal subtitle tracks are simply called "English",
        /// "Español", etc.
        case unknown

        /// Preference when the user wants actual dialogue subtitles.
        ///
        /// This is NOT part of stream/source scoring. It is only
        /// intended to choose between subtitle tracks inside an
        /// already selected media file.
        var dialogueSelectionPriority: Int {
            switch self {
            case .full:
                600

            case .sdh:
                550

            case .unknown:
                500

            case .signsAndSongs:
                200

            case .forced:
                150

            case .lyrics:
                100

            case .commentary:
                0
            }
        }

        var isFullDialogueTrack: Bool {
            switch self {
            case .full, .sdh, .unknown:
                true

            case .forced,
                 .signsAndSongs,
                 .lyrics,
                 .commentary:
                false
            }
        }
    }

    struct SubtitleClassification: Hashable, Sendable {
        let kind: SubtitleKind
        let confidence: Confidence
    }

    // MARK: - Audio

    enum AudioKind: String, Hashable, Sendable {
        /// Normal program audio.
        case main

        /// Director / staff / cast commentary.
        case commentary

        /// Audio-description / descriptive narration.
        case descriptive

        /// Couldn't confidently classify it.
        case unknown

        /// Preference when choosing a normal playback track.
        var playbackSelectionPriority: Int {
            switch self {
            case .main:
                300

            case .unknown:
                250

            case .descriptive:
                100

            case .commentary:
                0
            }
        }
    }

    struct AudioClassification: Hashable, Sendable {
        let kind: AudioKind
        let confidence: Confidence
    }

    // MARK: - Public API

    static func subtitleType(
        title: String?,
        forcedFlag: Bool = false
    ) -> SubtitleClassification {

        // The container/mpv flag is stronger than anything we can
        // infer from the title.
        if forcedFlag {
            return SubtitleClassification(
                kind: .forced,
                confidence: .explicit
            )
        }

        guard let normalized = normalize(title),
              !normalized.isEmpty
        else {
            return SubtitleClassification(
                kind: .unknown,
                confidence: .unknown
            )
        }

        // Forced must come early because titles can contain things like
        // "English Forced Dialogue".
        if containsAny(
            normalized,
            phrases: [
                "forced",
                "forced subtitle",
                "forced subtitles",
                "forced narrative",
                "foreign parts",
                "foreign only",
                "forzado",
                "forzados",
                "forzada",
                "forzadas",
                "subtitulos forzados",
                "subtitulo forzado",
                "force",
                "forces"
            ]
        ) {
            return SubtitleClassification(
                kind: .forced,
                confidence: .explicit
            )
        }

        if containsAny(
            normalized,
            phrases: [
                "commentary",
                "comment",
                "director commentary",
                "cast commentary",
                "comentario",
                "comentarios",
                "commentaire",
                "kommentar"
            ]
        ) {
            return SubtitleClassification(
                kind: .commentary,
                confidence: .explicit
            )
        }

        if containsAny(
            normalized,
            phrases: [
                "sdh",
                "closed caption",
                "closed captions",
                "closed captioning",
                "hearing impaired",
                "hard of hearing",
                "deaf and hard of hearing"
            ]
        ) || containsToken("cc", in: normalized)
          || containsToken("hoh", in: normalized) {
            return SubtitleClassification(
                kind: .sdh,
                confidence: .explicit
            )
        }

        if containsAny(
            normalized,
            phrases: [
                "signs and songs",
                "songs and signs",
                "signs songs",
                "songs signs",
                "signs only",
                "songs only",
                "signs",
                "carteles y canciones",
                "carteles",
                "letreros",
                "songs"
            ]
        ) {
            return SubtitleClassification(
                kind: .signsAndSongs,
                confidence: .explicit
            )
        }

        if containsAny(
            normalized,
            phrases: [
                "karaoke",
                "lyrics",
                "lyrics only",
                "song lyrics",
                "letras",
                "paroles"
            ]
        ) {
            return SubtitleClassification(
                kind: .lyrics,
                confidence: .explicit
            )
        }

        if containsAny(
            normalized,
            phrases: [
                "full",
                "full subtitle",
                "full subtitles",
                "full subs",
                "dialogue",
                "dialog",
                "dialogue subtitles",
                "complete",
                "completo",
                "completos",
                "completa",
                "completas"
            ]
        ) {
            return SubtitleClassification(
                kind: .full,
                confidence: .explicit
            )
        }

        // Important:
        //
        // "English", "Español", "Deutsch", etc. normally represent
        // a perfectly valid full subtitle track even though the title
        // doesn't explicitly say "Full".
        //
        // Keep it as unknown instead of assuming a special type.
        return SubtitleClassification(
            kind: .unknown,
            confidence: .unknown
        )
    }

    static func audioType(
        title: String?
    ) -> AudioClassification {
        guard let normalized = normalize(title),
              !normalized.isEmpty
        else {
            // Unnamed audio tracks are overwhelmingly likely to be
            // normal playback audio.
            return AudioClassification(
                kind: .main,
                confidence: .inferred
            )
        }

        if containsAny(
            normalized,
            phrases: [
                "commentary",
                "director commentary",
                "cast commentary",
                "staff commentary",
                "audio commentary",
                "comentario",
                "comentarios",
                "commentaire",
                "kommentar"
            ]
        ) {
            return AudioClassification(
                kind: .commentary,
                confidence: .explicit
            )
        }

        if containsAny(
            normalized,
            phrases: [
                "audio description",
                "audio described",
                "audio descriptive",
                "descriptive audio",
                "described video",
                "descriptive narration",
                "descripcion de audio",
                "audiodescription",
                "audiodescription",
                "audio description francaise"
            ]
        ) {
            return AudioClassification(
                kind: .descriptive,
                confidence: .explicit
            )
        }

        // If there are no special-purpose markers, treat it as the
        // normal program audio. Whether it is Japanese/English/etc.
        // is decided separately by LanguageDetector.
        return AudioClassification(
            kind: .main,
            confidence: .inferred
        )
    }

    // MARK: - Helpers

    private static func normalize(
        _ text: String?
    ) -> String? {
        guard let text else {
            return nil
        }

        let folded = text
            .folding(
                options: [
                    .diacriticInsensitive,
                    .widthInsensitive
                ],
                locale: nil
            )
            .lowercased()

        // Convert punctuation/separators to spaces so:
        //
        // "Signs & Songs"
        // "Signs-and-Songs"
        // "Signs_And_Songs"
        //
        // become comparable.
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(String(scalar))
            }

            return " "
        }

        return String(scalars)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func containsAny(
        _ text: String,
        phrases: [String]
    ) -> Bool {
        phrases.contains { phrase in
            let normalizedPhrase =
                normalize(phrase) ?? phrase.lowercased()

            return containsPhrase(
                normalizedPhrase,
                in: text
            )
        }
    }

    private static func containsPhrase(
        _ phrase: String,
        in text: String
    ) -> Bool {
        guard !phrase.isEmpty else {
            return false
        }

        if phrase.contains(" ") {
            return text.contains(phrase)
        }

        return containsToken(
            phrase,
            in: text
        )
    }

    private static func containsToken(
        _ token: String,
        in text: String
    ) -> Bool {
        text.split(separator: " ")
            .contains {
                $0 == Substring(token)
            }
    }
}