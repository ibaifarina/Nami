import Foundation

/// One representative stream response kept for calibration.
///
/// `fields` holds the verbatim text fields for deterministic validation;
/// sanitized copies are the only thing ever shown to the on-device model.
struct CalibrationSample: Hashable, Sendable {
    let titleName: String
    let kind: StreamContentKind
    let fields: [StreamField: String]
    let sizeBytes: Int64?
    let seeders: Int?

    init(
        titleName: String,
        kind: StreamContentKind,
        fields: [StreamField: String],
        sizeBytes: Int64? = nil,
        seeders: Int? = nil
    ) {
        self.titleName = titleName
        self.kind = kind
        self.fields = fields
        self.sizeBytes = sizeBytes
        self.seeders = seeders
    }

    var hasText: Bool {
        fields.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Sanitized field values safe to include in an on-device model prompt.
    var promptFields: [StreamField: String] {
        fields.compactMapValues { value in
            let sanitized = StreamSampleSanitizer.sanitize(value)
            return sanitized.isEmpty ? nil : sanitized
        }
    }

    var promptContext: [String: String] {
        var context: [String: String] = [:]
        if let sizeBytes, sizeBytes > 0 {
            context["videoSize"] = ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        }
        if let seeders {
            context["seeders"] = String(seeders)
        }
        return context
    }

    var featureSignature: StreamFeatureSignature {
        StreamFeatureSignature.make(from: self)
    }
}

struct CalibrationSampleBatch: Sendable, Hashable {
    var episodes: [CalibrationSample]
    var movies: [CalibrationSample]

    var isEmpty: Bool { episodes.isEmpty && movies.isEmpty }
    var totalCount: Int { episodes.count + movies.count }
}

/// Compact feature fingerprint used to keep calibration samples diverse and
/// free of near-duplicates.
struct StreamFeatureSignature: Hashable, Sendable {
    var resolution: String?
    var codec: String?
    var dynamicRange: String?
    var source: String?
    var releaseGroup: String?
    var sizeBucket: Int?
    var languages: Set<String>
    var flags: Set<String>

    /// Feature tokens used for greedy diversity selection.
    var tokens: Set<String> {
        var result: Set<String> = []
        if let resolution { result.insert("res:\(resolution)") }
        if let codec { result.insert("codec:\(codec)") }
        if let dynamicRange { result.insert("dr:\(dynamicRange)") }
        if let source { result.insert("source:\(source)") }
        if let releaseGroup { result.insert("group:\(releaseGroup.lowercased())") }
        if let sizeBucket { result.insert("size:\(sizeBucket)") }
        for language in languages { result.insert("lang:\(language)") }
        for flag in flags { result.insert("flag:\(flag)") }
        return result
    }

    static func make(from sample: CalibrationSample) -> StreamFeatureSignature {
        let text = sample.fields.values.joined(separator: " ")
        let parsed = ReleaseParser.parse(text)
        var flags: Set<String> = []
        let lowered = text.lowercased()
        if lowered.contains("dual audio") || lowered.contains("multi audio")
            || lowered.contains("dual-audio") {
            flags.insert("dual-audio")
        }
        if lowered.contains("multi subs") || lowered.contains("multi-sub")
            || lowered.contains("multisub") {
            flags.insert("multi-subs")
        }
        if StreamCachedIndicators.containsIndicator(in: lowered) {
            flags.insert("cached-token")
        }
        if sample.seeders != nil || ReleaseParser.seeders(from: text) != nil {
            flags.insert("seeders")
        }
        let qualityTags = ["10bit", "8bit", "remux", "flac", "aac", "opus", "dts", "truehd", "atmos"]
        for tag in qualityTags where lowered.contains(tag) {
            flags.insert("tag:\(tag)")
        }
        if lowered.contains("sub") || lowered.contains("subtitle") {
            flags.insert("subs")
        }
        if let size = sample.sizeBytes ?? ReleaseParser.fileSize(from: text), size > 0 {
            flags.insert("size-present")
        }
        return StreamFeatureSignature(
            resolution: parsed.resolution?.rawValue
                ?? sample.fields.values.compactMap { ProfileValueNormalizer.videoResolution($0) }.first?.rawValue,
            codec: parsed.codec?.rawValue,
            dynamicRange: parsed.dynamicRange?.rawValue,
            source: parsed.source?.rawValue,
            releaseGroup: parsed.releaseGroup,
            sizeBucket: sizeBucket(sample.sizeBytes ?? parsed.sizeBytes),
            languages: parsed.audioLanguages,
            flags: flags
        )
    }

