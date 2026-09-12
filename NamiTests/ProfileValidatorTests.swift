import Foundation
import Testing
@testable import Nami

struct ProfileValidatorTests {
    private let validator = ProfileValidator()
    private let converter = LearnedRuleConverter()

    private func sample(
        _ title: String,
        name: String? = nil,
        sizeBytes: Int64? = nil,
        seeders: Int? = nil
    ) -> CalibrationSample {
        var fields: [StreamField: String] = [.title: title]
        if let name { fields[.name] = name }
        return CalibrationSample(
            titleName: "Test Title",
            kind: .episode,
            fields: fields,
            sizeBytes: sizeBytes,
            seeders: seeders
        )
    }

    @Test func keepsRulesThatMatchVisibleFields() {
        let samples = [
            sample("Show E1 [1080p][HEVC]"),
            sample("Show E2 [1080p][AVC]"),
            sample("Show E3 [720p][HEVC]"),
            sample("Show E4 [1080p][HEVC]"),
        ]
        let candidate = ContentParsingProfile(
            rules: [
                AddonParsingRule(
                    attribute: .resolution,
                    field: .title,
                    kind: .keyword,
                    pattern: "1080p",
                    value: "1080p"
                ),
                AddonParsingRule(
                    attribute: .resolution,
                    field: .title,
                    kind: .keyword,
                    pattern: "720p",
                    value: "720p"
                ),
            ],
            confidence: 0.9,
            coverage: 0,
            sampleCount: 0
        )

        let result = validator.validate(candidate, samples: samples)

        #expect(!result.profile.isEmpty)
        #expect(result.profile.rules.count == 2)
        #expect(result.coverage == 1)
        #expect(result.profile.sampleCount == 4)
        let supports = Set(result.profile.rules.map(\.support))
        #expect(supports == [3, 1])
    }

    @Test func dropsRulesThatNeverMatch() {
        let samples = [
            sample("Show E1 [1080p]"),
            sample("Show E2 [720p]"),
        ]
        let candidate = ContentParsingProfile(
            rules: [
                AddonParsingRule(
                    attribute: .resolution,
                    field: .title,
                    kind: .keyword,
                    pattern: "4320p",
                    value: "4320p"
                ),
            ],
            confidence: 1,
            coverage: 0,
            sampleCount: 0
        )

        let result = validator.validate(candidate, samples: samples)

        #expect(result.profile.isEmpty)
        #expect(result.coverage == 0)
    }

    @Test func dropsOneOffAnecdotes() {
        let samples = (1...8).map { sample("Show E\($0) [1080p]") }
            + [sample("Show E9 [1080p] TOKYO-DRIFT-EDITION")]
        let candidate = ContentParsingProfile(
            rules: [
                AddonParsingRule(
                    attribute: .releaseGroup,
                    field: .title,
                    kind: .releaseGroup,
                    pattern: ""
                ),
            ],
            confidence: 1,
            coverage: 0,
            sampleCount: 0
        )

        let result = validator.validate(candidate, samples: samples)

        #expect(result.profile.isEmpty)
    }

    @Test func converterSplitsPatternsAndNormalizesValues() {
        let learned = [
            LearnedStreamFormat.Rule(
                attribute: "resolution",
                sourceField: "title",
                patterns: ["2160p", "4K"],
                value: "2160p",
                confidence: 0.8
            ),
            LearnedStreamFormat.Rule(
                attribute: "cached",
                sourceField: "name",
                patterns: ["RD+", "cached"],
                confidence: 0.9
            ),
            LearnedStreamFormat.Rule(
                attribute: "seeders",
                sourceField: "title",
                patterns: ["\u{1F464}"],
                numberPrefix: "\u{1F464}",
                confidence: 0.7
            ),
            LearnedStreamFormat.Rule(
                attribute: "notAThing",
                sourceField: "title",
                patterns: ["whatever"]
            ),
            LearnedStreamFormat.Rule(
                attribute: "codec",
                sourceField: "notAField",
                patterns: ["x265"]
            ),
        ]

        let profile = converter.convert(learned, kind: .episode)

        #expect(profile.rules.count == 5)
        let resolutionRules = profile.rules(for: .resolution)
        #expect(resolutionRules.count == 2)
        #expect(resolutionRules.allSatisfy { $0.value == "2160p" })
        let cachedRules = profile.rules(for: .cached)
        #expect(cachedRules.count == 2)
        #expect(cachedRules.allSatisfy { $0.kind == .flag })
        let seederRules = profile.rules(for: .seeders)
        #expect(seederRules.count == 1)
        #expect(seederRules.first?.kind == .number)
        #expect(seederRules.first?.numberPrefix == "\u{1F464}")
    }

    @Test func converterRejectsSymbolOnlyPatternsOutsideLanguages() {
        let profile = converter.convert(
            [
                LearnedStreamFormat.Rule(
                    attribute: "resolution",
                    sourceField: "title",
                    patterns: ["\u{1F39E}\u{FE0F}"],
                    value: "1080p"
                ),
                LearnedStreamFormat.Rule(
                    attribute: "audioLanguage",
                    sourceField: "title",
                    patterns: ["\u{1F1EF}\u{1F1F5}"],
                    value: "japanese"
                ),
                LearnedStreamFormat.Rule(
                    attribute: "seeders",
                    sourceField: "title",
                    patterns: ["\u{1F464}"],
                    numberPrefix: "\u{1F464}"
                ),
                LearnedStreamFormat.Rule(
                    attribute: "cached",
                    sourceField: "title",
                    patterns: ["\u{26A1}"]
                ),
            ],
            kind: .episode
        )

        #expect(profile.rules(for: .resolution).isEmpty)
        #expect(profile.rules(for: .audioLanguage).count == 1)
        #expect(profile.rules(for: .seeders).count == 1)
        #expect(profile.rules(for: .cached).count == 1)
    }

    @Test func converterDropsUnnormalizableEnumValues() {
        let profile = converter.convert(
            [
                LearnedStreamFormat.Rule(
                    attribute: "codec",
                    sourceField: "title",
                    patterns: ["whatever-code"],
                    value: "made-up-codec"
                ),
                LearnedStreamFormat.Rule(
                    attribute: "releaseGroup",
                    sourceField: "title",
                    patterns: ["[PMR]"],
                    value: "PMR"
                ),
            ],
            kind: .episode
        )

        #expect(profile.rules(for: .codec).isEmpty)
        #expect(profile.rules(for: .releaseGroup).count == 1)
    }

    @Test func weightedCoveragePrioritizesResolution() {
        let samples = [
            sample("Show E1 [1080p]", sizeBytes: 1_000_000_000),
            sample("Show E2 [720p]", sizeBytes: 2_000_000_000),
        ]
        let candidate = ContentParsingProfile(
            rules: [
                AddonParsingRule(
                    attribute: .resolution,
                    field: .title,
                    kind: .keyword,
                    pattern: "1080p",
                    value: "1080p"
                ),
                AddonParsingRule(
                    attribute: .releaseGroup,
                    field: .title,
                    kind: .releaseGroup,
                    pattern: ""
                ),
            ],
            confidence: 0.8,
            coverage: 0,
            sampleCount: 0
        )

        let result = validator.validate(candidate, samples: samples)

        // Only the resolution rule survives, so coverage reflects resolution
        // coverage rather than being diluted by the optional release-group rule.
        #expect(result.profile.rules(for: .resolution).count == 1)
        #expect(result.coverage == 0.5)
    }
}
