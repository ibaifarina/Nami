import Foundation

/// Detects the audio and subtitle languages named in release titles and addon
/// metadata, using ISO 639-1 codes as canonical identifiers.
///
/// The vocabulary combines three sources:
/// 1. Structured codes: ISO 639-1, ISO 639-2/B and /T, plus region and script
///    variants such as `es-419`, `pt-BR`, or `zh-Hans`.
/// 2. Locale-generated names: every supported language is asked for its name
///    in many locales. This yields endonyms and exonyms far beyond English
///    terms ("Deutsch", "Español", "Português", "Русский", "日本語", ...).
/// 3. Release conventions and inference tags that locale data cannot know
///    ("Castellano", "VOSTFR", "Dublado", "Dual Audio", "RAW", ...).
enum LanguageDetector {
    struct Mention {
        enum Context {
            case audio
            case subtitle
            case neutral
        }

        let code: String
        let context: Context
    }

    /// Languages recognized by the detector, as ISO 639-1 codes.
    static let supportedCodes = [
        "ja", "en", "es", "pt", "fr", "de", "it", "ru", "ko", "zh",
        "ar", "pl", "nl", "tr", "hi", "th", "vi", "id", "sv", "no",
        "da", "fi", "cs", "el", "he", "hu", "ro", "uk", "ms", "fil",
        "bn", "ta", "te", "fa", "sw",
    ]

    /// Locales whose own language names are harvested. Together they cover the
    /// languages that appear most often in release metadata.
    private static let nameLocales = [
        "en", "es", "pt-BR", "de", "fr", "it", "ru", "ja", "ko", "zh-Hans",
        "ar", "pl", "nl", "tr", "hi", "th", "vi", "id", "uk", "he", "sv",
    ]

    /// Release conventions, alternate spellings, and ISO 639-2 codes that the
    /// locale tables do not provide.
    private static let curatedTokens: [String: String] = [
        // ISO 639-2/B and 639-2/T codes.
        "jpn": "ja", "jap": "ja", "eng": "en", "spa": "es", "esp": "es",
        "fre": "fr", "fra": "fr", "ger": "de", "deu": "de", "ita": "it",
        "por": "pt", "rus": "ru", "kor": "ko", "chi": "zh", "zho": "zh",
        "ara": "ar", "pol": "pl", "dut": "nl", "nld": "nl", "tur": "tr",
        "hin": "hi", "tha": "th", "vie": "vi", "ind": "id", "swe": "sv",
        "nor": "no", "dan": "da", "fin": "fi", "cze": "cs", "ces": "cs",
        "gre": "el", "ell": "el", "heb": "he", "hun": "hu", "rum": "ro",
        "ron": "ro", "ukr": "uk", "may": "ms", "msa": "ms", "fil": "fil",
        "tgl": "fil", "ben": "bn", "tam": "ta", "tel": "te", "urd": "ur",
        "per": "fa", "fas": "fa", "swa": "sw",
        // Region and script variants.
        "es-419": "es", "es-es": "es", "es-mx": "es", "es-ar": "es",
        "pt-br": "pt", "pt-pt": "pt", "zh-hans": "zh", "zh-hant": "zh",
        "zh-cn": "zh", "zh-tw": "zh", "zh-hk": "zh",
        // Release conventions and alternate names.
        "castellano": "es", "latino": "es", "español": "es", "espanol": "es",
        "japonés": "ja", "japones": "ja",
        "français": "fr", "francais": "fr", "vostfr": "fr", "truefrench": "fr",
        "vff": "fr", "vfq": "fr", "vf": "fr",
        "deutsch": "de", "italiano": "it",
        "português": "pt", "portugues": "pt", "dublado": "pt", "legendado": "pt",
        "coreano": "ko", "chino": "zh",
    ]

    /// Tokens that describe subtitles rather than audio.
    private static let subtitleOnlyTokens: Set<String> = ["vostfr", "legendado"]

    // MARK: - Vocabulary

    private static let vocabulary: [String: String] = buildVocabulary()

    /// Every two-letter token, only trusted when delimited or bracketed.
    private static let shortCodes: [String: String] = vocabulary.filter { $0.key.count == 2 }

    /// Tokens long enough to be matched anywhere in a title. Space-less
    /// scripts (CJK, Thai) are allowed at two characters.
    private static let longTokens: [String: String] = vocabulary.filter {
        $0.key.count > 2 || requiresSubstringMatch($0.key)
    }

    private static let substringTokens = Set(longTokens.keys.filter(requiresSubstringMatch))
    private static let boundaryTokens = Set(longTokens.keys).subtracting(substringTokens)

    private static func buildVocabulary() -> [String: String] {
        var vocabulary: [String: String] = [:]
        for code in supportedCodes {
            vocabulary[code] = code
        }
        for code in supportedCodes {
            for localeID in nameLocales {
                let locale = Locale(identifier: localeID)
                guard let name = locale.localizedString(forLanguageCode: code) else { continue }
                for token in normalizedTokens(name) where vocabulary[token] == nil {
                    vocabulary[token] = code
                }
            }
        }
        for (token, code) in curatedTokens {
            for normalized in normalizedTokens(token) {
                vocabulary[normalized] = code
            }
        }
        return vocabulary
    }

