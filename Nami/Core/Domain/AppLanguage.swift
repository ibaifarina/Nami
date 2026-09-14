import Foundation

/// Languages Nami can display.
///
/// To add a language:
/// 1. Add a case with its language code.
/// 2. Add the language to `Localizable.xcstrings` and translate its entries.
enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case spanish

    var id: String { rawValue }

    /// Language code written to `AppleLanguages`, or `nil` to follow the system.
    var languageCode: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .spanish: "es"
        }
    }

    /// Name shown in the picker, written in the language it represents.
    var displayName: String {
        switch self {
        case .system: String(localized: "System Default")
        case .english: "English"
        case .spanish: "Español"
        }
    }
}
