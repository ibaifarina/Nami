import Foundation

/// Metadata attributes a calibration profile can learn to extract.
enum StreamAttribute: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case resolution
    case codec
    case dynamicRange
    case audioLanguage
    case subtitleLanguage
    case releaseGroup
    case fileSize
    case seeders
    case cached
    case source

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .resolution: String(localized: "Resolution")
        case .codec: String(localized: "Codec")
        case .dynamicRange: String(localized: "Dynamic range")
        case .audioLanguage: String(localized: "Audio language")
        case .subtitleLanguage: String(localized: "Subtitle language")
        case .releaseGroup: String(localized: "Release group")
        case .fileSize: String(localized: "File size")
        case .seeders: String(localized: "Seeders")
        case .cached: String(localized: "Cached")
        case .source: String(localized: "Source")
        }
    }

    /// Relative importance for Nami's source selection. Resolution, size, and
    /// cache status matter far more than optional metadata such as release
    /// groups, so calibration coverage is weighted accordingly.
    var coverageWeight: Double {
        switch self {
        case .resolution: 3
        case .fileSize: 2
        case .cached: 2
        case .codec: 1.5
        case .dynamicRange: 1
        case .audioLanguage: 1
        case .source: 1
        case .seeders: 1
        case .releaseGroup: 0.75
        case .subtitleLanguage: 0.75
        }
    }
}

/// How the deterministic parser interprets a rule. Rules are plain data;
/// profiles never contain executable expressions.
enum ParsingRuleKind: String, Codable, Hashable, Sendable {
    /// A literal fragment copied from the addon's output; the matched text (or
    /// the rule's canonical value) becomes the attribute value.
    case keyword
    /// A number surrounded by a known prefix and/or suffix, e.g. `👤 120`.
    case number
    /// A human-readable size such as `1.4 GB`, parsed with the generic parser.
    case fileSize
    /// The first bracket-enclosed or trailing token, e.g. `[PMR]`.
    case releaseGroup
    /// Presence of the fragment means `true`, e.g. a cached indicator.
    case flag
}

/// One extraction rule learned for a specific addon configuration.
struct AddonParsingRule: Codable, Hashable, Sendable {
    let attribute: StreamAttribute
    let field: StreamField
    let kind: ParsingRuleKind
    /// Literal pattern / prefix / bracket marker, exactly as it appears.
    let pattern: String
    /// Canonical value for keyword rules. `nil` falls back to the matched text.
    let value: String?
    /// Exact text before a numeric value, e.g. `👤` or `Seeders:`.
    let numberPrefix: String?
    /// Exact text after a numeric value, e.g. `seeders`.
    let numberSuffix: String?
    var confidence: Double
    /// Number of calibration samples the rule matched.
    var support: Int
    /// Share of visibly-present samples the rule matched, `0...1`.
    var coverage: Double

    init(
        attribute: StreamAttribute,
        field: StreamField,
        kind: ParsingRuleKind,
        pattern: String,
        value: String? = nil,
        numberPrefix: String? = nil,
        numberSuffix: String? = nil,
        confidence: Double = 0.5,
        support: Int = 0,
        coverage: Double = 0
    ) {
        self.attribute = attribute
        self.field = field
        self.kind = kind
        self.pattern = pattern
        self.value = value
        self.numberPrefix = numberPrefix
        self.numberSuffix = numberSuffix
        self.confidence = confidence
        self.support = support
        self.coverage = coverage
    }
}

/// Learned parsing rules for one content kind (episodes or movies) of one
/// configured addon.
struct ContentParsingProfile: Codable, Hashable, Sendable {
    var rules: [AddonParsingRule]
    var confidence: Double
    var coverage: Double
    var sampleCount: Int

    static let empty = ContentParsingProfile(
        rules: [],
        confidence: 0,
        coverage: 0,
        sampleCount: 0
    )

    var isEmpty: Bool { rules.isEmpty }

    var attributes: [StreamAttribute] {
        var seen: Set<StreamAttribute> = []
        return rules.compactMap { seen.insert($0.attribute).inserted ? $0.attribute : nil }
    }

    func rules(for attribute: StreamAttribute) -> [AddonParsingRule] {
        rules
            .filter { $0.attribute == attribute }
            .sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
                return lhs.support > rhs.support
            }
    }
}

/// Whether a saved profile belongs to episodes or movies.
enum StreamContentKind: String, Codable, CaseIterable, Hashable, Sendable {
    case episode
    case movie

    var displayName: String {
        switch self {
        case .episode: String(localized: "Episodes")
        case .movie: String(localized: "Movies")
        }
    }
}

enum AddonCalibrationStatus: String, Codable, Hashable, Sendable {
    case success
    case partial
    case failure
    case unavailable
    case skipped
}

/// Values the deterministic parser extracted using a saved profile. Everything
/// is optional: unknown metadata is acceptable and never blocks playback.
struct ProfileExtraction: Hashable, Sendable {
    var attributeCount: Int = 0
    var resolution: VideoResolution?
    var codec: VideoCodec?
    var dynamicRange: DynamicRange?
    var source: ReleaseSource?
    var releaseGroup: String?
    var sizeBytes: Int64?
    var seeders: Int?
    var isCached: Bool = false
    var audioLanguages: Set<String> = []
    var subtitleLanguages: Set<String> = []

