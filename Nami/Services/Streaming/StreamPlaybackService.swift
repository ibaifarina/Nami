import Foundation

/// Result of asking for a validated, playable stream for a candidate.
enum StreamLookupResult: Equatable, Sendable {
    /// A resolved stream that passed (or could not disprove) validation.
    case ready(ResolvedStream)
    /// This candidate cannot be played; try the next preferred candidate.
    case unavailable
    /// Real-Debrid itself is unavailable or the account is restricted, so
    /// trying another source will not help.
    case blocked(DebridError?)
}

@MainActor
protocol StreamPlaybackProviding: AnyObject {
    /// Warms and validates the most preferred candidates in the background.
    func prefetch(anime: Anime, episode: Episode, candidates: [StreamCandidate])
    /// Returns a validated stream for a candidate, reusing prefetched work.
    func stream(
        for candidate: StreamCandidate,
        fileID: Int?,
        anime: Anime,
        episode: Episode
    ) async -> StreamLookupResult
    /// Records that playback failed on this candidate's stream so it is not
    /// retried immediately.
    func markPlaybackFailed(for candidate: StreamCandidate, anime: Anime, episode: Episode)
    /// Drops every cached and in-flight lookup.
    func clear()
}

extension StreamPlaybackProviding {
    /// Convenience for the common case where automatic file selection applies.
    func stream(
        for candidate: StreamCandidate,
        anime: Anime,
        episode: Episode
    ) async -> StreamLookupResult {
        await stream(for: candidate, fileID: nil, anime: anime, episode: episode)
    }
}

/// Resolves and validates streams with an eye on latency:
///
/// - The detail page prefetches a few top candidates with small bounded
///   concurrency, so pressing Play usually finds a validated stream instantly.
/// - Validation verdicts are cached per detail page/session; known-bad
///   candidates are remembered temporarily so fallback never retries them.
/// - A resolve that fails for an account-level reason stops the fallback chain
///   instead of hammering Real-Debrid with candidates that cannot work.
@MainActor
final class StreamPlaybackService: StreamPlaybackProviding {
    private struct Key: Hashable {
        let animeID: String
        let episodeNumber: Int
        let candidateID: String
        let fileID: Int?
    }

    private struct ValidEntry {
        let stream: ResolvedStream
        let savedAt: Date
    }

    /// Reference wrapper so an awaiter can tell whether it still owns the
    /// in-flight entry when it finishes.
    private final class Lookup {
        let task: Task<StreamLookupResult, Never>

        init(_ task: Task<StreamLookupResult, Never>) {
            self.task = task
        }
    }

    private let resolver: SourceResolver
    private let validator: any StreamValidating
    private let validationTTL: TimeInterval
    private let invalidationTTL: TimeInterval
    private let prefetchLimit: Int
    private let prefetchConcurrency: Int

    private var valid: [Key: ValidEntry] = [:]
    private var invalid: [Key: Date] = [:]
    private var lookups: [Key: Lookup] = [:]
    private var prefetchTask: Task<Void, Never>?
    private var generation = 0

    init(
        resolver: SourceResolver,
        validator: any StreamValidating,
        validationTTL: TimeInterval = 900,
        invalidationTTL: TimeInterval = 600,
        prefetchLimit: Int = 3,
        prefetchConcurrency: Int = 2
    ) {
        self.resolver = resolver
        self.validator = validator
        self.validationTTL = validationTTL
        self.invalidationTTL = invalidationTTL
        self.prefetchLimit = max(1, prefetchLimit)
        self.prefetchConcurrency = max(1, prefetchConcurrency)
    }

    // MARK: - Prefetch

    func prefetch(anime: Anime, episode: Episode, candidates: [StreamCandidate]) {
        prefetchTask?.cancel()
        prefetchTask = nil
        // Only warm candidates that resolve instantly. Probing an uncached
        // torrent would start a Real-Debrid download the user never asked for.
        let top = candidates
            .filter { $0.debridStatus == .cached || $0.directURL != nil }
            .prefix(prefetchLimit)
            .map { $0 }
        guard !top.isEmpty else { return }
        let token = generation
        prefetchTask = Task { [weak self] in
            await self?.prefetch(top, anime: anime, episode: episode, token: token)
        }
    }

    private func prefetch(
        _ candidates: [StreamCandidate],
        anime: Anime,
        episode: Episode,
        token: Int
    ) async {
        await withTaskGroup(of: Void.self) { group in
            var iterator = candidates.makeIterator()
            var started = 0
            while started < prefetchConcurrency, let candidate = iterator.next() {
                started += 1
                group.addTask { [weak self] in
                    guard let self else { return }
                    _ = await self.lookup(candidate, fileID: nil, anime: anime, episode: episode)
                }
            }
            while await group.next() != nil {
                guard
                    token == generation,
                    !Task.isCancelled,
                    let candidate = iterator.next()
                else {
                    continue
                }
                group.addTask { [weak self] in
                    guard let self else { return }
                    _ = await self.lookup(candidate, fileID: nil, anime: anime, episode: episode)
                }
            }
        }
    }

    // MARK: - Lookup

    func stream(
        for candidate: StreamCandidate,
        fileID: Int?,
        anime: Anime,
        episode: Episode
    ) async -> StreamLookupResult {
        await lookup(candidate, fileID: fileID, anime: anime, episode: episode)
    }

