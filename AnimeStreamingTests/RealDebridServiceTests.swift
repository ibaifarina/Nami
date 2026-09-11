import Foundation
import Testing
@testable import AnimeStreaming

struct RealDebridServiceTests {
    private func makeService(
        token: String? = "rd-token",
        backend: DebridStubBackend,
        maxProbes: Int = 6,
        pollAttempts: Int = 3,
        pollInterval: Duration = .milliseconds(1)
    ) -> RealDebridService {
        let http = MockHTTPClient { request in
            try await backend.respond(to: request)
        }
        return RealDebridService(
            tokenProvider: StubDebridTokenProvider(token: token),
            http: http,
            maxAvailabilityProbes: maxProbes,
            resolvePollAttempts: pollAttempts,
            resolvePollInterval: pollInterval
        )
    }

    private func candidate(
        hash: String? = "aabbccddeeff00112233445566778899aabbccdd",
        magnet: String? = nil,
        url: String? = nil,
        targetEpisode: Int? = nil
    ) -> StreamCandidate {
        StreamCandidate(
            id: hash ?? url ?? "candidate",
            addonID: "addon",
            addonName: "Addon",
            displayTitle: "Show - 07 [1080p]",
            rawTitle: "Show - 07 [1080p]",
            infoHash: hash,
            magnetURI: magnet.flatMap { URL(string: $0) },
            directURL: url.flatMap { URL(string: $0) },
            parsedEpisode: ParsedEpisodeInfo(season: nil, episode: 7, isBatch: false, isSpecial: false),
            targetEpisode: targetEpisode
        )
    }

    // MARK: Account

    @Test func validatesPremiumAccount() async throws {
        let backend = DebridStubBackend()
        let service = makeService(backend: backend)

        let account = try await service.validateAccount()

        #expect(account.username == "tester")
        #expect(account.isPremium)
    }

    @Test func mapsUnauthorizedAccount() async {
        let backend = DebridStubBackend(
            userError: (status: 401, code: 8, message: "Bad token")
        )
        let service = makeService(backend: backend)

        await expectDebridError(service, matching: { $0 == .unauthorized }) {
            _ = try await service.validateAccount()
        }
    }

    @Test func mapsLockedAccount() async {
        let backend = DebridStubBackend(
            userError: (status: 403, code: 14, message: "Account locked")
        )
        let service = makeService(backend: backend)

        await expectDebridError(service, matching: { $0 == .accountLocked }) {
            _ = try await service.validateAccount()
        }
    }

    @Test func validateAccountWithoutTokenThrowsNotConfigured() async {
        let service = makeService(token: nil, backend: DebridStubBackend())

        await expectDebridError(service, matching: { $0 == .notConfigured }) {
            _ = try await service.validateAccount()
        }
    }

    @Test func buildsRequestsAgainstVersionedAPIBasePath() async throws {
        let backend = DebridStubBackend(
            infoStatuses: ["waiting_files_selection", "downloaded"],
            infoFiles: [(1, "/Show - 07.mkv", 1_400_000_000, 0)],
            infoLinks: ["https://real-debrid.com/dl/abc"]
        )
        let service = makeService(backend: backend)

        _ = try await service.validateAccount()
        _ = try await service.checkAvailability([candidate()])
        _ = try await service.resolve(candidate(targetEpisode: 7))

        let urls = await backend.requestURLs
        #expect(!urls.isEmpty)
        #expect(urls.allSatisfy { $0.hasPrefix("https://api.real-debrid.com/rest/1.0/") })
        #expect(urls.contains("https://api.real-debrid.com/rest/1.0/user"))
        #expect(urls.contains("https://api.real-debrid.com/rest/1.0/torrents/addMagnet"))
        #expect(urls.contains("https://api.real-debrid.com/rest/1.0/torrents/info/T1"))
        #expect(urls.contains("https://api.real-debrid.com/rest/1.0/unrestrict/link"))
    }

