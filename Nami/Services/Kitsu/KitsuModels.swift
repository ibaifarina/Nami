import Foundation

/// Kitsu JSON:API resource attributes.
///
/// Field names mirror the live Kitsu API exactly; only fields the product
/// consumes are declared.
struct KitsuImageAttributes: Decodable, Sendable {
    let tiny: String?
    let small: String?
    let medium: String?
    let large: String?
    let original: String?
}

struct KitsuAnimeAttributes: Decodable, Sendable {
    let slug: String?
    let synopsis: String?
    let description: String?
    /// Kitsu encodes missing title keys as JSON null, so values are optional.
    let titles: [String: String?]?
    let canonicalTitle: String?
    let abbreviatedTitles: [String]?
    let averageRating: String?
    let userCount: Int?
    let startDate: String?
    let endDate: String?
    let popularityRank: Int?
    let ratingRank: Int?
    let ageRating: String?
    let ageRatingGuide: String?
    let subtype: String?
    let status: String?
    let posterImage: KitsuImageAttributes?
    let coverImage: KitsuImageAttributes?
    let episodeCount: Int?
    let episodeLength: Int?
    let totalLength: Int?
    let nsfw: Bool?
}

struct KitsuEpisodeThumbnailAttributes: Decodable, Sendable {
    let original: String?
}

struct KitsuEpisodeAttributes: Decodable, Sendable {
    let synopsis: String?
    let description: String?
    /// Kitsu encodes missing title keys as JSON null, so values are optional.
    let titles: [String: String?]?
    let canonicalTitle: String?
    let seasonNumber: Int?
    let number: Int?
    let relativeNumber: Int?
    let airdate: String?
    let length: Int?
    let thumbnail: KitsuEpisodeThumbnailAttributes?
}

struct KitsuCategoryAttributes: Decodable, Sendable {
    let title: String?
    let slug: String?
    let nsfw: Bool?
}

struct KitsuMediaRelationshipAttributes: Decodable, Sendable {
    let role: String?
}

struct KitsuMappingAttributes: Decodable, Sendable {
    let externalSite: String?
    let externalId: String?
}

/// Heterogeneous `included` payload for Kitsu detail requests.
///
/// Unknown resource types (for example `manga` destinations of adaptation
/// relationships) are tolerated and ignored rather than failing decoding.
enum KitsuIncludedResource: Decodable, Sendable {
    case anime(JSONAPIResource<KitsuAnimeAttributes>)
    case category(JSONAPIResource<KitsuCategoryAttributes>)
    case mediaRelationship(JSONAPIResource<KitsuMediaRelationshipAttributes>)
    case mapping(JSONAPIResource<KitsuMappingAttributes>)
    case episode(JSONAPIResource<KitsuEpisodeAttributes>)
    case unknown(type: String, id: String)

    private enum TypeKey: String, CodingKey {
        case type
        case id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "anime":
            self = .anime(try JSONAPIResource<KitsuAnimeAttributes>(from: decoder))
        case "categories":
            self = .category(try JSONAPIResource<KitsuCategoryAttributes>(from: decoder))
        case "mediaRelationships":
            self = .mediaRelationship(
                try JSONAPIResource<KitsuMediaRelationshipAttributes>(from: decoder)
            )
        case "mappings":
            self = .mapping(try JSONAPIResource<KitsuMappingAttributes>(from: decoder))
        case "episodes":
            self = .episode(try JSONAPIResource<KitsuEpisodeAttributes>(from: decoder))
        default:
            self = .unknown(
                type: type,
                id: try container.decode(String.self, forKey: .id)
            )
        }
    }
}
