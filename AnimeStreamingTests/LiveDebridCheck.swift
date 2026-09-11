import Foundation
import Testing
@testable import AnimeStreaming

struct LiveDebridCheck {
    @Test func invalidTokenMapsToUnauthorized() async throws {
        guard ProcessInfo.processInfo.environment["LIVE_DEBRID"] == "1" else {
            return
        }
        let service = RealDebridService(
            tokenProvider: StubDebridTokenProvider(token: nil),
            http: URLSessionHTTPClient()
        )

        do {
            _ = try await service.validateAccount(token: "invalid-token-for-testing")
            Issue.record("Expected an unauthorized error")
        } catch let error as DebridError {
            #expect(error == .unauthorized)
        }
    }
}
