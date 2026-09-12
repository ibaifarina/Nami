import Foundation

/// Platform-neutral result of one batched format analysis. The on-device model
/// produces this shape; tests can stub it without FoundationModels.
struct LearnedStreamFormat: Hashable, Sendable {
    struct Rule: Hashable, Sendable {
        var attribute: String
        var sourceField: String
        var patterns: [String]
        var value: String?
        var numberPrefix: String?
        var numberSuffix: String?
        var confidence: Double

        init(
            attribute: String,
            sourceField: String,
            patterns: [String],
            value: String? = nil,
            numberPrefix: String? = nil,
            numberSuffix: String? = nil,
            confidence: Double = 0.5
        ) {
            self.attribute = attribute
            self.sourceField = sourceField
            self.patterns = patterns
            self.value = value
            self.numberPrefix = numberPrefix
            self.numberSuffix = numberSuffix
            self.confidence = confidence
        }
    }

    var episodeRules: [Rule]
    var movieRules: [Rule]
    var confidence: Double

    static let empty = LearnedStreamFormat(episodeRules: [], movieRules: [], confidence: 0)
}

enum StreamFormatAnalyzerError: Error, Equatable, Sendable {
    case unavailable
    case noSamples
    /// The rendered samples did not fit the on-device model's context window.
    /// Callers can retry with a smaller batch.
    case inputTooLarge
    case generationFailed(String)

    var localizedDescription: String {
        switch self {
        case .unavailable:
            "On-device format analysis is not available on this Mac."
        case .noSamples:
            "The addon did not return streams to analyze."
        case .inputTooLarge:
            "The addon's sample text was too large for the on-device model."
        case .generationFailed(let detail):
            "The format analysis failed. \(detail)"
        }
    }
}

/// Analyzes representative samples and learns reusable extraction rules.
/// Implementations run only during calibration, never during playback.
protocol StreamFormatAnalyzing: Sendable {
    var isAvailable: Bool { get }
    func analyze(_ batch: CalibrationSampleBatch) async throws -> LearnedStreamFormat
}

/// Builds the single batched analysis prompt.
///
/// The on-device model has a small fixed context window, so the prompt is
/// deliberately compact: field values are flattened to one line and shortened,
/// and callers are expected to send a bounded number of samples. URLs, tokens,
/// and hashes have already been sanitized away.
enum StreamFormatPrompt {
    /// Longest field value included in the prompt. Values keep both their head
    /// and tail because addons often put the quality tag first and the release
    /// group (or size) last.
    static let maximumFieldLength = 200

    static func make(batch: CalibrationSampleBatch) -> String {
        var lines: [String] = []
        lines.append(
            """
            Calibrate a parser for ONE streaming addon.
            Each sample lists text fields of one stream result:
            - name: short label (quality/source)
            - title: multi-line detail block
            - description: optional extra text
            - filename: underlying file name

            Infer literal extraction rules describing how THIS addon formats metadata.
            Allowed attributes: resolution, codec, dynamicRange, audioLanguage, \
            subtitleLanguage, releaseGroup, fileSize, seeders, cached, source.
            Rules:
            - Emit one rule per attribute and use the field that really contains the value.
            - patterns: 1 or 2 fragments copied verbatim from that field that contain \
            the distinguishing word or number (e.g. 1080p, hevc, DDP2.0, WEB-DL). \
            Omit decorative emoji entirely; a lone emoji is only allowed when it is \
            the only marker for the value (e.g. a flag for an audio language).
            - For number-like attributes (seeders, fileSize) set numberPrefix and \
            numberSuffix to the exact text around the number.
            - value: the normalized form (1080p, hevc, japanese) when the pattern is \
            not already normalized; otherwise leave empty.
            - Only report attributes that clearly appear. Never guess.
            - episodeRules only from EPISODE SAMPLES and movieRules only from MOVIE \
            SAMPLES; leave a list empty when no samples of that kind are present.
            - Do not choose, rank, or recommend streams.
            """
        )

        lines.append(contentsOf: render(section: "EPISODE SAMPLES", samples: batch.episodes, prefix: "E"))
        lines.append(contentsOf: render(section: "MOVIE SAMPLES", samples: batch.movies, prefix: "M"))
        return lines.joined(separator: "\n")
    }

