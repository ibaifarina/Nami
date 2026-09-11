import Foundation

struct ParsedRelease: Hashable, Sendable {
    let rawTitle: String

    let resolution: VideoResolution?
    let codec: VideoCodec?
    let source: ReleaseSource?
    let releaseGroup: String?

    let season: Int?
    let episode: Int?
    let episodeVersion: Int?
    let episodeRange: ClosedRange<Int>?

    let isBatch: Bool
    let isSpecial: Bool
    let isExtra: Bool
    let isDualAudio: Bool
    let isDubbed: Bool
    let isSubbed: Bool

    let audioLanguages: Set<String>
    let subtitleLanguages: Set<String>
    let fileExtension: String?
    let sizeBytes: Int64?
    let seeders: Int?
}

enum ReleaseParser {
    static func parse(_ rawTitle: String) -> ParsedRelease {
        let range = episodeRange(from: rawTitle)
        let episodeInfo = episode(from: rawTitle)
        let isRangeBatch = range.map { $0.lowerBound != $0.upperBound } ?? false
        let resolvedEpisode = isRangeBatch ? nil : episodeInfo.episode
        let batchWord = contains(Self.batch, in: rawTitle)
        let isBatch = batchWord || range != nil
        let special = contains(Self.special, in: rawTitle)
        let extra = contains(Self.extra, in: rawTitle)
        let languages = Self.languages(in: rawTitle)
        let subtitleLanguages = contains(Self.multiSubs, in: rawTitle) ? languages : []

        return ParsedRelease(
            rawTitle: rawTitle,
            resolution: resolution(from: rawTitle),
            codec: codec(from: rawTitle),
            source: source(from: rawTitle),
            releaseGroup: releaseGroup(from: rawTitle),
            season: episodeInfo.season,
            episode: resolvedEpisode,
            episodeVersion: episodeInfo.version,
            episodeRange: range,
            isBatch: isBatch,
            isSpecial: special,
            isExtra: extra,
            isDualAudio: contains(Self.dualAudio, in: rawTitle),
            isDubbed: contains(Self.dubbed, in: rawTitle),
            isSubbed: contains(Self.subbed, in: rawTitle),
            audioLanguages: languages,
            subtitleLanguages: Set(subtitleLanguages),
            fileExtension: fileExtension(from: rawTitle),
            sizeBytes: fileSize(from: rawTitle),
            seeders: seeders(from: rawTitle)
        )
    }

