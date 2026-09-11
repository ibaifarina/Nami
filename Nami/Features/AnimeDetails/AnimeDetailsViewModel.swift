import Foundation
import Observation

@MainActor
@Observable
final class AnimeDetailsViewModel {
    let animeID: String

    private let media: any MediaRepository
    private let episodeRepository: any EpisodeRepository
    private let progressStore: any PlaybackProgressStore
    private let library: any LibraryRepository
    private let grouping: SeriesGroupingService

    var state: LoadingState<AnimeDetails> = .idle
    var episodesState: LoadingState<[Episode]> = .idle
    var series: AnimeSeries?
    var selectedInstallmentID: String?
    var progress: PlaybackProgress?
    var watchedEpisodeNumbers: Set<Int> = []
    var libraryEntry: LibraryEntry?
    var libraryError: String?
    var isUpdatingLibrary = false

    private var absoluteEpisodeOffset = 0

    init(environment: AppEnvironment, animeID: String) {
        self.animeID = animeID
        media = environment.media
        episodeRepository = environment.episodes
        progressStore = environment.progress
        library = environment.library
        grouping = SeriesGroupingService(repository: environment.media)
    }

    init(
        animeID: String,
        media: any MediaRepository,
        episodeRepository: any EpisodeRepository,
        progressStore: any PlaybackProgressStore,
        library: any LibraryRepository,
        grouping: SeriesGroupingService? = nil
    ) {
        self.animeID = animeID
        self.media = media
        self.episodeRepository = episodeRepository
        self.progressStore = progressStore
        self.library = library
        self.grouping = grouping ?? SeriesGroupingService(repository: media)
    }

    var details: AnimeDetails? { state.value }

    var selectedInstallment: AnimeInstallment? {
        guard let series else { return nil }
        let id = selectedInstallmentID ?? animeID
        return series.installment(id: id) ?? series.installments.first
    }

    var selectedAnime: Anime? {
        selectedInstallment?.anime ?? details?.anime
    }

    var episodes: [Episode] { episodesState.value ?? [] }

    var availableInstallments: [AnimeInstallment] {
        series?.installments ?? []
    }

    var related: [AnimeRelation] {
        series?.related ?? []
    }

    var continuesFromProgress: Bool {
        guard let progress, !progress.isCompleted else { return false }
        return progress.fraction < 0.95
    }

    var primaryActionTitle: String {
        if continuesFromProgress, let progress {
            return "Continue Episode \(progress.episodeNumber)"
        }
        return "Play Episode 1"
    }

    var primaryEpisode: Episode? {
        if let progress, continuesFromProgress {
            if let match = episodes.first(where: { $0.number == progress.episodeNumber }) {
                return match
            }
            if let selectedAnime {
                return Episode(
                    id: "\(selectedAnime.id)-\(progress.episodeNumber)",
                    animeID: selectedAnime.id,
                    number: progress.episodeNumber,
                    relativeNumber: progress.episodeNumber,
                    absoluteNumber: progress.absoluteEpisodeNumber,
                    durationMinutes: selectedAnime.durationMinutes
                )
            }
        }
        return episodes.first
    }

    func load() async {
        guard case .idle = state else { return }
        state = .loading
        episodesState = .loading

        async let detailsTask: Void = loadDetails()
        async let episodesTask: Void = loadEpisodes(for: animeID)
        async let contextTask: Void = loadLocalContext(for: animeID)
        _ = await (detailsTask, episodesTask, contextTask)

        // Re-derive absolute numbers once grouping is known.
        applyAbsoluteNumbers()
    }

    func retry() async {
        state = .idle
        episodesState = .idle
        series = nil
        await load()
    }

    func selectInstallment(_ installment: AnimeInstallment) {
        guard installment.id != selectedInstallmentID else { return }
        selectedInstallmentID = installment.id
        absoluteEpisodeOffset = installment.absoluteEpisodeOffset
        episodesState = .loading
        progress = nil
        watchedEpisodeNumbers = []
        libraryEntry = nil
        Task { [weak self] in
            guard let self else { return }
            await self.loadEpisodes(for: installment.id)
            await self.loadLocalContext(for: installment.id)
        }
    }

    func retryEpisodes() async {
        let id = selectedInstallmentID ?? animeID
        await loadEpisodes(for: id)
    }

    func setLibraryStatus(_ status: LibraryStatus) async {
        guard let anime = selectedAnime else { return }
        isUpdatingLibrary = true
        defer { isUpdatingLibrary = false }
        do {
            libraryEntry = try await library.update(
                anime: anime,
                status: status,
                progress: libraryEntry?.progress
            )
            libraryError = nil
        } catch is CancellationError {
            return
        } catch {
            libraryError = CatalogError.map(error).errorDescription
        }
    }

