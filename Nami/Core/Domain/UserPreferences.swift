import Foundation

struct UserPreferences: Codable, Hashable, Sendable {
    static let defaultMaximumEpisodeFileSizeBytes: Int64 = 5_000_000_000
    static let defaultMaximumMovieFileSizeBytes: Int64 = 20_000_000_000
    static let defaultMinimumEpisodeFileSizeBytes: Int64 = 100_000_000
    static let defaultMinimumMovieFileSizeBytes: Int64 = 300_000_000

    var autoSelectBestStream = true
    var preferredQuality: QualityPreference = .auto
    var qualityBalance: QualityBalance = .balanced
    var preferCachedStreams = true
    var preferredAudio: AudioPreference = .japanese
    var preferredSubtitles: SubtitlePreference = .english
    var autoplayNextEpisode = true
    var skipIntroEnabled = true
    var preferredReleaseGroups: [String] = []
    var blockedReleaseGroups: [String] = []
    var minimumSeedersForUncached = 2
    var minimumEpisodeFileSizeBytes: Int64 = UserPreferences.defaultMinimumEpisodeFileSizeBytes
    var minimumMovieFileSizeBytes: Int64 = UserPreferences.defaultMinimumMovieFileSizeBytes
    var maximumEpisodeFileSizeBytes: Int64 = UserPreferences.defaultMaximumEpisodeFileSizeBytes
    var maximumMovieFileSizeBytes: Int64 = UserPreferences.defaultMaximumMovieFileSizeBytes
    var autoSelectConfidenceThreshold = 0.88
    var showStreamScoringDebugInfo = false
    var heroBackgroundBlur: HeroBackgroundBlur = .subtle
    var animeTitleLanguage: AnimeTitleLanguage = .standard
    var playbackEngine: PlaybackEngineKind = .mpv
    var externalPlayerBundleID: String?
    var cacheResolvedSources = true
    var hasCompletedOnboarding = false

    init() {}

    private enum LegacyCodingKeys: String, CodingKey {
        case maximumFileSizeBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyMaximumFileSizeBytes = try decoder
            .container(keyedBy: LegacyCodingKeys.self)
            .decodeIfPresent(Int64.self, forKey: .maximumFileSizeBytes)
            .flatMap { $0 > 0 ? $0 : nil }
        autoSelectBestStream = try container.decodeIfPresent(Bool.self, forKey: .autoSelectBestStream) ?? true
        preferredQuality = try container.decodeIfPresent(QualityPreference.self, forKey: .preferredQuality) ?? .auto
        qualityBalance = try container.decodeIfPresent(QualityBalance.self, forKey: .qualityBalance) ?? .balanced
        preferCachedStreams = try container.decodeIfPresent(Bool.self, forKey: .preferCachedStreams) ?? true
        preferredAudio = try container.decodeIfPresent(AudioPreference.self, forKey: .preferredAudio) ?? .japanese
        preferredSubtitles = try container.decodeIfPresent(SubtitlePreference.self, forKey: .preferredSubtitles) ?? .english
        autoplayNextEpisode = try container.decodeIfPresent(Bool.self, forKey: .autoplayNextEpisode) ?? true
        skipIntroEnabled = try container.decodeIfPresent(Bool.self, forKey: .skipIntroEnabled) ?? true
        preferredReleaseGroups = try container.decodeIfPresent([String].self, forKey: .preferredReleaseGroups) ?? []
        blockedReleaseGroups = try container.decodeIfPresent([String].self, forKey: .blockedReleaseGroups) ?? []
        minimumSeedersForUncached = try container.decodeIfPresent(Int.self, forKey: .minimumSeedersForUncached) ?? 2
        minimumEpisodeFileSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .minimumEpisodeFileSizeBytes)
            ?? Self.defaultMinimumEpisodeFileSizeBytes
        minimumMovieFileSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .minimumMovieFileSizeBytes)
            ?? Self.defaultMinimumMovieFileSizeBytes
        maximumEpisodeFileSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .maximumEpisodeFileSizeBytes)
            ?? legacyMaximumFileSizeBytes
            ?? Self.defaultMaximumEpisodeFileSizeBytes
        maximumMovieFileSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .maximumMovieFileSizeBytes)
            ?? legacyMaximumFileSizeBytes
            ?? Self.defaultMaximumMovieFileSizeBytes
        autoSelectConfidenceThreshold = try container.decodeIfPresent(Double.self, forKey: .autoSelectConfidenceThreshold) ?? 0.88
        showStreamScoringDebugInfo = try container.decodeIfPresent(Bool.self, forKey: .showStreamScoringDebugInfo) ?? false
        heroBackgroundBlur = try container.decodeIfPresent(HeroBackgroundBlur.self, forKey: .heroBackgroundBlur) ?? .subtle
        animeTitleLanguage = try container.decodeIfPresent(AnimeTitleLanguage.self, forKey: .animeTitleLanguage) ?? .standard
        playbackEngine = try container.decodeIfPresent(PlaybackEngineKind.self, forKey: .playbackEngine) ?? .mpv
        externalPlayerBundleID = try container.decodeIfPresent(String.self, forKey: .externalPlayerBundleID)
        cacheResolvedSources = try container.decodeIfPresent(Bool.self, forKey: .cacheResolvedSources) ?? true
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
    }
}

