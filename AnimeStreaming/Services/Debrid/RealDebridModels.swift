import Foundation

enum RealDebridModels {
    static let baseURL: URL = {
        guard let url = URL(string: "https://api.real-debrid.com/rest/1.0") else {
            preconditionFailure("Invalid Real-Debrid base URL")
        }
        return url
    }()

    static func parseErrorCode(_ body: String?) -> Int? {
        guard let body, let data = body.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ErrorResponse.self, from: data).error_code
    }

    static func parseErrorMessage(_ body: String?) -> String? {
        guard let body, let data = body.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ErrorResponse.self, from: data).error
    }

    static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}

struct RealDebridErrorResponse: Decodable, Sendable {
    let error: String?
    let error_code: Int?
}

extension RealDebridModels {
    typealias ErrorResponse = RealDebridErrorResponse
}

struct RealDebridUser: Decodable, Sendable {
    let id: Int
    let username: String
    let email: String?
    let points: Int?
    let type: String?
    let premium: Int?
    let expiration: String?
}

struct RealDebridAddMagnetResponse: Decodable, Sendable {
    let id: String
    let uri: String?
}

struct RealDebridTorrentFile: Decodable, Sendable {
    let id: Int
    let path: String
    let bytes: Int64
    let selected: Int?
}

struct RealDebridTorrentInfo: Decodable, Sendable {
    let id: String
    let hash: String?
    let filename: String?
    let status: String?
    let progress: Int?
    let links: [String]?
    let files: [RealDebridTorrentFile]?

    var fileInfos: [DebridFileInfo] {
        (files ?? []).map { file in
            DebridFileInfo(
                id: file.id,
                path: file.path,
                bytes: file.bytes,
                selected: file.selected == 1
            )
        }
    }
}

struct RealDebridTorrentListItem: Decodable, Sendable {
    let id: String
    let hash: String?
    let status: String?
}

struct RealDebridUnrestrictResponse: Decodable, Sendable {
    let id: String?
    let filename: String?
    let filesize: Int64?
    let download: String?
    let streamable: Int?
}

extension DebridAccount {
    init(realDebrid user: RealDebridUser) {
        self.init(
            id: user.id,
            username: user.username,
            email: user.email,
            type: DebridAccountType(raw: user.type),
            premiumSecondsRemaining: user.premium ?? 0,
            expiration: RealDebridModels.parseDate(user.expiration),
            points: user.points
        )
    }
}