    var isEmpty: Bool { attributeCount == 0 }
}

/// Applies a saved profile deterministically. No AI, no regex generation, no
/// network: rules are literal fragments interpreted with fixed logic.
struct ProfileStreamParser: Sendable {
    func parse(
        fields: [StreamField: String],
        profile: ContentParsingProfile
    ) -> ProfileExtraction {
        var extraction = ProfileExtraction()
        guard !profile.isEmpty else { return extraction }
        for attribute in StreamAttribute.allCases {
            for rule in profile.rules(for: attribute) {
                guard
                    let rawText = fields[rule.field],
                    case .matched = apply(rule, text: rawText, extraction: &extraction)
                else {
                    continue
                }
                extraction.attributeCount += 1
                break
            }
        }
        return extraction
    }

    private enum ApplyResult {
        case noMatch
        case rejected
        case matched
    }

    private func apply(
        _ rule: AddonParsingRule,
        text rawText: String,
        extraction: inout ProfileExtraction
    ) -> ApplyResult {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .noMatch }

        switch rule.kind {
        case .keyword:
            guard contains(rule.pattern, in: text) else { return .noMatch }
            let rawValue = (rule.value?.isEmpty == false) ? rule.value! : rule.pattern
            return assign(rawValue, for: rule.attribute, extraction: &extraction)

        case .number:
            guard let number = Self.number(in: text, prefix: rule.numberPrefix, suffix: rule.numberSuffix)
            else {
                return .noMatch
            }
            switch rule.attribute {
            case .seeders:
                extraction.seeders = min(max(number, 0), 10_000_000)
                return .matched
            case .fileSize:
                extraction.sizeBytes = Int64(number)
                return .matched
            default:
                return assign(String(number), for: rule.attribute, extraction: &extraction)
            }

        case .fileSize:
            guard let bytes = ReleaseParser.fileSize(from: text) else { return .noMatch }
            extraction.sizeBytes = bytes
            return .matched

        case .releaseGroup:
            guard let group = Self.releaseGroup(in: text, hint: rule.pattern) else { return .noMatch }
            extraction.releaseGroup = group
            return .matched

        case .flag:
            guard contains(rule.pattern, in: text) else { return .noMatch }
            if rule.attribute == .cached {
                extraction.isCached = true
                return .matched
            }
            return assign(rule.value ?? rule.pattern, for: rule.attribute, extraction: &extraction)
        }
    }

    private func assign(
        _ rawValue: String,
        for attribute: StreamAttribute,
        extraction: inout ProfileExtraction
    ) -> ApplyResult {
        switch attribute {
        case .resolution:
            guard let value = ProfileValueNormalizer.videoResolution(rawValue) else { return .rejected }
            extraction.resolution = value
        case .codec:
            guard let value = ProfileValueNormalizer.videoCodec(rawValue) else { return .rejected }
            extraction.codec = value
        case .dynamicRange:
            guard let value = ProfileValueNormalizer.dynamicRange(rawValue) else { return .rejected }
            extraction.dynamicRange = value
        case .source:
            guard let value = ProfileValueNormalizer.releaseSource(rawValue) else { return .rejected }
            extraction.source = value
        case .audioLanguage:
            guard let language = ProfileValueNormalizer.language(rawValue) else { return .rejected }
            extraction.audioLanguages.insert(language)
        case .subtitleLanguage:
            guard let language = ProfileValueNormalizer.language(rawValue) else { return .rejected }
            extraction.subtitleLanguages.insert(language)
        case .releaseGroup:
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return .rejected }
            extraction.releaseGroup = value
        case .fileSize:
            guard let bytes = ReleaseParser.fileSize(from: rawValue) else { return .rejected }
            extraction.sizeBytes = bytes
        case .seeders:
            guard let value = Int(rawValue.filter(\.isNumber)) else { return .rejected }
            extraction.seeders = min(max(value, 0), 10_000_000)
        case .cached:
            extraction.isCached = true
        }
        return .matched
    }

    private func contains(_ pattern: String, in text: String) -> Bool {
        guard !pattern.isEmpty else { return false }
        return text.range(
            of: pattern,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    // MARK: - Scalar helpers

    static func number(in text: String, prefix: String?, suffix: String?) -> Int? {
        var searchStart = text.startIndex
        if let prefix, !prefix.isEmpty {
            guard
                let range = text.range(
                    of: prefix,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchStart..<text.endIndex
                )
            else {
                return nil
            }
            searchStart = range.upperBound
        }

        var digits = ""
        var cursor = searchStart
        while cursor < text.endIndex {
            let character = text[cursor]
            if character.isNumber {
                digits.append(character)
            } else if !digits.isEmpty, character == "," || character == " " || character == "\u{202F}" {
                // `1,234` and `1 234` seeders are common in tracker listings.
                let next = text.index(after: cursor)
                guard next < text.endIndex, text[next].isNumber else { break }
            } else if !digits.isEmpty {
                break
            } else if character == " " || character == "\t" || character == ":" || character == "=" {
                // Skip separators between the prefix and the number.
            } else {
                return nil
            }
            cursor = text.index(after: cursor)
        }

        guard !digits.isEmpty else { return nil }
        if let suffix, !suffix.isEmpty, cursor > text.startIndex {
            if text.range(
                of: suffix,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: cursor..<text.endIndex
            ) == nil {
                return nil
            }
        }
        return Int(digits)
    }

    static func releaseGroup(in text: String, hint: String?) -> String? {
        if let group = ReleaseParser.releaseGroup(from: text), !group.isEmpty, !isNoise(group) {
            return group
        }
        for groups in ReleaseParser.allMatches("\\[([^\\]]{2,40})\\]", in: text) {
            if let group = groups[safe: 1] ?? nil, !isNoise(group) {
                return group
            }
        }
        if let hint, !hint.isEmpty, hint != "[", hint != "]" {
            let stripped = hint.trimmingCharacters(in: CharacterSet(charactersIn: "[](){} "))
            if !stripped.isEmpty, stripped.lowercased() != text.lowercased() {
                return stripped
            }
        }
        return nil
    }

    private static func isNoise(_ value: String) -> Bool {
        let lowered = value.lowercased()
        let noise: Set<String> = [
            "1080p", "720p", "2160p", "480p", "4k", "uhd", "fhd", "hd",
            "hevc", "avc", "x265", "x264", "h265", "h264", "av1",
            "web", "web-dl", "webdl", "webrip", "bluray", "mkv", "mp4",
            "dual audio", "multi audio", "multi subs", "hdr", "sdr",
        ]
        return noise.contains(lowered)
    }
}

/// Maps free-form text values onto Nami's canonical attribute vocabularies.
/// Used both when converting AI output into rules and when applying rules, so
/// malformed model output can never produce an invalid value.
enum ProfileValueNormalizer {
    static func videoResolution(_ raw: String) -> VideoResolution? {
        let key = cleaned(raw)
        switch key {
        case "2160p", "4k", "uhd", "2160": return .p2160
        case "1080p", "fhd", "1080": return .p1080
        case "720p", "720", "hd": return .p720
        case "480p", "576p", "360p", "sd": return .p480
        default: return nil
        }
    }

    static func videoCodec(_ raw: String) -> VideoCodec? {
        let key = cleaned(raw)
        switch key {
        case "av1": return .av1
        case "hevc", "h265", "x265", "h.265", "hvc": return .hevc
        case "avc", "h264", "x264", "h.264": return .avc
        default: return nil
        }
    }

    static func dynamicRange(_ raw: String) -> DynamicRange? {
        let key = cleaned(raw)
        switch key {
        case "dolbyvision", "dolby vision", "dovi", "dv": return .dolbyVision
        case "hdr10+", "hdr10plus": return .hdr10Plus
        case "hdr10": return .hdr10
        case "hdr": return .hdr
        default: return nil
        }
    }

    static func releaseSource(_ raw: String) -> ReleaseSource? {
        let key = cleaned(raw)
        switch key {
        case "bluray", "blu ray", "blu-ray", "bd", "bdrip", "brrip", "remux", "bdmv": return .bluRay
        case "webdl", "web dl", "web-dl", "web": return .webDL
        case "webrip", "web rip", "web-rip": return .webRip
        case "hdtv": return .hdtv
        case "dvd", "dvdrip": return .dvd
        case "cam": return .cam
        case "ts", "telesync", "hdts": return .ts
        default: return nil
        }
    }

    static func language(_ raw: String) -> String? {
        let key = cleaned(raw)
        guard !key.isEmpty else { return nil }
        if LanguageVocabulary.known.contains(key) { return key }
        for language in LanguageVocabulary.known where key.contains(language) {
            return language
        }
        return LanguageVocabulary.aliases[key]
    }

    private static func cleaned(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[](){}.,;:/|"))
            .lowercased()
    }
}

/// Shared language vocabulary used by the generic parser and calibrated
/// profiles. Includes common ISO 639 codes seen in release names.
enum LanguageVocabulary {
    static let known = [
        "japanese", "english", "spanish", "french", "german",
        "italian", "portuguese", "russian", "korean", "chinese",
    ]

    static let aliases: [String: String] = [
        "jpn": "japanese", "jap": "japanese", "jp": "japanese", "ja": "japanese",
        "eng": "english", "en": "english",
        "spa": "spanish", "esp": "spanish", "es": "spanish",
        "fre": "french", "fra": "french", "fr": "french",
        "ger": "german", "deu": "german", "de": "german",
        "ita": "italian", "it": "italian",
        "por": "portuguese", "pt": "portuguese",
        "rus": "russian", "ru": "russian",
        "kor": "korean", "ko": "korean",
        "chi": "chinese", "zho": "chinese", "zh": "chinese",
    ]

    /// Canonicalizes a free-form language token.
    static func canonical(_ raw: String) -> String? {
        ProfileValueNormalizer.language(raw)
    }
}
