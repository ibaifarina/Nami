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

    /// Lists the files inside a torrent candidate so a caller can offer an
    /// explicit choice when automatic file selection is ambiguous, such as a
    /// movie release split into multiple parts.
    func files(for candidate: StreamCandidate) async throws -> [DebridFileInfo] {
        try await debrid.files(for: candidate)
    }

    /// Returns the cached source when one matches the candidate, otherwise
    /// resolves it through the debrid service and caches the result.
    func resolve(
        _ candidate: StreamCandidate,
        anime: Anime,
        episode: Episode,
        fileID: Int? = nil
    ) async throws -> ResolvedStream {
        if let cached = await cachedStream(anime: anime, episode: episode, candidateID: candidate.id),
           fileID == nil || cached.fileID == fileID {
            return cached
        }
        let stream = try await resolveUncached(candidate, fileID: fileID)
        await store(stream, candidateID: candidate.id, anime: anime, episode: episode)
        return stream
    }

    /// Resolves through the debrid service without reading or writing the
    /// persistent source cache. Callers that validate several candidates
    /// before choosing one can keep the disk cache focused on the winner.
    func resolveUncached(
        _ candidate: StreamCandidate,
        fileID: Int? = nil
    ) async throws -> ResolvedStream {
        try await debrid.resolve(candidate, fileID: fileID)
    }

    /// Persists a resolved source so returning to the episode can reuse it.
    func store(
        _ stream: ResolvedStream,
        candidateID: String,
        anime: Anime,
        episode: Episode
    ) async {
        guard preferences.cacheResolvedSources else { return }
        await cache.store(
            stream,
            candidateID: candidateID,
            animeID: anime.id,
            episodeNumber: episode.number
        )
    }

    /// Drops the cached source for an episode. Called when playback of a
    /// cached URL fails so the next attempt resolves a fresh source.
    func invalidate(anime: Anime, episode: Episode) async {
        await cache.remove(animeID: anime.id, episodeNumber: episode.number)
    }
}
