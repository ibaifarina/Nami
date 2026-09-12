import Foundation

/// Converts the model's structured output into safe internal rules. Unknown
/// attributes, unknown fields, and values that cannot be normalized are
/// dropped instead of guessing.
struct LearnedRuleConverter: Sendable {
    func convert(
        _ rules: [LearnedStreamFormat.Rule],
        kind: StreamContentKind
    ) -> ContentParsingProfile {
        var converted: [AddonParsingRule] = []
        var seen: Set<AddonParsingRule> = []
        for rule in rules {
            guard let attribute = Self.attribute(from: rule.attribute) else { continue }
            guard let field = StreamField(rawValue: rule.sourceField.lowercased()) else { continue }
            let allowsSymbolOnly = attribute == .audioLanguage
                || attribute == .subtitleLanguage
                || attribute == .cached
                || !(rule.numberPrefix ?? "").isEmpty
                || !(rule.numberSuffix ?? "").isEmpty
            let patterns = Self.sanitizedPatterns(rule.patterns, allowsSymbolOnly: allowsSymbolOnly)
            guard !patterns.isEmpty || attribute == .fileSize else { continue }

            let kind = Self.ruleKind(
                attribute: attribute,
                numberPrefix: rule.numberPrefix,
                numberSuffix: rule.numberSuffix
            )
            let confidence = min(max(rule.confidence, 0), 1)

            if kind == .fileSize {
                converted.append(
                    AddonParsingRule(
                        attribute: attribute,
                        field: field,
                        kind: .fileSize,
                        pattern: patterns.first ?? attribute.rawValue,
                        value: nil,
                        confidence: confidence
                    )
                )
                continue
            }

            if patterns.isEmpty, kind == .number {
                converted.append(
                    AddonParsingRule(
                        attribute: attribute,
                        field: field,
                        kind: .number,
                        pattern: rule.numberPrefix ?? rule.numberSuffix ?? attribute.rawValue,
                        value: nil,
                        numberPrefix: rule.numberPrefix,
                        numberSuffix: rule.numberSuffix,
                        confidence: confidence
                    )
                )
                continue
            }

            for pattern in patterns {
                let canonical = Self.canonicalValue(
                    declared: rule.value,
                    pattern: pattern,
                    attribute: attribute
                )
                // Keyword rules must resolve to a known vocabulary value; other
                // rule kinds may legitimately have no canonical value.
                if kind == .keyword, canonical == nil { continue }
                let parsed = AddonParsingRule(
                    attribute: attribute,
                    field: field,
                    kind: kind,
                    pattern: pattern,
                    value: canonical,
                    numberPrefix: rule.numberPrefix,
                    numberSuffix: rule.numberSuffix,
                    confidence: confidence
                )
                guard seen.insert(parsed).inserted else { continue }
                converted.append(parsed)
            }
        }
        return ContentParsingProfile(
            rules: converted,
            confidence: 0,
            coverage: 0,
            sampleCount: 0
        )
    }

    static func attribute(from raw: String) -> StreamAttribute? {
        let key = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch key {
        case "resolution", "quality": return .resolution
        case "codec", "videocodec": return .codec
        case "dynamicrange", "hdr", "dolbyvision": return .dynamicRange
        case "audiolanguage", "audio", "language", "audiolanguages": return .audioLanguage
        case "subtitlelanguage", "subtitles", "subtitle": return .subtitleLanguage
        case "releasegroup", "group": return .releaseGroup
        case "filesize", "size": return .fileSize
        case "seeders", "seeds", "seed": return .seeders
        case "cached", "cache", "debrid", "debriscached": return .cached
        case "source", "release": return .source
        default: return nil
        }
    }

    static func ruleKind(
        attribute: StreamAttribute,
        numberPrefix: String?,
        numberSuffix: String?
    ) -> ParsingRuleKind {
        switch attribute {
        case .fileSize:
            return .fileSize
        case .releaseGroup:
            return .releaseGroup
        case .cached:
            return .flag
        case .seeders:
            return (numberPrefix?.isEmpty == false || numberSuffix?.isEmpty == false)
                ? .number : .keyword
        default:
            return .keyword
        }
    }

    /// Resolves the canonical value for a pattern. Enum-like attributes must
    /// normalize or the rule is discarded, so a hallucinated value can never
    /// reach the parser.
    static func canonicalValue(
        declared: String?,
        pattern: String,
        attribute: StreamAttribute
    ) -> String? {
        let raw = (declared?.isEmpty == false) ? declared! : pattern
        switch attribute {
        case .resolution:
            return ProfileValueNormalizer.videoResolution(raw)?.rawValue
        case .codec:
            return ProfileValueNormalizer.videoCodec(raw)?.rawValue
        case .dynamicRange:
            return ProfileValueNormalizer.dynamicRange(raw)?.rawValue
        case .source:
            return ProfileValueNormalizer.releaseSource(raw)?.rawValue
        case .audioLanguage, .subtitleLanguage:
            return ProfileValueNormalizer.language(raw)
        case .releaseGroup, .fileSize, .seeders, .cached:
            return declared?.isEmpty == false ? declared : nil
        }
    }

