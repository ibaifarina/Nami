import Foundation
import Observation

@MainActor
@Observable
final class DiscoverViewModel {
    private struct Query {
        let text: String
        let filters: DiscoverFilters
        let page: Int
    }

    private let media: any MediaRepository
    private let recentSearchStore: any RecentSearchStoring
    private let debounce: Duration

    var query = ""
    var filters = DiscoverFilters()
    var results: [Anime] = []
    var state: LoadingState<[Anime]> = .idle
    var isLoadingMore = false
    var canLoadMore = true
    var recentSearches: [String] = []

    private var searchTask: Task<Void, Never>?
    private var page = 0
    private var generation = UUID()

    init(environment: AppEnvironment, debounce: Duration = .milliseconds(300)) {
        media = environment.media
        recentSearchStore = UserDefaultsRecentSearchStore()
        self.debounce = debounce
    }

    init(
        media: any MediaRepository,
        recentSearchStore: any RecentSearchStoring = InMemoryRecentSearchStore(),
        debounce: Duration = .milliseconds(300)
    ) {
        self.media = media
        self.recentSearchStore = recentSearchStore
        self.debounce = debounce
    }

    var hasActiveFilters: Bool { !filters.isDefault }
    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    func loadInitial() async {
        guard case .idle = state else { return }
        recentSearches = await recentSearchStore.searches()
        await performSearch(reset: true)
    }

    func queryDidChange() {
        // Do not search on empty text; browsing uses the filters instead.
        scheduleSearch(delay: debounce)
    }

    func filtersDidChange() {
        scheduleSearch(delay: .zero)
    }

    func clearFilters() {
        filters = DiscoverFilters()
    }

    func retry() async {
        await performSearch(reset: true)
    }

    func recordCurrentQuery() async {
        await recentSearchStore.record(trimmedQuery)
        recentSearches = await recentSearchStore.searches()
    }

    func useRecentSearch(_ value: String) {
        query = value
        scheduleSearch(delay: .zero)
    }

    func clearRecentSearches() async {
        await recentSearchStore.clear()
        recentSearches = []
    }

    func loadMoreIfNeeded(currentItem: Anime) async {
        guard canLoadMore, !isLoadingMore, case .loaded = state else { return }
        guard let index = results.firstIndex(of: currentItem) else { return }
        guard index >= results.count - 4 else { return }
        await performSearch(reset: false)
    }

    private func scheduleSearch(delay: Duration) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await performSearch(reset: true)
        }
    }

    private func performSearch(reset: Bool) async {
        let token: UUID
        if reset {
            token = UUID()
            generation = token
            state = .loading
            results = []
            page = 0
            canLoadMore = true
            isLoadingMore = false
        } else {
            token = generation
            isLoadingMore = true
        }

        defer {
            // A superseded load-more must not clear the flag of the request
            // that replaced it, otherwise paging silently stops.
            if !reset, generation == token {
                isLoadingMore = false
            }
        }

        let request = Query(text: trimmedQuery, filters: filters, page: reset ? 0 : page)
        do {
            let items = try await media.discover(
                query: request.text,
                filters: request.filters,
                page: request.page
            )
            guard generation == token else { return }
            if reset {
                results = items
            } else {
                let existing = Set(results.map(\.id))
                results.append(contentsOf: items.filter { !existing.contains($0.id) })
            }
            page = request.page + 1
            canLoadMore = items.count >= KitsuPagination.pageLimit
            state = .loaded(results)
            if !request.text.isEmpty {
                await recentSearchStore.record(request.text)
                recentSearches = await recentSearchStore.searches()
            }
        } catch is CancellationError {
            // A newer search superseded this one.
        } catch {
            guard generation == token else { return }
            if reset {
                state = .failed(CatalogError.map(error))
            }
        }
        isLoadingMore = false
    }
}
