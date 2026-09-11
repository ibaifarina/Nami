import Foundation
import Testing
@testable import Nami

struct GenericHTTPAddonAdapterTests {
    private let descriptor = AddonDescriptor(
        id: "example.provider",
        name: "Example Provider",
        version: "1.0.0",
        protocolType: .animeStreamV1,
        capabilities: [.streams],
        idNamespaces: [.anilist, .mal],
        baseURL: testURL("https://example.com"),
        manifestURL: testURL("https://example.com/manifest.json")
    )

    private let media = MediaIdentity(kitsuID: "7442", malID: 5114, anilistID: 52991)
    private let episode = Episode(id: "7442-7", animeID: "7442", number: 7)

    @Test func sendsExpectedRequestAndNormalizesStreams() async throws {
        let http = MockHTTPClient { _ in AddonFixtures.genericStreamsJSON }
        let adapter = GenericHTTPAddonAdapter(
            descriptor: descriptor,
            streamsPath: "/v1/streams",
            http: http
        )

        let results = try await adapter.streams(for: media, episode: episode)

        #expect(results.count == 3)
        let first = try #require(results.first)
        #expect(first.infoHash == "aabbccddeeff")
        #expect(first.seeders == 120)
        #expect(first.providerMetadata["quality"] == "1080p")
        #expect(first.providerMetadata["group"] == "Group")
        #expect(results.contains { $0.directURL?.absoluteString == "https://example.com/stream.mp4" })
        #expect(results.allSatisfy { $0.addonID == descriptor.id })

        let request = try #require(await http.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://example.com/v1/streams")

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["anilistId"] as? Int == 52991)
        #expect(json["malId"] as? Int == 5114)
        #expect(json["episode"] as? Int == 7)
        #expect(json["season"] as? Int == 1)
    }

    @Test func filtersUnusableStreams() async throws {
        let http = MockHTTPClient { _ in AddonFixtures.genericStreamsJSON }
        let adapter = GenericHTTPAddonAdapter(
            descriptor: descriptor,
            streamsPath: "/v1/streams",
            http: http
        )

        let results = try await adapter.streams(for: media, episode: episode)

        #expect(!results.contains { $0.displayTitle == "Local file" })
        #expect(!results.contains { $0.displayTitle == "Nothing usable" })
    }

    @Test func healthCheckReportsHealthy() async {
        let adapter = GenericHTTPAddonAdapter(
            descriptor: descriptor,
            streamsPath: "/v1/streams",
            http: MockHTTPClient { _ in AddonFixtures.genericManifestJSON }
        )

        #expect(await adapter.healthCheck() == .healthy)
    }

    @Test func healthCheckReportsFailing() async {
        let adapter = GenericHTTPAddonAdapter(
            descriptor: descriptor,
            streamsPath: "/v1/streams",
            http: MockHTTPClient { _ in
                throw HTTPError.transport("down")
            }
        )

        #expect(await adapter.healthCheck() == .failing)
    }

    @Test func mapsOversizedStreamResponse() async {
        let adapter = GenericHTTPAddonAdapter(
            descriptor: descriptor,
            streamsPath: "/v1/streams",
            http: MockHTTPClient { _ in
                throw HTTPError.responseTooLarge(limit: 10)
            }
        )

        do {
            _ = try await adapter.streams(for: media, episode: episode)
            Issue.record("Expected response-too-large error")
        } catch let error as AddonError {
            #expect(error == .responseTooLarge)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func malformedResponseFailsGracefully() async {
        let adapter = GenericHTTPAddonAdapter(
            descriptor: descriptor,
            streamsPath: "/v1/streams",
            http: MockHTTPClient { _ in Data("<html>oops</html>".utf8) }
        )

        do {
            _ = try await adapter.streams(for: media, episode: episode)
            Issue.record("Expected request failure")
        } catch let error as AddonError {
            guard case .requestFailed = error else {
                Issue.record("Unexpected addon error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
