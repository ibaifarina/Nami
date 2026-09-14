import AppKit
import Foundation
import Observation

/// Owns the app's display language.
///
/// The selection is persisted and written to the app's `AppleLanguages`
/// defaults domain, so `Bundle.main` resolves localized strings in the chosen
/// language when the app launches. Changing the language requires a restart,
/// which the settings screen offers to perform.
@MainActor
@Observable
final class AppLocalization {
    static let storageKey = "app-display-language"
    static let appleLanguagesKey = "AppleLanguages"

    private let defaults: UserDefaults
    private(set) var language: AppLanguage
    private(set) var requiresRestart = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = defaults
            .string(forKey: Self.storageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system

        if let code = language.languageCode {
            defaults.set([code], forKey: Self.appleLanguagesKey)
        }
    }

    func select(_ newLanguage: AppLanguage) {
        guard newLanguage != language else { return }
        let previous = language
        language = newLanguage
        defaults.set(newLanguage.rawValue, forKey: Self.storageKey)

        if let code = newLanguage.languageCode {
            defaults.set([code], forKey: Self.appleLanguagesKey)
        } else if previous.languageCode != nil {
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        }

        requiresRestart = true
    }

    /// Launches a fresh instance and quits the current one so the new language
    /// takes effect.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

#if DEBUG
extension AppLocalization {
    static func preview() -> AppLocalization {
        AppLocalization(
            defaults: UserDefaults(suiteName: "com.auax.Nami.preview") ?? .standard
        )
    }
}
#endif
