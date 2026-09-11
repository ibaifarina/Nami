import Foundation

/// Community-maintained intro/outro/recap timings from the AniSkip API.
///
/// AniSkip keys its timings by MyAnimeList anime ID and the episode number
/// within that MAL entry. Lookups are strictly best-effort: unavailable
/// episodes yield no intervals and playback never waits on the network.
actor AniSkipService {
    static let baseURL = URL(string: "https://api.aniskip.com/v2")!

    private let http: any HTTPClient
    private let timeout: TimeInterval
    private var cache: [String: [SkipInterval]] = [:]
    private var inFlight: [String: Task<[SkipInterval], Never>] = [:]

    init(http: any HTTPClient = URLSessionHTTPClient(), timeout: TimeInterval = 15) {
        self.http = http
        self.timeout = timeout
    }

    /// Returns known skip intervals for the episode, or an empty array when
    /// the API has no data (including 404s) or the request fails.
    func intervals(
        malID: Int,
        episodeNumber: Int,
        episodeLengthSeconds: Double? = nil
    ) async -> [SkipInterval] {
        let key = Self.cacheKey(
            malID: malID,
            episodeNumber: episodeNumber,
            episodeLengthSeconds: episodeLengthSeconds
        )
        if let cached = cache[key] {
            return cached
        }
        if let inFlight = inFlight[key] {
            return await inFlight.value
        }
        let http = self.http
        let timeout = self.timeout
        let task = Task<[SkipInterval], Never> {
            await Self.fetch(
                http: http,
                timeout: timeout,
                malID: malID,
                episodeNumber: episodeNumber,
                episodeLengthSeconds: episodeLengthSeconds
            )
        }
        inFlight[key] = task
        let intervals = await task.value
        inFlight[key] = nil
        cache[key] = intervals
        return intervals
    }

    static func makeURL(
        malID: Int,
        episodeNumber: Int,
        episodeLengthSeconds: Double?
    ) -> URL? {
        let endpoint = baseURL.appending(path: "skip-times/\(malID)/\(episodeNumber)")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var queryItems = ["op", "ed", "recap", "mixed-op", "mixed-ed"].map {
            URLQueryItem(name: "types", value: $0)
        }
        if let episodeLengthSeconds, episodeLengthSeconds.isFinite, episodeLengthSeconds > 0 {
            queryItems.append(
                URLQueryItem(
                    name: "episodeLength",
                    value: String(Int(episodeLengthSeconds.rounded()))
                )
            )
        }
        components.queryItems = queryItems
        return components.url
    }

    private static func cacheKey(
        malID: Int,
        episodeNumber: Int,
        episodeLengthSeconds: Double?
    ) -> String {
        let length = episodeLengthSeconds.flatMap { $0.isFinite && $0 > 0 ? Int($0.rounded()) : nil }
        return "\(malID)-\(episodeNumber)-\(length.map(String.init) ?? "unknown")"
    }

    private static func fetch(
        http: any HTTPClient,
        timeout: TimeInterval,
        malID: Int,
        episodeNumber: Int,
        episodeLengthSeconds: Double?
    ) async -> [SkipInterval] {
        guard
            let url = makeURL(
                malID: malID,
                episodeNumber: episodeNumber,
                episodeLengthSeconds: episodeLengthSeconds
            )
        else {
            return []
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let data = try await http.data(for: request, maxBytes: 1_000_000)
            let response = try JSONDecoder().decode(AniSkipResponse.self, from: data)
            guard response.found else { return [] }
            return (response.results ?? []).compactMap(\.skipInterval)
        } catch let error as HTTPError {
            if case .httpStatus(let code, _) = error, code == 400 || code == 404 {
                return []
            }
            AppLogger.playback.debug("AniSkip lookup failed: \(error.localizedDescription, privacy: .public)")
            return []
        } catch {
            AppLogger.playback.debug("AniSkip lookup failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

struct AniSkipResponse: Decodable, Sendable {
    let found: Bool
    let results: [AniSkipResult]?

    struct AniSkipResult: Decodable, Sendable {
        let interval: AniSkipInterval
        let skipType: String

        var skipInterval: SkipInterval? {
            guard
                let kind = SkipInterval.Kind(rawValue: skipType.lowercased()),
                interval.startTime.isFinite,
                interval.endTime.isFinite,
                interval.startTime >= 0,
                interval.endTime > interval.startTime
            else {
                return nil
            }
            return SkipInterval(
                kind: kind,
                startSeconds: interval.startTime,
                endSeconds: interval.endTime
            )
        }
    }

    struct AniSkipInterval: Decodable, Sendable {
        let startTime: Double
        let endTime: Double
    }
}
