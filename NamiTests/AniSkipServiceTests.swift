import Foundation
import Testing
@testable import Nami

struct AniSkipServiceTests {
    private var responseJSON: Data {
        Data("""
        {
          "found": true,
          "results": [
            {
              "interval": { "startTime": 12.5, "endTime": 102.5 },
              "skipType": "op",
              "skipId": "1",
              "episodeLength": 1420
            },
            {
              "interval": { "startTime": 1330, "endTime": 1420 },
              "skipType": "ed",
              "skipId": "2",
              "episodeLength": 1420
            },
            {
              "interval": { "startTime": 0, "endTime": 12.5 },
              "skipType": "recap",
              "skipId": "3",
              "episodeLength": 1420
            }
          ],
          "statusCode": 200
        }
        """.utf8)
    }

    @Test func decodesIntervals() async {
        let http = MockHTTPClient { _ in responseJSON }
        let service = AniSkipService(http: http)

        let intervals = await service.intervals(
            malID: 16498,
            episodeNumber: 1,
            episodeLengthSeconds: 1420
        )

        #expect(intervals.count == 3)
        #expect(intervals[0].kind == .opening)
        #expect(intervals[0].startSeconds == 12.5)
        #expect(intervals[0].endSeconds == 102.5)
        #expect(intervals[1].kind == .ending)
        #expect(intervals[2].kind == .recap)
    }

    @Test func buildsRequestWithAllTypesAndRoundedLength() async throws {
        let http = MockHTTPClient { _ in Data("{\"found\": false}".utf8) }
        let service = AniSkipService(http: http)

        _ = await service.intervals(
            malID: 52991,
            episodeNumber: 3,
            episodeLengthSeconds: 1441.6
        )

        let request = try #require(await http.lastRequest)
        let url = try #require(request.url)
        #expect(url.path() == "/v2/skip-times/52991/3")
        let queryItems = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )
        let types = queryItems.filter { $0.name == "types" }.map(\.value)
        #expect(types == ["op", "ed", "recap", "mixed-op", "mixed-ed"])
        #expect(queryItems.first { $0.name == "episodeLength" }?.value == "1442")
    }

    @Test func omitsEpisodeLengthWhenUnknown() async throws {
        let http = MockHTTPClient { _ in Data("{\"found\": false}".utf8) }
        let service = AniSkipService(http: http)

        _ = await service.intervals(malID: 52991, episodeNumber: 3)

        let request = try #require(await http.lastRequest)
        let url = try #require(request.url)
        let queryItems = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )
        #expect(!queryItems.contains { $0.name == "episodeLength" })
    }

    @Test func notFoundReturnsEmpty() async {
        let http = MockHTTPClient { _ in throw HTTPError.httpStatus(code: 404, body: nil) }
        let service = AniSkipService(http: http)

        let intervals = await service.intervals(malID: 1, episodeNumber: 1)

        #expect(intervals.isEmpty)
    }

    @Test func foundFalseReturnsEmpty() async {
        let http = MockHTTPClient { _ in Data("{\"found\": false, \"statusCode\": 200}".utf8) }
        let service = AniSkipService(http: http)

        let intervals = await service.intervals(malID: 1, episodeNumber: 1)

        #expect(intervals.isEmpty)
    }

    @Test func serverFailureReturnsEmpty() async {
        let http = MockHTTPClient { _ in throw HTTPError.httpStatus(code: 500, body: nil) }
        let service = AniSkipService(http: http)

        let intervals = await service.intervals(malID: 1, episodeNumber: 1)

        #expect(intervals.isEmpty)
    }

    @Test func dropsMalformedAndUnknownIntervals() async {
        let json = Data("""
        {
          "found": true,
          "results": [
            { "interval": { "startTime": 100, "endTime": 90 }, "skipType": "op" },
            { "interval": { "startTime": 5, "endTime": 10 }, "skipType": "something" },
            { "interval": { "startTime": 20, "endTime": 30 }, "skipType": "mixed-op" }
          ]
        }
        """.utf8)
        let http = MockHTTPClient { _ in json }
        let service = AniSkipService(http: http)

        let intervals = await service.intervals(malID: 1, episodeNumber: 1)

        #expect(intervals.count == 1)
        #expect(intervals.first?.kind == .mixedOpening)
    }

    @Test func cachesResultsPerLookup() async {
        let http = MockHTTPClient { _ in responseJSON }
        let service = AniSkipService(http: http)

        _ = await service.intervals(malID: 16498, episodeNumber: 1, episodeLengthSeconds: 1420)
        _ = await service.intervals(malID: 16498, episodeNumber: 1, episodeLengthSeconds: 1420)

        #expect(await http.requestCount == 1)
    }
}
