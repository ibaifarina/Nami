import Foundation
import Testing
@testable import Nami

@MainActor
struct StreamPlaybackServiceTests {
    private struct Setup {
        let service: StreamPlaybackService
        let debrid: StubDebridService
        let validator: StubStreamValidator
        let defaults: UserDefaults
        let suite: String
    }

    private var anime: Anime { SampleCatalog.anime[0] }

    private var resolvedURL: URL { testURL("https://resolved.example/video.mp4") }

    private func episode(_ number: Int) -> Episode {
        Episode(
            id: "\(anime.id)-\(number)",
            animeID: anime.id,
            number: number,
            relativeNumber: number,
            seasonNumber: 1,
            durationMinutes: anime.durationMinutes
        )
    }

    private func candidate(
        _ id: String,
        availability: DebridAvailability = .cached
    ) -> StreamCandidate {
        StreamCandidate(
            id: id,
            addonID: "one",
            addonName: "One",
            displayTitle: "Sousou no Frieren - 07 [1080p] BluRay HEVC",
            infoHash: id,
            resolution: .p1080,
            codec: .hevc,
            source: .bluRay,
            sizeBytes: 1_400_000_000,
            seeders: 50,
            debridStatus: availability,
            episodeMatchConfidence: 1
        )
    }

    private func makeSetup(
        validator: StubStreamValidator = StubStreamValidator(),
        validationTTL: TimeInterval = 900,
        invalidationTTL: TimeInterval = 600,
        prefetchLimit: Int = 3,
        prefetchConcurrency: Int = 2
    ) throws -> Setup {
        let suite = "stream-playback-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let preferences = PreferencesStore(defaults: defaults)
        let debrid = StubDebridService()
        let resolver = SourceResolver(
            debrid: debrid,
            cache: ResolvedStreamCache(fileURL: nil),
            preferences: preferences
        )
        let service = StreamPlaybackService(
            resolver: resolver,
            validator: validator,
            validationTTL: validationTTL,
            invalidationTTL: invalidationTTL,
            prefetchLimit: prefetchLimit,
            prefetchConcurrency: prefetchConcurrency
        )
        return Setup(
            service: service,
            debrid: debrid,
            validator: validator,
            defaults: defaults,
            suite: suite
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () async -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func streamResolvesValidatesAndCaches() async throws {
        let setup = try makeSetup()
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        let candidate = candidate("aaaaaaaa")

        let first = await setup.service.stream(for: candidate, anime: anime, episode: episode(7))
        let second = await setup.service.stream(for: candidate, anime: anime, episode: episode(7))

        guard case .ready(let firstStream) = first, case .ready(let secondStream) = second else {
            Issue.record("Expected ready results")
            return
        }
        #expect(firstStream == secondStream)
        #expect(firstStream.url == resolvedURL)
        #expect(await setup.debrid.resolvedCandidateIDs == [candidate.id])
        #expect(await setup.validator.validatedURLs.count == 1)
    }

    @Test func prefetchSharesWorkWithPlaybackLookup() async throws {
        let setup = try makeSetup()
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        let candidate = candidate("aaaaaaaa")

        setup.service.prefetch(anime: anime, episode: episode(7), candidates: [candidate])
        let result = await setup.service.stream(for: candidate, anime: anime, episode: episode(7))

        guard case .ready = result else {
            Issue.record("Expected a ready result")
            return
        }
        #expect(await setup.debrid.resolvedCandidateIDs == [candidate.id])
    }

    @Test func prefetchValidatesOnlyTopCandidates() async throws {
        let setup = try makeSetup(prefetchLimit: 3, prefetchConcurrency: 2)
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        let candidates = (0..<6).map { candidate("candidate-\($0)") }

        setup.service.prefetch(anime: anime, episode: episode(7), candidates: candidates)
        await waitUntil { await setup.debrid.resolvedCandidateIDs.count >= 3 }

        #expect(await setup.debrid.resolvedCandidateIDs.count == 3)
    }

    @Test func explicitFileSelectionIsForwardedAndCachedPerFile() async throws {
        let setup = try makeSetup()
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        let candidate = candidate("aaaaaaaa")

        _ = await setup.service.stream(
            for: candidate,
            fileID: 3,
            anime: anime,
            episode: episode(7)
        )
        _ = await setup.service.stream(
            for: candidate,
            fileID: 3,
            anime: anime,
            episode: episode(7)
        )
        _ = await setup.service.stream(
            for: candidate,
            fileID: 4,
            anime: anime,
            episode: episode(7)
        )

        #expect(await setup.debrid.resolvedFileIDs == [3, 4])
    }

    @Test func prefetchSkipsUncachedTorrents() async throws {
        let setup = try makeSetup()
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        setup.service.prefetch(
            anime: anime,
            episode: episode(7),
            candidates: [candidate("uncached", availability: .notCached)]
        )
        try? await Task.sleep(for: .milliseconds(80))

        #expect(await setup.debrid.resolvedCandidateIDs.isEmpty)
    }

    @Test func invalidCandidateIsNotRetried() async throws {
        let validator = StubStreamValidator()
        await validator.setVerdict(
            .candidateInvalid(StreamValidationIssue(kind: .infringing)),
            for: resolvedURL
        )
        let setup = try makeSetup(validator: validator)
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        let candidate = candidate("aaaaaaaa")

        let first = await setup.service.stream(for: candidate, anime: anime, episode: episode(7))
        let second = await setup.service.stream(for: candidate, anime: anime, episode: episode(7))

        #expect(first == .unavailable)
        #expect(second == .unavailable)
        #expect(await setup.debrid.resolvedCandidateIDs == [candidate.id])
    }

    @Test func invalidCandidateIsRetriedAfterNegativeCacheExpires() async throws {
        let validator = StubStreamValidator()
        await validator.setVerdict(
            .candidateInvalid(StreamValidationIssue(kind: .unavailableFile)),
            for: resolvedURL
        )
        let setup = try makeSetup(validator: validator, invalidationTTL: 0.01)
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        let candidate = candidate("aaaaaaaa")

        _ = await setup.service.stream(for: candidate, anime: anime, episode: episode(7))
        try? await Task.sleep(for: .milliseconds(60))
        _ = await setup.service.stream(for: candidate, anime: anime, episode: episode(7))

        #expect(await setup.debrid.resolvedCandidateIDs.count == 2)
    }

    @Test func accountErrorBlocksFallback() async throws {
        let setup = try makeSetup()
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        await setup.debrid.configure(resolveError: .accountLocked)

        let result = await setup.service.stream(
            for: candidate("aaaaaaaa"),
            anime: anime,
            episode: episode(7)
        )

        #expect(result == .blocked(.accountLocked))
    }

    @Test func sourceSpecificResolveErrorMarksCandidateInvalid() async throws {
        let setup = try makeSetup()
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        await setup.debrid.configure(resolveError: .infringingContent)
        let candidate = candidate("aaaaaaaa")

        let first = await setup.service.stream(for: candidate, anime: anime, episode: episode(7))
        let second = await setup.service.stream(for: candidate, anime: anime, episode: episode(7))

        #expect(first == .unavailable)
        #expect(second == .unavailable)
        #expect(await setup.debrid.resolvedCandidateIDs == [candidate.id])
    }

    @Test func uncertainValidationStillPlays() async throws {
        let validator = StubStreamValidator(verdict: .uncertain)
        let setup = try makeSetup(validator: validator)
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        let result = await setup.service.stream(
            for: candidate("aaaaaaaa"),
            anime: anime,
            episode: episode(7)
        )

        guard case .ready(let stream) = result else {
            Issue.record("Expected a ready result")
            return
        }
        #expect(stream.url == resolvedURL)
    }

    @Test func markPlaybackFailedBlocksImmediateRetry() async throws {
        let setup = try makeSetup()
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        let candidate = candidate("aaaaaaaa")

        _ = await setup.service.stream(for: candidate, anime: anime, episode: episode(7))
        setup.service.markPlaybackFailed(for: candidate, anime: anime, episode: episode(7))
        let retry = await setup.service.stream(for: candidate, anime: anime, episode: episode(7))

        #expect(retry == .unavailable)
        #expect(await setup.debrid.resolvedCandidateIDs == [candidate.id])
    }
}
