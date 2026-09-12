import Foundation
import Testing
@testable import Nami

struct AddonCalibrationServiceTests {
    private struct StubAnalyzer: StreamFormatAnalyzing {
        var isAvailable = true
        var result: LearnedStreamFormat = .empty
        var failure: Error?

        func analyze(_ batch: CalibrationSampleBatch) async throws -> LearnedStreamFormat {
            if let failure { throw failure }
            return result
        }
    }

    /// Throws `inputTooLarge` while the batch exceeds the limit, recording the
    /// size of every batch it was asked to analyze.
    private actor ShrinkingAnalyzer: StreamFormatAnalyzing {
        nonisolated let isAvailable = true
        private let limit: Int
        private let result: LearnedStreamFormat
        private(set) var receivedCounts: [Int] = []

        init(limit: Int, result: LearnedStreamFormat) {
            self.limit = limit
            self.result = result
        }

        func analyze(_ batch: CalibrationSampleBatch) async throws -> LearnedStreamFormat {
            receivedCounts.append(batch.totalCount)
            guard batch.totalCount <= limit else {
                throw StreamFormatAnalyzerError.inputTooLarge
            }
            return result
        }
    }

    private static let streamsJSON = Data("""
    {
      "streams": [
        {
          "name": "Source A",
          "title": "Frieren E10 1080p HEVC",
          "infoHash": "aabbccddeeff00112233445566778899aabbccdd"
        },
        {
          "name": "Source B",
          "title": "Frieren E10 720p x264",
          "infoHash": "aabbccddeeff00112233445566778899aabbccde"
        },
        {
          "name": "Source C",
          "title": "Frieren E10 2160p AV1",
          "infoHash": "aabbccddeeff00112233445566778899aabbccdf"
        },
        {
          "name": "RD+ cached",
          "title": "Frieren E10 1080p HEVC 5.2 GB",
          "infoHash": "aabbccddeeff00112233445566778899aabbccd0"
        },
        {
          "name": "Source E",
          "title": "Frieren E10 1080p AVC",
          "infoHash": "aabbccddeeff00112233445566778899aabbccd1"
        },
        {
          "name": "Source F",
          "title": "Frieren E10 720p HEVC Dual Audio",
          "infoHash": "aabbccddeeff00112233445566778899aabbccd2"
        }
      ]
    }
    """.utf8)

    private static let learnedFormat = LearnedStreamFormat(
        episodeRules: [
            LearnedStreamFormat.Rule(
                attribute: "resolution",
                sourceField: "title",
                patterns: ["1080p", "720p", "2160p"],
                confidence: 0.9
            ),
            LearnedStreamFormat.Rule(
                attribute: "cached",
                sourceField: "name",
                patterns: ["RD+"],
                confidence: 0.9
            ),
        ],
        movieRules: [
            LearnedStreamFormat.Rule(
                attribute: "resolution",
                sourceField: "title",
                patterns: ["1080p", "720p", "2160p"],
                confidence: 0.9
            ),
        ],
        confidence: 0.9
    )

    private func addon(
        id: String = "org.example.custom",
        name: String = "Custom Addon"
    ) -> InstalledAddon {
        InstalledAddon(
            id: id,
            name: name,
            manifestURL: testURL("https://custom.example/manifest.json"),
            baseURL: testURL("https://custom.example"),
            protocolType: .stremio,
            priority: 0,
            idNamespaces: [.kitsu],
            supportedTypes: ["anime", "movie", "series"]
        )
    }

    @Test func calibratesAndSavesSeparateProfiles() async {
        let http = MockHTTPClient { _ in Self.streamsJSON }
        let store = ParsingProfileStore(directory: nil)
        let service = AddonCalibrationService(
            addonManager: AddonManager(http: http),
            profileStore: store,
            analyzer: StubAnalyzer(result: Self.learnedFormat)
        )
        let installed = addon()

        let report = await service.calibrate(addon: installed)

        #expect(report.status == .success)
        #expect(report.coverage == 1)
        let fingerprint = AddonFingerprint(
            addonID: installed.id,
            manifestURL: installed.manifestURL
        )
        let stored = await store.profile(for: fingerprint)
        #expect(stored?.status == .success)
        #expect(stored?.episode?.isEmpty == false)
        #expect(stored?.movie?.isEmpty == false)
        #expect(stored?.episode?.rules(for: .resolution).isEmpty == false)
        // Three episode samples from the primary + fallback titles and at most
        // two movie samples: bounded and well short of fetching everything.
        let requestCount = await http.requestCount
        #expect(requestCount <= 5)
    }

    @Test func skipsRecalibrationWhenProfileAlreadyExists() async {
        let http = MockHTTPClient { _ in Self.streamsJSON }
        let store = ParsingProfileStore(directory: nil)
        let service = AddonCalibrationService(
            addonManager: AddonManager(http: http),
            profileStore: store,
            analyzer: StubAnalyzer(result: Self.learnedFormat)
        )
        let installed = addon()

        _ = await service.calibrate(addon: installed)
        let firstCount = await http.requestCount
        let second = await service.calibrate(addon: installed)

        #expect(second.status == .success)
        #expect(await http.requestCount == firstCount)
    }

