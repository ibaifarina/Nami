import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppEnvironment {
    let preferences: PreferencesStore
    let router: AppRouter
    let progress: any PlaybackProgressStore
    let library: any LibraryRepository
    let addons: AddonRegistry
    let addonManager: AddonManager
    let addonInstaller: AddonInstallService
    let debrid: RealDebridService
    let debridAuth: RealDebridAuthService
    let streamDiscovery: StreamDiscoveryService
    let streamPreload: StreamPreloadService
    let sourceResolver: SourceResolver
    let playback: PlaybackCoordinator
    let playbackLaunch: PlaybackLaunchController
    let nextEpisode: NextEpisodeController
    let skipIntro: SkipIntroController
    let externalPlayers: ExternalPlayerService

    /// Increments whenever playback persists progress, letting open screens
    /// refresh watched state without a manual reload.
    private(set) var progressRevision = 0

    /// Kitsu is the canonical metadata provider.
    let media: any MediaRepository
    let episodes: any EpisodeRepository

    private let metadataCache: MetadataCache
    private let sourceCache: ResolvedStreamCache

    init(
        preferences: PreferencesStore = PreferencesStore(),
        progress: (any PlaybackProgressStore)? = nil,
        secureStore: (any SecureStore)? = nil,
        addonPersistence: (any AddonPersistence)? = nil,
        libraryPersistence: (any LibraryPersistence)? = nil,
        metadataCache: MetadataCache? = nil,
        resolvedStreamCache: ResolvedStreamCache? = nil,
        http: any HTTPClient = URLSessionHTTPClient()
    ) {
        self.preferences = preferences
        router = AppRouter()

        let container: ModelContainer? = (progress == nil || addonPersistence == nil)
            ? SwiftDataStack.makeContainer()
            : nil

        if let progress {
            self.progress = progress
        } else if let container {
            self.progress = SwiftDataPlaybackProgressStore(modelContainer: container)
        } else {
            AppLogger.persistence.error("Unable to create progress store; using in-memory store")
            self.progress = InMemoryPlaybackProgressStore()
        }

        let cache = metadataCache ?? MetadataCache()
        self.metadataCache = cache

        let resolvedSecureStore = secureStore ?? KeychainStore()

        let client = KitsuClient(http: http)
        media = KitsuMediaRepository(client: client, cache: cache)
        episodes = KitsuEpisodeRepository(client: client, cache: cache)
        library = LocalLibraryRepository(
            persistence: libraryPersistence ?? UserDefaultsLibraryPersistence()
        )

        let debridTokenStore = SecureTokenStore(
            secureStore: resolvedSecureStore,
            key: "realdebrid.accessToken"
        )
        let debridService = RealDebridService(tokenProvider: debridTokenStore)
        debrid = debridService
        debridAuth = RealDebridAuthService(service: debridService, tokenStore: debridTokenStore)

        let streamCache = resolvedStreamCache ?? ResolvedStreamCache()
        sourceCache = streamCache
        sourceResolver = SourceResolver(
            debrid: debridService,
            cache: streamCache,
            preferences: preferences
        )

        let persistence: any AddonPersistence
        if let providedPersistence = addonPersistence {
            persistence = providedPersistence
        } else if let container {
            persistence = SwiftDataAddonPersistence(container: container)
        } else {
            AppLogger.persistence.error("Unable to create addon store; using in-memory store")
            persistence = InMemoryAddonPersistence()
        }
        let registry = AddonRegistry(persistence: persistence)
        addons = registry
        let identityResolver = MediaIdentityResolver(client: client, cache: cache)
        let manager = AddonManager(identityResolver: identityResolver)
        addonManager = manager
        addonInstaller = AddonInstallService()
        let discoveryService = StreamDiscoveryService(addonManager: manager, debrid: debridService)
        streamDiscovery = discoveryService
        streamPreload = StreamPreloadService(
            discovery: discoveryService,
            episodes: episodes,
            preferences: preferences,
            registry: registry
        )

        let nextEpisodeController = NextEpisodeController(
            discovery: discoveryService,
            resolver: sourceResolver,
            preferences: preferences,
            registry: registry
        )
        nextEpisode = nextEpisodeController

        let skipIntroController = SkipIntroController(
            skipTimes: AniSkipService(http: http),
            identityResolver: identityResolver,
            preferences: preferences
        )
        skipIntro = skipIntroController

        let externalPlayerService = ExternalPlayerService()
        externalPlayers = externalPlayerService

        let coordinator = PlaybackCoordinator(
            engineKind: preferences.playbackEngine,
            progressStore: self.progress,
            preferences: preferences,
            library: library,
            externalPlayers: externalPlayerService
        )
        coordinator.onPlaybackTick = { [weak nextEpisodeController, weak skipIntroController] anime, episode, time, duration in
            nextEpisodeController?.progressTick(
                anime: anime,
                episode: episode,
                currentTime: time,
                duration: duration
            )
            skipIntroController?.progressTick(
                anime: anime,
                episode: episode,
                currentTime: time,
                duration: duration
            )
        }
        coordinator.onPlaybackEnded = { [weak nextEpisodeController] in
            nextEpisodeController?.playbackEnded()
        }
        coordinator.onSessionClosed = { [weak nextEpisodeController, weak skipIntroController] in
            nextEpisodeController?.reset()
            skipIntroController?.reset()
        }
        coordinator.onStreamFailed = { [weak streamCache] anime, episode in
            Task {
                await streamCache?.remove(animeID: anime.id, episodeNumber: episode.number)
            }
        }
        nextEpisodeController.startPlayback = { [weak coordinator] stream, anime, episode in
            coordinator?.start(
                stream: stream,
                anime: anime,
                episode: episode,
                startAt: nil
            )
        }
        skipIntroController.onSkip = { [weak coordinator] target in
            coordinator?.seek(to: target)
        }
        playback = coordinator
        playbackLaunch = PlaybackLaunchController(
            preload: streamPreload,
            resolver: sourceResolver,
            playback: coordinator
        )
        coordinator.onProgressSaved = { [weak self] _ in
            self?.progressRevision += 1
        }
    }

    func clearCaches() async {
        await metadataCache.removeAll()
        await sourceCache.removeAll()
        streamPreload.clear()
        ImageCache.shared.removeAll()
    }
}

#if DEBUG
extension AppEnvironment {
    /// Preview-only environment backed by isolated in-memory stores. It fetches
    /// the same live Kitsu data as the app; no placeholder content is injected.
    static func preview() -> AppEnvironment {
        let defaults = UserDefaults(suiteName: "com.auax.Nami.preview") ?? .standard
        return AppEnvironment(
            preferences: PreferencesStore(defaults: defaults),
            progress: InMemoryPlaybackProgressStore(),
            secureStore: InMemorySecureStore(),
            addonPersistence: InMemoryAddonPersistence(),
            libraryPersistence: InMemoryLibraryPersistence(),
            metadataCache: MetadataCache(directory: nil),
            resolvedStreamCache: ResolvedStreamCache(fileURL: nil)
        )
    }
}
#endif
