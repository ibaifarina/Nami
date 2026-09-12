import Foundation
@testable import Nami

func testURL(_ string: String) -> URL {
    guard let url = URL(string: string) else {
        preconditionFailure("Invalid test URL: \(string)")
    }
    return url
}

actor MockHTTPClient: HTTPClient {
    typealias Handler = @Sendable (URLRequest) async throws -> Data

    private var handler: Handler
    private(set) var requestCount = 0
    private(set) var lastRequest: URLRequest?

    init(handler: @escaping Handler = { _ in Data() }) {
        self.handler = handler
    }

    func setHandler(_ handler: @escaping Handler) {
        self.handler = handler
    }

    func data(for request: URLRequest, maxBytes: Int) async throws -> Data {
        requestCount += 1
        lastRequest = request
        return try await handler(request)
    }
}

actor CallCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

actor StubDebridTokenProvider: DebridTokenProviding {
    private let value: String?

    init(token: String?) {
        value = token
    }

    func token() async -> String? {
        value
    }
}

actor StubDebridService: DebridService {
    var availabilityByCandidateID: [String: DebridAvailability] = [:]
    var filesByCandidateID: [String: [DebridFileInfo]] = [:]
    var checkError: DebridError?
    var resolveError: DebridError?
    var resolveURL: URL = testURL("https://resolved.example/video.mp4")
    var resolveURLByCandidateID: [String: URL] = [:]
    private(set) var checkedCandidateIDs: [String] = []
    private(set) var resolvedCandidateIDs: [String] = []
    private(set) var resolvedFileIDs: [Int?] = []

    func configure(availability: [String: DebridAvailability]) {
        availabilityByCandidateID = availability
    }

    func configure(files: [String: [DebridFileInfo]]) {
        filesByCandidateID = files
    }

    func configure(checkError: DebridError?) {
        self.checkError = checkError
    }

    func configure(resolveError: DebridError?) {
        self.resolveError = resolveError
    }

    func configure(resolveURLs: [String: URL]) {
        resolveURLByCandidateID = resolveURLs
    }

    func validateAccount() async throws -> DebridAccount {
        DebridAccount(
            id: 1,
            username: "tester",
            email: nil,
            type: .premium,
            premiumSecondsRemaining: 1_000,
            expiration: nil,
            points: nil
        )
    }

    func validateAccount(token: String) async throws -> DebridAccount {
        try await validateAccount()
    }

    func checkAvailability(_ candidates: [StreamCandidate]) async throws -> [DebridCheckResult] {
        if let checkError { throw checkError }
        checkedCandidateIDs = candidates.map(\.id)
        return candidates.map { candidate in
            DebridCheckResult(
                candidateID: candidate.id,
                availability: availabilityByCandidateID[candidate.id] ?? .unknown,
                files: filesByCandidateID[candidate.id] ?? []
            )
        }
    }

    func files(for candidate: StreamCandidate) async throws -> [DebridFileInfo] {
        filesByCandidateID[candidate.id] ?? []
    }

    func resolve(_ candidate: StreamCandidate, fileID: Int?) async throws -> ResolvedStream {
        resolvedCandidateIDs.append(candidate.id)
        resolvedFileIDs.append(fileID)
        if let resolveError { throw resolveError }
        return ResolvedStream(
            url: resolveURLByCandidateID[candidate.id] ?? resolveURL,
            filename: candidate.displayTitle,
            sizeBytes: candidate.sizeBytes,
            streamable: true,
            fileID: fileID ?? 1
        )
    }
}

actor StubStreamValidator: StreamValidating {
    private var defaultVerdict: StreamValidationVerdict
    private var verdictsByURL: [String: StreamValidationVerdict] = [:]
    private(set) var validatedURLs: [URL] = []

    init(verdict: StreamValidationVerdict = .playable) {
        defaultVerdict = verdict
    }

    func setVerdict(_ verdict: StreamValidationVerdict, for url: URL) {
        verdictsByURL[url.absoluteString] = verdict
    }

    func validate(
        _ stream: ResolvedStream,
        context: StreamValidationContext
    ) async -> StreamValidationVerdict {
        validatedURLs.append(stream.url)
        return verdictsByURL[stream.url.absoluteString] ?? defaultVerdict
    }
}

struct StubMediaRepository: MediaRepository {
    var details: [String: AnimeDetails] = [:]
    var popularResult: [Anime] = []
    var topRatedResult: [Anime] = []
    var airingResult: [Anime] = []
    var upcomingResult: [Anime] = []
    var recentResult: [Anime] = []
    var pages: [[Anime]] = []
    var error: CatalogError?
    var onDiscover: @Sendable () async -> Void = {}

    func anime(id: String) async throws -> AnimeDetails {
        if let details = details[id] { return details }
        if let anime = SampleCatalog.anime(withID: id) {
            return AnimeDetails(anime: anime, relations: [])
        }
        throw CatalogError.notFound
    }

    func search(query: String, page: Int) async throws -> [Anime] {
        try await discover(query: query, filters: DiscoverFilters(), page: page)
    }

    func popular(page: Int) async throws -> [Anime] {
        page == 0 ? popularResult : []
    }

    func topRated(page: Int) async throws -> [Anime] {
        page == 0 ? topRatedResult : []
    }

    func currentlyAiring(page: Int) async throws -> [Anime] {
        page == 0 ? airingResult : []
    }

    func upcoming(page: Int) async throws -> [Anime] {
        page == 0 ? upcomingResult : []
    }

    func recentlyReleased(page: Int) async throws -> [Anime] {
        page == 0 ? recentResult : []
    }

    func discover(query: String?, filters: DiscoverFilters, page: Int) async throws -> [Anime] {
        await onDiscover()
        if let error { throw error }
        guard page >= 0, page < pages.count else { return [] }
        return pages[page]
    }
}

struct StubEpisodeRepository: EpisodeRepository {
    var episodesByAnimeID: [String: [Episode]] = [:]
    var error: CatalogError?

    func episodes(forAnimeID id: String) async throws -> [Episode] {
        if let error { throw error }
        return episodesByAnimeID[id] ?? []
    }
}

actor StubLibraryRepository: LibraryRepository {
    private var storage: [String: LibraryEntry]
    private var error: CatalogError?

    init(entries: [LibraryEntry] = [], error: CatalogError? = nil) {
        storage = Dictionary(entries.map { ($0.animeID, $0) }, uniquingKeysWith: { first, _ in first })
        self.error = error
    }

    func configure(error: CatalogError?) {
        self.error = error
    }

    func entries() async throws -> [LibraryEntry] {
        if let error { throw error }
        return storage.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    func entry(animeID: String) async throws -> LibraryEntry? {
        if let error { throw error }
        return storage[animeID]
    }

    @discardableResult
    func update(
        anime: Anime,
        status: LibraryStatus,
        progress: Int?
    ) async throws -> LibraryEntry {
        if let error { throw error }
        let entry = LibraryEntry(
            animeID: anime.id,
            status: status,
            progress: progress ?? storage[anime.id]?.progress ?? 0,
            updatedAt: Date(),
            anime: anime
        )
        storage[anime.id] = entry
        return entry
    }

    func remove(animeID: String) async throws {
        if let error { throw error }
        storage[animeID] = nil
    }
}
