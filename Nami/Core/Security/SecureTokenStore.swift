import Foundation

enum SecureTokenError: Error, Equatable, Sendable {
    case storeFailed
}

protocol DebridTokenProviding: Sendable {
    func token() async -> String?
}

actor SecureTokenStore: DebridTokenProviding {
    private let secureStore: any SecureStore
    private let key: String
    private var cachedToken: String?

    init(secureStore: any SecureStore, key: String) {
        self.secureStore = secureStore
        self.key = key
    }

    func token() -> String? {
        if let cachedToken {
            return cachedToken
        }
        guard
            let data = try? secureStore.data(for: key),
            let value = String(data: data, encoding: .utf8),
            !value.isEmpty
        else {
            return nil
        }
        cachedToken = value
        return value
    }

    func save(_ token: String) throws {
        do {
            try secureStore.set(Data(token.utf8), for: key)
        } catch {
            AppLogger.persistence.error("Failed to store token in Keychain")
            throw SecureTokenError.storeFailed
        }
        cachedToken = token
    }

    func clear() {
        try? secureStore.delete(key)
        cachedToken = nil
    }
}