    @Test func findTorrentUsesVersionedListURL() async throws {
        let hash = "aabbccddeeff00112233445566778899aabbccdd"
        let backend = DebridStubBackend(
            addMagnetResult: .apiError(httpStatus: 400, code: 33, message: "Torrent already active"),
            infoStatuses: ["downloaded"],
            torrentList: [(id: "T9", hash: hash, status: "downloaded")]
        )
        let service = makeService(backend: backend)

        _ = try await service.checkAvailability([candidate()])

        let urls = await backend.requestURLs
        #expect(urls.contains("https://api.real-debrid.com/rest/1.0/torrents?limit=100"))
    }

    // MARK: Availability

    @Test func probeReportsCachedAndCleansUp() async throws {
        let backend = DebridStubBackend(
            infoStatuses: ["downloaded"],
            infoFiles: [(1, "/Show - 07.mkv", 1_400_000_000, 0)]
        )
        let service = makeService(backend: backend)

        let results = try await service.checkAvailability([candidate()])

        #expect(results.count == 1)
        #expect(results[0].availability == .cached)
        #expect(results[0].files.first?.path == "/Show - 07.mkv")

        let requests = await backend.requests
        #expect(requests.contains { $0.method == "POST" && $0.path == "/torrents/addMagnet" })
        #expect(requests.contains { $0.method == "POST" && $0.path.hasPrefix("/torrents/selectFiles/") })
        #expect(requests.contains { $0.method == "DELETE" && $0.path.hasPrefix("/torrents/delete/") })
    }

    @Test func probeReportsNotCachedForDownloadingTorrent() async throws {
        let backend = DebridStubBackend(infoStatuses: ["downloading"])
        let service = makeService(backend: backend)

        let results = try await service.checkAvailability([candidate()])

        #expect(results[0].availability == .notCached)
        let requests = await backend.requests
        #expect(requests.contains { $0.method == "DELETE" })
    }

    @Test func probeMapsInfringingContent() async throws {
        let backend = DebridStubBackend(
            addMagnetResult: .apiError(httpStatus: 451, code: 35, message: "infringing_file")
        )
        let service = makeService(backend: backend)

        let results = try await service.checkAvailability([candidate()])

        #expect(results[0].availability == .unavailable)
        let requests = await backend.requests
        #expect(!requests.contains { $0.method == "DELETE" })
        #expect(!requests.contains { $0.path.hasPrefix("/torrents/selectFiles/") })
    }

    @Test func probeUsesExistingTorrentWhenAlreadyActive() async throws {
        let hash = "aabbccddeeff00112233445566778899aabbccdd"
        let backend = DebridStubBackend(
            addMagnetResult: .apiError(httpStatus: 400, code: 33, message: "Torrent already active"),
            infoStatuses: ["downloaded"],
            torrentList: [(id: "T9", hash: hash, status: "downloaded")]
        )
        let service = makeService(backend: backend)

        let results = try await service.checkAvailability([candidate()])

        #expect(results[0].availability == .cached)
        let requests = await backend.requests
        #expect(!requests.contains { $0.method == "DELETE" })
    }

    @Test func probeLimitMarksRemainingUnknown() async throws {
        let backend = DebridStubBackend(infoStatuses: ["downloaded"])
        let service = makeService(backend: backend, maxProbes: 2)

        let candidates = [
            candidate(hash: "1111111111111111111111111111111111111111"),
            candidate(hash: "2222222222222222222222222222222222222222"),
            candidate(hash: "3333333333333333333333333333333333333333"),
        ]
        let results = try await service.checkAvailability(candidates)

        #expect(results.count == 3)
        #expect(results[0].availability == .cached)
        #expect(results[1].availability == .cached)
        #expect(results[2].availability == .unknown)

        let addCount = await backend.requests.filter { $0.path == "/torrents/addMagnet" }.count
        #expect(addCount == 2)
    }

    @Test func directURLCandidateIsUnknownWithoutNetwork() async throws {
        let backend = DebridStubBackend()
        let service = makeService(backend: backend)

        let results = try await service.checkAvailability([
            candidate(hash: nil, url: "https://cdn.example/video.mp4"),
        ])

        #expect(results[0].availability == .unknown)
        let requests = await backend.requests
        #expect(requests.isEmpty)
    }

    @Test func availabilityWithoutTokenThrowsNotConfigured() async {
        let service = makeService(token: nil, backend: DebridStubBackend())

        await expectDebridError(service, matching: { $0 == .notConfigured }) {
            _ = try await service.checkAvailability([candidate()])
        }
    }

