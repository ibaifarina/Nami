import SwiftUI

struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: HomeViewModel

    init(environment: AppEnvironment) {
        _model = State(initialValue: HomeViewModel(environment: environment))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xxl) {
                heroSection
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    if !model.continueWatching.isEmpty {
                        continueWatchingSection
                    }
                    ForEach(model.rows) { row in
                        rowSection(row)
                    }
                }
                .contentPadding()
            }
            .padding(.bottom, Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .topBarScrim()
        .background(AppColor.background)
        .ignoresSafeArea(edges: .top)
        .navigationTitle("Home")
        .task { await model.load() }
        .onChange(of: environment.progressRevision) {
            guard !environment.playback.isPresenting else { return }
            Task { await model.refreshContinueWatching() }
        }
    }

    @ViewBuilder
    private var heroSection: some View {
        switch model.heroState {
        case .idle, .loading:
            LoadingSkeleton(cornerRadius: 0)
                .frame(maxWidth: .infinity)
                .frame(height: Layout.heroHeight)
        case .loaded(let anime):
            HeroSection(
                anime: anime,
                blurRadius: CGFloat(environment.preferences.heroBackgroundBlur.radius),
                onPlay: {
                    environment.playbackLaunch.play(
                        PlaybackRequest(anime: anime, episodeNumber: 1)
                    )
                },
                onDetails: { open(anime) }
            )
        case .failed:
            EmptyView()
        }
    }

    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Continue Watching")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Spacing.md) {
                    ForEach(model.continueWatching) { entry in
                        ContinueWatchingCard(
                            anime: entry.anime,
                            progress: entry.progress,
                            episode: entry.episode,
                            seasonNumber: entry.seasonNumber,
                            onOpen: {
                                open(entry.anime)
                            },
                            onResume: {
                                environment.playbackLaunch.play(
                                    PlaybackRequest(
                                        anime: entry.anime,
                                        episodeNumber: entry.progress.episodeNumber,
                                        startPositionSeconds: entry.progress.positionSeconds
                                    )
                                )
                            },
                            onRemove: {
                                Task { await model.removeFromContinueWatching(entry) }
                            }
                        )
                        .frame(width: 280)
                    }
                }
                .animation(.easeOut(duration: Motion.transition), value: model.continueWatching.map(\.id))
                .padding(.vertical, Spacing.xxs)
            }
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private func rowSection(_ row: HomeViewModel.Row) -> some View {
        switch row.state {
        case .idle, .loading:
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: row.id.title)
                RowSkeleton()
            }
        case .loaded(let items) where items.isEmpty:
            EmptyView()
        case .loaded(let items):
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: row.id.title)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Spacing.md) {
                        ForEach(items) { anime in
                            AnimePosterCard(anime: anime) {
                                open(anime)
                            }
                            .frame(width: Layout.posterCardMinWidth)
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }
                .scrollClipDisabled()
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: row.id.title)
                CompactErrorRow(
                    error: error,
                    onRetry: { Task { await model.retryRow(row.id) } }
                )
            }
        }
    }

    private func open(_ anime: Anime) {
        environment.router.push(.anime(id: anime.id), in: .home)
    }
}

private struct CompactErrorRow: View {
    let error: CatalogError
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.errorDescription ?? "Something went wrong")
                    .font(AppFont.cardTitle)
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let onRetry {
                Button("Retry", action: onRetry)
                    .controlSize(.small)
                    .hoverFeedback(scale: 1.03)
            }
        }
        .padding(Spacing.md)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(AppColor.stroke, lineWidth: 0.5)
        }
    }
}

#if DEBUG
#Preview("Home") {
    let environment = AppEnvironment.preview()
    HomeView(environment: environment)
        .environment(environment)
        .frame(width: 1100, height: 820)
}
#endif