    func removeFromLibrary() async {
        guard let anime = selectedAnime else { return }
        isUpdatingLibrary = true
        defer { isUpdatingLibrary = false }
        do {
            try await library.remove(animeID: anime.id)
            libraryEntry = nil
            libraryError = nil
        } catch is CancellationError {
            return
        } catch {
            libraryError = CatalogError.map(error).errorDescription
        }
    }

    func markEpisodeWatched(_ episode: Episode) async {
        guard let anime = selectedAnime else { return }
        let progress = PlaybackProgress(
            animeID: anime.id,
            episodeID: episode.id,
            episodeNumber: episode.displayNumber,
            absoluteEpisodeNumber: episode.absoluteNumber,
            positionSeconds: 0,
            durationSeconds: 0,
            isCompleted: true,
            updatedAt: Date(),
            animeTitle: anime.displayTitle,
            posterURL: anime.posterURL,
            bannerURL: anime.bannerURL,
            episodeCount: anime.episodeCount
        )
        await progressStore.save(progress)
        watchedEpisodeNumbers.insert(episode.displayNumber)
        await refreshProgress(for: anime.id)
    }

    func markEpisodeUnwatched(_ episode: Episode) async {
        guard let anime = selectedAnime else { return }
        await progressStore.remove(animeID: anime.id, episodeNumber: episode.displayNumber)
        watchedEpisodeNumbers.remove(episode.displayNumber)
        await refreshProgress(for: anime.id)
    }

    func toggleEpisodeWatched(_ episode: Episode) async {
        if isWatched(episode) {
            await markEpisodeUnwatched(episode)
        } else {
            await markEpisodeWatched(episode)
        }
    }

    func isWatched(_ episode: Episode) -> Bool {
        watchedEpisodeNumbers.contains(episode.displayNumber)
    }

    /// The latest unfinished episode is the meaningful "Continue" target;
    /// manually marking an older episode watched must not hijack it.
    private func refreshProgress(for animeID: String) async {
        let history = await progressStore.progress(forAnimeID: animeID)
        guard (selectedInstallmentID ?? self.animeID) == animeID else { return }
        progress = history.first { !$0.isCompleted }
    }

    // MARK: - Loading

    private func loadDetails() async {
        do {
            let details = try await media.anime(id: animeID)
            guard !Task.isCancelled else { return }
            state = .loaded(details)
            let grouped = await grouping.series(for: details.anime, details: details)
            guard !Task.isCancelled else { return }
            series = grouped
            if selectedInstallmentID == nil {
                selectedInstallmentID = details.anime.id
                absoluteEpisodeOffset = grouped.installment(id: details.anime.id)?.absoluteEpisodeOffset ?? 0
            }
        } catch is CancellationError {
            return
        } catch {
            state = .failed(CatalogError.map(error))
        }
    }

    private func loadEpisodes(for id: String) async {
        episodesState = .loading
        do {
            let isAiring = state.value?.anime.status?.isAiring ?? false
            let episodes = try await episodeRepository.episodes(forAnimeID: id, isAiring: isAiring)
            guard !Task.isCancelled, (selectedInstallmentID ?? animeID) == id else { return }
            episodesState = .loaded(applyAbsoluteNumbers(to: episodes))
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, (selectedInstallmentID ?? animeID) == id else { return }
            episodesState = .failed(CatalogError.map(error))
        }
    }

    private func loadLocalContext(for id: String) async {
        async let historyTask: [PlaybackProgress] = progressStore.progress(forAnimeID: id)
        async let entryTask: LibraryEntry? = try? library.entry(animeID: id)
        let (history, entry) = await (historyTask, entryTask)
        guard !Task.isCancelled, (selectedInstallmentID ?? animeID) == id else { return }
        watchedEpisodeNumbers = Set(
            history.filter(\.isCompleted).map(\.episodeNumber)
        )
        progress = history.first { !$0.isCompleted }
        libraryEntry = entry
        libraryError = nil
    }

    private func applyAbsoluteNumbers() {
        if let installment = selectedInstallment {
            absoluteEpisodeOffset = installment.absoluteEpisodeOffset
        }
        if let episodes = episodesState.value {
            episodesState = .loaded(applyAbsoluteNumbers(to: episodes))
        }
    }

    private func applyAbsoluteNumbers(to episodes: [Episode]) -> [Episode] {
        guard absoluteEpisodeOffset > 0 else { return episodes }
        return episodes.map {
            $0.withAbsoluteNumber(absoluteEpisodeOffset + max($0.number, 1))
        }
    }
}
