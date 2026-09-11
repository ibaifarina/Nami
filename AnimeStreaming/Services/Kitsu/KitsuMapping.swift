import Foundation

/// Maps Kitsu JSON:API resources into app domain models.
enum KitsuMapping {
    static func anime(_ resource: JSONAPIResource<KitsuAnimeAttributes>) -> Anime {
        let attributes = resource.attributes
        let titles = attributes.titles ?? [:]
        let english = title(in: titles, keys: "en", "en_us")
        let romaji = title(in: titles, keys: "en_jp")
        let japanese = title(in: titles, keys: "ja_jp")
        let title = firstNonEmpty(
            attributes.canonicalTitle,
            english,
            romaji,
            japanese
        ) ?? "Untitled"

        return Anime(
            identity: MediaIdentity(kitsuID: resource.id),
            title: title,
            canonicalTitle: cleaned(attributes.canonicalTitle),
            englishTitle: cleaned(english),
            romajiTitle: cleaned(romaji),
            japaneseTitle: cleaned(japanese),
            synopsis: firstNonEmpty(attributes.synopsis, attributes.description),
            posterURL: posterURL(from: attributes.posterImage),
            bannerURL: bannerURL(from: attributes.coverImage),
            status: attributes.status.flatMap(AnimeStatus.init(kitsuValue:)),
            subtype: attributes.subtype.flatMap(AnimeSubtype.init(kitsuValue:)),
            episodeCount: attributes.episodeCount.flatMap { $0 > 0 ? $0 : nil },
            episodeLength: attributes.episodeLength.flatMap { $0 > 0 ? $0 : nil },
            startDate: date(from: attributes.startDate),
            endDate: date(from: attributes.endDate),
            popularityRank: attributes.popularityRank,
            ratingRank: attributes.ratingRank,
            averageRating: attributes.averageRating.flatMap(Double.init),
            ageRating: cleaned(attributes.ageRating),
            genres: []
        )
    }

    static func episode(
        _ resource: JSONAPIResource<KitsuEpisodeAttributes>,
        animeID: String
    ) -> Episode? {
        let attributes = resource.attributes
        let titles = attributes.titles ?? [:]
        guard let number = attributes.number ?? attributes.relativeNumber else {
            return nil
        }
        return Episode(
            id: resource.id,
            animeID: animeID,
            number: number,
            relativeNumber: attributes.relativeNumber,
            seasonNumber: attributes.seasonNumber,
            title: firstNonEmpty(
                attributes.canonicalTitle,
                title(in: titles, keys: "en", "en_us"),
                title(in: titles, keys: "en_jp"),
                title(in: titles, keys: "ja_jp")
            ),
            synopsis: firstNonEmpty(attributes.synopsis, attributes.description),
            thumbnailURL: attributes.thumbnail?.original.flatMap(URL.init(string:)),
            airDate: date(from: attributes.airdate),
            durationMinutes: attributes.length.flatMap { $0 > 0 ? $0 : nil }
        )
    }

    static func relationRole(_ raw: String?) -> MediaRelationRole? {
        guard let raw else { return nil }
        return MediaRelationRole(rawValue: raw.lowercased())
    }

    /// Applies Kitsu `mappings` to an anime identity. Only identifiers the
    /// app can use are extracted.
    static func identities(
        from mappings: [JSONAPIResource<KitsuMappingAttributes>],
        kitsuID: String
    ) -> MediaIdentity? {
        var identity = MediaIdentity(kitsuID: kitsuID)
        var hasUsefulID = false
        for mapping in mappings {
            let site = mapping.attributes.externalSite?.lowercased() ?? ""
            let externalID = mapping.attributes.externalId
            switch site {
            case "myanimelist/anime":
                if let value = externalID.flatMap(Int.init) {
                    identity.malID = value
                    hasUsefulID = true
                }
            case "anilist/anime":
                if let value = externalID.flatMap(Int.init) {
                    identity.anilistID = value
                    hasUsefulID = true
                }
            case "themoviedb", "tmdb":
                if let value = externalID.flatMap(Int.init) {
                    identity.tmdbID = value
                    hasUsefulID = true
                }
            case "imdb":
                if let value = cleaned(externalID) {
                    identity.imdbID = value
                    hasUsefulID = true
                }
            default:
                continue
            }
        }
        return hasUsefulID ? identity : nil
    }

    static func date(from string: String?) -> Date? {
        guard let string, string.count >= 10 else { return nil }
        return KitsuDateParser.date(from: String(string.prefix(10)))
    }

    // MARK: - Helpers

    private static func title(in titles: [String: String?], keys: String...) -> String? {
        for key in keys {
            if let value = titles[key] ?? nil, !value.isEmpty { return value }
        }
        return nil
    }

    private static func posterURL(from image: KitsuImageAttributes?) -> URL? {
        guard let image else { return nil }
        let value = image.medium ?? image.small ?? image.large ?? image.original
        return value.flatMap(URL.init(string:))
    }

    private static func bannerURL(from image: KitsuImageAttributes?) -> URL? {
        guard let image else { return nil }
        let value = image.small ?? image.large ?? image.original
        return value.flatMap(URL.init(string:))
    }

    static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let cleaned = cleaned(value) { return cleaned }
        }
        return nil
    }
}

enum KitsuDateParser {
    private static let lock = NSLock()
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func date(from string: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return formatter.date(from: string)
    }
}
