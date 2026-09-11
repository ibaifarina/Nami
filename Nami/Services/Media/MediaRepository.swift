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
        GenreOption(slug: "action", title: "Action"),
        GenreOption(slug: "adventure", title: "Adventure"),
        GenreOption(slug: "comedy", title: "Comedy"),
        GenreOption(slug: "drama", title: "Drama"),
        GenreOption(slug: "fantasy", title: "Fantasy"),
        GenreOption(slug: "horror", title: "Horror"),
        GenreOption(slug: "mecha", title: "Mecha"),
        GenreOption(slug: "music", title: "Music"),
        GenreOption(slug: "mystery", title: "Mystery"),
        GenreOption(slug: "psychological", title: "Psychological"),
        GenreOption(slug: "romance", title: "Romance"),
        GenreOption(slug: "sci-fi", title: "Sci-Fi"),
        GenreOption(slug: "slice-of-life", title: "Slice of Life"),
        GenreOption(slug: "sports", title: "Sports"),
        GenreOption(slug: "supernatural", title: "Supernatural"),
        GenreOption(slug: "thriller", title: "Thriller"),
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
        case .popularity: "Popularity"
        case .rating: "Rating"
        case .newest: "Newest"
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
