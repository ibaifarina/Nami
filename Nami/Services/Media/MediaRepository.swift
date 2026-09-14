import Foundation

/// Canonical media catalog abstraction. Views depend on this protocol, never
/// on Kitsu response models directly.
protocol MediaRepository: Sendable {
    func anime(id: String) async throws -> AnimeDetails
    func search(query: String, page: Int) async throws -> [Anime]
    func popular(page: Int) async throws -> [Anime]
    func topRated(page: Int) async throws -> [Anime]
    func currentlyAiring(page: Int) async throws -> [Anime]
    func upcoming(page: Int) async throws -> [Anime]
    func recentlyReleased(page: Int) async throws -> [Anime]
    func discover(query: String?, filters: DiscoverFilters, page: Int) async throws -> [Anime]
}

/// Episode metadata abstraction, backed by Kitsu's dedicated episode data.
protocol EpisodeRepository: Sendable {
    func episodes(forAnimeID id: String) async throws -> [Episode]
    /// Currently airing shows use a shorter cache lifetime.
    func episodes(forAnimeID id: String, isAiring: Bool) async throws -> [Episode]
}

extension EpisodeRepository {
    func episodes(forAnimeID id: String, isAiring: Bool) async throws -> [Episode] {
        try await episodes(forAnimeID: id)
    }
}

struct GenreOption: Hashable, Sendable, Identifiable {
    let slug: String
    let title: String

    var id: String { slug }
}

struct DiscoverFilters: Hashable, Sendable {
    var genre: String?
    var season: AnimeSeason?
    var year: Int?
    var status: AnimeStatus?
    var subtype: AnimeSubtype?
    var sort: DiscoverSort = .popularity

    static let genres: [GenreOption] = [
        GenreOption(slug: "action", title: String(localized: "Action")),
        GenreOption(slug: "adventure", title: String(localized: "Adventure")),
        GenreOption(slug: "comedy", title: String(localized: "Comedy")),
        GenreOption(slug: "drama", title: String(localized: "Drama")),
        GenreOption(slug: "ecchi", title: String(localized: "Ecchi")),
        GenreOption(slug: "fantasy", title: String(localized: "Fantasy")),
        GenreOption(slug: "horror", title: String(localized: "Horror")),
        GenreOption(slug: "mecha", title: String(localized: "Mecha")),
        GenreOption(slug: "music", title: String(localized: "Music")),
        GenreOption(slug: "mystery", title: String(localized: "Mystery")),
        GenreOption(slug: "psychological", title: String(localized: "Psychological")),
        GenreOption(slug: "romance", title: String(localized: "Romance")),
        GenreOption(slug: "science-fiction", title: String(localized: "Sci-Fi")),
        GenreOption(slug: "slice-of-life", title: String(localized: "Slice of Life")),
        GenreOption(slug: "sports", title: String(localized: "Sports")),
        GenreOption(slug: "supernatural", title: String(localized: "Supernatural")),
        GenreOption(slug: "thriller", title: String(localized: "Thriller")),
    ]

    static let years: [Int] = {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 30)...current).reversed()
    }()

    var cacheKey: String {
        [
            genre ?? "-",
            season?.rawValue ?? "-",
            year.map(String.init) ?? "-",
            status?.rawValue ?? "-",
            subtype?.rawValue ?? "-",
            sort.rawValue,
        ].joined(separator: "|")
    }

    var isDefault: Bool { self == DiscoverFilters() }
}

enum DiscoverSort: String, CaseIterable, Identifiable, Sendable {
    case popularity
    case rating
    case newest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .popularity: String(localized: "Popularity")
        case .rating: String(localized: "Rating")
        case .newest: String(localized: "Newest")
        }
    }

    var kitsuSort: String {
        switch self {
        case .popularity: "popularityRank"
        case .rating: "ratingRank"
        case .newest: "-startDate"
        }
    }
}
