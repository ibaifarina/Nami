import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    enum RowID: String, CaseIterable, Identifiable {
        case popular
        case topRated
        case airing
        case newReleases
        case upcoming

        var id: String { rawValue }

        var title: String {
            switch self {
            case .popular: "Popular Now"
            case .topRated: "Top Rated"
            case .airing: "Currently Airing"
            case .newReleases: "New Releases"
            case .upcoming: "Upcoming"
            }
        }
    }

    struct Row: Identifiable {
        let id: RowID
        var state: LoadingState<[Anime]>

        var isEmpty: Bool {
            if case .loaded(let items) = state { return items.isEmpty }
            return false
        }
    }

    struct ContinueWatchingEntry: Identifiable, Sendable {
        var id: String { progress.id }
        let anime: Anime
        let progress: PlaybackProgress
        let episode: Episode?
        let seasonNumber: Int?
    }

    private struct SeriesContext {
        let key: String
        let installment: AnimeInstallment?
    }

    private struct ResolvedEntry: Sendable {
        let entry: ContinueWatchingEntry
        let seriesKey: String
    }

    private let media: any MediaRepository
    private let episodes: any EpisodeRepository
    private let progressStore: any PlaybackProgressStore
    private let grouping: SeriesGroupingService

    var hero: Anime?
    var heroState: LoadingState<Anime> = .idle
    var continueWatching: [ContinueWatchingEntry] = []
    var rows: [Row] = RowID.allCases.map { Row(id: $0, state: .idle) }

    /// Bumped by every load and by removals so a slow in-flight pass can never
    /// overwrite fresher state with stale cards.
    private var continueWatchingGeneration = 0

    init(environment: AppEnvironment) {
        media = environment.media
        episodes = environment.episodes
        progressStore = environment.progress
        grouping = SeriesGroupingService(repository: environment.media)
    }

    init(
        media: any MediaRepository,
        progressStore: any PlaybackProgressStore,
        episodes: any EpisodeRepository,
        grouping: SeriesGroupingService? = nil
    ) {
        self.media = media
        self.episodes = episodes
        self.progressStore = progressStore
        self.grouping = grouping ?? SeriesGroupingService(repository: media)
    }

    /// Every section loads concurrently and independently: one failing section
    /// never blocks the others.
    func load() async {
        async let continueTask: Void = loadContinueWatching()
        async let popularTask: Void = loadRow(.popular)
        async let topRatedTask: Void = loadRow(.topRated)
        async let airingTask: Void = loadRow(.airing)
        async let newReleasesTask: Void = loadRow(.newReleases)
        async let upcomingTask: Void = loadRow(.upcoming)
        _ = await (
            continueTask,
            popularTask,
            topRatedTask,
            airingTask,
            newReleasesTask,
            upcomingTask
        )
    }

    func retryRow(_ id: RowID) async {
        await loadRow(id)
    }

    /// Re-reads only the Continue Watching shelf. Called when playback persists
    /// progress so the row reflects the just-watched episode immediately.
    func refreshContinueWatching() async {
        await loadContinueWatching()
    }

    func removeFromContinueWatching(_ entry: ContinueWatchingEntry) async {
        // Invalidate any in-flight load so the removed card cannot reappear.
        continueWatchingGeneration += 1
        continueWatching.removeAll { $0.id == entry.id }
        // A card represents the whole series, so removal must clear every
        // unfinished season. Otherwise an older season reappears on refresh.
        let targetKey = await seriesKey(forAnimeID: entry.progress.animeID)
        let items = await progressStore.allProgress(limit: 64)
        var seriesKeyByAnimeID: [String: String] = [:]
        for item in items where !item.isCompleted {
            let key: String
            if let cached = seriesKeyByAnimeID[item.animeID] {
                key = cached
            } else {
                key = await seriesKey(forAnimeID: item.animeID)
                seriesKeyByAnimeID[item.animeID] = key
            }
            guard key == targetKey else { continue }
            await progressStore.remove(
                animeID: item.animeID,
                episodeNumber: item.episodeNumber
            )
        }
    }

    private func loadRow(_ id: RowID) async {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].state = .loading
        do {
            let items: [Anime] = switch id {
            case .popular: try await media.popular(page: 0)
            case .topRated: try await media.topRated(page: 0)
            case .airing: try await media.currentlyAiring(page: 0)
            case .newReleases: try await media.recentlyReleased(page: 0)
            case .upcoming: try await media.upcoming(page: 0)
            }
            guard !Task.isCancelled else { return }
            rows[index].state = .loaded(items)
            if id == .popular, let featured = items.first {
                hero = featured
                heroState = .loaded(featured)
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            rows[index].state = .failed(CatalogError.map(error))
        }
    }

    private func loadContinueWatching() async {
        continueWatchingGeneration += 1
        let generation = continueWatchingGeneration

        let items = await progressStore.allProgress(limit: 32)
        guard generation == continueWatchingGeneration else { return }

        // One candidate per anime, most recent first. Seasons of one series are
        // separate Kitsu entries and collapse once grouping resolves.
        var seenAnimeIDs = Set<String>()
        let candidates = Array(
            items
                .filter { !$0.isCompleted }
                .filter { seenAnimeIDs.insert($0.animeID).inserted }
                .prefix(16)
        )

        // Entries resolve concurrently: the shelf waits for the slowest show,
        // not for the sum of every show's details, episodes and seasons. Only
        // the fully resolved set is published, so cards never appear and then
        // change once grouping and the entry cap have been applied. On refresh
        // the previous cards stay on screen until the new set is ready.
        let resolved = await resolveEntries(candidates)
        guard generation == continueWatchingGeneration else { return }

        var seenSeriesKeys = Set<String>()
        var entries: [ContinueWatchingEntry] = []
        for resolvedEntry in resolved {
            guard seenSeriesKeys.insert(resolvedEntry.seriesKey).inserted else { continue }
            entries.append(resolvedEntry.entry)
            guard entries.count < 8 else { break }
        }
        continueWatching = entries
    }

    private nonisolated func resolveEntries(_ items: [PlaybackProgress]) async -> [ResolvedEntry] {
        await withTaskGroup(of: (Int, ResolvedEntry?).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    (index, await self.resolveEntry(item))
                }
            }
            var results: [(Int, ResolvedEntry?)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.compactMap(\.1)
        }
    }

    private nonisolated func resolveEntry(_ item: PlaybackProgress) async -> ResolvedEntry? {
        // Details and episodes feed different parts of the card and are fetched
        // together; season grouping only starts once details are in hand.
        async let detailsRequest = media.anime(id: item.animeID)
        async let episodesRequest = episodes.episodes(forAnimeID: item.animeID)
        let details = try? await detailsRequest
        let episodeList = (try? await episodesRequest) ?? []

        let context: SeriesContext?
        if let details {
            context = await seriesContext(for: details)
        } else {
            context = nil
        }
        // Continue Watching must survive Kitsu outages.
        guard let anime = details?.anime ?? item.animeSnapshot else { return nil }

        let episode = episodeList.first {
            $0.displayNumber == item.episodeNumber || $0.number == item.episodeNumber
        }
        return ResolvedEntry(
            entry: ContinueWatchingEntry(
                anime: anime,
                progress: item,
                episode: episode,
                seasonNumber: Self.seasonNumber(for: context?.installment)
            ),
            seriesKey: context?.key ?? item.animeID
        )
    }

    /// Stable key for the whole series a detail belongs to. TV seasons share
    /// the first installment; movies and OVAs stay separate from the seasons.
    private nonisolated func seriesContext(for details: AnimeDetails) async -> SeriesContext {
        let series = await grouping.series(for: details.anime, details: details)
        return SeriesContext(
            key: series.installments.first?.id ?? details.anime.id,
            installment: series.installment(id: details.anime.id)
        )
    }

    private nonisolated func seriesKey(forAnimeID animeID: String) async -> String {
        guard let details = try? await media.anime(id: animeID) else { return animeID }
        return await seriesContext(for: details).key
    }

    /// Season number shown on continue watching cards. The series grouping is
    /// the source of truth for multi-season shows; movies and specials have no
    /// season number.
    private nonisolated static func seasonNumber(for installment: AnimeInstallment?) -> Int? {
        guard let installment, installment.anime.subtype == .tv else { return nil }
        if let parsed = SeriesGroupingService.seasonNumber(inTitle: installment.displayName) {
            return parsed
        }
        return installment.displayOrder + 1
    }
}
