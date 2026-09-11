import Foundation
import Testing
@testable import AnimeStreaming

struct KeychainStoreTests {
    @Test func roundTripStoresUpdatesAndDeletes() throws {
        let service = "com.auax.AnimeStreaming.tests.\(UUID().uuidString)"
        let store = KeychainStore(service: service)
        defer { try? store.delete("token") }

        #expect(try store.data(for: "token") == nil)

        try store.set(Data("secret".utf8), for: "token")
        #expect(try store.data(for: "token") == Data("secret".utf8))

        try store.set(Data("updated".utf8), for: "token")
        #expect(try store.data(for: "token") == Data("updated".utf8))

        try store.delete("token")
        #expect(try store.data(for: "token") == nil)
    }

    @Test func deletingMissingKeyDoesNotThrow() throws {
        let service = "com.auax.AnimeStreaming.tests.\(UUID().uuidString)"
        let store = KeychainStore(service: service)
        try store.delete("missing")
    }
}