    static func normalizedTitle(for rawTitle: String) -> String {
        var text = rawTitle
        text = replacing(Self.fileExtension, in: text, with: " ")
        text = replacing(Self.bracketedSegment, in: text, with: " ")
        text = replacing(Self.parentheticalSegment, in: text, with: " ")
        for pattern in Self.noisePatterns {
            text = replacing(pattern, in: text, with: " ")
        }
        text = text.lowercased()
        text = replacing("[^a-z0-9]+", in: text, with: " ")
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespaces)
    }

    static func titleTokens(for rawTitle: String) -> Set<String> {
        Set(
            normalizedTitle(for: rawTitle)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= 2 }
        )
    }

    // MARK: - Episode

    struct EpisodeInfo {
        let season: Int?
        let episode: Int?
        let version: Int?
    }

    static func episode(from rawTitle: String) -> EpisodeInfo {
        let season = seasonNumber(from: rawTitle)
        if let groups = firstMatch(Self.seasonEpisode, in: rawTitle),
           let episode = plausibleEpisode(int(groups, 2)) {
            return EpisodeInfo(season: int(groups, 1) ?? season, episode: episode, version: version(from: rawTitle))
        }
        if let groups = firstMatch(Self.episodeWord, in: rawTitle),
           let episode = plausibleEpisode(int(groups, 1)) {
            return EpisodeInfo(season: season, episode: episode, version: version(from: rawTitle))
        }
        if let groups = firstMatch(Self.dashEpisode, in: rawTitle),
           let episode = plausibleEpisode(int(groups, 1)) {
            let tag = groups[safe: 2] ?? nil
            return EpisodeInfo(season: season, episode: episode, version: versionInt(from: tag) ?? version(from: rawTitle))
        }
        if let groups = firstMatch(Self.bracketEpisode, in: rawTitle),
           let episode = plausibleEpisode(int(groups, 1)) {
            return EpisodeInfo(season: season, episode: episode, version: version(from: rawTitle))
        }
        return EpisodeInfo(season: season, episode: nil, version: version(from: rawTitle))
    }

    static func plausibleEpisode(_ value: Int?) -> Int? {
        guard let value else { return nil }
        if (1900...2100).contains(value) { return nil }
        return value
    }

    static func seasonNumber(from rawTitle: String) -> Int? {
        if let groups = firstMatch(Self.seasonEpisode, in: rawTitle), let season = int(groups, 1) {
            return season
        }
        if let groups = firstMatch(Self.nthSeason, in: rawTitle), let season = int(groups, 1) {
            return season
        }
        if let groups = firstMatch(Self.seasonWord, in: rawTitle), let season = int(groups, 1) {
            return season
        }
        return nil
    }

    static func episodeRange(from rawTitle: String) -> ClosedRange<Int>? {
        guard
            let groups = firstMatch(Self.range, in: rawTitle),
            let start = int(groups, 1),
            let end = int(groups, 2),
            start >= 1, end > start, end <= 300
        else {
            return nil
        }
        return start...end
    }

    static func version(from rawTitle: String) -> Int? {
        guard let groups = firstMatch(Self.versionTag, in: rawTitle) else { return nil }
        return int(groups, 1)
    }

    static func versionInt(from tag: String?) -> Int? {
        guard let tag, !tag.isEmpty else { return nil }
        return Int(tag.dropFirst())
    }

    // MARK: - Attributes

    static func resolution(from rawTitle: String) -> VideoResolution? {
        if contains(Self.resolution2160, in: rawTitle) { return .p2160 }
        if contains(Self.resolution1080, in: rawTitle) { return .p1080 }
        if contains(Self.resolution720, in: rawTitle) { return .p720 }
        if contains(Self.resolution480, in: rawTitle) { return .p480 }
        return nil
    }

    static func codec(from rawTitle: String) -> VideoCodec? {
        if contains(Self.codecAV1, in: rawTitle) { return .av1 }
        if contains(Self.codecHEVC, in: rawTitle) { return .hevc }
        if contains(Self.codecAVC, in: rawTitle) { return .avc }
        return nil
    }

    static func source(from rawTitle: String) -> ReleaseSource? {
        if contains(Self.sourceBluRay, in: rawTitle) { return .bluRay }
        if contains(Self.sourceWebDL, in: rawTitle) { return .webDL }
        if contains(Self.sourceWebRip, in: rawTitle) { return .webRip }
        if contains(Self.sourceHDTV, in: rawTitle) { return .hdtv }
        if contains(Self.sourceDVD, in: rawTitle) { return .dvd }
        if contains(Self.sourceCAM, in: rawTitle) { return .cam }
        if contains(Self.sourceTS, in: rawTitle) { return .ts }
        if contains(Self.sourceWeb, in: rawTitle) { return .webDL }
        return nil
    }

    static func releaseGroup(from rawTitle: String) -> String? {
        if let groups = firstMatch(Self.leadingBracket, in: rawTitle),
           let group = groups[safe: 1] ?? nil,
           !isNoiseTag(group) {
            return group
        }
        if let groups = firstMatch(Self.trailingGroup, in: rawTitle),
           let group = groups[safe: 1] ?? nil,
           !isNoiseTag(group) {
            return group
        }
        return nil
    }

    static func fileExtension(from rawTitle: String) -> String? {
        guard let groups = firstMatch(Self.fileExtension, in: rawTitle) else { return nil }
        return (groups[safe: 1] ?? nil)?.lowercased()
    }

    static func fileSize(from rawTitle: String) -> Int64? {
        guard
            let groups = firstMatch(Self.fileSize, in: rawTitle),
            let numberString = groups[safe: 1] ?? nil,
            let unit = (groups[safe: 2] ?? nil)?.lowercased(),
            let value = Double(numberString.replacingOccurrences(of: ",", with: "."))
        else {
            return nil
        }
        let multiplier: Double
        switch unit {
        case "tib": multiplier = 1_099_511_627_776
        case "tb": multiplier = 1_000_000_000_000
        case "gib": multiplier = 1_073_741_824
        case "gb": multiplier = 1_000_000_000
        case "mib": multiplier = 1_048_576
        case "mb": multiplier = 1_000_000
        case "kib": multiplier = 1_024
        case "kb": multiplier = 1_000
        default: return nil
        }
        return Int64((value * multiplier).rounded())
    }

    static func seeders(from rawTitle: String) -> Int? {
        if let groups = firstMatch(Self.seedersEmoji, in: rawTitle),
           let value = int(groups, 1) {
            return value
        }
        if let groups = firstMatch(Self.seedersLabeled, in: rawTitle),
           let value = int(groups, 1) {
            return value
        }
        if let groups = firstMatch(Self.seedersSuffixed, in: rawTitle),
           let value = int(groups, 1) {
            return value
        }
        return nil
    }

    static func languages(in rawTitle: String) -> Set<String> {
        let matches = allMatches(Self.language, in: rawTitle)
        return Set(matches.compactMap { $0[safe: 1] ?? nil }.map { $0.lowercased() })
    }

    private static func isNoiseTag(_ value: String) -> Bool {
        let lowered = value.lowercased()
        if lowered.first?.isNumber == true { return true }
        return noiseTags.contains(lowered)
    }

    private static let noiseTags: Set<String> = [
        "1080p", "720p", "2160p", "480p", "4k", "uhd", "fhd", "hd",
        "hevc", "avc", "x265", "x264", "h265", "h264", "av1",
        "web", "web-dl", "webdl", "webrip", "bluray", "bd", "bdrip", "brrip",
        "mkv", "mp4", "avi", "mov", "webm",
        "aac", "flac", "opus", "ac3", "dts", "eac3",
        "multi", "dual", "sub", "subs", "dub", "dubbed",
        "10bit", "8bit", "hdr", "sdr", "remux", "complete", "batch",
    ]

    // MARK: - Patterns

    private static let seasonEpisode = "\\bS(\\d{1,2})E(\\d{1,4})\\b"
    private static let episodeWord = "\\b(?:episode|ep|e)\\s*(\\d{1,4})\\b"
    private static let nthSeason = "\\b(\\d{1,2})(?:st|nd|rd|th)\\s*season\\b"
    private static let seasonWord = "\\bseason\\s*(\\d{1,2})\\b"
    private static let dashEpisode = "[-–—]\\s*(\\d{1,4})(v\\d)?\\b"
    private static let bracketEpisode = "\\[(\\d{1,4})(?:v\\d)?\\]"
    private static let versionTag = "\\bv(\\d{1,2})\\b"
    private static let batch = "\\b(?:batch|complete|\u{5168}\u{96C6})\\b"
    private static let range = "\\b(\\d{1,3})[-~](\\d{1,3})\\b"

    private static let resolution2160 = "\\b(?:2160p|4k|uhd)\\b"
    private static let resolution1080 = "\\b(?:1080p|fhd)\\b"
    private static let resolution720 = "\\b(?:720p)\\b"
    private static let resolution480 = "\\b(?:480p|576p|360p)\\b"

    private static let codecAV1 = "\\bav1\\b"
    private static let codecHEVC = "\\b(?:hevc|h\\.?265|x265|h265)\\b"
    private static let codecAVC = "\\b(?:avc|h\\.?264|x264|h264)\\b"

    private static let sourceBluRay = "\\b(?:blu-?ray|bdrip|bdremux|brrip|bdmv|remux)\\b"
    private static let sourceWebDL = "\\b(?:web-?dl|webdl)\\b"
    private static let sourceWebRip = "\\bweb-?rip\\b"
    private static let sourceHDTV = "\\bhdtv\\b"
    private static let sourceDVD = "\\bdvd(?:rip)?\\b"
    private static let sourceCAM = "\\bcam\\b"
    private static let sourceTS = "\\b(?:ts|telesync|hdts)\\b"
    private static let sourceWeb = "\\bweb\\b"

    private static let special = "\\b(?:special|specials|ova|oad|ona)\\b"
    private static let extra = "\\b(?:ncop|nced|trailer|preview|pv|sample|menu)\\b"
    private static let dualAudio = "\\b(?:dual|multi)[\\s\\-_]?audio\\b"
    private static let dubbed = "\\bdub(?:bed)?\\b"
    private static let subbed = "\\bsub(?:bed|s)?\\b"
    private static let multiSubs = "\\bmulti[\\s\\-_]?subs?\\b"
    private static let language = "\\b(english|japanese|spanish|french|german|italian|portuguese|russian|korean|chinese)\\b"
    private static let fileExtension = "\\.(mkv|mp4|avi|mov|webm)\\b"
    private static let fileSize = "\\b(\\d+(?:[.,]\\d+)?)\\s*(tib|tb|gib|gb|mib|mb|kib|kb)\\b"
    private static let seedersEmoji = "\u{1F464}\\s*(\\d+)"
    private static let seedersLabeled = "\\b(?:seeders?|seeds?)\\s*[:=]?\\s*(\\d+)\\b"
    private static let seedersSuffixed = "\\b(\\d+)\\s*(?:seeders?|seeds?)\\b"

    private static let leadingBracket = "^\\s*\\[([^\\]]{2,40})\\]"
    private static let trailingGroup = "[-–—]\\s*([A-Za-z][A-Za-z0-9_.-]{1,30})\\s*(?:\\[[^\\]]*\\])?\\s*$"
    private static let bracketedSegment = "\\[[^\\]]*\\]"
    private static let parentheticalSegment = "\\([^)]*\\)"

    private static let noisePatterns: [String] = [
        resolution2160, resolution1080, resolution720, resolution480,
        codecAV1, codecHEVC, codecAVC,
        sourceBluRay, sourceWebDL, sourceWebRip, sourceHDTV, sourceDVD, sourceCAM, sourceTS,
        special, extra, dualAudio, dubbed, subbed,
        seasonEpisode, episodeWord, nthSeason, seasonWord, dashEpisode,
        versionTag, batch, range, fileExtension, fileSize,
        seedersEmoji, seedersLabeled, seedersSuffixed,
    ]
}

// MARK: - Regex helpers

extension ReleaseParser {
    static func firstMatch(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = PatternCache.shared.regex(pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return groups(from: match, in: text)
    }

    static func allMatches(_ pattern: String, in text: String) -> [[String?]] {
        guard let regex = PatternCache.shared.regex(pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).map { groups(from: $0, in: text) }
    }

    static func contains(_ pattern: String, in text: String) -> Bool {
        guard let regex = PatternCache.shared.regex(pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    static func replacing(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = PatternCache.shared.regex(pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    static func int(_ groups: [String?], _ index: Int) -> Int? {
        guard let value = groups[safe: index] ?? nil else { return nil }
        return Int(value)
    }

    private static func groups(from match: NSTextCheckingResult, in text: String) -> [String?] {
        (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }
}

final class PatternCache: @unchecked Sendable {
    static let shared = PatternCache()

    private let lock = NSLock()
    private var cache: [String: NSRegularExpression] = [:]

    func regex(_ pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[pattern] {
            return cached
        }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        cache[pattern] = regex
        return regex
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
