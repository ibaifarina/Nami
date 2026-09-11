import Foundation

protocol PlaybackProgressStore: Sendable {
    func allProgress(limit: Int) async -> [PlaybackProgress]
    func progress(animeID: String, episodeNumber: Int) async -> PlaybackProgress?
    func progress(forAnimeID animeID: String) async -> [PlaybackProgress]
    func latestProgress(animeID: String) async -> PlaybackProgress?
    func save(_ progress: PlaybackProgress) async
    func remove(animeID: String, episodeNumber: Int) async
}

actor InMemoryPlaybackProgressStore: PlaybackProgressStore {
    private var items: [PlaybackProgress]

    init(items: [PlaybackProgress] = []) {
        self.items = items
    }

    func allProgress(limit: Int) async -> [PlaybackProgress] {
        Array(items.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }

    func progress(animeID: String, episodeNumber: Int) async -> PlaybackProgress? {
        items.first { $0.animeID == animeID && $0.episodeNumber == episodeNumber }
    }

    func progress(forAnimeID animeID: String) async -> [PlaybackProgress] {
        items
            .filter { $0.animeID == animeID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func latestProgress(animeID: String) async -> PlaybackProgress? {
        items
            .filter { $0.animeID == animeID }
            .max { $0.updatedAt < $1.updatedAt }
    }

    func save(_ progress: PlaybackProgress) async {
        if let index = items.firstIndex(where: { $0.id == progress.id }) {
            items[index] = progress
        } else {
            items.append(progress)
        }
    }

    func remove(animeID: String, episodeNumber: Int) async {
        let id = "\(animeID)-\(episodeNumber)"
        items.removeAll { $0.id == id }
    }
}
