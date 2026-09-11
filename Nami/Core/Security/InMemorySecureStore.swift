import Foundation

final class InMemorySecureStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    init(storage: [String: Data] = [:]) {
        self.storage = storage
    }

    func set(_ data: Data, for key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = data
    }

    func data(for key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func delete(_ key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = nil
    }
}
