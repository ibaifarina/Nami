import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    enum Filter: String, CaseIterable, Identifiable {
        case watching
        case planToWatch
        case completed
        case favorites

        var id: String { rawValue }

        var status: LibraryStatus {
            switch self {
            case .watching: .watching
            case .planToWatch: .planToWatch
            case .completed: .completed
            case .favorites: .favorites
            }
        }

        var title: String { status.displayName }
    }

    private let library: any LibraryRepository

    var entries: [LibraryEntry] = []
    var state: LoadingState<[LibraryEntry]> = .idle
    var filter: Filter = .watching
    var removalError: CatalogError?

    init(environment: AppEnvironment) {
        library = environment.library
    }

    init(library: any LibraryRepository) {
        self.library = library
    }

    var filteredEntries: [LibraryEntry] {
        entries
            .filter { $0.status == filter.status }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var hasAnyEntries: Bool { !entries.isEmpty }

    func load() async {
        state = .loading
        do {
            let entries = try await library.entries()
            guard !Task.isCancelled else { return }
            self.entries = entries
            state = .loaded(entries)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(CatalogError.map(error))
        }
    }

    func remove(_ entry: LibraryEntry) async {
        do {
            try await library.remove(animeID: entry.animeID)
            entries.removeAll { $0.id == entry.id }
            state = .loaded(entries)
            removalError = nil
        } catch is CancellationError {
            return
        } catch {
            removalError = CatalogError.map(error)
        }
    }

    func reset() {
        entries = []
        state = .idle
        removalError = nil
    }
}
