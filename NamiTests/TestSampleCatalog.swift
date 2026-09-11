import Foundation
@testable import Nami

enum SampleCatalog {
    static let anime: [Anime] = [
        make(
            id: "46474", malID: 52991, title: "Frieren: Beyond Journey's End",
            canonical: "Frieren: Beyond Journey's End", romaji: "Sousou no Frieren",
            japanese: "葬送のフリーレン",
            subtype: .tv, status: .finished, year: 2023,
            episodes: 28, duration: 24, rating: 91.2, popularityRank: 5,
            genres: ["Adventure", "Drama", "Fantasy"],
            synopsis: "After the adventure ends, the elven mage Frieren begins a quiet journey to understand the humans she outlived."
        ),
        make(
            id: "7442", malID: 16498, title: "Attack on Titan",
            canonical: "Attack on Titan", romaji: "Shingeki no Kyojin", japanese: "進撃の巨人",
            subtype: .tv, status: .finished, year: 2013,
            episodes: 25, duration: 24, rating: 84.4, popularityRank: 1,
            genres: ["Action", "Drama", "Fantasy"],
            synopsis: "Humanity fights for survival behind towering walls while Eren Yeager swears to destroy the man-eating titans."
        ),
        make(
            id: "8671", malID: 25777, title: "Attack on Titan Season 2",
            canonical: "Attack on Titan Season 2", romaji: "Shingeki no Kyojin Season 2",
            japanese: "進撃の巨人 Season 2",
            subtype: .tv, status: .finished, year: 2017,
            episodes: 12, duration: 24, rating: 86.0, popularityRank: 20,
            genres: ["Action", "Drama", "Fantasy"],
            synopsis: "The mystery of the Titans deepens as the Survey Corps faces a new threat within the walls."
        ),
        make(
            id: "12", malID: 21, title: "One Piece",
            canonical: "One Piece", romaji: "One Piece", japanese: "ONE PIECE",
            subtype: .tv, status: .current, year: 1999,
            episodes: nil, duration: 24, rating: 88.0, popularityRank: 2,
            genres: ["Action", "Adventure", "Comedy", "Fantasy"],
            synopsis: "Monkey D. Luffy sails the Grand Line with his crew in search of the legendary treasure."
        ),
        make(
            id: "11614", malID: 21519, title: "Your Name.",
            canonical: "Your Name.", romaji: "Kimi no Na wa.", japanese: "君の名は。",
            subtype: .movie, status: .finished, year: 2016,
            episodes: 1, duration: 106, rating: 83.3, popularityRank: 30,
            genres: ["Drama", "Romance", "Supernatural"],
            synopsis: "Two teenagers who have never met begin swapping bodies across time."
        ),
        make(
            id: "41370", malID: 101922, title: "Demon Slayer: Kimetsu no Yaiba",
            canonical: "Demon Slayer: Kimetsu no Yaiba", romaji: "Kimetsu no Yaiba",
            japanese: "鬼滅の刃",
            subtype: .tv, status: .finished, year: 2019,
            episodes: 26, duration: 24, rating: 83.0, popularityRank: 4,
            genres: ["Action", "Supernatural"],
            synopsis: "Tanjiro Kamado joins the Demon Slayer Corps to find a cure for his sister."
        ),
    ]

    static let relations: [String: [(MediaRelationRole, String)]] = [
        "7442": [(.sequel, "8671")],
        "8671": [(.prequel, "7442")],
    ]

    static func anime(withID id: String) -> Anime? {
        anime.first { $0.id == id }
    }

    static func make(
        id: String,
        malID: Int? = nil,
        title: String,
        canonical: String? = nil,
        romaji: String? = nil,
        japanese: String? = nil,
        subtype: AnimeSubtype,
        status: AnimeStatus,
        year: Int? = nil,
        episodes: Int? = nil,
        duration: Int? = nil,
        rating: Double? = nil,
        popularityRank: Int? = nil,
        genres: [String] = [],
        synopsis: String? = nil
    ) -> Anime {
        Anime(
            identity: MediaIdentity(kitsuID: id, malID: malID),
            title: title,
            canonicalTitle: canonical,
            englishTitle: title,
            romajiTitle: romaji,
            japaneseTitle: japanese,
            synopsis: synopsis,
            posterURL: URL(string: "https://media.kitsu.app/anime/poster_images/\(id)/medium.jpg"),
            bannerURL: URL(string: "https://media.kitsu.app/anime/cover_images/\(id)/small.jpg"),
            status: status,
            subtype: subtype,
            episodeCount: episodes,
            episodeLength: duration,
            startDate: year.map {
                Calendar(identifier: .gregorian).date(from: DateComponents(year: $0, month: 1, day: 1))!
            },
            popularityRank: popularityRank,
            ratingRank: nil,
            averageRating: rating,
            ageRating: "PG",
            genres: genres
        )
    }

    static func episodes(forAnimeID id: String, count: Int, duration: Int = 24) -> [Episode] {
        (1...max(count, 1)).map { number in
            Episode(
                id: "\(id)-ep-\(number)",
                animeID: id,
                number: number,
                relativeNumber: number,
                seasonNumber: 1,
                title: "Episode \(number)",
                synopsis: nil,
                thumbnailURL: nil,
                airDate: nil,
                durationMinutes: duration
            )
        }
    }
}
