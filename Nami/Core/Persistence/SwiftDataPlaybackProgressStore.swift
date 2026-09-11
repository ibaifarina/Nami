import Foundation
import SwiftData

enum SwiftDataStack {
    static func makeContainer(inMemory: Bool = false) -> ModelContainer? {
        let schema = Schema([StoredAddon.self, StoredPlaybackProgress.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return container
        }
        guard !inMemory else { return nil }
        // A schema change from an early development build can leave a store
        // that cannot be migrated automatically. Start fresh instead of
        // failing to launch; playback progress is the only data at risk.
        AppLogger.persistence.error("SwiftData store could not be opened; recreating it")
        destroyDefaultStore()
        return try? ModelContainer(for: schema, configurations: [configuration])
    }

    private static func destroyDefaultStore() {
        let base = URL.applicationSupportDirectory.appending(path: "default.store")
        let fileManager = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            let url = base.deletingLastPathComponent()
                .appending(path: base.lastPathComponent + suffix)
            try? fileManager.removeItem(at: url)
        }
    }
}

@Model
final class StoredPlaybackProgress {
    @Attribute(.unique) var id: String
    var animeID: String
    var episodeID: String?
    var episodeNumber: Int
    var absoluteEpisodeNumber: Int?
    var positionSeconds: Double
    var durationSeconds: Double
    var isCompleted: Bool
    var updatedAt: Date
    var animeTitle: String?
    var posterURLString: String?
    var bannerURLString: String?
    var episodeCount: Int?

    init(
        id: String,
        animeID: String,
        episodeID: String?,
        episodeNumber: Int,
        absoluteEpisodeNumber: Int?,
        positionSeconds: Double,
        durationSeconds: Double,
        isCompleted: Bool,
        updatedAt: Date,
        animeTitle: String?,
        posterURLString: String?,
        bannerURLString: String?,
        episodeCount: Int?
    ) {
        self.id = id
        self.animeID = animeID
        self.episodeID = episodeID
        self.episodeNumber = episodeNumber
        self.absoluteEpisodeNumber = absoluteEpisodeNumber
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.isCompleted = isCompleted
        self.updatedAt = updatedAt
        self.animeTitle = animeTitle
        self.posterURLString = posterURLString
        self.bannerURLString = bannerURLString
        self.episodeCount = episodeCount
    }

    convenience init(_ progress: PlaybackProgress) {
        self.init(
            id: progress.id,
            animeID: progress.animeID,
            episodeID: progress.episodeID,
            episodeNumber: progress.episodeNumber,
            absoluteEpisodeNumber: progress.absoluteEpisodeNumber,
            positionSeconds: progress.positionSeconds,
            durationSeconds: progress.durationSeconds,
            isCompleted: progress.isCompleted,
            updatedAt: progress.updatedAt,
            animeTitle: progress.animeTitle,
            posterURLString: progress.posterURL?.absoluteString,
            bannerURLString: progress.bannerURL?.absoluteString,
            episodeCount: progress.episodeCount
        )
    }

    func update(from progress: PlaybackProgress) {
        episodeID = progress.episodeID
        episodeNumber = progress.episodeNumber
        absoluteEpisodeNumber = progress.absoluteEpisodeNumber
        positionSeconds = progress.positionSeconds
        durationSeconds = progress.durationSeconds
        isCompleted = progress.isCompleted
        updatedAt = progress.updatedAt
        animeTitle = progress.animeTitle
        posterURLString = progress.posterURL?.absoluteString
        bannerURLString = progress.bannerURL?.absoluteString
        episodeCount = progress.episodeCount
    }

    func toDomain() -> PlaybackProgress {
        PlaybackProgress(
            animeID: animeID,
            episodeID: episodeID,
            episodeNumber: episodeNumber,
            absoluteEpisodeNumber: absoluteEpisodeNumber,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            isCompleted: isCompleted,
            updatedAt: updatedAt,
            animeTitle: animeTitle,
            posterURL: posterURLString.flatMap(URL.init(string:)),
            bannerURL: bannerURLString.flatMap(URL.init(string:)),
            episodeCount: episodeCount
        )
    }
}

@ModelActor
actor SwiftDataPlaybackProgressStore: PlaybackProgressStore {
    func allProgress(limit: Int) async -> [PlaybackProgress] {
        var descriptor = FetchDescriptor<StoredPlaybackProgress>(
            sortBy: [SortDescriptor(\StoredPlaybackProgress.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(limit, 1)
        let stored = (try? modelContext.fetch(descriptor)) ?? []
        return stored.map { $0.toDomain() }
    }

    func progress(animeID: String, episodeNumber: Int) async -> PlaybackProgress? {
        let id = "\(animeID)-\(episodeNumber)"
        var descriptor = FetchDescriptor<StoredPlaybackProgress>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.toDomain()
    }

    func progress(forAnimeID animeID: String) async -> [PlaybackProgress] {
        let descriptor = FetchDescriptor<StoredPlaybackProgress>(
            predicate: #Predicate { $0.animeID == animeID },
            sortBy: [SortDescriptor(\StoredPlaybackProgress.updatedAt, order: .reverse)]
        )
        let stored = (try? modelContext.fetch(descriptor)) ?? []
        return stored.map { $0.toDomain() }
    }

    func latestProgress(animeID: String) async -> PlaybackProgress? {
        var descriptor = FetchDescriptor<StoredPlaybackProgress>(
            predicate: #Predicate { $0.animeID == animeID },
            sortBy: [SortDescriptor(\StoredPlaybackProgress.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.toDomain()
    }

    func save(_ progress: PlaybackProgress) async {
        let id = progress.id
        var descriptor = FetchDescriptor<StoredPlaybackProgress>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.update(from: progress)
        } else {
            modelContext.insert(StoredPlaybackProgress(progress))
        }
        do {
            try modelContext.save()
        } catch {
            AppLogger.persistence.error("Failed to save playback progress")
        }
    }

    func remove(animeID: String, episodeNumber: Int) async {
        let id = "\(animeID)-\(episodeNumber)"
        var descriptor = FetchDescriptor<StoredPlaybackProgress>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let existing = (try? modelContext.fetch(descriptor))?.first else { return }
        modelContext.delete(existing)
        do {
            try modelContext.save()
        } catch {
            AppLogger.persistence.error("Failed to remove playback progress")
        }
    }
}
