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
    let playback: PlaybackCoordinator
    let nextEpisode: NextEpisodeController

    /// Kitsu is the canonical metadata provider.
    let media: any MediaRepository
    let episodes: any EpisodeRepository

    private let metadataCache: MetadataCache

    init(
        preferences: PreferencesStore = PreferencesStore(),
        progress: (any PlaybackProgressStore)? = nil,
        secureStore: (any SecureStore)? = nil,
        addonPersistence: (any AddonPersistence)? = nil,
        libraryPersistence: (any LibraryPersistence)? = nil,
        metadataCache: MetadataCache? = nil,
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

        let nextEpisodeController = NextEpisodeController(
            discovery: discoveryService,
            debrid: debridService,
            preferences: preferences,
            registry: registry
        )
        nextEpisode = nextEpisodeController

        let coordinator = PlaybackCoordinator(
            progressStore: self.progress,
            preferences: preferences
        )
        coordinator.onPlaybackTick = { [weak nextEpisodeController] anime, episode, time, duration in
            nextEpisodeController?.progressTick(
                anime: anime,
                episode: episode,
                currentTime: time,
                duration: duration
            )
        }
        coordinator.onPlaybackEnded = { [weak nextEpisodeController] in
            nextEpisodeController?.playbackEnded()
        }
        coordinator.onSessionClosed = { [weak nextEpisodeController] in
            nextEpisodeController?.reset()
        }
        nextEpisodeController.startPlayback = { [weak coordinator] stream, anime, episode in
            coordinator?.start(
                stream: stream,
                anime: anime,
                episode: episode,
                startAt: nil
            )
        }
        playback = coordinator
    }

    func clearCaches() async {
        await metadataCache.removeAll()
    }
}

#if DEBUG
extension AppEnvironment {
    /// Preview-only environment backed by isolated in-memory stores. It fetches
    /// the same live Kitsu data as the app; no placeholder content is injected.
    static func preview() -> AppEnvironment {
        let defaults = UserDefaults(suiteName: "com.auax.AnimeStreaming.preview") ?? .standard
        return AppEnvironment(
            preferences: PreferencesStore(defaults: defaults),
            progress: InMemoryPlaybackProgressStore(),
            secureStore: InMemorySecureStore(),
            addonPersistence: InMemoryAddonPersistence(),
            libraryPersistence: InMemoryLibraryPersistence(),
            metadataCache: MetadataCache(directory: nil)
        )
    }
}
#endif
