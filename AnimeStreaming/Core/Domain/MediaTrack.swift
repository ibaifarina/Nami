import Foundation

struct MediaTrack: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case audio
        case subtitle
    }

    let id: String
    let kind: Kind
    let title: String
    let language: String?
    let isDefault: Bool
    let isForced: Bool

    init(
        id: String,
        kind: Kind,
        title: String,
        language: String? = nil,
        isDefault: Bool = false,
        isForced: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.language = language
        self.isDefault = isDefault
        self.isForced = isForced
    }

    var displayName: String {
        if let language, !language.isEmpty, !title.localizedCaseInsensitiveContains(language) {
            return "\(title) (\(language))"
        }
        return title
    }
}
