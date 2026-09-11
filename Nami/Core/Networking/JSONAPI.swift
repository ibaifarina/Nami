import Foundation

/// Minimal JSON:API structures covering exactly what the Kitsu endpoints used
/// by this app return: resources, relationships, pagination links and metadata.
struct JSONAPILinks: Decodable, Sendable {
    let first: URL?
    let next: URL?
    let last: URL?
    let prev: URL?
}

struct JSONAPIMeta: Decodable, Sendable {
    let count: Int?
}

struct JSONAPIResourceIdentifier: Decodable, Sendable {
    let type: String
    let id: String
}

/// JSON:API relationships may be to-one (object) or to-many (array).
enum JSONAPIRelationshipData: Decodable, Sendable {
    case one(JSONAPIResourceIdentifier)
    case many([JSONAPIResourceIdentifier])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let many = try? container.decode([JSONAPIResourceIdentifier].self) {
            self = .many(many)
        } else {
            self = .one(try container.decode(JSONAPIResourceIdentifier.self))
        }
    }

    var first: JSONAPIResourceIdentifier? {
        switch self {
        case .one(let value): value
        case .many(let values): values.first
        }
    }
}

struct JSONAPIRelationship: Decodable, Sendable {
    struct Links: Decodable, Sendable {
        let related: URL?
        let `self`: URL?
    }

    let links: Links?
    let data: JSONAPIRelationshipData?
}

struct JSONAPIResource<Attributes: Decodable & Sendable>: Decodable, Sendable {
    let type: String
    let id: String
    let attributes: Attributes
    let relationships: [String: JSONAPIRelationship]?
}

struct JSONAPIDocument<Data: Decodable & Sendable, Included: Decodable & Sendable>: Decodable, Sendable {
    let data: Data
    let included: [Included]?
    let links: JSONAPILinks?
    let meta: JSONAPIMeta?
}
