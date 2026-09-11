import Foundation

/// Disk-backed cache of resolved playback URLs, keyed by episode.
///
/// Resolving a source is expensive and the resulting URL is only valid for a
/// limited time. Keeping the most recent resolution for an episode lets
/// playback restart instantly when a viewer returns to it without re-querying
/// addons or the debrid service. Entries are never served past
/// `maximumAge`.
actor ResolvedStreamCache {
    struct Entry: Codable, Sendable {
        let stream: ResolvedStream
        let candidateID: String
        let savedAt: Date
    }

    /// Resolved URLs are temporary, so entries are never kept longer than
    /// half a day even when the viewer returns to the episode later.
    static let defaultMaximumAge: TimeInterval = 12 * 60 * 60

    private let fileURL: URL?
    private let maximumAge: TimeInterval
    private let maximumEntries: Int
    private var entries: [String: Entry]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// - Parameters:
    ///   - fileURL: location of the persisted cache. Pass `nil` for an
    ///     in-memory cache (tests/previews).
    ///   - maximumAge: the longest an entry may be served.
    ///   - maximumEntries: upper bound on cached episodes, oldest evicted first.
    init(
        fileURL: URL? = ResolvedStreamCache.defaultFileURL(),
        maximumAge: TimeInterval = ResolvedStreamCache.defaultMaximumAge,
        maximumEntries: Int = 200
    ) {
        self.fileURL = fileURL
        self.maximumAge = maximumAge
        self.maximumEntries = maximumEntries
        entries = Self.loadEntries(from: fileURL, maximumAge: maximumAge, maximumEntries: maximumEntries)
    }

    /// The resolved stream for an episode, when it was saved recently enough.
    /// When `candidateID` is provided the entry only matches when it was
    /// produced by that exact candidate.
    func stream(animeID: String, episodeNumber: Int, candidateID: String? = nil) -> ResolvedStream? {
        let key = Self.key(animeID: animeID, episodeNumber: episodeNumber)
        guard let entry = entries[key], isFresh(entry) else {
            entries[key] = nil
            return nil
        }
        if let candidateID, entry.candidateID != candidateID {
            return nil
        }
        return entry.stream
    }

    func store(
        _ stream: ResolvedStream,
        candidateID: String,
        animeID: String,
        episodeNumber: Int,
        now: Date = Date()
    ) {
        let key = Self.key(animeID: animeID, episodeNumber: episodeNumber)
        entries[key] = Entry(stream: stream, candidateID: candidateID, savedAt: now)
        prune()
        persist()
    }

    func remove(animeID: String, episodeNumber: Int) {
        let key = Self.key(animeID: animeID, episodeNumber: episodeNumber)
        guard entries.removeValue(forKey: key) != nil else { return }
        persist()
    }

    func removeAll() {
        entries.removeAll()
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func defaultFileURL() -> URL? {
        guard
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else {
            return nil
        }
        return caches
            .appending(path: "Nami", directoryHint: .isDirectory)
            .appending(path: "resolved-streams.json", directoryHint: .notDirectory)
    }

    static var maximumAgeDescription: String {
        let hours = Int(defaultMaximumAge / 3600)
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    // MARK: - Helpers

    private static func key(animeID: String, episodeNumber: Int) -> String {
        "\(animeID)#\(episodeNumber)"
    }

    private func isFresh(_ entry: Entry) -> Bool {
        Date().timeIntervalSince(entry.savedAt) <= maximumAge
    }

    private func prune() {
        entries = entries.filter { isFresh($0.value) }
        guard entries.count > maximumEntries else { return }
        let sorted = entries.sorted { $0.value.savedAt > $1.value.savedAt }
        entries = Dictionary(uniqueKeysWithValues: sorted.prefix(maximumEntries).map { ($0.key, $0.value) })
    }

    // MARK: - Disk

    private static func loadEntries(
        from fileURL: URL?,
        maximumAge: TimeInterval,
        maximumEntries: Int
    ) -> [String: Entry] {
        guard
            let fileURL,
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else {
            return [:]
        }
        let now = Date()
        let fresh = decoded.filter { now.timeIntervalSince($0.value.savedAt) <= maximumAge }
        guard fresh.count > maximumEntries else { return fresh }
        let sorted = fresh.sorted { $0.value.savedAt > $1.value.savedAt }
        return Dictionary(uniqueKeysWithValues: sorted.prefix(maximumEntries).map { ($0.key, $0.value) })
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.persistence.error("Failed to persist resolved stream cache")
        }
    }
}