    func markPlaybackFailed(
        for candidate: StreamCandidate,
        anime: Anime,
        episode: Episode
    ) {
        let key = key(for: candidate, fileID: nil, anime: anime, episode: episode)
        rememberInvalid(key)
        lookups[key]?.task.cancel()
        lookups[key] = nil
        let resolver = self.resolver
        Task { await resolver.invalidate(anime: anime, episode: episode) }
    }

    func clear() {
        generation += 1
        prefetchTask?.cancel()
        prefetchTask = nil
        for lookup in lookups.values {
            lookup.task.cancel()
        }
        lookups.removeAll()
        valid.removeAll()
        invalid.removeAll()
    }

    // MARK: - Internals

    private func lookup(
        _ candidate: StreamCandidate,
        fileID: Int?,
        anime: Anime,
        episode: Episode
    ) async -> StreamLookupResult {
        let key = key(for: candidate, fileID: fileID, anime: anime, episode: episode)

        if let entry = valid[key], isFresh(entry.savedAt, ttl: validationTTL) {
            return .ready(entry.stream)
        }
        valid[key] = nil

        if let stamped = invalid[key], isFresh(stamped, ttl: invalidationTTL) {
            return .unavailable
        }
        invalid[key] = nil

        if let existing = lookups[key] {
            return await existing.task.value
        }

        let token = generation
        let lookup = Lookup(
            Task { [weak self] () -> StreamLookupResult in
                guard let self, token == self.generation else { return .unavailable }
                return await self.resolveAndValidate(
                    candidate,
                    fileID: fileID,
                    anime: anime,
                    episode: episode,
                    key: key
                )
            }
        )
        lookups[key] = lookup
        let result = await lookup.task.value
        if lookups[key] === lookup {
            lookups[key] = nil
        }
        return result
    }

    private func resolveAndValidate(
        _ candidate: StreamCandidate,
        fileID: Int?,
        anime: Anime,
        episode: Episode,
        key: Key
    ) async -> StreamLookupResult {
        guard !Task.isCancelled else { return .unavailable }
        let context = StreamValidationContext(
            expectedSizeBytes: candidate.sizeBytes,
            expectedDurationMinutes: episode.durationMinutes ?? anime.durationMinutes
        )

        // A previously resolved URL for this exact candidate is far cheaper to
        // re-check than a full Real-Debrid round trip.
        if let cached = await resolver.cachedStream(
            anime: anime,
            episode: episode,
            candidateID: candidate.id
        ), fileID == nil || cached.fileID == fileID {
            guard !Task.isCancelled else { return .unavailable }
            switch await validator.validate(cached, context: context) {
            case .playable, .uncertain:
                valid[key] = ValidEntry(stream: cached, savedAt: Date())
                return .ready(cached)
            case .candidateInvalid:
                await resolver.invalidate(anime: anime, episode: episode)
            case .accountIssue(let issue):
                return .blocked(debridError(for: issue))
            case .transient:
                break
            }
        }

        do {
            let stream = try await resolver.resolveUncached(candidate, fileID: fileID)
            guard !Task.isCancelled else { return .unavailable }
            switch await validator.validate(stream, context: context) {
            case .playable:
                await rememberReady(stream, candidate: candidate, anime: anime, episode: episode, key: key)
                return .ready(stream)
            case .uncertain:
                // Validation could not decide; let the player try instead of
                // blocking playback.
                await rememberReady(stream, candidate: candidate, anime: anime, episode: episode, key: key)
                return .ready(stream)
            case .candidateInvalid(let issue):
                AppLogger.playback.debug(
                    "Skipping invalid stream for \(candidate.id, privacy: .public): \(String(describing: issue.kind), privacy: .public)"
                )
                rememberInvalid(key)
                return .unavailable
            case .transient(let issue):
                AppLogger.playback.debug(
                    "Transient stream failure for \(candidate.id, privacy: .public): \(String(describing: issue.kind), privacy: .public)"
                )
                return .unavailable
            case .accountIssue(let issue):
                return .blocked(debridError(for: issue))
            }
        } catch is CancellationError {
            return .unavailable
        } catch {
            let mapped = DebridError.map(error)
            if mapped.isSourceSpecific {
                rememberInvalid(key)
                return .unavailable
            }
            if mapped.isGlobal {
                return .blocked(mapped)
            }
            return .unavailable
        }
    }

    private func rememberReady(
        _ stream: ResolvedStream,
        candidate: StreamCandidate,
        anime: Anime,
        episode: Episode,
        key: Key
    ) async {
        valid[key] = ValidEntry(stream: stream, savedAt: Date())
        await resolver.store(
            stream,
            candidateID: candidate.id,
            anime: anime,
            episode: episode
        )
    }

    private func rememberInvalid(_ key: Key) {
        invalid[key] = Date()
        valid[key] = nil
    }

    private func key(
        for candidate: StreamCandidate,
        fileID: Int?,
        anime: Anime,
        episode: Episode
    ) -> Key {
        Key(
            animeID: anime.id,
            episodeNumber: episode.number,
            candidateID: candidate.id,
            fileID: fileID
        )
    }

    private func isFresh(_ date: Date, ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(date) <= ttl
    }

    private func debridError(for issue: StreamValidationIssue) -> DebridError? {
        switch issue.kind {
        case .unauthorized:
            .unauthorized
        case .accountIssue:
            .accountLocked
        case .premiumRequired:
            .notPremium
        case .trafficExhausted:
            .trafficExceeded
        case .fairUseLimit:
            .fairUseLimit
        case .rateLimited:
            .rateLimited
        default:
            nil
        }
    }
}
