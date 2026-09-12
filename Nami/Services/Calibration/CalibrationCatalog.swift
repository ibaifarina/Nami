import Foundation

/// One entry in the fixed calibration corpus.
///
/// The corpus is intentionally tiny and centralized: IDs are verified against
/// Kitsu, and every addon sample request resolves through Nami's normal
/// metadata/identity layer, so no mysterious IDs live anywhere else.
struct CalibrationTitle: Hashable, Sendable, Identifiable {
    let id: String
    let displayName: String
    /// Titles used when an addon needs an ID resolved through metadata lookups.
    let titles: [String]
    let identity: MediaIdentity
    let year: Int
    let kind: StreamContentKind
    /// Episode number to request. Ignored for movies.
    let episodeNumber: Int
    /// Season override, so fallback titles exercise season/cour-style naming.
    let seasonNumber: Int?
    /// Absolute episode number, so long-running shows exercise absolute numbering.
    let absoluteEpisode: Int?
}

/// The bounded calibration corpus requested by the product spec.
///
/// Episodes: Frieren (modern TV formatting) → One Piece (absolute numbering,
/// 1000+) → Attack on Titan (later-season naming) only when samples are thin.
/// Movies: Your Name. → Demon Slayer: Mugen Train when samples are thin.
enum CalibrationCatalog {
    static let episodeTitles: [CalibrationTitle] = [
        CalibrationTitle(
            id: "frieren",
            displayName: "Frieren: Beyond Journey's End",
            titles: ["Frieren: Beyond Journey's End", "Sousou no Frieren"],
            identity: MediaIdentity(kitsuID: "46474", malID: 52991, anilistID: 154587),
            year: 2023,
            kind: .episode,
            episodeNumber: 10,
            seasonNumber: 1,
            absoluteEpisode: nil
        ),
        CalibrationTitle(
            id: "one-piece",
            displayName: "One Piece",
            titles: ["One Piece"],
            identity: MediaIdentity(kitsuID: "12", malID: 21, anilistID: 21),
            year: 1999,
            kind: .episode,
            episodeNumber: 1000,
            seasonNumber: nil,
            absoluteEpisode: 1000
        ),
        CalibrationTitle(
            id: "attack-on-titan",
            displayName: "Attack on Titan",
            titles: ["Attack on Titan", "Shingeki no Kyojin"],
            identity: MediaIdentity(kitsuID: "7442", malID: 16498, anilistID: 16498),
            year: 2013,
            kind: .episode,
            episodeNumber: 5,
            seasonNumber: 2,
            absoluteEpisode: nil
        ),
    ]

    static let movieTitles: [CalibrationTitle] = [
        CalibrationTitle(
            id: "your-name",
            displayName: "Your Name.",
            titles: ["Your Name.", "Kimi no Na wa."],
            identity: MediaIdentity(kitsuID: "11614", malID: 32281, anilistID: 21519),
            year: 2016,
            kind: .movie,
            episodeNumber: 1,
            seasonNumber: nil,
            absoluteEpisode: nil
        ),
        CalibrationTitle(
            id: "mugen-train",
            displayName: "Demon Slayer: Mugen Train",
            titles: ["Demon Slayer: Mugen Train", "Kimetsu no Yaiba: Mugen Ressha-hen"],
            identity: MediaIdentity(kitsuID: "42586", malID: 40456, anilistID: 112151),
            year: 2020,
            kind: .movie,
            episodeNumber: 1,
            seasonNumber: nil,
            absoluteEpisode: nil
        ),
    ]

    static func episode(for title: CalibrationTitle) -> Episode {
        Episode(
            id: "calibration-\(title.id)",
            animeID: title.identity.kitsuID,
            number: title.episodeNumber,
            relativeNumber: title.seasonNumber == nil ? nil : title.episodeNumber,
            seasonNumber: title.seasonNumber,
            absoluteNumber: title.absoluteEpisode
        )
    }

    static func movie(for title: CalibrationTitle) -> Episode {
        Episode(
            id: "calibration-\(title.id)",
            animeID: title.identity.kitsuID,
            number: title.episodeNumber
        )
    }
}

/// Addons whose result formatting Nami already handles natively. They skip AI
/// calibration and keep their existing optimized parsing.
enum BuiltInAddonFormats {
    private static let knownMarkers = ["torrentio", "comet"]

    static func isOptimized(_ addon: InstalledAddon) -> Bool {
        let candidates = [
            addon.id.lowercased(),
            addon.name.lowercased(),
            addon.baseURL.host?.lowercased() ?? "",
        ]
        return knownMarkers.contains { marker in
            candidates.contains { $0.contains(marker) }
        }
    }
}
