import Foundation
import Testing
@testable import Nami

struct AddonParsingProfileTests {
    private let parser = ProfileStreamParser()

    private func profile(_ rules: [AddonParsingRule]) -> ContentParsingProfile {
        ContentParsingProfile(rules: rules, confidence: 0.9, coverage: 0.9, sampleCount: 4)
    }

    @Test func extractsKeywordRulesFromCustomFields() {
        let extraction = parser.parse(
            fields: [
                .title: "Awesome Show .E10. | 1080p | x265 | [SUBS]",
                .name: "RD+ cached | 4.2 GB | 120 seeders",
            ],
            profile: profile([
                AddonParsingRule(
                    attribute: .resolution,
                    field: .title,
                    kind: .keyword,
                    pattern: "1080p",
                    value: "1080p"
                ),
                AddonParsingRule(
                    attribute: .codec,
                    field: .title,
                    kind: .keyword,
                    pattern: "x265",
                    value: "hevc"
                ),
                AddonParsingRule(
                    attribute: .cached,
                    field: .name,
                    kind: .flag,
                    pattern: "RD+"
                ),
            ])
        )

        #expect(extraction.resolution == .p1080)
        #expect(extraction.codec == .hevc)
        #expect(extraction.isCached)
        #expect(extraction.attributeCount == 3)
    }

    @Test func parsesNumericSizeAndSeeders() {
        let extraction = parser.parse(
            fields: [.description: "Size 4.2 GB | \u{1F464} 1,234 | Seeders: n/a"],
            profile: profile([
                AddonParsingRule(
                    attribute: .fileSize,
                    field: .description,
                    kind: .fileSize,
                    pattern: "size"
                ),
                AddonParsingRule(
                    attribute: .seeders,
                    field: .description,
                    kind: .number,
                    pattern: "\u{1F464}",
                    numberPrefix: "\u{1F464}"
                ),
            ])
        )

        #expect(extraction.sizeBytes == 4_200_000_000)
        #expect(extraction.seeders == 1234)
    }

    @Test func parsesLanguagesAndDynamicRange() {
        let extraction = parser.parse(
            fields: [.title: "Show E10 | JPN | ENG subs | Dolby Vision | HDR10+"],
            profile: profile([
                AddonParsingRule(
                    attribute: .audioLanguage,
                    field: .title,
                    kind: .keyword,
                    pattern: "JPN",
                    value: "ja"
                ),
                AddonParsingRule(
                    attribute: .subtitleLanguage,
                    field: .title,
                    kind: .keyword,
                    pattern: "ENG subs",
                    value: "en"
                ),
                AddonParsingRule(
                    attribute: .dynamicRange,
                    field: .title,
                    kind: .keyword,
                    pattern: "Dolby Vision"
                ),
            ])
        )

        #expect(extraction.audioLanguages == ["ja"])
        #expect(extraction.subtitleLanguages == ["en"])
        #expect(extraction.dynamicRange == .dolbyVision)
    }

    @Test func extractBracketReleaseGroup() {
        let extraction = parser.parse(
            fields: [.title: "Show - 10 [1080p] [SubsPlease]"],
            profile: profile([
                AddonParsingRule(
                    attribute: .releaseGroup,
                    field: .title,
                    kind: .releaseGroup,
                    pattern: ""
                ),
            ])
        )

        #expect(extraction.releaseGroup == "SubsPlease")
    }

    @Test func unknownMetadataStaysUnknown() {
        let extraction = parser.parse(
            fields: [.title: "Show - 10"],
            profile: profile([
                AddonParsingRule(
                    attribute: .resolution,
                    field: .title,
                    kind: .keyword,
                    pattern: "1080p",
                    value: "1080p"
                ),
            ])
        )

        #expect(extraction.resolution == nil)
        #expect(extraction.isEmpty)
    }

    @Test func nonNormalizableValueIsRejected() {
        let extraction = parser.parse(
            fields: [.title: "Show 1080p"],
            profile: profile([
                AddonParsingRule(
                    attribute: .resolution,
                    field: .title,
                    kind: .keyword,
                    pattern: "1080p",
                    value: "not-a-resolution"
                ),
            ])
        )

        #expect(extraction.resolution == nil)
    }

    @Test func valueNormalizationVocabulary() {
        #expect(ProfileValueNormalizer.videoResolution("4K") == .p2160)
        #expect(ProfileValueNormalizer.videoCodec("x264") == .avc)
        #expect(ProfileValueNormalizer.dynamicRange("HDR10+") == .hdr10Plus)
        #expect(ProfileValueNormalizer.releaseSource("BDRip") == .bluRay)
        #expect(ProfileValueNormalizer.language("jpn") == "ja")
        #expect(ProfileValueNormalizer.language("English") == "en")
        #expect(ProfileValueNormalizer.videoResolution("nonsense") == nil)
    }

    @Test func keywordRuleFallsBackToMatchedText() {
        let extraction = parser.parse(
            fields: [.title: "Show 2160p AV1"],
            profile: profile([
                AddonParsingRule(
                    attribute: .resolution,
                    field: .title,
                    kind: .keyword,
                    pattern: "2160p"
                ),
                AddonParsingRule(
                    attribute: .codec,
                    field: .title,
                    kind: .keyword,
                    pattern: "AV1"
                ),
            ])
        )

        #expect(extraction.resolution == .p2160)
        #expect(extraction.codec == .av1)
    }
}
