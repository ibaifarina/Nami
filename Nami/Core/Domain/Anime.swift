import Foundation

/// Kitsu airing status.
enum AnimeStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case current
    case finished
    case tba
    case unreleased
    case upcoming

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .current: "Airing"
        case .finished: "Finished"
        case .tba: "TBA"
        case .unreleased: "Unreleased"
        case .upcoming: "Upcoming"
        }
    }

    var isAiring: Bool { self == .current }

    init?(kitsuValue: String) {
        let lowered = kitsuValue.lowercased()
        guard let value = Self.allCases.first(where: { $0.rawValue == lowered }) else {
            return nil
        }
        self = value
    }
}

/// Kitsu media subtype.
enum AnimeSubtype: String, Codable, Sendable, CaseIterable, Identifiable {
    case tv = "TV"
    case tvSpecial = "TV special"
    case movie = "movie"
    case ova = "OVA"
    case ona = "ONA"
    case special = "special"
    case music = "music"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tv: "TV"
        case .tvSpecial: "TV Special"
        case .movie: "Movie"
        case .ova: "OVA"
        case .ona: "ONA"
        case .special: "Special"
        case .music: "Music"
        }
    }

    var isEpisodic: Bool {
        switch self {
        case .tv, .tvSpecial, .ona, .ova, .special: true
        case .movie, .music: false
        }
    }

    var isMovie: Bool { self == .movie }

    init?(kitsuValue: String) {
        let direct = Self(rawValue: kitsuValue)
        if let direct {
            self = direct
            return
        }
        let lowered = kitsuValue.lowercased()
        switch lowered {
        case "tv": self = .tv
        case "tv special": self = .tvSpecial
        case "movie": self = .movie
        case "ova": self = .ova
        case "ona": self = .ona
        case "special": self = .special
        case "music": self = .music
        default: return nil
        }
    }
}

/// Season of the year used by the Discover filter.
enum AnimeSeason: String, Codable, Sendable, CaseIterable, Identifiable {
    case winter
    case spring
    case summer
    case fall

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .winter: "Winter"
        case .spring: "Spring"
        case .summer: "Summer"
        case .fall: "Fall"
        }
    }
}

/// Kitsu `mediaRelationships.role`.
enum MediaRelationRole: String, Codable, Sendable, CaseIterable {
    case adaptation
    case alternativeSetting = "alternative_setting"
    case alternativeVersion = "alternative_version"
    case character
    case fullStory = "full_story"
    case other
    case parentStory = "parent_story"
    case prequel
    case sequel
    case sideStory = "side_story"
    case spinOff = "spin_off"
    case summary

    var displayName: String {
        switch self {
        case .adaptation: "Adaptation"
        case .alternativeSetting: "Alternative Setting"
        case .alternativeVersion: "Alternative Version"
        case .character: "Character"
        case .fullStory: "Full Story"
        case .other: "Related"
        case .parentStory: "Parent Story"
        case .prequel: "Prequel"
        case .sequel: "Sequel"
        case .sideStory: "Side Story"
        case .spinOff: "Spin-off"
        case .summary: "Summary"
        }
    }

    /// Only these roles are considered for sequential season grouping.
    var isSequentialInstallment: Bool {
        self == .sequel || self == .prequel
    }
}

struct Anime: Identifiable, Hashable, Codable, Sendable {
    let identity: MediaIdentity
    let title: String
    let canonicalTitle: String?
    let englishTitle: String?
    let romajiTitle: String?
    let japaneseTitle: String?
    let synopsis: String?
    let posterURL: URL?
    let bannerURL: URL?
    let status: AnimeStatus?
    let subtype: AnimeSubtype?
    let episodeCount: Int?
    let episodeLength: Int?
    let startDate: Date?
    let endDate: Date?
    let popularityRank: Int?
    let ratingRank: Int?
    let averageRating: Double?
    let ageRating: String?
    let genres: [String]

