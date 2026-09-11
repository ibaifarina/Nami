#if DEBUG
import Foundation

/// Minimal, DEBUG-only values used exclusively by Xcode previews. The app
/// runtime never uses these; live data comes from Kitsu.
enum PreviewFixtures {
    static let anime = Anime(
        identity: MediaIdentity(kitsuID: "7442", malID: 16498, anilistID: 16498),
        title: "Preview Anime",
        canonicalTitle: "Preview Anime",
        englishTitle: "Preview Anime",
        romajiTitle: "Preview Anime",
        japaneseTitle: nil,
        synopsis: "Placeholder used by Xcode previews only.",
        posterURL: url("https://media.kitsu.app/anime/poster_images/7442/medium.jpg"),
        bannerURL: url("https://media.kitsu.app/anime/cover_images/7442/small.jpg"),
        status: .finished,
        subtype: .tv,
        episodeCount: 12,
        episodeLength: 24,
        startDate: Date(timeIntervalSince1970: 0),
        averageRating: 85,
        genres: ["Action"]
    )

    private static func url(_ string: String) -> URL? {
        URL(string: string)
    }
}
#endif
