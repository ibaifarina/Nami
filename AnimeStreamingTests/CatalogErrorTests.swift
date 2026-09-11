import Foundation
import Testing
@testable import AnimeStreaming

struct CatalogErrorTests {
    @Test func forbiddenMapsToUnavailable() {
        let error = CatalogError.map(HTTPError.httpStatus(code: 403, body: nil))
        #expect(error == .unavailable)
    }

    @Test func offlineMapsToOffline() {
        let error = CatalogError.map(HTTPError.offline)
        #expect(error == .offline)
    }

    @Test func timeoutMapsToTimeout() {
        let error = CatalogError.map(HTTPError.timedOut)
        #expect(error == .timeout)
    }

    @Test func notFoundMapsToNotFound() {
        let error = CatalogError.map(HTTPError.httpStatus(code: 404, body: nil))
        #expect(error == .notFound)
    }

    @Test func decodingMapsToDecoding() {
        let error = CatalogError.map(HTTPError.decoding("bad key"))
        #expect(error == .decoding)
    }

    @Test func unauthorizedStatusMapsToUnauthorized() {
        #expect(CatalogError.map(HTTPError.httpStatus(code: 401, body: nil)) == .unauthorized)
    }

    @Test func invalidTokenBodyMapsToUnauthorized() {
        let body = #"{"errors":[{"message":"Invalid token"}]}"#
        #expect(CatalogError.map(HTTPError.httpStatus(code: 400, body: body)) == .unauthorized)
    }

    @Test func rateLimitMapsToServerMessage() {
        let error = CatalogError.map(HTTPError.httpStatus(code: 429, body: nil))
        guard case .server(let message) = error else {
            Issue.record("Expected server error, got \(error)")
            return
        }
        #expect(message.lowercased().contains("rate limit"))
    }

    @Test func serverErrorMapsToServer() {
        let error = CatalogError.map(HTTPError.httpStatus(code: 500, body: "boom"))
        guard case .server = error else {
            Issue.record("Expected server error, got \(error)")
            return
        }
    }

    @Test func unavailableMentionsKitsu() {
        #expect(CatalogError.unavailable.errorDescription?.contains("Kitsu") == true)
        #expect(CatalogError.unavailable.recoverySuggestion?.contains("Cached") == true)
    }

    @Test func errorsHaveUserFacingMessages() {
        #expect(CatalogError.unavailable.errorDescription?.isEmpty == false)
        #expect(CatalogError.offline.errorDescription?.isEmpty == false)
        #expect(CatalogError.notFound.errorDescription?.isEmpty == false)
        #expect(CatalogError.server("HTTP 500").errorDescription?.isEmpty == false)
    }
}
