import SwiftUI

struct AnimeDetailsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: AnimeDetailsViewModel
    @State private var isSynopsisExpanded = false
    @State private var episodeViewMode: EpisodeViewMode = .cards
    @State private var isLibraryMenuExpanded = false
    @State private var synopsisFullHeight: CGFloat = 0
    @State private var synopsisClampedHeight: CGFloat = 0

    private static let synopsisLineLimit = 4

    init(animeID: String, environment: AppEnvironment) {
        _model = State(initialValue: AnimeDetailsViewModel(environment: environment, animeID: animeID))
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                skeletonContent
            case .loaded(let details):
                content(details)
            case .failed(let error):
                ErrorStateView(
                    title: error.errorDescription ?? "Something went wrong",
                    message: error.recoverySuggestion,
                    technicalDetail: error.technicalDetail,
                    onRetry: { Task { await model.retry() } }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppColor.background)
        .task { await model.load() }
        .task(id: preloadKey) {
            guard
                let anime = model.selectedAnime,
                let episode = model.primaryEpisode
            else {
                return
            }
            environment.streamPreload.prepare(anime: anime, episode: episode)
        }
        .onChange(of: environment.progressRevision) {
            guard !environment.playback.isPresenting else { return }
            Task { await model.refreshLocalContext() }
        }
    }

    private func content(_ details: AnimeDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                header(model.selectedAnime ?? details.anime)
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    synopsis(model.selectedAnime ?? details.anime)
                    if model.availableInstallments.count > 1 {
                        seasonSection
                    } else if model.series == nil, hasLikelySeasons(details) {
                        skeletonSeason
                    }
                    if !model.isMovie {
                        episodesSection
                    }
                    if model.series == nil, model.related.isEmpty, hasLikelyRelated(details) {
                        skeletonRelated
                    } else {
                        relatedSection
                    }
                }
                .contentPadding()
                .padding(.top, -Layout.detailHeroOverlap)
            }
            .padding(.bottom, Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 0, idealWidth: 900, maxWidth: .infinity)
        .topBarScrim()
        .ignoresSafeArea(edges: .top)
        .navigationTitle((model.selectedAnime ?? details.anime).displayTitle)
    }

    private var skeletonContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                skeletonHeader
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    skeletonSynopsis
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        SectionHeader(title: "Episodes")
                        episodeSkeleton
                    }
                }
                .contentPadding()
                .padding(.top, -Layout.detailHeroOverlap)
            }
            .padding(.bottom, Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 0, idealWidth: 900, maxWidth: .infinity)
        .ignoresSafeArea(edges: .top)
        .scrollDisabled(true)
        .accessibilityHidden(true)
    }

    private var skeletonHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LoadingSkeleton(cornerRadius: 0)
                .frame(height: Layout.detailHeroHeight)
                .frame(maxWidth: .infinity)
            AppColor.detailHeroFade
            HStack(alignment: .bottom, spacing: Spacing.lg) {
                LoadingSkeleton()
                    .aspectRatio(Layout.posterAspectRatio, contentMode: .fit)
                    .frame(width: 150)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    LoadingSkeleton(cornerRadius: 6)
                        .frame(width: 380, height: 36)
                    LoadingSkeleton(cornerRadius: 4)
                        .frame(width: 210, height: 12)
                    HStack(spacing: Spacing.xs) {
                        ForEach(0..<4, id: \.self) { index in
                            LoadingSkeleton(cornerRadius: Radius.control)
                                .frame(width: index.isMultiple(of: 2) ? 58 : 76, height: 20)
                        }
                    }
                    .padding(.top, Spacing.xxs)
                    HStack(spacing: Spacing.sm) {
                        LoadingSkeleton(cornerRadius: Radius.button)
                            .frame(width: 150, height: 34)
                        LoadingSkeleton(cornerRadius: Radius.button)
                            .frame(width: 104, height: 34)
                        LoadingSkeleton(cornerRadius: Radius.button)
                            .frame(width: 38, height: 34)
                    }
                    .padding(.top, Spacing.sm)
                }
                .padding(.bottom, Spacing.xs)
                Spacer(minLength: 0)
            }
            .contentPadding()
            .padding(.bottom, Layout.detailHeroContentInset)
        }
        .frame(height: Layout.detailHeroHeight)
        .frame(maxWidth: .infinity)
    }

    private var skeletonSynopsis: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader(title: "Synopsis")
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(0..<4, id: \.self) { index in
                    LoadingSkeleton(cornerRadius: 4)
                        .frame(height: 12)
                        .frame(maxWidth: index == 3 ? 480 : .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var skeletonSeason: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Season")
            HStack(spacing: Spacing.xs) {
                ForEach(0..<4, id: \.self) { index in
                    LoadingSkeleton(cornerRadius: 15)
                        .frame(width: index.isMultiple(of: 2) ? 108 : 88, height: 30)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityHidden(true)
    }

    private var skeletonRelated: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Related")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Spacing.md) {
                    ForEach(0..<6, id: \.self) { _ in
                        PosterSkeleton()
                            .frame(width: Layout.posterCardMinWidth)
                    }
                }
                .padding(.vertical, Spacing.xxs)
            }
        }
        .accessibilityHidden(true)
    }

    /// Whether the direct relations fetched with the details suggest multiple
    /// TV installments, so the season selector is likely to appear once the
    /// full series grouping resolves. Only TV entries get a season selector.
    private func hasLikelySeasons(_ details: AnimeDetails) -> Bool {
        details.anime.subtype == .tv && details.relations.contains {
            $0.role.isSequentialInstallment && $0.anime.subtype == .tv
        }
    }

    /// Whether the direct relations suggest non-installment entries, so the
    /// related row is likely to appear once the full series grouping resolves.
    /// For non-TV entries the whole sequential chain becomes related media.
    private func hasLikelyRelated(_ details: AnimeDetails) -> Bool {
        let entryIsTV = details.anime.subtype == .tv
        return details.relations.contains { relation in
            guard relation.role.isSequentialInstallment, relation.anime.subtype == .tv else {
                return true
            }
            return !entryIsTV
        }
    }

    private func header(_ anime: Anime) -> some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .scrollView)
            let topOverscroll = max(frame.minY, 0)
            let leadingOverscroll = max(frame.minX, 0)
            let horizontalOverscroll = abs(frame.minX)

            ZStack(alignment: .topLeading) {
                ZStack {
                    ParallaxHeroImage(
                        url: anime.bannerURL ?? anime.posterURL,
                        height: Layout.detailHeroHeight,
                        blurRadius: CGFloat(environment.preferences.heroBackgroundBlur.radius)
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .mask { AppColor.detailHeroMask }
                    Color.black.opacity(0.7)
                    AppColor.detailHeroFade
                }
                .frame(
                    width: proxy.size.width + horizontalOverscroll,
                    height: Layout.detailHeroHeight + topOverscroll
                )
                .offset(x: -leadingOverscroll, y: -topOverscroll)

                HStack(alignment: .bottom, spacing: Spacing.lg) {
                    poster(anime)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(anime.displayTitle)
                            .font(AppFont.heroTitle)
                            .lineLimit(2)
                        if let alternative = anime.alternativeTitle {
                            Text(alternative)
                                .font(AppFont.cardMeta)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        metadataPills(anime)
                            .padding(.top, Spacing.xxs)
                        actions
                            .padding(.top, Spacing.sm)
                    }
                    .padding(.bottom, Spacing.xs)
                    Spacer(minLength: 0)
                }
                .contentPadding()
                .padding(.bottom, Layout.detailHeroContentInset)
                .frame(
                    width: proxy.size.width,
                    height: Layout.detailHeroHeight,
                    alignment: .bottomLeading
                )
                .offset(x: -frame.minX, y: -topOverscroll)
            }
            .frame(width: proxy.size.width, height: Layout.detailHeroHeight)
        }
        .frame(height: Layout.detailHeroHeight)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            if let listError = model.libraryError {
                Text(listError)
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())
                    .padding(Layout.contentPadding)
            }
        }
    }

    private func poster(_ anime: Anime) -> some View {
        Color.clear
            .aspectRatio(Layout.posterAspectRatio, contentMode: .fit)
            .frame(width: 150)
            .overlay {
                RemoteImage(url: anime.posterURL, contentMode: .fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(AppColor.stroke, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            .accessibilityHidden(true)
    }

    private func metadataPills(_ anime: Anime) -> some View {
        HStack(spacing: Spacing.xs) {
            if let score = anime.averageScore {
                Pill(text: "\(score)", systemImage: "star.fill")
            }
            if let subtype = anime.subtype { Pill(text: subtype.displayName) }
            if let year = anime.startYear { Pill(text: String(year)) }
            if let episodes = anime.episodesAvailable { Pill(text: "\(episodes) episodes") }
            if let status = anime.status { Pill(text: status.displayName) }
            if let age = anime.ageRating { Pill(text: age) }
        }
    }

    private var actions: some View {
        HStack(spacing: Spacing.sm) {
            Button(model.primaryActionTitle, systemImage: "play.fill") {
                playPrimary()
            }
            .buttonStyle(BrandButtonStyle())
            .disabled(model.selectedAnime == nil)

            Button("Source", systemImage: "list.bullet") {
                playPrimary(manual: true)
            }
            .buttonStyle(GlassButtonStyle())
            .disabled(model.selectedAnime == nil)

            libraryMenu
        }
    }

    private var libraryMenu: some View {
        Button {
            isLibraryMenuExpanded.toggle()
        } label: {
            Label(
                model.libraryEntry?.status.displayName ?? "Add to Library",
                systemImage: model.libraryEntry == nil ? "bookmark" : "bookmark.fill"
            )
            .labelStyle(.iconOnly)
        }
        .buttonStyle(GlassButtonStyle())
        .fixedSize()
        .hoverFeedback(scale: 1.03)
        .accessibilityLabel(model.libraryEntry?.status.displayName ?? "Add to Library")
        .disabled(model.isUpdatingLibrary || model.selectedAnime == nil)
        .help("Manage your local library")
        .popover(isPresented: $isLibraryMenuExpanded, arrowEdge: .top) {
            SettingsDropdownPanel(
                options: libraryOptions,
                selection: model.libraryEntry?.status,
                onSelect: { status in
                    guard let status else { return }
                    isLibraryMenuExpanded = false
                    Task { await model.setLibraryStatus(status) }
                },
                action: removeFromLibraryAction
            )
            .frame(width: 240)
        }
    }

    private var libraryOptions: [SettingsDropdownOption<LibraryStatus?>] {
        LibraryStatus.libraryCases.map {
            SettingsDropdownOption(value: Optional($0), label: $0.displayName, systemImage: $0.systemImage)
        }
    }

    private var removeFromLibraryAction: SettingsDropdownAction? {
        guard model.libraryEntry != nil else { return nil }
        return SettingsDropdownAction(
            label: "Remove from Library",
            systemImage: "trash",
            isDestructive: true
        ) {
            isLibraryMenuExpanded = false
            Task { await model.removeFromLibrary() }
        }
    }

    @ViewBuilder
    private func synopsis(_ anime: Anime) -> some View {
        if let synopsis = anime.synopsis {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionHeader(title: "Synopsis")
                Text(synopsis)
                    .font(AppFont.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(isSynopsisExpanded ? nil : Self.synopsisLineLimit)
                    .background(synopsisTruncationProbe(synopsis))
                if isSynopsisExpanded || isSynopsisTruncated {
                    Button(isSynopsisExpanded ? "Show Less" : "Show More") {
                        withAnimation(.easeOut(duration: Motion.transition)) {
                            isSynopsisExpanded.toggle()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppColor.brand)
                    .hoverFeedback(brightness: 0.2)
                }
            }
        }
    }

    private func synopsisTruncationProbe(_ synopsis: String) -> some View {
        ZStack {
            Text(synopsis)
                .font(AppFont.body)
                .lineLimit(Self.synopsisLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    synopsisClampedHeight = height
                }
            Text(synopsis)
                .font(AppFont.body)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    synopsisFullHeight = height
                }
        }
    }

    private var isSynopsisTruncated: Bool {
        synopsisFullHeight > synopsisClampedHeight + 0.5
    }

    private var seasonSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Season")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(model.availableInstallments) { installment in
                        let isSelected = model.selectedInstallment?.id == installment.id
                        Button {
                            withAnimation(.easeOut(duration: Motion.transition)) {
                                model.selectInstallment(installment)
                            }
                        } label: {
                            Text(installment.displayName)
                                .font(AppFont.cardTitle)
                                .foregroundStyle(isSelected ? AppColor.buttonLabel : .primary)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, 7)
                                .background(
                                    isSelected ? AppColor.brand : Color.primary.opacity(0.06),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .hoverFeedback(scale: 1.03)
                        .help(installment.anime.displayTitle)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(
                    title: "Episodes",
                    subtitle: model.selectedAnime?.status == .current
                        ? "New episodes air as they release"
                        : nil
                )
                episodeViewToggle
            }
            switch model.episodesState {
            case .idle, .loading:
                episodeSkeleton
            case .loaded(let episodes) where episodes.isEmpty:
                Text("Episode metadata is not available yet for this title.")
                    .font(AppFont.body)
                    .foregroundStyle(.secondary)
            case .loaded(let episodes):
                switch episodeViewMode {
                case .list: episodeList(episodes)
                case .cards: episodeCards(episodes)
                }
            case .failed(let error):
                CompactEpisodeError(error: error) {
                    Task { await model.retryEpisodes() }
                }
            }
        }
    }

    @ViewBuilder
    private var episodeSkeleton: some View {
        switch episodeViewMode {
        case .list: episodeListSkeleton
        case .cards: episodeCardsSkeleton
        }
    }

    private var episodeListSkeleton: some View {
        LazyVStack(spacing: Spacing.xxs) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: Spacing.sm) {
                    LoadingSkeleton(cornerRadius: Radius.control)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        LoadingSkeleton(cornerRadius: 4)
                            .frame(width: 220, height: 12)
                        LoadingSkeleton(cornerRadius: 4)
                            .frame(width: 120, height: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    AppColor.surface,
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                )
            }
        }
    }

    private var episodeCardsSkeleton: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Spacing.md) {
                ForEach(0..<4, id: \.self) { _ in
                    LoadingSkeleton(cornerRadius: Radius.card)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(width: 360)
                }
            }
            .padding(.vertical, Spacing.xxs)
        }
    }

    private var episodeViewToggle: some View {
        HStack(spacing: 2) {
            ForEach(EpisodeViewMode.allCases) { mode in
                Button {
                    withAnimation(.easeOut(duration: Motion.transition)) {
                        episodeViewMode = mode
                    }
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(episodeViewMode == mode ? AppColor.buttonLabel : Color.secondary)
                        .frame(width: 28, height: 24)
                        .background(
                            episodeViewMode == mode ? AppColor.brand : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("\(mode.title) view")
                .accessibilityLabel("\(mode.title) episode view")
                .accessibilityAddTraits(episodeViewMode == mode ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppColor.stroke, lineWidth: 0.5)
        }
    }

    private func episodeList(_ episodes: [Episode]) -> some View {
        LazyVStack(spacing: Spacing.xxs) {
            ForEach(episodes) { episode in
                EpisodeListRow(
                    episode: episode,
                    fallbackImageURL: model.selectedAnime?.bannerURL
                        ?? model.selectedAnime?.posterURL,
                    isWatched: model.isWatched(episode),
                    onPlay: { play(episode: episode) },
                    onToggleWatched: {
                        Task { await model.toggleEpisodeWatched(episode) }
                    }
                )
                .id(episode.id)
                .contextMenu { watchedMenu(episode) }
            }
        }
    }

    private func episodeCards(_ episodes: [Episode]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Spacing.md) {
                    ForEach(episodes) { episode in
                        EpisodeCard(
                            episode: episode,
                            fallbackImageURL: model.selectedAnime?.bannerURL
                                ?? model.selectedAnime?.posterURL,
                            isWatched: model.isWatched(episode),
                            progress: model.episodeProgress(for: episode),
                            onPlay: { play(episode: episode) },
                            onToggleWatched: {
                                Task { await model.toggleEpisodeWatched(episode) }
                            }
                        )
                        .frame(width: 360)
                        .id(episode.id)
                        .contextMenu { watchedMenu(episode) }
                    }
                }
                .padding(.vertical, Spacing.xxs)
            }
            .scrollClipDisabled()
            .task(id: episodeScrollTarget) {
                guard model.hasWatchHistory, let target = model.currentEpisode else { return }
                // Let the lazy stack lay out the loaded cards before scrolling.
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: Motion.transition)) {
                    proxy.scrollTo(target.id, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func watchedMenu(_ episode: Episode) -> some View {
        let watched = model.isWatched(episode)
        Button(
            watched
                ? "Mark Episode \(episode.displayNumber) as Unwatched"
                : "Mark Episode \(episode.displayNumber) as Watched",
            systemImage: watched ? "eye.slash" : "eye"
        ) {
            Task { await model.toggleEpisodeWatched(episode) }
        }
    }

    @ViewBuilder
    private var relatedSection: some View {
        if !model.related.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: "Related")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Spacing.md) {
                        ForEach(model.related) { relation in
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                AnimePosterCard(
                                    anime: relation.anime,
                                    metaOverride: relation.role.displayName
                                ) {
                                    open(relation.anime)
                                }
                                .frame(width: Layout.posterCardMinWidth)
                            }
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }
                .scrollClipDisabled()
            }
        }
    }

    private var currentSection: AppRouter.SidebarItem {
        environment.router.selection ?? .home
    }

    /// Re-warms the stream cache whenever the play button's target changes.
    private var preloadKey: String? {
        guard
            let anime = model.selectedAnime,
            let episode = model.primaryEpisode
        else {
            return nil
        }
        return "\(anime.id)-\(episode.displayNumber)"
    }

    /// Changes whenever the episode that should be scrolled into view changes,
    /// including after episodes load or playback marks one watched.
    private var episodeScrollTarget: String {
        [
            model.selectedInstallmentID ?? model.animeID,
            String(model.episodes.count),
            model.currentEpisode?.id ?? "none",
            episodeViewMode.rawValue,
        ]
        .joined(separator: "-")
    }

    private func open(_ anime: Anime) {
        environment.router.push(.anime(id: anime.id), in: currentSection)
    }

    private func playPrimary(manual: Bool = false) {
        guard let anime = model.selectedAnime else { return }
        if let episode = model.primaryEpisode {
            play(anime: anime, episode: episode, manual: manual)
        } else {
            play(anime: anime, episodeNumber: 1, manual: manual)
        }
    }

    private func play(episode: Episode) {
        guard let anime = model.selectedAnime else { return }
        play(anime: anime, episode: episode)
    }

    private func play(
        anime: Anime,
        episode: Episode,
        manual: Bool = false
    ) {
        let resumePosition: Double? = {
            guard !manual,
                  let progress = model.progress,
                  progress.episodeNumber == episode.displayNumber,
                  !progress.isCompleted
            else {
                return nil
            }
            return progress.positionSeconds
        }()
        environment.playbackLaunch.play(
            PlaybackRequest(
                anime: anime,
                episode: episode,
                prefersManualSelection: manual,
                startPositionSeconds: resumePosition
            )
        )
    }

    private func play(anime: Anime, episodeNumber: Int, manual: Bool = false) {
        environment.playbackLaunch.play(
            PlaybackRequest(
                anime: anime,
                episodeNumber: episodeNumber,
                prefersManualSelection: manual
            )
        )
    }
}

