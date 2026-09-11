import Foundation

/// Local, canonical watch progress. No external account is required.
struct PlaybackProgress: Identifiable, Hashable, Codable, Sendable {
    var id: String { "\(animeID)-\(episodeNumber)" }

    /// Kitsu anime (installment) ID.
    let animeID: String
    /// Kitsu episode ID, when known.
    let episodeID: String?
    let episodeNumber: Int
    /// Absolute episode number across the grouped series, when known.
    let absoluteEpisodeNumber: Int?

    var positionSeconds: Double
    var durationSeconds: Double
    var isCompleted: Bool
    var updatedAt: Date

    // Local snapshot so Continue Watching keeps working when Kitsu is
    // unavailable and no cached metadata exists.
    var animeTitle: String?
    var posterURL: URL?
    var bannerURL: URL?
    var episodeCount: Int?

    init(
        animeID: String,
        episodeID: String? = nil,
        episodeNumber: Int,
        absoluteEpisodeNumber: Int? = nil,
        positionSeconds: Double,
        durationSeconds: Double,
        isCompleted: Bool = false,
        updatedAt: Date,
        animeTitle: String? = nil,
        posterURL: URL? = nil,
        bannerURL: URL? = nil,
        episodeCount: Int? = nil
    ) {
        self.animeID = animeID
        self.episodeID = episodeID
        self.episodeNumber = episodeNumber
        self.absoluteEpisodeNumber = absoluteEpisodeNumber
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.isCompleted = isCompleted
        self.updatedAt = updatedAt
        self.animeTitle = animeTitle
        self.posterURL = posterURL
        self.bannerURL = bannerURL
        self.episodeCount = episodeCount
    }

    var fraction: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(max(positionSeconds / durationSeconds, 0), 1)
    }

    var percentage: Double { fraction * 100 }

    var remainingSeconds: Double {
        max(0, durationSeconds - positionSeconds)
    }

    var timecode: String {
        "\(Timecode.format(positionSeconds)) / \(Timecode.format(durationSeconds))"
    }

    /// A minimal anime snapshot used for offline Continue Watching cards.
    var animeSnapshot: Anime? {
        guard let animeTitle, !animeTitle.isEmpty else { return nil }
        return Anime(
            identity: MediaIdentity(kitsuID: animeID),
            title: animeTitle,
            posterURL: posterURL,
            bannerURL: bannerURL,
            episodeCount: episodeCount
        )
    }
}
