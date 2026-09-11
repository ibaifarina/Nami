import Foundation
import Observation

@MainActor
@Observable
final class PreferencesStore {
    private static let storageKey = "user-preferences-v1"

    private let defaults: UserDefaults
    private(set) var preferences: UserPreferences

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if
            let data = defaults.data(forKey: Self.storageKey),
            let decoded = try? JSONDecoder().decode(UserPreferences.self, from: data)
        {
            preferences = decoded
        } else {
            preferences = UserPreferences()
        }
    }

    var autoSelectBestStream: Bool {
        get { preferences.autoSelectBestStream }
        set { update { $0.autoSelectBestStream = newValue } }
    }

    var preferredQuality: QualityPreference {
        get { preferences.preferredQuality }
        set { update { $0.preferredQuality = newValue } }
    }

    var qualityBalance: QualityBalance {
        get { preferences.qualityBalance }
        set { update { $0.qualityBalance = newValue } }
    }

    var preferCachedStreams: Bool {
        get { preferences.preferCachedStreams }
        set { update { $0.preferCachedStreams = newValue } }
    }

    var preferredAudio: AudioPreference {
        get { preferences.preferredAudio }
        set { update { $0.preferredAudio = newValue } }
    }

    var preferredSubtitles: SubtitlePreference {
        get { preferences.preferredSubtitles }
        set { update { $0.preferredSubtitles = newValue } }
    }

    var autoplayNextEpisode: Bool {
        get { preferences.autoplayNextEpisode }
        set { update { $0.autoplayNextEpisode = newValue } }
    }

    var preferredReleaseGroups: [String] {
        get { preferences.preferredReleaseGroups }
        set { update { $0.preferredReleaseGroups = newValue } }
    }

    var blockedReleaseGroups: [String] {
        get { preferences.blockedReleaseGroups }
        set { update { $0.blockedReleaseGroups = newValue } }
    }

    var minimumSeedersForUncached: Int {
        get { preferences.minimumSeedersForUncached }
        set { update { $0.minimumSeedersForUncached = max(0, newValue) } }
    }

    var maximumFileSizeBytes: Int64 {
        get { preferences.maximumFileSizeBytes }
        set { update { $0.maximumFileSizeBytes = max(0, newValue) } }
    }

    var autoSelectConfidenceThreshold: Double {
        get { preferences.autoSelectConfidenceThreshold }
        set { update { $0.autoSelectConfidenceThreshold = min(max(newValue, 0.5), 1.0) } }
    }

    var showStreamScoringDebugInfo: Bool {
        get { preferences.showStreamScoringDebugInfo }
        set { update { $0.showStreamScoringDebugInfo = newValue } }
    }

    var heroBackgroundBlur: HeroBackgroundBlur {
        get { preferences.heroBackgroundBlur }
        set { update { $0.heroBackgroundBlur = newValue } }
    }

    var playbackEngine: PlaybackEngineKind {
        get { preferences.playbackEngine }
        set { update { $0.playbackEngine = newValue } }
    }

    var externalPlayerBundleID: String? {
        get { preferences.externalPlayerBundleID }
        set { update { $0.externalPlayerBundleID = newValue } }
    }

    var cacheResolvedSources: Bool {
        get { preferences.cacheResolvedSources }
        set { update { $0.cacheResolvedSources = newValue } }
    }

    var hasCompletedOnboarding: Bool {
        get { preferences.hasCompletedOnboarding }
        set { update { $0.hasCompletedOnboarding = newValue } }
    }

    private func update(_ change: (inout UserPreferences) -> Void) {
        var copy = preferences
        change(&copy)
        guard copy != preferences else { return }
        preferences = copy
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else {
            AppLogger.persistence.error("Failed to encode preferences")
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}