enum QualityPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case p2160
    case p1080
    case p720

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .p2160: "2160p"
        case .p1080: "1080p"
        case .p720: "720p"
        }
    }
}

enum QualityBalance: String, Codable, CaseIterable, Identifiable, Sendable {
    case dataSaver
    case balanced
    case best

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dataSaver: String(localized: "Data Saver")
        case .balanced: String(localized: "Balanced")
        case .best: String(localized: "Best Quality")
        }
    }
}

enum AudioPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case japanese
    case english
    case spanish
    case french
    case german
    case italian
    case portuguese
    case russian
    case korean
    case chinese
    case any

    var id: String { rawValue }

    var displayName: String {
        languageCode.map { LanguageDetector.displayName(for: $0) } ?? String(localized: "Any")
    }

    /// ISO 639-1 code used by the detector and scoring, or `nil` for "Any".
    var languageCode: String? {
        switch self {
        case .japanese: "ja"
        case .english: "en"
        case .spanish: "es"
        case .french: "fr"
        case .german: "de"
        case .italian: "it"
        case .portuguese: "pt"
        case .russian: "ru"
        case .korean: "ko"
        case .chinese: "zh"
        case .any: nil
        }
    }
}

enum SubtitlePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case english
    case japanese
    case spanish
    case french
    case german
    case italian
    case portuguese
    case russian
    case korean
    case chinese
    case any

    var id: String { rawValue }

    var displayName: String {
        languageCode.map { LanguageDetector.displayName(for: $0) } ?? String(localized: "Any")
    }

    /// ISO 639-1 code used by the detector and scoring, or `nil` for "Any".
    var languageCode: String? {
        switch self {
        case .english: "en"
        case .japanese: "ja"
        case .spanish: "es"
        case .french: "fr"
        case .german: "de"
        case .italian: "it"
        case .portuguese: "pt"
        case .russian: "ru"
        case .korean: "ko"
        case .chinese: "zh"
        case .any: nil
        }
    }
}

enum HeroBackgroundBlur: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case subtle
    case medium
    case strong

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: String(localized: "Off")
        case .subtle: String(localized: "Subtle")
        case .medium: String(localized: "Medium")
        case .strong: String(localized: "Strong")
        }
    }

    var radius: Double {
        switch self {
        case .off: 0
        case .subtle: 6
        case .medium: 12
        case .strong: 24
        }
    }
}

enum AnimeTitleLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard
    case english
    case japanese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: String(localized: "Default")
        case .english: String(localized: "English")
        case .japanese: String(localized: "Original (Japanese)")
        }
    }
}

enum PlaybackEngineKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case mpv
    case avPlayer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mpv: String(localized: "MPV (Recommended)")
        case .avPlayer: String(localized: "AVPlayer")
        }
    }
}