    private static func render(
        section: String,
        samples: [CalibrationSample],
        prefix: String
    ) -> [String] {
        guard !samples.isEmpty else { return [] }
        var lines = ["", section]
        for (index, sample) in samples.enumerated() {
            lines.append("Sample \(prefix)\(index + 1) — \(sample.titleName)")
            for field in StreamField.allCases {
                guard let value = sample.promptFields[field], !value.isEmpty else { continue }
                lines.append("  \(field.rawValue): \(compact(value))")
            }
            for (key, value) in sample.promptContext.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(key): \(value)")
            }
        }
        return lines
    }

    /// Flattens a field value onto one line and shortens it around the middle.
    static func compact(_ value: String) -> String {
        let flattened = value
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " \u{00B7} ")
        guard flattened.count > maximumFieldLength else { return flattened }
        let tailCount = 60
        let head = flattened.prefix(maximumFieldLength - tailCount)
        let tail = flattened.suffix(tailCount)
        return "\(head)\u{2026}\(tail)"
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable
struct GeneratedStreamFormat {
    @Guide(description: "Reusable rules learned from the episode samples. Empty when no episode samples were provided.")
    var episodeRules: [GeneratedAttributeRule]
    @Guide(description: "Reusable rules learned from the movie samples. Empty when no movie samples were provided.")
    var movieRules: [GeneratedAttributeRule]
    @Guide(description: "Overall confidence in these rules, from 0 to 1.")
    var confidence: Double
}

@available(macOS 26.0, *)
@Generable
struct GeneratedAttributeRule {
    @Guide(description: "One of: resolution, codec, dynamicRange, audioLanguage, subtitleLanguage, releaseGroup, fileSize, seeders, cached, source.")
    var attribute: String
    @Guide(description: "One of: title, name, description, filename.")
    var sourceField: String
    @Guide(description: "Up to 2 short verbatim fragments copied from the sample field that mark this attribute.")
    var patterns: [String]
    @Guide(description: "Canonical value for keyword rules, e.g. 1080p, hevc, japanese. Leave empty for numeric, size, release-group, or flag rules.")
    var value: String?
    @Guide(description: "For numeric attributes, the exact text immediately before the number, e.g. 👤 or Seeders:.")
    var numberPrefix: String?
    @Guide(description: "For numeric attributes, the exact text immediately after the number, e.g. seeders.")
    var numberSuffix: String?
    @Guide(description: "Confidence in this rule, from 0 to 1.")
    var confidence: Double
}

/// On-device analysis through Apple's FoundationModels framework. Runs exactly
/// once per calibration with a single batched request.
@available(macOS 26.0, *)
struct FoundationModelStreamFormatAnalyzer: StreamFormatAnalyzing {
    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    func analyze(_ batch: CalibrationSampleBatch) async throws -> LearnedStreamFormat {
        guard !batch.isEmpty else { throw StreamFormatAnalyzerError.noSamples }
        guard isAvailable else { throw StreamFormatAnalyzerError.unavailable }

        let session = LanguageModelSession(
            instructions: """
            You extract literal formatting rules from streaming addon listings. \
            You never guess, never rank streams, and never invent text that is \
            not present in the samples.
            """
        )
        do {
            let response = try await session.respond(
                to: StreamFormatPrompt.make(batch: batch),
                generating: GeneratedStreamFormat.self,
                options: GenerationOptions(
                    sampling: .greedy,
                    temperature: 0.1,
                    maximumResponseTokens: 2_000
                )
            )
            return response.content.asLearnedFormat
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            throw StreamFormatAnalyzerError.inputTooLarge
        } catch let error as LanguageModelSession.GenerationError {
            throw StreamFormatAnalyzerError.generationFailed(error.errorDescription ?? "Generation failed")
        } catch {
            throw StreamFormatAnalyzerError.generationFailed(error.localizedDescription)
        }
    }
}

@available(macOS 26.0, *)
extension GeneratedStreamFormat {
    var asLearnedFormat: LearnedStreamFormat {
        LearnedStreamFormat(
            episodeRules: episodeRules.map(\.asLearnedRule),
            movieRules: movieRules.map(\.asLearnedRule),
            confidence: confidence
        )
    }
}

@available(macOS 26.0, *)
extension GeneratedAttributeRule {
    var asLearnedRule: LearnedStreamFormat.Rule {
        LearnedStreamFormat.Rule(
            attribute: attribute,
            sourceField: sourceField,
            patterns: patterns,
            value: value,
            numberPrefix: numberPrefix,
            numberSuffix: numberSuffix,
            confidence: confidence
        )
    }
}
#endif
