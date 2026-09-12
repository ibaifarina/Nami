import Foundation
import Testing
@testable import Nami

struct CalibrationSampleTests {
    private func sample(
        _ title: String,
        name: String? = nil,
        sizeBytes: Int64? = nil,
        seeders: Int? = nil
    ) -> CalibrationSample {
        var fields: [StreamField: String] = [.title: title]
        if let name { fields[.name] = name }
        return CalibrationSample(
            titleName: "Test",
            kind: .episode,
            fields: fields,
            sizeBytes: sizeBytes,
            seeders: seeders
        )
    }

    @Test func selectorDeduplicatesEquivalentSamples() {
        let selector = CalibrationSampleSelector()
        let samples = [
            sample("Show E1 [1080p][HEVC]"),
            sample("Show E2 [1080p][HEVC]"),
            sample("Show E3 [1080p][HEVC]"),
        ]

        let selected = selector.select(from: samples, limit: 5)

        #expect(selected.count == 1)
    }

    @Test func selectorPrefersDiverseSamples() {
        let selector = CalibrationSampleSelector()
        let samples = [
            sample("Show E1 [2160p][HEVC]"),
            sample("Show E2 [1080p][x264]"),
            sample("Show E3 [720p]"),
            sample("Show E4 [1080p]", name: "RD+ cached"),
        ]

        let selected = selector.select(from: samples, limit: 3)

        #expect(selected.count == 3)
        let resolutions = selected.compactMap { $0.featureSignature.resolution }
        #expect(Set(resolutions).count == 3)
    }

    @Test func selectorAddsCachedSampleWhenAvailable() {
        let selector = CalibrationSampleSelector()
        let samples = [
            sample("Show E1 [2160p][HEVC]"),
            sample("Show E2 [1080p][x264]"),
            sample("Show E3 [720p]", name: "RD+ cached"),
        ]

        let selected = selector.select(from: samples, limit: 3)

        #expect(selected.contains { $0.featureSignature.flags.contains("cached-token") })
    }

    @Test func selectorSkipsEmptyTextSamples() {
        let selector = CalibrationSampleSelector()
        let empty = CalibrationSample(
            titleName: "Test",
            kind: .episode,
            fields: [.title: "   "]
        )

        let selected = selector.select(from: [empty, sample("Show [1080p]")], limit: 5)

        #expect(selected.count == 1)
    }

    @Test func sanitizerRemovesLinksAndOpaqueTokens() {
        let raw = "Frieren E10 1080p https://addon.example/play/abc?token=supersecret "
            + "magnet:?xt=urn:btih:ddeeff00112233445566778899aabbccddeeff00 "
            + "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

        let sanitized = StreamSampleSanitizer.sanitize(raw)

        #expect(!sanitized.contains("supersecret"))
        #expect(!sanitized.contains("https://"))
        #expect(!sanitized.contains("ddeeff00112233445566778899aabbccddeeff00"))
        #expect(sanitized.contains("Frieren E10 1080p"))
    }

    @Test func sanitizerRedactsCredentials() {
        let sanitized = StreamSampleSanitizer.sanitize(
            "title token=abc123def456 apikey: zzz999 signature=deadbeef"
        )

        #expect(!sanitized.contains("abc123def456"))
        #expect(!sanitized.contains("zzz999"))
        #expect(!sanitized.contains("deadbeef"))
    }

    @Test func promptFlattensAndShortensLongFields() {
        let long = (1...40).map { "line\($0)" }.joined(separator: "\n")

        let compact = StreamFormatPrompt.compact(long)

        #expect(!compact.contains("\n"))
        #expect(compact.count <= StreamFormatPrompt.maximumFieldLength + 1)
        #expect(compact.contains("line1"))
        #expect(compact.contains("line40"))
        #expect(compact.contains("\u{2026}"))
    }

    @Test func promptKeepsShortFieldsVerbatim() {
        let compact = StreamFormatPrompt.compact("Frieren E10 1080p")

        #expect(compact == "Frieren E10 1080p")
    }

    @Test func promptFieldsHideURLs() {
        let sample = sample(
            "Show E10 1080p https://private.example/stream?auth=secret-value"
        )

        let prompt = sample.promptFields[.title] ?? ""

        #expect(!prompt.contains("secret-value"))
        #expect(prompt.contains("[link]"))
    }
}
