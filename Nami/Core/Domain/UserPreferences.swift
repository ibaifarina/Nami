import Foundation

struct UserPreferences: Codable, Hashable, Sendable {
    var autoSelectBestStream = true
    var preferredQuality: QualityPreference = .auto
    var qualityBalance: QualityBalance = .balanced
    var preferCachedStreams = true
    var preferredAudio: AudioPreference = .japanese
    var preferredSubtitles: SubtitlePreference = .english
    var autoplayNextEpisode = true
    var preferredReleaseGroups: [String] = []
    var blockedReleaseGroups: [String] = []
    var minimumSeedersForUncached = 2
    var maximumFileSizeBytes: Int64 = 0
    var autoSelectConfidenceThreshold = 0.88
    var showStreamScoringDebugInfo = false
    var heroBackgroundBlur: HeroBackgroundBlur = .subtle
    var playbackEngine: PlaybackEngineKind = .mpv
    var externalPlayerBundleID: String?
    var cacheResolvedSources = true
    var hasCompletedOnboarding = false

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoSelectBestStream = try container.decodeIfPresent(Bool.self, forKey: .autoSelectBestStream) ?? true
        preferredQuality = try container.decodeIfPresent(QualityPreference.self, forKey: .preferredQuality) ?? .auto
        qualityBalance = try container.decodeIfPresent(QualityBalance.self, forKey: .qualityBalance) ?? .balanced
        preferCachedStreams = try container.decodeIfPresent(Bool.self, forKey: .preferCachedStreams) ?? true
        preferredAudio = try container.decodeIfPresent(AudioPreference.self, forKey: .preferredAudio) ?? .japanese
        preferredSubtitles = try container.decodeIfPresent(SubtitlePreference.self, forKey: .preferredSubtitles) ?? .english
        autoplayNextEpisode = try container.decodeIfPresent(Bool.self, forKey: .autoplayNextEpisode) ?? true
        preferredReleaseGroups = try container.decodeIfPresent([String].self, forKey: .preferredReleaseGroups) ?? []
        blockedReleaseGroups = try container.decodeIfPresent([String].self, forKey: .blockedReleaseGroups) ?? []
        minimumSeedersForUncached = try container.decodeIfPresent(Int.self, forKey: .minimumSeedersForUncached) ?? 2
        maximumFileSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .maximumFileSizeBytes) ?? 0
        autoSelectConfidenceThreshold = try container.decodeIfPresent(Double.self, forKey: .autoSelectConfidenceThreshold) ?? 0.88
        showStreamScoringDebugInfo = try container.decodeIfPresent(Bool.self, forKey: .showStreamScoringDebugInfo) ?? false
        heroBackgroundBlur = try container.decodeIfPresent(HeroBackgroundBlur.self, forKey: .heroBackgroundBlur) ?? .subtle
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
        case .auto: "Auto"
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
        case .dataSaver: "Data Saver"
        case .balanced: "Balanced"
        case .best: "Best Quality"
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
        self == .any ? "Any" : LanguageName.displayName(for: rawValue)
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
        self == .any ? "Any" : LanguageName.displayName(for: rawValue)
    }
}

enum LanguageName {
    static func displayName(for token: String) -> String {
        switch token {
        case "japanese": "Japanese"
        case "english": "English"
        case "spanish": "Spanish"
        case "french": "French"
        case "german": "German"
        case "italian": "Italian"
        case "portuguese": "Portuguese"
        case "russian": "Russian"
        case "korean": "Korean"
        case "chinese": "Chinese"
        default: token.capitalized
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
        case .off: "Off"
        case .subtle: "Subtle"
        case .medium: "Medium"
        case .strong: "Strong"
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

enum PlaybackEngineKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case mpv
    case avPlayer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mpv: "MPV (Recommended)"
        case .avPlayer: "AVPlayer"
        }
    }
}
