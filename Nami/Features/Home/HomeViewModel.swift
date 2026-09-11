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

    struct ContinueWatchingEntry: Identifiable {
        var id: String { progress.id }
        let anime: Anime
        let progress: PlaybackProgress
    }

    private let media: any MediaRepository
    private let progressStore: any PlaybackProgressStore

    var hero: Anime?
    var heroState: LoadingState<Anime> = .idle
    var continueWatching: [ContinueWatchingEntry] = []
    var rows: [Row] = RowID.allCases.map { Row(id: $0, state: .idle) }

    init(environment: AppEnvironment) {
        media = environment.media
        progressStore = environment.progress
    }

    init(media: any MediaRepository, progressStore: any PlaybackProgressStore) {
        self.media = media
        self.progressStore = progressStore
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
        let items = await progressStore.allProgress(limit: 32)
        var seenAnimeIDs = Set<String>()
        var entries: [ContinueWatchingEntry] = []
        for item in items where !item.isCompleted {
            guard entries.count < 8 else { break }
            // One card per show: the most recently watched episode wins.
            guard seenAnimeIDs.insert(item.animeID).inserted else { continue }
            if let details = try? await media.anime(id: item.animeID) {
                entries.append(ContinueWatchingEntry(anime: details.anime, progress: item))
            } else if let snapshot = item.animeSnapshot {
                // Continue Watching must survive Kitsu outages.
                entries.append(ContinueWatchingEntry(anime: snapshot, progress: item))
            }
        }
        continueWatching = entries
    }
}
