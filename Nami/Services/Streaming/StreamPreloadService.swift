import Foundation

@MainActor
protocol StreamPreloading: AnyObject {
    /// Warms the cache for an episode the user is likely to play next.
    func prepare(anime: Anime, episode: Episode)
    /// Returns stream discovery results, reusing an in-flight or cached run.
    func streams(anime: Anime, episode: Episode) async -> StreamDiscoveryResult
    /// Drops every cached and in-flight discovery.
    func clear()
}

/// Caches stream discovery results so playback can reuse the work started
/// while the user was browsing an anime's detail page.
@MainActor
final class StreamPreloadService: StreamPreloading {
    private struct Key: Hashable {
        let animeID: String
        let episodeNumber: Int
        let options: StreamScoringOptions
    }

    private struct Entry {
        let result: StreamDiscoveryResult
        let createdAt: Date
    }

    private let discovery: StreamDiscoveryService
    private let episodes: any EpisodeRepository
    private let preferences: PreferencesStore
    private let registry: AddonRegistry
    private let cacheTTL: TimeInterval

    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: Task<StreamDiscoveryResult, Never>] = [:]
    private var generation = 0

    init(
        discovery: StreamDiscoveryService,
        episodes: any EpisodeRepository,
        preferences: PreferencesStore,
        registry: AddonRegistry,
        cacheTTL: TimeInterval = 300
    ) {
        self.discovery = discovery
        self.episodes = episodes
        self.preferences = preferences
        self.registry = registry
        self.cacheTTL = cacheTTL
    }

    func prepare(anime: Anime, episode: Episode) {
        guard !registry.enabledAddons.isEmpty else { return }
        let options = currentOptions()
        let key = Key(
            animeID: anime.id,
            episodeNumber: episode.displayNumber,
            options: options
        )
        guard entry(for: key) == nil, inFlight[key] == nil else { return }
        inFlight[key] = makeTask(anime: anime, episode: episode, options: options, key: key)
    }

    func streams(anime: Anime, episode: Episode) async -> StreamDiscoveryResult {
        let episode = await episodeWithAbsoluteNumber(episode, anime: anime)
        let options = currentOptions()
        let key = Key(
            animeID: anime.id,
            episodeNumber: episode.displayNumber,
            options: options
        )
        if let entry = entry(for: key) {
            return entry.result
        }

        let task: Task<StreamDiscoveryResult, Never>
        if let existing = inFlight[key] {
            task = existing
        } else {
            let created = makeTask(anime: anime, episode: episode, options: options, key: key)
            inFlight[key] = created
            task = created
        }
        return await task.value
    }

    func clear() {
        generation += 1
        entries.removeAll()
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
    }

    private func currentOptions() -> StreamScoringOptions {
        StreamScoringOptions(
            preferences: preferences.preferences,
            debridAvailable: true
        )
    }

    private func makeTask(
        anime: Anime,
        episode: Episode,
        options: StreamScoringOptions,
        key: Key
    ) -> Task<StreamDiscoveryResult, Never> {
        let request = StreamDiscoveryService.Request(
            anime: anime,
            episode: episode,
            addons: registry.enabledAddons,
            options: options
        )
        let discovery = self.discovery
        let generation = self.generation
        return Task { [weak self] in
            let result = await discovery.discover(request)
            self?.store(result, for: key, generation: generation)
            return result
        }
    }

    private func store(_ result: StreamDiscoveryResult, for key: Key, generation: Int) {
        guard generation == self.generation else { return }
        inFlight[key] = nil
        entries[key] = Entry(result: result, createdAt: Date())
    }

    private func entry(for key: Key) -> Entry? {
        guard let entry = entries[key] else { return nil }
        guard Date().timeIntervalSince(entry.createdAt) <= cacheTTL else {
            entries[key] = nil
            return nil
        }
        return entry
    }

    private func episodeWithAbsoluteNumber(_ episode: Episode, anime: Anime) async -> Episode {
        guard episode.absoluteNumber == nil else { return episode }
        guard
            let metadata = try? await episodes.episodes(
                forAnimeID: anime.id,
                isAiring: anime.status?.isAiring ?? false
            )
        else {
            return episode
        }
        return metadata.first {
            $0.number == episode.number || $0.displayNumber == episode.number
        } ?? episode
    }
}
