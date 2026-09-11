import Foundation
import Testing
@testable import AnimeStreaming

struct TimeoutTests {
    @Test func returnsFastResult() async throws {
        let value = try await withTimeout(.seconds(1)) { 42 }
        #expect(value == 42)
    }

    @Test func timesOutSlowOperation() async {
        do {
            _ = try await withTimeout(.milliseconds(30)) {
                try await Task.sleep(for: .milliseconds(500))
                return 1
            }
            Issue.record("Expected a timeout")
        } catch TimeoutError.timedOut {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func propagatesOperationError() async {
        do {
            _ = try await withTimeout(.seconds(1)) {
                throw AddonError.invalidURL
            }
            Issue.record("Expected an error")
        } catch let error as AddonError {
            #expect(error == .invalidURL)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

struct AddonURLPolicyTests {
    @Test func acceptsHTTPS() throws {
        try AddonURLPolicy.validate(
            testURL("https://example.com/manifest.json"),
            allowInsecureHTTP: false
        )
    }

    @Test func rejectsHTTPByDefault() {
        #expect(throws: AddonError.insecureURL) {
            try AddonURLPolicy.validate(
                testURL("http://example.com/manifest.json"),
                allowInsecureHTTP: false
            )
        }
    }

    @Test func allowsHTTPWithOverride() throws {
        try AddonURLPolicy.validate(
            testURL("http://localhost:8080/manifest.json"),
            allowInsecureHTTP: true
        )
    }

    @Test func rejectsFileScheme() {
        #expect(throws: AddonError.unsupportedScheme("file")) {
            try AddonURLPolicy.validate(
                testURL("file:///etc/passwd"),
                allowInsecureHTTP: false
            )
        }
    }

    @Test func rejectsEmbeddedCredentials() {
        #expect(throws: AddonError.credentialsInURL) {
            try AddonURLPolicy.validate(
                testURL("https://user:pass@example.com/manifest.json"),
                allowInsecureHTTP: false
            )
        }
    }

    @Test func rejectsURLWithoutHost() {
        #expect(throws: AddonError.invalidURL) {
            try AddonURLPolicy.validate(
                testURL("https:///manifest.json"),
                allowInsecureHTTP: false
            )
        }
    }
}
