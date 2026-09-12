import Foundation
import Testing
@testable import Nami

@MainActor
struct LibraryViewModelTests {
    private func entry(
        id: String,
        status: LibraryStatus,
        progress: Int,
        updatedAt: Date,
        anime: Anime
    ) -> LibraryEntry {
        LibraryEntry(
            animeID: id,
            status: status,
            progress: progress,
            updatedAt: updatedAt,
            anime: anime
        )
    }

    @Test func filtersAndSortsByMostRecentlyUpdated() {
        let older = entry(
            id: "46474",
            status: .watching,
            progress: 3,
            updatedAt: Date().addingTimeInterval(-3_600),
            anime: SampleCatalog.anime[0]
        )
        let newer = entry(
            id: "7442",
            status: .watching,
            progress: 7,
            updatedAt: Date(),
            anime: SampleCatalog.anime[1]
        )
        let planned = entry(
            id: "8671",
            status: .planToWatch,
            progress: 0,
            updatedAt: Date(),
            anime: SampleCatalog.anime[2]
        )
        let repository = StubLibraryRepository(entries: [older, newer, planned])
        let model = LibraryViewModel(library: repository)
        model.entries = [older, newer, planned]

        model.filter = .watching
        #expect(model.filteredEntries.map(\.id) == ["7442", "46474"])

        model.filter = .planToWatch
        #expect(model.filteredEntries.map(\.id) == ["8671"])

        model.filter = .favorites
        #expect(model.filteredEntries.isEmpty)
        #expect(model.hasAnyEntries)
    }

    @Test func loadPopulatesEntries() async {
        let repository = StubLibraryRepository(entries: [
            entry(
                id: "46474",
                status: .watching,
                progress: 5,
                updatedAt: Date(),
                anime: SampleCatalog.anime[0]
            ),
        ])
        let model = LibraryViewModel(library: repository)

        await model.load()

        #expect(model.entries.count == 1)
        if case .loaded(let entries) = model.state {
            #expect(entries.count == 1)
        } else {
            Issue.record("Expected loaded state, got \(model.state)")
        }
    }

    @Test func loadFailureExposesError() async {
        let repository = StubLibraryRepository(error: .server("boom"))
        let model = LibraryViewModel(library: repository)

        await model.load()

        guard case .failed(let error) = model.state else {
            Issue.record("Expected failed state, got \(model.state)")
            return
        }
        #expect(error == .server("boom"))
    }

    @Test func removeDeletesEntryFromRepositoryAndModel() async throws {
        let item = entry(
            id: "46474",
            status: .watching,
            progress: 5,
            updatedAt: Date(),
            anime: SampleCatalog.anime[0]
        )
        let repository = StubLibraryRepository(entries: [item])
        let model = LibraryViewModel(library: repository)
        await model.load()

        await model.remove(item)

        #expect(model.entries.isEmpty)
        #expect(try await repository.entry(animeID: item.animeID) == nil)
        #expect(model.removalError == nil)
    }

    @Test func removeFailureKeepsEntryAndExposesError() async {
        let item = entry(
            id: "46474",
            status: .watching,
            progress: 5,
            updatedAt: Date(),
            anime: SampleCatalog.anime[0]
        )
        let repository = StubLibraryRepository(entries: [item])
        let model = LibraryViewModel(library: repository)
        await model.load()
        await repository.configure(error: .server("boom"))

        await model.remove(item)

        #expect(model.entries == [item])
        #expect(model.removalError == .server("boom"))
    }

    @Test func resetClearsEntries() async {
        let repository = StubLibraryRepository(entries: [
            entry(
                id: "46474",
                status: .watching,
                progress: 5,
                updatedAt: Date(),
                anime: SampleCatalog.anime[0]
            ),
        ])
        let model = LibraryViewModel(library: repository)
        await model.load()

        model.reset()

        #expect(model.entries.isEmpty)
        #expect(model.state.value == nil)
    }
}