    // MARK: Resolve

    @Test func resolvesCachedTorrentSelectingCorrectFile() async throws {
        let backend = DebridStubBackend(
            infoStatuses: ["waiting_files_selection", "downloaded"],
            infoFiles: [
                (1, "/Show - 01.mkv", 1_000_000_000, 0),
                (2, "/Show - 07.mkv", 1_400_000_000, 0),
                (3, "/Show - 07.srt", 20_000, 0),
                (4, "/sample.mkv", 5_000_000, 0),
            ],
            infoLinks: ["https://real-debrid.com/dl/abc"]
        )
        let service = makeService(backend: backend)

        let stream = try await service.resolve(candidate(targetEpisode: 7))

        #expect(stream.url.absoluteString == "https://download.real-debrid.com/file.mkv")
        #expect(stream.fileID == 2)
        #expect(stream.filename == "Show - 07.mkv")

        let bodies = await backend.formBodies
        #expect(bodies.contains { $0.contains("files=2") })

        let unrestrictedBody = bodies.first { $0.contains("link=") }
        #expect(unrestrictedBody?.contains("real-debrid.com") == true)
    }

    @Test func resolveUncachedLeavesTorrentPreparing() async throws {
        let backend = DebridStubBackend(
            infoStatuses: ["waiting_files_selection", "downloading"],
            infoFiles: [(1, "/Show - 07.mkv", 1_400_000_000, 0)]
        )
        let service = makeService(backend: backend)

        await expectDebridError(service, matching: { $0 == .itemNotReady }) {
            _ = try await service.resolve(candidate(targetEpisode: 7))
        }

        let requests = await backend.requests
        #expect(!requests.contains { $0.method == "DELETE" })
    }

    @Test func resolveFailsWhenBatchMissesEpisode() async throws {
        let backend = DebridStubBackend(
            infoStatuses: ["waiting_files_selection"],
            infoFiles: [
                (1, "/Show - 01.mkv", 1_000_000_000, 0),
                (2, "/Show - 02.mkv", 1_100_000_000, 0),
            ]
        )
        let service = makeService(backend: backend)

        await expectDebridError(service, matching: { error in
            if case .fileSelectionFailed = error { return true }
            return false
        }) {
            _ = try await service.resolve(candidate(targetEpisode: 7))
        }

        let requests = await backend.requests
        #expect(requests.contains { $0.method == "DELETE" })
    }

    @Test func resolveDirectURLBypassesDebrid() async throws {
        let backend = DebridStubBackend()
        let service = makeService(backend: backend)

        let stream = try await service.resolve(
            candidate(hash: nil, url: "https://cdn.example/video.mp4")
        )

        #expect(stream.url.absoluteString == "https://cdn.example/video.mp4")
        let requests = await backend.requests
        #expect(requests.isEmpty)
    }

    @Test func resolveWithoutPlayableSourceThrows() async {
        let service = makeService(backend: DebridStubBackend())

        await expectDebridError(service, matching: { $0 == .unresolvableCandidate }) {
            _ = try await service.resolve(candidate(hash: nil, url: nil))
        }
    }

    @Test func resolveMapsInfringingContent() async {
        let backend = DebridStubBackend(
            addMagnetResult: .apiError(httpStatus: 451, code: 35, message: "infringing_file")
        )
        let service = makeService(backend: backend)

        await expectDebridError(service, matching: { $0 == .infringingContent }) {
            _ = try await service.resolve(candidate())
        }
    }

    @Test func magnetIsBuiltFromHash() {
        let hash = "aabbccddeeff00112233445566778899aabbccdd"
        let magnet = RealDebridService.magnet(for: candidate())
        #expect(magnet == "magnet:?xt=urn:btih:\(hash)")

        let explicit = RealDebridService.magnet(
            for: candidate(hash: nil, magnet: "magnet:?xt=urn:btih:abc")
        )
        #expect(explicit == "magnet:?xt=urn:btih:abc")
    }

    private func expectDebridError(
        _ service: RealDebridService,
        matching predicate: @escaping (DebridError) -> Bool,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected a debrid error")
        } catch let error as DebridError {
            #expect(predicate(error), "Unexpected debrid error: \(error)")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
