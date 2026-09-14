import Foundation

/// How an installment connects to the rest of the series.
enum InstallmentRelationship: String, Codable, Sendable {
    case original
    case sequel
    case prequel

    var displayName: String {
        switch self {
        case .original: String(localized: "Original")
        case .sequel: String(localized: "Sequel")
        case .prequel: String(localized: "Prequel")
        }
    }
}

/// One selectable entry inside a grouped anime series.
struct AnimeInstallment: Identifiable, Hashable, Codable, Sendable {
    var id: String { anime.id }
    let anime: Anime
    let relationship: InstallmentRelationship
    let displayOrder: Int
    let displayName: String
    /// Sum of the episode counts of all preceding installments. Used to
    /// derive absolute episode numbers for stream matching.
    let absoluteEpisodeOffset: Int

    /// Absolute number for an episode of this installment.
    func absoluteNumber(forEpisodeNumber number: Int) -> Int {
        guard absoluteEpisodeOffset > 0 else { return number }
        return absoluteEpisodeOffset + max(number, 1)
    }
}

/// A viewer-facing series built from Kitsu's separate anime records.
struct AnimeSeries: Hashable, Codable, Sendable {
    let rootAnime: Anime
    let installments: [AnimeInstallment]
    /// Related media that must not appear in the season selector
    /// (movies, OVAs, side stories, spin-offs, ...).
    let related: [AnimeRelation]

    static func single(_ anime: Anime) -> AnimeSeries {
        AnimeSeries(
            rootAnime: anime,
            installments: [
                AnimeInstallment(
                    anime: anime,
                    relationship: .original,
                    displayOrder: 0,
                    displayName: String(localized: "Season 1"),
                    absoluteEpisodeOffset: 0
                ),
            ],
            related: []
        )
    }

    func installment(id: String) -> AnimeInstallment? {
        installments.first { $0.id == id }
    }
}
