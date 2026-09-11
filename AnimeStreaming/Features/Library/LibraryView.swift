import SwiftUI

struct LibraryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: LibraryViewModel

    init(environment: AppEnvironment) {
        _model = State(initialValue: LibraryViewModel(environment: environment))
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error):
                ErrorStateView(
                    title: error.errorDescription ?? "Couldn't load your library",
                    message: error.recoverySuggestion,
                    technicalDetail: error.technicalDetail,
                    onRetry: { Task { await model.load() } }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                listsContent
            }
        }
        .background(AppColor.background)
        .navigationTitle("Library")
        .task { await model.load() }
    }

    private var listsContent: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            SegmentedSwitcher(
                options: LibraryViewModel.Filter.allCases,
                selection: $model.filter,
                title: \.title,
                systemImage: { $0.status.systemImage }
            )
            .padding(.bottom, Spacing.md)

            content
        }
        .padding(.top, Spacing.xl)
    }

    @ViewBuilder
    private var content: some View {
        if model.filteredEntries.isEmpty {
            EmptyStateView(
                systemImage: "books.vertical",
                title: model.hasAnyEntries
                    ? "Nothing in \(model.filter.title)"
                    : "Your library is empty",
                message: model.hasAnyEntries
                    ? "Try another status tab."
                    : "Add anime from their details page to build your local library. Everything is stored on this Mac.",
                actionTitle: "Browse",
                action: { environment.router.select(.discover) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: Spacing.lg) {
                    ForEach(model.filteredEntries) { entry in
                        AnimePosterCard(anime: entry.anime, metaOverride: progressLabel(entry)) {
                            environment.router.push(.anime(id: entry.anime.id), in: .library)
                        }
                    }
                }
                .contentPadding()
                .padding(.bottom, Spacing.xl)
            }
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: Layout.posterCardMinWidth,
                    maximum: Layout.posterCardMaxWidth
                ),
                spacing: Spacing.lg,
                alignment: .top
            )
        ]
    }

    private func progressLabel(_ entry: LibraryEntry) -> String? {
        if let total = entry.anime.episodesAvailable, total > 0 {
            return "Ep \(entry.progress) / \(total)"
        }
        return entry.progress > 0 ? "Ep \(entry.progress)" : nil
    }
}

#if DEBUG
#Preview("Library") {
    let environment = AppEnvironment.preview()
    LibraryView(environment: environment)
        .environment(environment)
        .frame(width: 1100, height: 820)
}
#endif
