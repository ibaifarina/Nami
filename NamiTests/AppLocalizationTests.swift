import Foundation
import Testing
@testable import Nami

@MainActor
struct AppLocalizationTests {
    private func makeDefaults() throws -> (suite: String, defaults: UserDefaults) {
        let suite = "app-localization-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (suite, defaults)
    }

    /// Reads the suite's own domain, bypassing the argument domain that the
    /// test scheme uses to force its language.
    private func storedAppleLanguages(
        suite: String,
        defaults: UserDefaults
    ) -> [String]? {
        UserDefaults.standard.persistentDomain(forName: suite)?[
            AppLocalization.appleLanguagesKey
        ] as? [String]
    }

    @Test func defaultsToSystemWithoutTouchingAppleLanguages() throws {
        let (suite, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["fr"], forKey: AppLocalization.appleLanguagesKey)

        let localization = AppLocalization(defaults: defaults)

        #expect(localization.language == .system)
        #expect(storedAppleLanguages(suite: suite, defaults: defaults) == ["fr"])
    }

    @Test func selectingLanguagePersistsAndUpdatesAppleLanguages() throws {
        let (suite, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let localization = AppLocalization(defaults: defaults)
        localization.select(.spanish)

        #expect(localization.language == .spanish)
        #expect(localization.requiresRestart)
        #expect(defaults.string(forKey: AppLocalization.storageKey) == AppLanguage.spanish.rawValue)
        #expect(storedAppleLanguages(suite: suite, defaults: defaults) == ["es"])

        let reloaded = AppLocalization(defaults: defaults)
        #expect(reloaded.language == .spanish)
        #expect(storedAppleLanguages(suite: suite, defaults: defaults) == ["es"])
    }

    @Test func selectingSystemClearsOverride() throws {
        let (suite, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let localization = AppLocalization(defaults: defaults)
        localization.select(.english)
        #expect(storedAppleLanguages(suite: suite, defaults: defaults) == ["en"])

        localization.select(.system)
        #expect(localization.language == .system)
        #expect(storedAppleLanguages(suite: suite, defaults: defaults) == nil)
    }

    @Test func reselectingSameLanguageDoesNotRequireRestart() throws {
        let (suite, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let localization = AppLocalization(defaults: defaults)
        #expect(!localization.requiresRestart)

        localization.select(.spanish)
        let restarted = AppLocalization(defaults: defaults)
        restarted.select(.spanish)

        #expect(!restarted.requiresRestart)
    }

    @Test func languagesHaveUniqueCodesAndNames() {
        let codes = AppLanguage.allCases.compactMap(\.languageCode)
        #expect(Set(codes).count == codes.count)
        #expect(AppLanguage.allCases.allSatisfy { !$0.displayName.isEmpty })
    }
}