    /// Lowercases a name and adds a diacritic-folded variant, so both
    /// "Português" and "Portugues" are recognized.
    private static func normalizedTokens(_ name: String) -> [String] {
        let lowered = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !lowered.isEmpty, !lowered.contains(where: \.isNumber) else { return [] }
        var tokens = [lowered]
        let folded = lowered.folding(options: .diacriticInsensitive, locale: nil)
        if folded != lowered {
            tokens.append(folded)
        }
        return tokens
    }

    /// Scripts without spaces cannot rely on word boundaries.
    private static func requiresSubstringMatch(_ token: String) -> Bool {
        token.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
                 0xAC00...0xD7AF, 0x0E00...0x0E7F, 0x0E80...0x0EFF,
                 0x1000...0x109F, 0x1780...0x17FF:
                true

            default:
                false
            }
        }
    }

    // MARK: - Patterns

    private static let boundaryPattern: String = {
        let alternatives = boundaryTokens
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
        return "(?<![\\p{L}\\p{N}])(?:" + alternatives.joined(separator: "|") + ")(?![\\p{L}\\p{N}])"
    }()

    private static let substringPattern: String = {
        let alternatives = substringTokens
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
        guard !alternatives.isEmpty else { return "" }
        return "(?:" + alternatives.joined(separator: "|") + ")"
    }()

    private static let shortCodePattern = "[\\[\\(\\{]([a-z]{2})(?:[-_][a-z0-9]{2,4})?[\\]\\)\\}]"
    private static let regionCodePattern =
        "(?<![\\p{L}\\p{N}])([a-z]{2})[-_](?:br|pt|us|uk|gb|mx|ar|cl|co|419|latn?|hans|hant|cn|tw|hk|kr|jp)(?![\\p{L}\\p{N}])"

    private static let raw = "\\braws?\\b"
    private static let dualAudio = "\\b(?:dual|multi|multiple)[\\s\\-_]?(?:audio|áudio)\\b"
    private static let dubbed = "\\b(?:dub(?:bed|s)?|doblaje|doblado|dublado)\\b"
    private static let subbed = "\\b(?:sub(?:bed|s)?|subtitulad[oa]s?|legendado)\\b"
    private static let multiSubs = "\\b(?:multi|multiple)[\\s\\-_]?(?:subs?|subtitles?|legendas?)\\b"
    private static let spanishDub = "\\b(?:doblaje|doblado)\\b"
    private static let portugueseDub = "\\bdublado\\b"
    private static let subtitleMarker =
        "\\b(?:subs?|subbed|subtitles?|vostfr|legendado|legendas?|subtitulad[oa]s?|subt[ií]tulos?|untertitel|sous-titres?)\\b"
    private static let audioMarker =
        "\\b(?:dub(?:bed|s)?|audio|áudio|dual|doblaje|doblado|dublado|doublage|synchron(?:isiert|isation)?)\\b"

    // MARK: - Detection

    /// Finds every language named in the text, using safe matching rules:
    /// long names need word boundaries, space-less scripts match as
    /// substrings, and two-letter codes are only trusted when bracketed or
    /// carrying a region suffix.
    static func mentions(in text: String) -> [Mention] {
        guard !text.isEmpty else { return [] }
        var mentions = matches(of: boundaryPattern, in: text)
        if !substringPattern.isEmpty {
            mentions.append(contentsOf: matches(of: substringPattern, in: text))
        }
        mentions.append(contentsOf: codeMatches(of: shortCodePattern, in: text))
        mentions.append(contentsOf: codeMatches(of: regionCodePattern, in: text))
        return mentions
    }

    /// Language codes named in a string, without track context. Bare tokens
    /// separated by punctuation are also resolved, which covers compact
    /// provider metadata such as `"ja, en"`.
    static func languages(in text: String) -> Set<String> {
        var codes = Set(mentions(in: text).map(\.code))
        for part in text.split(whereSeparator: { ",/|;•+".contains($0) }) {
            let candidate = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { continue }
            if let code = canonicalCode(forToken: candidate) {
                codes.insert(code)
            }
        }
        return codes
    }

    /// Resolves a single token, such as a track language or a profile value.
    static func canonicalCode(forToken token: String) -> String? {
        let key = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if let code = code(forVocabularyToken: key) {
            return code
        }
        if let prefix = key.split(separator: "-").first,
           prefix.count == 2,
           let code = shortCodes[String(prefix)] {
            return code
        }
        let codes = Set(mentions(in: token).map(\.code))
        return codes.count == 1 ? codes.first : nil
    }

    /// Audio and subtitle languages of a release, including the `Dual Audio`,
    /// `Dubbed`, `subbed`, and `RAW` conventions.
    static func sets(in text: String) -> (audio: Set<String>, subtitles: Set<String>) {
        let found = mentions(in: text)
        var audio = Set(found.filter { $0.context != .subtitle }.map(\.code))
        var subtitles = Set(found.filter { $0.context == .subtitle }.map(\.code))

        if audio.isEmpty {
            if contains(raw, in: text) {
                audio.insert("ja")
            }
            if contains(dualAudio, in: text) {
                audio.formUnion(["ja", "en"])
            }
            if contains(dubbed, in: text) {
                audio.insert(dubbedDefaultCode(in: text))
            }
        }

        if subtitles.isEmpty, contains(multiSubs, in: text) || contains(subbed, in: text) {
            subtitles.formUnion(found.filter { $0.context == .neutral }.map(\.code))
            if subtitles.isEmpty {
                subtitles.insert("en")
            }
        }

        return (audio, subtitles)
    }

    // MARK: - Display

    static func displayName(for code: String, locale: Locale = .current) -> String {
        guard let name = locale.localizedString(forLanguageCode: code) else {
            return code.uppercased()
        }
        return name.capitalized(with: locale)
    }

    static func shortCode(for code: String) -> String {
        code.uppercased()
    }

    // MARK: - Helpers

    private static func code(forVocabularyToken token: String) -> String? {
        if let code = vocabulary[token] {
            return code
        }
        let folded = token.folding(options: .diacriticInsensitive, locale: nil)
        return vocabulary[folded]
    }

    private static func matches(of pattern: String, in text: String) -> [Mention] {
        guard let regex = PatternCache.shared.regex(pattern) else { return [] }
        let fullRange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: fullRange).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let token = String(text[range]).lowercased()
            guard let code = code(forVocabularyToken: token) else { return nil }
            let context = subtitleOnlyTokens.contains(token)
                ? Mention.Context.subtitle
                : context(at: match.range, in: text)
            return Mention(code: code, context: context)
        }
    }

    private static func codeMatches(of pattern: String, in text: String) -> [Mention] {
        guard let regex = PatternCache.shared.regex(pattern) else { return [] }
        let fullRange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: fullRange).compactMap { match in
            let range = match.range(at: 1)
            guard
                let tokenRange = Range(range, in: text),
                let code = shortCodes[String(text[tokenRange]).lowercased()]
            else {
                return nil
            }
            return Mention(code: code, context: context(at: range, in: text))
        }
    }

    /// Looks for track markers on the mention's own line first, then within a
    /// window around it. This keeps multi-line addon descriptions (for example
    /// `Audio: Japanese` / `Subtitles: English`) from bleeding into each other.
    private static func context(at range: NSRange, in text: String) -> Mention.Context {
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: range)
        let line = nsText.substring(with: lineRange)
        let lineLocalRange = NSRange(location: range.location - lineRange.location, length: range.length)
        if let context = classify(in: line, at: lineLocalRange) {
            return context
        }

        let window = 48
        let start = max(0, range.location - window)
        let end = min(nsText.length, range.location + range.length + window)
        guard end > start else { return .neutral }
        let surrounding = nsText.substring(with: NSRange(location: start, length: end - start))
        let windowRange = NSRange(location: range.location - start, length: range.length)
        return classify(in: surrounding, at: windowRange) ?? .neutral
    }

    private static func classify(in text: String, at range: NSRange) -> Mention.Context? {
        let subtitleDistance = nearestMarker(subtitleMarker, in: text, to: range)
        let audioDistance = nearestMarker(audioMarker, in: text, to: range)

        switch (subtitleDistance, audioDistance) {
        case (nil, nil):
            return nil
        case (.some, nil):
            return .subtitle
        case (nil, .some):
            return .audio
        case let (.some(subtitle), .some(audio)):
            return subtitle <= audio ? .subtitle : .audio
        }
    }

    private static func nearestMarker(_ pattern: String, in text: String, to range: NSRange) -> Int? {
        guard let regex = PatternCache.shared.regex(pattern) else { return nil }
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let mentionStart = range.location
        let mentionEnd = range.location + range.length
        var nearest: Int?
        for match in regex.matches(in: text, options: [], range: fullRange) {
            let markerStart = match.range.location
            let markerEnd = match.range.location + match.range.length
            let distance: Int
            if markerEnd <= mentionStart {
                distance = mentionStart - markerEnd
            } else if markerStart >= mentionEnd {
                distance = markerStart - mentionEnd
            } else {
                distance = 0
            }
            if nearest == nil || distance < nearest! {
                nearest = distance
            }
        }
        return nearest
    }

    private static func dubbedDefaultCode(in text: String) -> String {
        if contains(spanishDub, in: text) {
            return "es"
        }
        if contains(portugueseDub, in: text) {
            return "pt"
        }
        return "en"
    }

    private static func contains(_ pattern: String, in text: String) -> Bool {
        guard let regex = PatternCache.shared.regex(pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