    static func sanitizedPatterns(
        _ patterns: [String],
        allowsSymbolOnly: Bool = false
    ) -> [String] {
        var result: [String] = []
        for raw in patterns.prefix(16) {
            let cleaned = raw
                .components(separatedBy: .newlines)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned.count <= 64 else { continue }
            guard !cleaned.allSatisfy(\.isNumber), !cleaned.allSatisfy(\.isWhitespace) else { continue }
            // A symbol-only fragment (typically a lone emoji) matches almost
            // every stream and would mislabel it. Language flags and numeric
            // markers are the legitimate exceptions.
            if !allowsSymbolOnly, !Self.containsWordOrNumber(cleaned) {
                continue
            }
            if !result.contains(cleaned) { result.append(cleaned) }
        }
        return result
    }

    private static func containsWordOrNumber(_ value: String) -> Bool {
        // `CharacterSet.alphanumerics` treats emoji variation selectors as
        // alphanumeric, so use the Unicode properties directly.
        value.unicodeScalars.contains { scalar in
            scalar.properties.isAlphabetic || CharacterSet.decimalDigits.contains(scalar)
        }
    }
}

struct CalibrationAttributeCoverage: Codable, Hashable, Sendable {
    let attribute: StreamAttribute
    let matched: Int
    let visible: Int
    let ratio: Double
}

struct ProfileValidationResult: Sendable {
    let profile: ContentParsingProfile
    let attributes: [CalibrationAttributeCoverage]
    let coverage: Double
}

/// Validates a learned profile against the samples it was derived from.
/// Rules that cannot extract fields that were visibly present are discarded,
/// and a weighted coverage score is produced. Missing optional fields are
/// tolerated.
struct ProfileValidator: Sendable {
    private let parser = ProfileStreamParser()

    func validate(
        _ candidate: ContentParsingProfile,
        samples: [CalibrationSample]
    ) -> ProfileValidationResult {
        guard !samples.isEmpty, !candidate.rules.isEmpty else {
            return ProfileValidationResult(
                profile: .empty,
                attributes: [],
                coverage: 0
            )
        }

        let minimumMatches = samples.count <= 4 ? 1 : 2
        var kept: [AddonParsingRule] = []
        for rule in candidate.rules {
            let matched = samples.filter { ruleMatches($0, rule: rule) }.count
            guard matched >= minimumMatches else { continue }
            let visible = samples.filter {
                SampleAttributeProbe.isVisible(rule.attribute, in: $0)
            }.count
            let denominator = visible > 0 ? visible : samples.count
            let ratio = Double(matched) / Double(max(denominator, 1))
            // Individual rules may cover only one pattern among several, so
            // pruning is lenient; attribute coverage below unions all rules.
            let threshold = visible > 0 ? 0.25 : 0.6
            guard ratio >= threshold else { continue }

            var validated = rule
            let declared = max(rule.confidence, 0.3)
            validated.confidence = min(declared, ratio)
            validated.support = matched
            validated.coverage = ratio
            kept.append(validated)
        }

        guard !kept.isEmpty else {
            return ProfileValidationResult(profile: .empty, attributes: [], coverage: 0)
        }

        // Attribute coverage counts a sample as covered when any kept rule for
        // that attribute matched it, which is what the parser does at runtime.
        var coverages: [CalibrationAttributeCoverage] = []
        for attribute in Set(kept.map(\.attribute)) {
            let rules = kept.filter { $0.attribute == attribute }
            let matched = samples.filter { sample in
                rules.contains { ruleMatches(sample, rule: $0) }
            }.count
            let visible = samples.filter {
                SampleAttributeProbe.isVisible(attribute, in: $0)
            }.count
            let denominator = visible > 0 ? visible : samples.count
            coverages.append(
                CalibrationAttributeCoverage(
                    attribute: attribute,
                    matched: matched,
                    visible: visible,
                    ratio: Double(matched) / Double(max(denominator, 1))
                )
            )
        }
        let totalWeight = coverages.reduce(0) { $0 + $1.attribute.coverageWeight }
        let coverage = totalWeight > 0
            ? coverages.reduce(0) { $0 + $1.attribute.coverageWeight * $1.ratio } / totalWeight
            : 0
        let confidence = kept.map(\.confidence).reduce(0, +) / Double(kept.count)

        let profile = ContentParsingProfile(
            rules: kept,
            confidence: confidence,
            coverage: coverage,
            sampleCount: samples.count
        )
        let attributes = coverages.sorted { $0.attribute.rawValue < $1.attribute.rawValue }
        return ProfileValidationResult(profile: profile, attributes: attributes, coverage: coverage)
    }

    private func ruleMatches(_ sample: CalibrationSample, rule: AddonParsingRule) -> Bool {
        let single = ContentParsingProfile(
            rules: [rule],
            confidence: 0,
            coverage: 0,
            sampleCount: 1
        )
        let extraction = parser.parse(fields: sample.fields, profile: single)
        switch rule.attribute {
        case .resolution: return extraction.resolution != nil
        case .codec: return extraction.codec != nil
        case .dynamicRange: return extraction.dynamicRange != nil
        case .source: return extraction.source != nil
        case .releaseGroup: return extraction.releaseGroup != nil
        case .fileSize: return extraction.sizeBytes != nil
        case .seeders: return extraction.seeders != nil
        case .cached: return extraction.isCached
        case .audioLanguage: return !extraction.audioLanguages.isEmpty
        case .subtitleLanguage: return !extraction.subtitleLanguages.isEmpty
        }
    }
}
