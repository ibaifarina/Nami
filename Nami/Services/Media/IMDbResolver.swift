import Foundation

/// Resolves the IMDb identifier for an anime when Kitsu cannot provide one.
///
/// Most Stremio stream addons key their requests off IMDb IDs, but Kitsu's
/// mapping table rarely contains them. Resolution happens in two steps:
///
/// 1. An exact lookup through Kitsu's TheTVDB mapping (TVmaze lookup).
/// 2. A ranked title search against Stremio's Cinemeta metadata service,
///    matched against every known title and the premiere year.
///
/// Positive and negative results are cached so each anime is resolved at most
/// once per cache window.
actor IMDbResolver {
    struct Context: Sendable {
        var titles: [String]
        var year: Int?
        var isMovie: Bool

        init(titles: [String] = [], year: Int? = nil, isMovie: Bool = false) {
            self.titles = titles
            self.year = year
            self.isMovie = isMovie
        }
    }

    private let http: any HTTPClient
    private let cache: MetadataCache
    private let tvmazeBaseURL: URL
    private let cinemetaBaseURL: URL
    private let timeout: TimeInterval
    private let maxBytes: Int

    init(
        http: any HTTPClient = URLSessionHTTPClient(),
        cache: MetadataCache = MetadataCache(),
        tvmazeBaseURL: URL = URL(string: "https://api.tvmaze.com")!,
        cinemetaBaseURL: URL = URL(string: "https://v3-cinemeta.strem.io")!,
        timeout: TimeInterval = 6,
        maxBytes: Int = 2_000_000
    ) {
        self.http = http
        self.cache = cache
        self.tvmazeBaseURL = tvmazeBaseURL
        self.cinemetaBaseURL = cinemetaBaseURL
        self.timeout = timeout
        self.maxBytes = maxBytes
    }

    func imdbID(
        kitsuID: String,
        theTVDBID: String?,
        context: Context
    ) async -> String? {
        let key = "imdb:\(kitsuID)"
        if case .imdbID(let cached)? = await cache.payload(for: key) {
            return cached.isEmpty ? nil : cached
        }

        var resolved = await exactLookup(theTVDBID: theTVDBID)
        var attemptedSearch = false
        if resolved == nil, !context.titles.isEmpty {
            attemptedSearch = true
            resolved = await searchLookup(context: context)
        }

        // Only remember definitive misses; a call without a TheTVDB ID or any
        // title has not really looked yet and must stay retryable.
        let isDefinitive = resolved != nil || attemptedSearch || theTVDBID?.isEmpty == false
        if isDefinitive {
            await cache.store(
                .imdbID(resolved ?? ""),
                for: key,
                ttl: resolved == nil ? CacheTTL.imdbMiss : CacheTTL.mappings
            )
        }
        return resolved
    }

    // MARK: - Exact lookup

    private func exactLookup(theTVDBID: String?) async -> String? {
        guard
            let theTVDBID,
            !theTVDBID.isEmpty,
            var components = URLComponents(url: tvmazeBaseURL, resolvingAgainstBaseURL: false)
        else {
            return nil
        }
        components.path = "/lookup/shows"
        components.queryItems = [URLQueryItem(name: "thetvdb", value: theTVDBID)]
        guard let url = components.url else { return nil }

        let request = RequestBuilder(
            url: url,
            headers: ["Accept": "application/json"],
            timeout: timeout
        ).build()
        guard
            let show = try? await http.send(request, as: TVmazeShow.self, maxBytes: maxBytes)
        else {
            return nil
        }
        return Self.validated(show.externals?.imdb)
    }

    // MARK: - Ranked title search

    private func searchLookup(context: Context) async -> String? {
        var best: (id: String, score: Double)?
        for title in context.titles.prefix(3) {
            let metas = await cinemetaSearch(title: title, type: context.isMovie ? "movie" : "series")
            for meta in metas.prefix(5) {
                guard
                    let id = Self.validated(meta.id),
                    let name = meta.name
                else {
                    continue
                }
                let score = Self.matchScore(
                    candidate: name,
                    releaseInfo: meta.releaseInfo,
                    titles: context.titles,
                    year: context.year
                )
                if score > (best?.score ?? 0) {
                    best = (id, score)
                }
            }
        }
        guard let best, best.score >= 0.65 else { return nil }
        return best.id
    }

    private func cinemetaSearch(title: String, type: String) async -> [CinemetaMeta] {
        guard
            let encoded = title.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
            !encoded.isEmpty,
            let url = URL(
                string: "\(cinemetaBaseURL.absoluteString)/catalog/\(type)/top/search=\(encoded).json"
            )
        else {
            return []
        }
        let request = RequestBuilder(
            url: url,
            headers: ["Accept": "application/json"],
            timeout: timeout
        ).build()
        guard
            let response = try? await http.send(request, as: CinemetaResponse.self, maxBytes: maxBytes)
        else {
            return []
        }
        return response.metas
    }

    // MARK: - Matching

    static func validated(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix("tt"), trimmed.count > 2, trimmed.dropFirst(2).allSatisfy(\.isNumber) else {
            return nil
        }
        return trimmed
    }

    static func matchScore(
        candidate: String,
        releaseInfo: String?,
        titles: [String],
        year: Int?
    ) -> Double {
        let candidateName = normalize(candidate)
        guard !candidateName.isEmpty else { return 0 }

        var titleScore = 0.0
        for title in titles {
            let normalized = normalize(title)
            guard !normalized.isEmpty else { continue }
            if candidateName == normalized {
                titleScore = max(titleScore, 1)
            } else if candidateName.hasPrefix(normalized) || normalized.hasPrefix(candidateName) {
                titleScore = max(titleScore, 0.85)
            } else if candidateName.contains(normalized) || normalized.contains(candidateName) {
                titleScore = max(titleScore, 0.7)
            } else {
                titleScore = max(titleScore, tokenOverlap(candidateName, normalized) * 0.7)
            }
        }
        guard titleScore > 0 else { return 0 }

        var score = titleScore
        if let year, let candidateYear = firstYear(in: releaseInfo) {
            if candidateYear == year {
                score += 0.25
            } else if abs(candidateYear - year) > 1 {
                score -= 0.4
            }
        }
        return max(score, 0)
    }

    static func firstYear(in releaseInfo: String?) -> Int? {
        guard let releaseInfo, releaseInfo.count >= 4 else { return nil }
        return Int(releaseInfo.prefix(4))
    }

    private static func tokenOverlap(_ lhs: String, _ rhs: String) -> Double {
        let left = Set(lhs.split(separator: " "))
        let right = Set(rhs.split(separator: " "))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let shared = left.intersection(right).count
        return Double(shared) / Double(max(left.count, right.count))
    }

    static func normalize(_ string: String) -> String {
        let folded = string.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let characters = folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : " "
        }
        return characters
            .joined()
            .split(separator: " ")
            .joined(separator: " ")
            .lowercased()
    }
}

private struct TVmazeShow: Decodable {
    struct Externals: Decodable {
        let imdb: String?
    }

    let externals: Externals?
}

private struct CinemetaResponse: Decodable {
    let metas: [CinemetaMeta]
}

private struct CinemetaMeta: Decodable {
    let id: String?
    let name: String?
    let releaseInfo: String?
}