    @Test func reportsUnavailableWithoutAnalyzer() async {
        let http = MockHTTPClient { _ in Self.streamsJSON }
        let store = ParsingProfileStore(directory: nil)
        let service = AddonCalibrationService(
            addonManager: AddonManager(http: http),
            profileStore: store,
            analyzer: nil
        )
        let installed = addon()

        let report = await service.calibrate(addon: installed)

        #expect(report.status == .unavailable)
        #expect(report.title == "Addon installed")
        let fingerprint = AddonFingerprint(
            addonID: installed.id,
            manifestURL: installed.manifestURL
        )
        #expect(await store.profile(for: fingerprint)?.status == .unavailable)
    }

    @Test func reportsFailureWhenModelLearnsNothing() async {
        let http = MockHTTPClient { _ in Self.streamsJSON }
        let store = ParsingProfileStore(directory: nil)
        let service = AddonCalibrationService(
            addonManager: AddonManager(http: http),
            profileStore: store,
            analyzer: StubAnalyzer(result: .empty)
        )

        let report = await service.calibrate(addon: addon())

        #expect(report.status == .failure)
        #expect(report.title == "Addon format not recognized")
    }

    @Test func shrinksAnalysisBatchWhenModelInputIsTooLarge() async {
        let http = MockHTTPClient { _ in Self.streamsJSON }
        let store = ParsingProfileStore(directory: nil)
        let analyzer = ShrinkingAnalyzer(limit: 3, result: Self.learnedFormat)
        let service = AddonCalibrationService(
            addonManager: AddonManager(http: http),
            profileStore: store,
            analyzer: analyzer
        )

        let report = await service.calibrate(addon: addon())

        #expect(report.status == .success)
        let received = await analyzer.receivedCounts
        #expect(received.first == 5)
        #expect(received.last ?? .max <= 3)
        #expect(received.count >= 2)
    }

    @Test func reportsUnavailableWhenModelInputNeverFits() async {
        let http = MockHTTPClient { _ in Self.streamsJSON }
        let store = ParsingProfileStore(directory: nil)
        let service = AddonCalibrationService(
            addonManager: AddonManager(http: http),
            profileStore: store,
            analyzer: StubAnalyzer(failure: StreamFormatAnalyzerError.inputTooLarge)
        )
        let installed = addon()

        let report = await service.calibrate(addon: installed)

        #expect(report.status == .unavailable)
        let fingerprint = AddonFingerprint(
            addonID: installed.id,
            manifestURL: installed.manifestURL
        )
        #expect(await store.profile(for: fingerprint)?.status == .unavailable)
    }

    @Test func analysisBatchSpreadsAcrossTitles() {
        let episodes = (1...6).map { index in
            CalibrationSample(
                titleName: index <= 3 ? "Title A" : "Title B",
                kind: .episode,
                fields: [.title: "Show E\(index) 1080p"]
            )
        }
        let batch = CalibrationSampleBatch(episodes: episodes, movies: [])
        let limited = AddonCalibrationService.analysisBatch(
            from: batch,
            episodeLimit: 3,
            movieLimit: 0
        )

        #expect(limited.movies.isEmpty)
        #expect(limited.episodes.count == 3)
        #expect(Set(limited.episodes.map(\.titleName)) == ["Title A", "Title B"])
    }

    @Test func reportsFailureWhenAnalyzerThrows() async {
        let http = MockHTTPClient { _ in Self.streamsJSON }
        let store = ParsingProfileStore(directory: nil)
        let service = AddonCalibrationService(
            addonManager: AddonManager(http: http),
            profileStore: store,
            analyzer: StubAnalyzer(failure: StreamFormatAnalyzerError.generationFailed("boom"))
        )

        let report = await service.calibrate(addon: addon())

        #expect(report.status == .failure)
    }

    @Test func reportsFailureWhenAddonReturnsNoStreams() async {
        let http = MockHTTPClient { _ in Data(#"{"streams":[]}"#.utf8) }
        let store = ParsingProfileStore(directory: nil)
        let analyzer = StubAnalyzer(result: Self.learnedFormat)
        let service = AddonCalibrationService(
            addonManager: AddonManager(http: http),
            profileStore: store,
            analyzer: analyzer
        )

        let report = await service.calibrate(addon: addon())

        #expect(report.status == .failure)
    }

    @Test func optimizedAddonsSkipCalibrationEntirely() async {
        let http = MockHTTPClient { _ in Self.streamsJSON }
        let store = ParsingProfileStore(directory: nil)
        let service = AddonCalibrationService(
            addonManager: AddonManager(http: http),
            profileStore: store,
            analyzer: StubAnalyzer(result: Self.learnedFormat)
        )
        let installed = addon(id: "org.stremio.torrentio.addon", name: "Torrentio")

        let report = await service.calibrate(addon: installed)

        #expect(report.status == .skipped)
        #expect(await http.requestCount == 0)
    }

    @Test func profileStoreSummariesIncludeCalibratedAddon() async {
        let http = MockHTTPClient { _ in Self.streamsJSON }
        let store = ParsingProfileStore(directory: nil)
        let service = AddonCalibrationService(
            addonManager: AddonManager(http: http),
            profileStore: store,
            analyzer: StubAnalyzer(result: Self.learnedFormat)
        )
        let installed = addon()
        _ = await service.calibrate(addon: installed)

        let summaries = await service.summaries(for: [installed])

        #expect(summaries[installed.id]?.status == .success)
    }
}
