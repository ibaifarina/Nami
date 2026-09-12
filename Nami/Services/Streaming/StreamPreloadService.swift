import Foundation

/// One snapshot of a discovery run delivered to streaming subscribers.
struct StreamPreloadUpdate: Sendable {
    let result: StreamDiscoveryResult
    let isFinal: Bool
}

@MainActor
protocol StreamPreloading: AnyObject {
    /// Warms the cache for an episode the user is likely to play next.
    func prepare(anime: Anime, episode: Episode)
    /// Streams discovery snapshots, reusing an in-flight or cached run.
    func stream(anime: Anime, episode: Episode) -> AsyncStream<StreamPreloadUpdate>
    /// Returns the final discovery result, reusing an in-flight or cached run.
    func streams(anime: Anime, episode: Episode) async -> StreamDiscoveryResult
    /// Drops every cached and in-flight discovery.
    func clear()
}

extension StreamPreloading {
    func stream(anime: Anime, episode: Episode) -> AsyncStream<StreamPreloadUpdate> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                let result = await streams(anime: anime, episode: episode)
                continuation.yield(StreamPreloadUpdate(result: result, isFinal: true))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Runs one discovery per anime/episode/options combination and fans the
/// snapshots out to every subscriber, so a prefetch started while browsing and
/// a playback launch that arrives later share the same work.
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

    private final class Run {
        var subscribers: [UUID: AsyncStream<StreamPreloadUpdate>.Continuation] = [:]
        var latest: StreamPreloadUpdate?
        var isFinished = false
        var task: Task<Void, Never>?
    }

    private let discovery: StreamDiscoveryService
    private let episodes: any EpisodeRepository
    private let preferences: PreferencesStore
    private let registry: AddonRegistry
    private let prefetcher: (any StreamPlaybackProviding)?
    private let cacheTTL: TimeInterval

    private var entries: [Key: Entry] = [:]
    private var runs: [Key: Run] = [:]
    private var generation = 0

    init(
        discovery: StreamDiscoveryService,
        episodes: any EpisodeRepository,
        preferences: PreferencesStore,
        registry: AddonRegistry,
        prefetcher: (any StreamPlaybackProviding)? = nil,
        cacheTTL: TimeInterval = 300
    ) {
        self.discovery = discovery
        self.episodes = episodes
        self.preferences = preferences
        self.registry = registry
        self.prefetcher = prefetcher
        self.cacheTTL = cacheTTL
    }

    func prepare(anime: Anime, episode: Episode) {
        guard !registry.enabledAddons.isEmpty else { return }
        let options = currentOptions()
        let key = key(anime: anime, episode: episode, options: options)
        guard entry(for: key) == nil, runs[key] == nil else { return }
        _ = startRun(anime: anime, episode: episode, options: options, key: key)
    }

    func stream(anime: Anime, episode: Episode) -> AsyncStream<StreamPreloadUpdate> {
        let options = currentOptions()
        let key = key(anime: anime, episode: episode, options: options)
        if let entry = entry(for: key) {
            return Self.single(update: StreamPreloadUpdate(result: entry.result, isFinal: true))
        }
        guard !registry.enabledAddons.isEmpty else {
            return Self.single(update: StreamPreloadUpdate(result: .empty, isFinal: true))
        }
        let run = runs[key] ?? startRun(anime: anime, episode: episode, options: options, key: key)
        return AsyncStream { continuation in
            if let latest = run.latest, latest.isFinal || run.isFinished {
                continuation.yield(latest)
                continuation.finish()
                return
            }
            let id = UUID()
            run.subscribers[id] = continuation
            if let latest = run.latest {
                continuation.yield(latest)
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.runs[key]?.subscribers[id] = nil
                }
            }
        }
    }

    func streams(anime: Anime, episode: Episode) async -> StreamDiscoveryResult {
        var latest: StreamDiscoveryResult?
        for await update in stream(anime: anime, episode: episode) {
            latest = update.result
            if update.isFinal { break }
        }
        return latest ?? .empty
    }

    func clear() {
        generation += 1
        entries.removeAll()
        for run in runs.values {
            run.task?.cancel()
            for continuation in run.subscribers.values {
                continuation.finish()
            }
        }
        runs.removeAll()
        prefetcher?.clear()
    }

    private func startRun(
        anime: Anime,
        episode: Episode,
        options: StreamScoringOptions,
        key: Key
    ) -> Run {
        let run = Run()
        runs[key] = run
        let discovery = self.discovery
        let generation = self.generation
        run.task = Task { [weak self] in
            guard let self else { return }
            let enriched = await self.episodeWithAbsoluteNumber(episode, anime: anime)
            guard !Task.isCancelled, generation == self.generation else { return }
            let request = StreamDiscoveryService.Request(
                anime: anime,
                episode: enriched,
                addons: self.registry.enabledAddons,
                options: options
            )
            var latest: StreamDiscoveryResult?
            var emittedFinal = false
            for await event in await discovery.discoverStream(request) {
                guard !Task.isCancelled, generation == self.generation else { return }
                latest = event.result
                self.broadcast(
                    StreamPreloadUpdate(result: event.result, isFinal: event.isFinal),
                    for: key
                )
                if event.isFinal {
                    emittedFinal = true
                    break
                }
            }
            guard !Task.isCancelled, generation == self.generation, let latest else { return }
            self.finishRun(
                key,
                result: latest,
                emittedFinal: emittedFinal,
                anime: anime,
                episode: episode
            )
        }
        return run
    }

    private func broadcast(_ update: StreamPreloadUpdate, for key: Key) {
        guard let run = runs[key] else { return }
        run.latest = update
        for continuation in run.subscribers.values {
            continuation.yield(update)
        }
    }

    private func finishRun(
        _ key: Key,
        result: StreamDiscoveryResult,
        emittedFinal: Bool,
        anime: Anime,
        episode: Episode
    ) {
        guard let run = runs[key] else { return }
        let finalUpdate = StreamPreloadUpdate(result: result, isFinal: true)
        run.isFinished = true
        run.latest = finalUpdate
        if !emittedFinal {
            for continuation in run.subscribers.values {
                continuation.yield(finalUpdate)
            }
        }
        for continuation in run.subscribers.values {
            continuation.finish()
        }
        run.subscribers.removeAll()
        runs[key] = nil
        entries[key] = Entry(result: result, createdAt: Date())
        // Warm the top candidates while the user is still browsing the detail
        // page so Play can start instantly.
        prefetcher?.prefetch(
            anime: anime,
            episode: episode,
            candidates: result.ranked.filter(\.isAutoEligible).map(\.candidate)
        )
    }

    private func entry(for key: Key) -> Entry? {
        guard let entry = entries[key] else { return nil }
        guard Date().timeIntervalSince(entry.createdAt) <= cacheTTL else {
            entries[key] = nil
            return nil
        }
        return entry
    }

    private func key(
        anime: Anime,
        episode: Episode,
        options: StreamScoringOptions
    ) -> Key {
        Key(
            animeID: anime.id,
            episodeNumber: episode.displayNumber,
            options: options
        )
    }

    private func currentOptions() -> StreamScoringOptions {
        StreamScoringOptions(
            preferences: preferences.preferences,
            debridAvailable: true
        )
    }

    private static func single(update: StreamPreloadUpdate) -> AsyncStream<StreamPreloadUpdate> {
        AsyncStream { continuation in
            continuation.yield(update)
            continuation.finish()
        }
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
