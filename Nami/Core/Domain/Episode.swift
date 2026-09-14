import Foundation

/// Kitsu-backed episode metadata.
///
/// Kitsu does not guarantee complete episode data, so every metadata field
/// except identity and numbering is optional. The UI must tolerate missing
/// values and never block playback on incomplete metadata.
struct Episode: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let animeID: String
    /// Number within the Kitsu anime record.
    let number: Int
    /// Number relative to the season, when Kitsu provides it.
    let relativeNumber: Int?
    /// Season number, when Kitsu provides it.
    let seasonNumber: Int?
    /// Absolute number across the grouped series, when it can be derived.
    let absoluteNumber: Int?
    let title: String?
    let synopsis: String?
    let thumbnailURL: URL?
    let airDate: Date?
    let durationMinutes: Int?

    init(
        id: String,
        animeID: String,
        number: Int,
        relativeNumber: Int? = nil,
        seasonNumber: Int? = nil,
        absoluteNumber: Int? = nil,
        title: String? = nil,
        synopsis: String? = nil,
        thumbnailURL: URL? = nil,
        airDate: Date? = nil,
        durationMinutes: Int? = nil
    ) {
        self.id = id
        self.animeID = animeID
        self.number = number
        self.relativeNumber = relativeNumber
        self.seasonNumber = seasonNumber
        self.absoluteNumber = absoluteNumber
        self.title = title
        self.synopsis = synopsis
        self.thumbnailURL = thumbnailURL
        self.airDate = airDate
        self.durationMinutes = durationMinutes
    }

    /// The number shown to the user, preferring season-relative numbering.
    var displayNumber: Int { relativeNumber ?? number }

    /// Fallback-aware title.
    var displayTitle: String {
        guard let title, !title.isEmpty else { return String(localized: "Episode \(displayNumber)") }
        return title
    }

    /// Fallback-aware optional title used to decide whether to render a
    /// separate title row.
    var hasTitle: Bool {
        guard let title else { return false }
        return !title.isEmpty
    }

    var hasSynopsis: Bool {
        guard let synopsis else { return false }
        return !synopsis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Synopsis cleaned for display: trailing "(Source: …)" attributions and
    /// any resulting trailing blank lines are removed.
    var displaySynopsis: String? {
        guard let synopsis else { return nil }
        let stripped = synopsis.replacingOccurrences(
            of: #"\s*\(\s*Source:[^)]*\)"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var durationText: String? {
        guard let durationMinutes, durationMinutes > 0 else { return nil }
        let hours = durationMinutes / 60
        let minutes = durationMinutes % 60
        if hours == 0 { return String(localized: "\(minutes)m") }
        if minutes == 0 { return String(localized: "\(hours)h") }
        return String(localized: "\(hours)h \(minutes)m")
    }

    var airDateText: String? {
        guard let airDate else { return nil }
        return Self.airDateFormatter.string(from: airDate)
    }

    /// A copy with an absolute number assigned by the series grouping layer.
    func withAbsoluteNumber(_ value: Int?) -> Episode {
        Episode(
            id: id,
            animeID: animeID,
            number: number,
            relativeNumber: relativeNumber,
            seasonNumber: seasonNumber,
            absoluteNumber: value ?? absoluteNumber,
            title: title,
            synopsis: synopsis,
            thumbnailURL: thumbnailURL,
            airDate: airDate,
            durationMinutes: durationMinutes
        )
    }

    private static let airDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