    init(
        identity: MediaIdentity,
        title: String,
        canonicalTitle: String? = nil,
        englishTitle: String? = nil,
        romajiTitle: String? = nil,
        japaneseTitle: String? = nil,
        synopsis: String? = nil,
        posterURL: URL? = nil,
        bannerURL: URL? = nil,
        status: AnimeStatus? = nil,
        subtype: AnimeSubtype? = nil,
        episodeCount: Int? = nil,
        episodeLength: Int? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        popularityRank: Int? = nil,
        ratingRank: Int? = nil,
        averageRating: Double? = nil,
        ageRating: String? = nil,
        genres: [String] = []
    ) {
        self.identity = identity
        self.title = title
        self.canonicalTitle = canonicalTitle
        self.englishTitle = englishTitle
        self.romajiTitle = romajiTitle
        self.japaneseTitle = japaneseTitle
        self.synopsis = synopsis
        self.posterURL = posterURL
        self.bannerURL = bannerURL
        self.status = status
        self.subtype = subtype
        self.episodeCount = episodeCount
        self.episodeLength = episodeLength
        self.startDate = startDate
        self.endDate = endDate
        self.popularityRank = popularityRank
        self.ratingRank = ratingRank
        self.averageRating = averageRating
        self.ageRating = ageRating
        self.genres = genres
    }

    var id: String { identity.kitsuID }

    var displayTitle: String { title }

    /// The primary title resolved for a display preference.
    func displayTitle(for language: AnimeTitleLanguage) -> String {
        switch language {
        case .standard:
            title
        case .english:
            englishTitle ?? title
        case .japanese:
            japaneseTitle ?? romajiTitle ?? title
        }
    }

    /// A secondary title in a different language than the resolved primary title.
    func alternativeTitle(for language: AnimeTitleLanguage) -> String? {
        let primary = displayTitle(for: language)
        let candidates: [String?]
        switch language {
        case .standard:
            candidates = [englishTitle, romajiTitle, japaneseTitle, canonicalTitle]
        case .english:
            candidates = [japaneseTitle, romajiTitle, canonicalTitle]
        case .japanese:
            candidates = [englishTitle, canonicalTitle, romajiTitle]
        }
        for candidate in candidates {
            if let candidate, !candidate.isEmpty, candidate != primary { return candidate }
        }
        return nil
    }

    var episodesAvailable: Int? {
        if let episodeCount, episodeCount > 0 { return episodeCount }
        return nil
    }

    var isEpisodic: Bool { subtype?.isEpisodic ?? false }

    var durationMinutes: Int? { episodeLength }

    var startYear: Int? {
        guard let startDate else { return nil }
        return Calendar(identifier: .gregorian).component(.year, from: startDate)
    }

    /// A rounded 0...100 score for compact UI display.
    var averageScore: Int? {
        guard let averageRating else { return nil }
        return Int(averageRating.rounded())
    }

    var kitsuURL: URL? {
        URL(string: "https://kitsu.io/anime/\(id)")
    }

    /// Returns a copy with selected fields replaced. Used while merging
    /// detail-only data (identity mappings, genres) into a list snapshot.
    func with(identity: MediaIdentity? = nil, genres: [String]? = nil) -> Anime {
        Anime(
            identity: identity ?? self.identity,
            title: title,
            canonicalTitle: canonicalTitle,
            englishTitle: englishTitle,
            romajiTitle: romajiTitle,
            japaneseTitle: japaneseTitle,
            synopsis: synopsis,
            posterURL: posterURL,
            bannerURL: bannerURL,
            status: status,
            subtype: subtype,
            episodeCount: episodeCount,
            episodeLength: episodeLength,
            startDate: startDate,
            endDate: endDate,
            popularityRank: popularityRank,
            ratingRank: ratingRank,
            averageRating: averageRating,
            ageRating: ageRating,
            genres: genres ?? self.genres
        )
    }
}

struct AnimeRelation: Identifiable, Hashable, Codable, Sendable {
    var id: String { anime.id }
    let role: MediaRelationRole
    let anime: Anime
}

struct AnimeDetails: Identifiable, Hashable, Codable, Sendable {
    var id: String { anime.id }
    let anime: Anime
    let relations: [AnimeRelation]

    func relations(for role: MediaRelationRole) -> [AnimeRelation] {
        relations.filter { $0.role == role }
    }
}
