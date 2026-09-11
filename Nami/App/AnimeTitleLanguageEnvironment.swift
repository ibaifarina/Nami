import SwiftUI

private struct AnimeTitleLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue: AnimeTitleLanguage = .standard
}

extension EnvironmentValues {
    var animeTitleLanguage: AnimeTitleLanguage {
        get { self[AnimeTitleLanguageEnvironmentKey.self] }
        set { self[AnimeTitleLanguageEnvironmentKey.self] = newValue }
    }
}
