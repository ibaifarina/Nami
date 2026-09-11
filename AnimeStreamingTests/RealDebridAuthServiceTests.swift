import Foundation
import Testing
@testable import AnimeStreaming

@MainActor
struct RealDebridAuthServiceTests {
    private struct Harness {
        let auth: RealDebridAuthService
        let secureStore: InMemorySecureStore
        let backend: DebridStubBackend
    }

    private func makeHarness(
        token: String? = nil,
        backend: DebridStubBackend = DebridStubBackend()
    ) -> Harness {
        var storage: [String: Data] = [:]
        if let token {
            storage["realdebrid.accessToken"] = Data(token.utf8)
        }
        let secureStore = InMemorySecureStore(storage: storage)
        let store = SecureTokenStore(secureStore: secureStore, key: "realdebrid.accessToken")
        let service = RealDebridService(
            tokenProvider: store,
            http: MockHTTPClient { request in
                try await backend.respond(to: request)
            },
            resolvePollInterval: .milliseconds(1)
        )
        let auth = RealDebridAuthService(service: service, tokenStore: store)
        return Harness(auth: auth, secureStore: secureStore, backend: backend)
    }

    @Test func connectValidatesSavesTokenAndConnects() async throws {
        let harness = makeHarness()

        await harness.auth.connect(token: "  rd-token  ")

        #expect(harness.auth.isConnected)
        #expect(harness.auth.account?.username == "tester")
        let saved = try harness.secureStore.data(for: "realdebrid.accessToken")
        #expect(saved == Data("rd-token".utf8))
    }

    @Test func connectRejectsNonPremiumWithoutSavingToken() async throws {
        let backend = DebridStubBackend(userType: "free", userPremiumSeconds: 0)
        let harness = makeHarness(backend: backend)

        await harness.auth.connect(token: "free-token")

        #expect(!harness.auth.isConnected)
        #expect(harness.auth.failureMessage?.contains("premium") == true)
        #expect(try harness.secureStore.data(for: "realdebrid.accessToken") == nil)
    }

    @Test func connectRejectsInvalidToken() async throws {
        let backend = DebridStubBackend(
            userError: (status: 401, code: 8, message: "Bad token")
        )
        let harness = makeHarness(backend: backend)

        await harness.auth.connect(token: "bad-token")

        #expect(!harness.auth.isConnected)
        #expect(harness.auth.failureMessage != nil)
        #expect(try harness.secureStore.data(for: "realdebrid.accessToken") == nil)
    }

    @Test func connectRejectsEmptyToken() async {
        let harness = makeHarness()

        await harness.auth.connect(token: "   ")

        #expect(!harness.auth.isConnected)
        #expect(harness.auth.failureMessage != nil)
    }

    @Test func restoreConnectsWithStoredToken() async {
        let harness = makeHarness(token: "stored-token")

        await harness.auth.restore()

        #expect(harness.auth.isConnected)
    }

    @Test func restoreClearsUnauthorizedToken() async throws {
        let backend = DebridStubBackend(
            userError: (status: 401, code: 8, message: "Bad token")
        )
        let harness = makeHarness(token: "stale-token", backend: backend)

        await harness.auth.restore()

        #expect(!harness.auth.isConnected)
        #expect(try harness.secureStore.data(for: "realdebrid.accessToken") == nil)
    }

    @Test func verifyKeepsTokenWhenServiceIsUnavailable() async throws {
        let backend = DebridStubBackend(
            userError: (status: 503, code: 25, message: "Service unavailable")
        )
        let harness = makeHarness(token: "good-token", backend: backend)

        await harness.auth.verify()

        #expect(!harness.auth.isConnected)
        #expect(harness.auth.failureMessage != nil)
        #expect(try harness.secureStore.data(for: "realdebrid.accessToken") == Data("good-token".utf8))
    }

    @Test func disconnectClearsTokenAndState() async throws {
        let harness = makeHarness(token: "stored-token")
        await harness.auth.restore()
        #expect(harness.auth.isConnected)

        await harness.auth.disconnect()

        #expect(!harness.auth.isConnected)
        #expect(try harness.secureStore.data(for: "realdebrid.accessToken") == nil)
    }
}
