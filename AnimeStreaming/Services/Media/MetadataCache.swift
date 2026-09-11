import CryptoKit
import Foundation

/// Persistent metadata cache. Entries survive app restarts so the app can
/// keep working from cached data when Kitsu is temporarily unavailable.
actor MetadataCache {
    enum Payload: Codable, Sendable {
        case animeList([Anime])
        case details(AnimeDetails)
        case episodes([Episode])
        case identity(MediaIdentity)
    }

    private struct Entry: Codable {
        let payload: Payload
        let expiresAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let directory: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// - Parameter directory: disk directory for persisted entries. Pass
    ///   `nil` for an in-memory cache (tests/previews).
    init(directory: URL? = MetadataCache.defaultDirectory()) {
        self.directory = directory
        entries = Self.loadEntries(from: directory)
    }

    func payload(for key: String) -> Payload? {
        guard let entry = entries[key], entry.expiresAt > Date() else { return nil }
        return entry.payload
    }

    /// Returns an entry regardless of expiry. Used as a fallback when a
    /// refresh fails so useful data is never thrown away.
    func stalePayload(for key: String) -> Payload? {
        entries[key]?.payload
    }

    func store(_ payload: Payload, for key: String, ttl: TimeInterval, now: Date = Date()) {
        let entry = Entry(payload: payload, expiresAt: now.addingTimeInterval(ttl))
        entries[key] = entry
        write(entry, for: key)
    }

    func removeAll() {
        entries.removeAll()
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    static func defaultDirectory() -> URL? {
        guard
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else {
            return nil
        }
        return caches
            .appending(path: "AnimeStreaming", directoryHint: .isDirectory)
            .appending(path: "MetadataCache", directoryHint: .isDirectory)
    }

    // MARK: - Disk

    private static func loadEntries(from directory: URL?) -> [String: Entry] {
        guard let directory else { return [:] }
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        else {
            return [:]
        }
        let decoder = JSONDecoder()
        var result: [String: Entry] = [:]
        for file in files {
            guard
                let data = try? Data(contentsOf: file),
                let entry = try? decoder.decode(Entry.self, from: data)
            else {
                continue
            }
            result[file.deletingPathExtension().lastPathComponent] = entry
        }
        return result
    }

    private func write(_ entry: Entry, for key: String) {
        guard let directory else { return }
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(entry)
            try data.write(to: fileURL(for: key, in: directory), options: .atomic)
        } catch {
            AppLogger.persistence.error("Failed to persist metadata cache entry")
        }
    }

    private func fileURL(for key: String, in directory: URL) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(name).json", directoryHint: .notDirectory)
    }
}

enum CacheTTL {
    /// Popular / top-rated / airing lists.
    static let list: TimeInterval = 30 * 60
    /// Search results in memory.
    static let search: TimeInterval = 5 * 60
    /// Anime details.
    static let details: TimeInterval = 24 * 60 * 60
    /// Episodes for completed shows.
    static let episodes: TimeInterval = 72 * 60 * 60
    /// Episodes for currently airing shows.
    static let airingEpisodes: TimeInterval = 6 * 60 * 60
    /// ID mappings used for addon interoperability.
    static let mappings: TimeInterval = 7 * 24 * 60 * 60
}