private enum EpisodeViewMode: String, CaseIterable, Identifiable {
    case cards
    case list

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .cards: "square.grid.2x2"
        }
    }

    var title: String {
        switch self {
        case .list: "List"
        case .cards: "Cards"
        }
    }
}

private struct EpisodeListRow: View {
    let episode: Episode
    let fallbackImageURL: URL?
    let isWatched: Bool
    let onPlay: () -> Void
    let onToggleWatched: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Button(action: onPlay) {
                HStack(spacing: Spacing.sm) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.displayTitle)
                            .font(AppFont.cardTitle)
                            .foregroundStyle(isWatched ? .secondary : .primary)
                            .lineLimit(1)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(AppFont.cardMeta)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: Spacing.sm)
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.brand)
                        .opacity(isHovered ? 1 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(episode.displayTitle)")

            watchedToggle
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            AppColor.surface,
            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(isHovered ? AppColor.brand.opacity(0.45) : AppColor.stroke, lineWidth: 0.5)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: Motion.hover)) {
                isHovered = hovering
            }
        }
    }

    private var watchedToggle: some View {
        Button(action: onToggleWatched) {
            Image(systemName: isWatched ? "eye.fill" : "eye.slash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isWatched ? AppColor.buttonLabel : Color.secondary)
                .frame(width: 26, height: 24)
                .background(
                    isWatched ? AppColor.brand : Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverFeedback(scale: 1.05)
        .help(isWatched ? "Mark as Unwatched" : "Mark as Watched")
        .accessibilityLabel(
            isWatched
                ? "Mark \(episode.displayTitle) as unwatched"
                : "Mark \(episode.displayTitle) as watched"
        )
    }

    private var thumbnail: some View {
        Color.clear
            .frame(width: 96, height: 54)
            .overlay {
                RemoteImage(url: episode.thumbnailURL ?? fallbackImageURL, contentMode: .fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(AppColor.stroke, lineWidth: 0.5)
            }
            .opacity(isWatched ? 0.55 : 1)
    }

    private var subtitle: String {
        var parts: [String] = []
        if episode.hasTitle {
            parts.append("Episode \(episode.displayNumber)")
        }
        if let duration = episode.durationText {
            parts.append(duration)
        }
        if let airDate = episode.airDateText {
            parts.append(airDate)
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}

private struct EpisodeCard: View {
    let episode: Episode
    let fallbackImageURL: URL?
    let isWatched: Bool
    let progress: PlaybackProgress?
    let onPlay: () -> Void
    let onToggleWatched: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onPlay) {
                Color.clear
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay {
                        RemoteImage(url: episode.thumbnailURL ?? fallbackImageURL, contentMode: .fill)
                    }
                    .overlay { scrim }
                    .overlay(alignment: .center) { playGlyph }
                    .overlay(alignment: .bottom) { progressBar }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(AppColor.stroke, lineWidth: 0.5)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isWatched ? 0.6 : 1)
            .accessibilityLabel(
                progress.map { "Resume \(episode.displayTitle), \($0.timecode)" }
                    ?? "Play \(episode.displayTitle)"
            )

            watchedToggle
                .padding(Spacing.xs)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: Motion.hover)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isHovered && !reduceMotion ? 1.02 : 1)
    }

    private var watchedToggle: some View {
        Button(action: onToggleWatched) {
            Image(systemName: isWatched ? "eye.fill" : "eye.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isWatched ? AppColor.buttonLabel : .white)
                .frame(width: 26, height: 26)
                .background {
                    if isWatched {
                        Circle().fill(AppColor.brand)
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
                .overlay {
                    Circle().strokeBorder(AppColor.stroke, lineWidth: 0.5)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isHovered || isWatched ? 1 : 0)
        .allowsHitTesting(isHovered || isWatched)
        .help(isWatched ? "Mark as Unwatched" : "Mark as Watched")
        .accessibilityLabel(
            isWatched
                ? "Mark \(episode.displayTitle) as unwatched"
                : "Mark \(episode.displayTitle) as watched"
        )
    }

    private var scrim: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.25),
                    .init(color: .black.opacity(0.8), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 2) {
                Text("Episode \(episode.displayNumber)")
                    .font(AppFont.cardMeta.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                if episode.hasTitle {
                    Text(episode.displayTitle)
                        .font(AppFont.cardTitle)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if let progress {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "play.fill")
                        Text(progress.timecode)
                    }
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.white.opacity(0.75))
                } else if let duration = episode.durationText {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "clock")
                        Text(duration)
                    }
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(Spacing.sm)
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        if let progress {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.white.opacity(0.25))
                    Rectangle()
                        .fill(AppColor.brandGradient)
                        .frame(width: max(3, geometry.size.width * progress.fraction))
                }
            }
            .frame(height: 3)
        }
    }

    @ViewBuilder
    private var playGlyph: some View {
        if isHovered {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white)
                .shadow(radius: 8)
                .transition(.opacity)
        }
    }
}

private struct CompactEpisodeError: View {
    let error: CatalogError
    var onRetry: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.errorDescription ?? "Episode metadata is unavailable")
                    .font(AppFont.cardTitle)
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button("Retry", action: onRetry)
                .controlSize(.small)
                .hoverFeedback(scale: 1.03)
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
#Preview("Anime Details") {
    let environment = AppEnvironment.preview()
    NavigationStack {
        AnimeDetailsView(animeID: "7442", environment: environment)
    }
    .environment(environment)
    .frame(width: 1000, height: 820)
}
#endif
