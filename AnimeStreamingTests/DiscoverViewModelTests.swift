import Foundation
import Testing
@testable import AnimeStreaming

@MainActor
struct DiscoverViewModelTests {
    private func makeAnime(_ index: Int) -> Anime {
        SampleCatalog.make(
            id: "page-item-\(index)",
            title: "Show \(index)",
            subtype: .tv,
            status: .finished,
            year: 2020,
            episodes: 12,
            duration: 24,
            rating: 80,
            popularityRank: index,
            genres: ["Action"]
        )
    }

    @Test func rapidQueriesAreDebouncedToOneSearch() async throws {
        let counter = CallCounter()
        var repository = StubMediaRepository(pages: [SampleCatalog.anime])
        repository.onDiscover = { await counter.increment() }
        let model = DiscoverViewModel(media: repository, debounce: .milliseconds(30))

        for query in ["f", "fr", "fri", "frie", "frier"] {
            model.query = query
            model.queryDidChange()
        }

        try await Task.sleep(for: .milliseconds(300))

        let callCount = await counter.count
        #expect(callCount == 1)
        #expect(model.results.count == SampleCatalog.anime.count)
        if case .loaded = model.state {
        } else {
            Issue.record("Expected loaded state, got \(model.state)")
        }
    }

    @Test func filterChangeSearchesImmediately() async throws {
        let counter = CallCounter()
        var repository = StubMediaRepository(pages: [[]])
        repository.onDiscover = { await counter.increment() }
        let model = DiscoverViewModel(media: repository, debounce: .milliseconds(500))

        model.filters.genre = "action"
        model.filtersDidChange()

        try await Task.sleep(for: .milliseconds(150))

        let callCount = await counter.count
        #expect(callCount == 1)
    }

    @Test func failedSearchExposesFriendlyError() async throws {
        var repository = StubMediaRepository()
        repository.error = .unavailable
        let model = DiscoverViewModel(media: repository, debounce: .milliseconds(10))

        model.queryDidChange()
        try await Task.sleep(for: .milliseconds(200))

        guard case .failed(let error) = model.state else {
            Issue.record("Expected failed state, got \(model.state)")
            return
        }
        #expect(error == .unavailable)
        #expect(error.errorDescription?.contains("Kitsu") == true)
    }

    @Test func loadInitialSearchesOnce() async {
        let counter = CallCounter()
        var repository = StubMediaRepository(pages: [SampleCatalog.anime])
        repository.onDiscover = { await counter.increment() }
        let model = DiscoverViewModel(media: repository)

        await model.loadInitial()
        await model.loadInitial()

        let callCount = await counter.count
        #expect(callCount == 1)
        #expect(!model.results.isEmpty)
    }

    @Test func paginationAppendsAndStopsWhenExhausted() async {
        let firstPage = (0..<20).map(makeAnime)
        let secondPage = (20..<25).map(makeAnime)
        let repository = StubMediaRepository(pages: [firstPage, secondPage])
        let model = DiscoverViewModel(media: repository)

        await model.loadInitial()
        #expect(model.results.count == 20)
        #expect(model.canLoadMore)

        await model.loadMoreIfNeeded(currentItem: firstPage[19])
        #expect(model.results.count == 25)
        #expect(!model.canLoadMore)

        await model.loadMoreIfNeeded(currentItem: secondPage[4])
        #expect(model.results.count == 25)
    }

    @Test func recentSearchesAreRecordedAndReused() async {
        let store = InMemoryRecentSearchStore()
        let repository = StubMediaRepository(pages: [SampleCatalog.anime])
        let model = DiscoverViewModel(media: repository, recentSearchStore: store)

        model.query = "frieren"
        model.queryDidChange()
        try? await Task.sleep(for: .milliseconds(400))
        await model.recordCurrentQuery()

        #expect(model.recentSearches.contains("frieren"))

        model.useRecentSearch("frieren")
        try? await Task.sleep(for: .milliseconds(400))
        #expect(model.query == "frieren")
    }

    @Test func emptyQueryDoesNotRecordRecentSearch() async {
        let store = InMemoryRecentSearchStore()
        let repository = StubMediaRepository(pages: [SampleCatalog.anime])
        let model = DiscoverViewModel(media: repository, recentSearchStore: store)

        await model.loadInitial()
        await model.recordCurrentQuery()

        #expect(model.recentSearches.isEmpty)
    }
}
