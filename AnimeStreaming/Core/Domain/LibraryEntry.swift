import Foundation

/// App-native library states. These are local and independent of any
/// third-party account.
enum LibraryStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case watching
    case planToWatch
    case completed
    case onHold
    case dropped
    case favorites

    var id: String { rawValue }

    /// Statuses surfaced in the library and status menus. `onHold` and
    /// `dropped` stay decodable for libraries saved by earlier builds.
    static let libraryCases: [LibraryStatus] = [.watching, .planToWatch, .completed, .favorites]

    var displayName: String {
        switch self {
        case .watching: "Watching"
        case .planToWatch: "To watch"
        case .completed: "Completed"
        case .onHold: "On Hold"
        case .dropped: "Dropped"
        case .favorites: "Favorites"
        }
    }

    var systemImage: String {
        switch self {
        case .watching: "play.circle"
        case .planToWatch: "bookmark"
        case .completed: "checkmark.circle"
        case .onHold: "pause.circle"
        case .dropped: "xmark.circle"
        case .favorites: "heart"
        }
    }
}

struct LibraryEntry: Identifiable, Hashable, Codable, Sendable {
    var id: String { animeID }

    /// Kitsu anime (installment) ID.
    let animeID: String
    var status: LibraryStatus
    var progress: Int
    var updatedAt: Date
    /// Snapshot so the library renders without network access.
    var anime: Anime
}

protocol LibraryRepository: Sendable {
    func entries() async throws -> [LibraryEntry]
    func entry(animeID: String) async throws -> LibraryEntry?
    @discardableResult
    func update(
        anime: Anime,
        status: LibraryStatus,
        progress: Int?
    ) async throws -> LibraryEntry
    func remove(animeID: String) async throws
}

protocol LibraryPersistence: Sendable {
    func load() async -> [LibraryEntry]
    func save(_ entries: [LibraryEntry]) async
}

actor InMemoryLibraryPersistence: LibraryPersistence {
    private var entries: [LibraryEntry]

    init(entries: [LibraryEntry] = []) {
        self.entries = entries
    }

    func load() async -> [LibraryEntry] { entries }

    func save(_ entries: [LibraryEntry]) async {
        self.entries = entries
    }
}

actor UserDefaultsLibraryPersistence: LibraryPersistence {
    private static let storageKey = "local-library-v1"

    private let defaults: UserDefaults

    init(suiteName: String? = nil) {
        if let suiteName, let suite = UserDefaults(suiteName: suiteName) {
            defaults = suite
        } else {
            defaults = .standard
        }
    }

    func load() async -> [LibraryEntry] {
        guard
            let data = defaults.data(forKey: Self.storageKey),
            let decoded = try? JSONDecoder().decode([LibraryEntry].self, from: data)
        else {
            return []
        }
        return decoded
    }

    func save(_ entries: [LibraryEntry]) async {
        guard let data = try? JSONEncoder().encode(entries) else {
            AppLogger.persistence.error("Failed to encode local library")
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}

/// Local-first library. Cloud sync could be layered on this protocol later.
actor LocalLibraryRepository: LibraryRepository {
    private let persistence: any LibraryPersistence
    private var cache: [String: LibraryEntry]?

    init(persistence: any LibraryPersistence = UserDefaultsLibraryPersistence()) {
        self.persistence = persistence
    }

    func entries() async throws -> [LibraryEntry] {
        let values = try await loadedEntries()
        return values.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    func entry(animeID: String) async throws -> LibraryEntry? {
        try await loadedEntries()[animeID]
    }

    @discardableResult
    func update(
        anime: Anime,
        status: LibraryStatus,
        progress: Int?
    ) async throws -> LibraryEntry {
        var values = try await loadedEntries()
        let existing = values[anime.id]
        let entry = LibraryEntry(
            animeID: anime.id,
            status: status,
            progress: progress ?? existing?.progress ?? 0,
            updatedAt: Date(),
            anime: anime
        )
        values[anime.id] = entry
        await persist(values)
        return entry
    }

    func remove(animeID: String) async throws {
        var values = try await loadedEntries()
        values[animeID] = nil
        await persist(values)
    }

    private func loadedEntries() async throws -> [String: LibraryEntry] {
        if let cache { return cache }
        let loaded = await persistence.load()
        let values = Dictionary(loaded.map { ($0.animeID, $0) }, uniquingKeysWith: { first, _ in first })
        cache = values
        return values
    }

    private func persist(_ values: [String: LibraryEntry]) async {
        cache = values
        await persistence.save(Array(values.values))
    }
}
