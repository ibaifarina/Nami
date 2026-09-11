import Foundation

enum DebridAccountType: String, Codable, Sendable {
    case premium
    case free

    init(raw: String?) {
        self = raw?.lowercased() == "premium" ? .premium : .free
    }
}

struct DebridAccount: Hashable, Sendable {
    let id: Int
    let username: String
    let email: String?
    let type: DebridAccountType
    let premiumSecondsRemaining: Int
    let expiration: Date?
    let points: Int?

    var isPremium: Bool {
        type == .premium && premiumSecondsRemaining > 0
    }

    var expirationDescription: String? {
        guard let expiration else { return nil }
        return expiration.formatted(date: .abbreviated, time: .omitted)
    }
}

struct DebridFileInfo: Hashable, Sendable {
    let id: Int
    let path: String
    let bytes: Int64
    let selected: Bool

    var filename: String {
        (path as NSString).lastPathComponent
    }
}

struct DebridCheckResult: Hashable, Sendable {
    let candidateID: String
    let availability: DebridAvailability
    let files: [DebridFileInfo]
}

struct ResolvedStream: Hashable, Sendable {
    let url: URL
    let filename: String
    let sizeBytes: Int64?
    let streamable: Bool?
    let fileID: Int?
}
