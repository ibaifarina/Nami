import Foundation

/// Resolves stream candidates into playable URLs and reuses recently
/// resolved sources.
///
/// Every catalog entry point that starts playback resolves through this type,
/// so returning to a partially watched episode can reuse the URL that was
/// stored when playback last started instead of repeating addon discovery and
/// debrid resolution.
@MainActor
final class SourceResolver {
    private let debrid: any DebridService
    private let cache: ResolvedStreamCache
    private let preferences: PreferencesStore

    init(
        debrid: any DebridService,
        cache: ResolvedStreamCache,
        preferences: PreferencesStore
    ) {
        self.debrid = debrid
        self.cache = cache
        self.preferences = preferences
    }

    /// The cached source for an episode, when source caching is enabled and a
    /// fresh entry exists. When `candidateID` is provided the entry must match
    /// that candidate.
    func cachedStream(
        anime: Anime,
        episode: Episode,
        candidateID: String? = nil
    ) async -> ResolvedStream? {
        guard preferences.cacheResolvedSources else { return nil }
        return await cache.stream(
            animeID: anime.id,
            episodeNumber: episode.number,
            candidateID: candidateID
        )
    }

    /// Returns the cached source when one matches the candidate, otherwise
    /// resolves it through the debrid service and caches the result.
    func resolve(
        _ candidate: StreamCandidate,
        anime: Anime,
        episode: Episode
    ) async throws -> ResolvedStream {
        if let cached = await cachedStream(anime: anime, episode: episode, candidateID: candidate.id) {
            return cached
        }
        let stream = try await debrid.resolve(candidate)
        if preferences.cacheResolvedSources {
            await cache.store(
                stream,
                candidateID: candidate.id,
                animeID: anime.id,
                episodeNumber: episode.number
            )
        }
        return stream
    }

    /// Drops the cached source for an episode. Called when playback of a
    /// cached URL fails so the next attempt resolves a fresh source.
    func invalidate(anime: Anime, episode: Episode) async {
        await cache.remove(animeID: anime.id, episodeNumber: episode.number)
    }
}