    private static func sizeBucket(_ bytes: Int64?) -> Int? {
        guard let bytes, bytes > 0 else { return nil }
        return Int(log2(Double(bytes)))
    }
}

enum StreamCachedIndicators {
    static let patterns = [
        "cached", "rd+", "[rd+]", "\u{26A1}", "instant", "ready", "available now",
    ]

    static func containsIndicator(in text: String) -> Bool {
        let lowered = text.lowercased()
        return patterns.contains { lowered.contains($0) }
    }
}

/// Picks a small, diverse subset (roughly 5 per title) instead of sending
/// dozens of near-identical results to the model.
struct CalibrationSampleSelector: Sendable {
    func select(from samples: [CalibrationSample], limit: Int) -> [CalibrationSample] {
        guard limit > 0 else { return [] }
        var unique: [CalibrationSample] = []
        var seen: Set<StreamFeatureSignature> = []
        for sample in samples where sample.hasText {
            let signature = sample.featureSignature
            guard seen.insert(signature).inserted else { continue }
            unique.append(sample)
        }
        guard unique.count > limit else { return unique }

        var selected: [CalibrationSample] = []
        var covered: Set<String> = []
        var remaining = unique
        while selected.count < limit, !remaining.isEmpty {
            var bestIndex: Int?
            var bestScore = 0
            for (index, sample) in remaining.enumerated() {
                let score = sample.featureSignature.tokens.subtracting(covered).count
                if score > bestScore {
                    bestScore = score
                    bestIndex = index
                }
            }
            guard let bestIndex, bestScore > 0 else { break }
            let sample = remaining.remove(at: bestIndex)
            selected.append(sample)
            covered.formUnion(sample.featureSignature.tokens)
        }
        return selected
    }
}

/// Strips anything that could contain credentials or opaque configuration from
/// sample text before it is included in an on-device model prompt. Calibration
/// only needs the release-formatting portion of the text.
enum StreamSampleSanitizer {
    private static let patterns: [(String, String)] = [
        ("(?i)\\b(?:https?|magnet|www\\.)\\S+", "[link]"),
        ("(?i)\\b(?:bearer|token|apikey|api_key|password|secret|auth|signature)\\s*[:=]\\s*\\S+", "[redacted]"),
        ("\\b[a-fA-F0-9]{32,64}\\b", "[hash]"),
        ("\\b[A-Za-z0-9_\\-+/]{40,}\\b", "[token]"),
        ("\\b[\\w.+-]+@[\\w-]+\\.[\\w.]+\\b", "[email]"),
    ]

    static func sanitize(_ value: String) -> String {
        var text = value
        for (pattern, replacement) in patterns {
            text = ReleaseParser.replacing(pattern, in: text, with: replacement)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Generic per-attribute detectors used to decide whether a calibration rule
/// found fields that were visibly present. They deliberately rely on broad
/// signals, never on the learned rules themselves.
enum SampleAttributeProbe {
    static func isVisible(_ attribute: StreamAttribute, in sample: CalibrationSample) -> Bool {
        let texts = sample.fields.values
        let combined = texts.joined(separator: " ").lowercased()
        switch attribute {
        case .resolution:
            return texts.contains { ReleaseParser.resolution(from: $0) != nil }
        case .codec:
            return texts.contains { ReleaseParser.codec(from: $0) != nil }
        case .dynamicRange:
            return texts.contains { ReleaseParser.dynamicRange(from: $0) != nil }
        case .source:
            return texts.contains { ReleaseParser.source(from: $0) != nil }
        case .releaseGroup:
            return texts.contains { ReleaseParser.releaseGroup(from: $0) != nil }
        case .fileSize:
            if sample.sizeBytes != nil { return true }
            return texts.contains { ReleaseParser.fileSize(from: $0) != nil }
        case .seeders:
            if sample.seeders != nil { return true }
            return texts.contains { ReleaseParser.seeders(from: $0) != nil }
        case .audioLanguage:
            if texts.contains(where: { !ReleaseParser.languages(in: $0).isEmpty }) { return true }
            return combined.contains("dual audio") || combined.contains("multi audio")
        case .subtitleLanguage:
            return combined.contains("sub") || combined.contains("subtitle")
        case .cached:
            return StreamCachedIndicators.containsIndicator(in: combined)
        }
    }
}
