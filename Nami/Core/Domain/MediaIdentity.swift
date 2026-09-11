import Foundation

/// Canonical identity for anime media.
///
/// The Kitsu ID is required because Kitsu is the application's primary
/// metadata provider. Every other identifier is optional interoperability
/// data used only when an addon requires it.
struct MediaIdentity: Hashable, Codable, Sendable {
    let kitsuID: String

    var malID: Int?
    var imdbID: String?
    var tmdbID: Int?
    var anilistID: Int?

    init(
        kitsuID: String,
        malID: Int? = nil,
        imdbID: String? = nil,
        tmdbID: Int? = nil,
        anilistID: Int? = nil
    ) {
        self.kitsuID = kitsuID
        self.malID = malID
        self.imdbID = imdbID
        self.tmdbID = tmdbID
        self.anilistID = anilistID
    }

    /// Returns a copy carrying any identifiers that were missing here but
    /// known elsewhere. Existing values always win.
    func merging(_ other: MediaIdentity) -> MediaIdentity {
        MediaIdentity(
            kitsuID: kitsuID,
            malID: malID ?? other.malID,
            imdbID: imdbID ?? other.imdbID,
            tmdbID: tmdbID ?? other.tmdbID,
            anilistID: anilistID ?? other.anilistID
        )
    }

    var hasAnimeInteroperabilityID: Bool {
        malID != nil || anilistID != nil
    }
}
