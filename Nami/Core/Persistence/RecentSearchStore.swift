import Foundation

/// Small local cache of recent searches, newest first.
protocol RecentSearchStoring: Sendable {
    func searches() async -> [String]
    func record(_ query: String) async
    func clear() async
}

actor UserDefaultsRecentSearchStore: RecentSearchStoring {
    private static let storageKey = "recent-searches-v1"
    private static let limit = 10

    private let defaults: UserDefaults

    init(suiteName: String? = nil) {
        if let suiteName, let suite = UserDefaults(suiteName: suiteName) {
            defaults = suite
        } else {
            defaults = .standard
        }
    }

    func searches() async -> [String] {
        defaults.stringArray(forKey: Self.storageKey) ?? []
    }

    func record(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var values = defaults.stringArray(forKey: Self.storageKey) ?? []
        values.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        values.insert(trimmed, at: 0)
        if values.count > Self.limit {
            values = Array(values.prefix(Self.limit))
        }
        defaults.set(values, forKey: Self.storageKey)
    }

    func clear() async {
        defaults.removeObject(forKey: Self.storageKey)
    }
}

actor InMemoryRecentSearchStore: RecentSearchStoring {
    private var values: [String]

    init(values: [String] = []) {
        self.values = values
    }

    func searches() async -> [String] { values }

    func record(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        values.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        values.insert(trimmed, at: 0)
        if values.count > 10 {
            values = Array(values.prefix(10))
        }
    }

    func clear() async {
        values = []
    }
}
