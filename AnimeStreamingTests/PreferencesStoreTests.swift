import Foundation
import Testing
@testable import AnimeStreaming

@MainActor
struct PreferencesStoreTests {
    @Test func defaultsAreSensible() throws {
        let suite = "preferences-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PreferencesStore(defaults: defaults)
        #expect(store.autoSelectBestStream)
        #expect(store.preferredQuality == .auto)
        #expect(store.qualityBalance == .balanced)
        #expect(store.preferCachedStreams)
        #expect(store.preferredAudio == .japanese)
        #expect(store.preferredSubtitles == .english)
        #expect(store.autoplayNextEpisode)
    }

    @Test func changesPersistAcrossInstances() throws {
        let suite = "preferences-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PreferencesStore(defaults: defaults)
        store.autoSelectBestStream = false
        store.preferredQuality = .p1080
        store.preferredSubtitles = .spanish

        let reloaded = PreferencesStore(defaults: defaults)
        #expect(reloaded.autoSelectBestStream == false)
        #expect(reloaded.preferredQuality == .p1080)
        #expect(reloaded.preferredSubtitles == .spanish)
    }

    @Test func updatesPersistOnlyWhenValueChanges() throws {
        let suite = "preferences-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PreferencesStore(defaults: defaults)
        store.autoSelectBestStream = true
        let stored = defaults.data(forKey: "user-preferences-v1")
        #expect(stored == nil)

        store.autoSelectBestStream = false
        #expect(defaults.data(forKey: "user-preferences-v1") != nil)
    }

    @Test func decodesLegacyPreferencesMissingNewKeys() throws {
        let legacy = Data(#"{"autoSelectBestStream":false,"preferredQuality":"p1080"}"#.utf8)

        let decoded = try JSONDecoder().decode(UserPreferences.self, from: legacy)

        #expect(decoded.autoSelectBestStream == false)
        #expect(decoded.preferredQuality == .p1080)
        #expect(decoded.qualityBalance == .balanced)
        #expect(decoded.preferredAudio == .japanese)
    }

    @Test func releaseGroupsAreStored() throws {
        let suite = "preferences-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PreferencesStore(defaults: defaults)
        store.preferredReleaseGroups = ["SubsPlease", "Erai-raws"]

        #expect(store.preferredReleaseGroups == ["SubsPlease", "Erai-raws"])
        let reloaded = PreferencesStore(defaults: defaults)
        #expect(reloaded.preferredReleaseGroups == ["SubsPlease", "Erai-raws"])
    }

    @Test func onboardingFlagPersists() throws {
        let suite = "preferences-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PreferencesStore(defaults: defaults)
        #expect(!store.hasCompletedOnboarding)

        store.hasCompletedOnboarding = true

        let reloaded = PreferencesStore(defaults: defaults)
        #expect(reloaded.hasCompletedOnboarding)
    }

    @Test func legacyPreferencesDefaultOnboardingToFalse() throws {
        let legacy = Data(#"{"autoSelectBestStream":true}"#.utf8)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: legacy)
        #expect(!decoded.hasCompletedOnboarding)
    }

    @Test func heroBackgroundBlurDefaultsAndPersists() throws {
        let suite = "preferences-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PreferencesStore(defaults: defaults)
        #expect(store.heroBackgroundBlur == .medium)

        store.heroBackgroundBlur = .strong

        let reloaded = PreferencesStore(defaults: defaults)
        #expect(reloaded.heroBackgroundBlur == .strong)
    }
}
