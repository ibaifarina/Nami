import Foundation

protocol SecureStore: Sendable {
    func set(_ data: Data, for key: String) throws
    func data(for key: String) throws -> Data?
    func delete(_ key: String) throws
}
