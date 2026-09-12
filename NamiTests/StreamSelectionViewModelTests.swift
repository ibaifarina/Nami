import Foundation
import Testing
@testable import Nami

@MainActor
struct StreamSelectionViewModelTests {
    private func makeModel() -> StreamSelectionViewModel {
        let environment = AppEnvironment.preview()
        let anime = SampleCatalog.anime[0]
        return StreamSelectionViewModel(
            request: PlaybackRequest(anime: anime, episodeNumber: 1),
            environment: environment
        )
    }

    private func scored(_ index: Int, eligible: Bool = true) -> ScoredStream {
        let candidate = StreamCandidate(
            id: "candidate-\(index)",
            addonID: "addon",
            addonName: "Addon",
            displayTitle: "Show - \(index) [1080p]",
            infoHash: String(format: "%040d", index),
            episodeMatchConfidence: eligible ? 0.95 : 0.2
        )
        return ScoredStream(
            candidate: candidate,
            breakdown: StreamScoreBreakdown(),
            isAutoEligible: eligible,
            rejectionReasons: eligible ? [] : ["Episode match is too uncertain"]
        )
    }

    @Test func limitsRenderedSourcesAndPagesOnDemand() {
        let model = makeModel()
        model.ranked = (0..<120).map { scored($0) }

        #expect(model.visibleStreams.count == 50)
        #expect(model.bestMatch?.candidate.id == "candidate-0")
        #expect(model.otherStreams.count == 49)
        #expect(model.otherSourceCount == 119)
        #expect(model.totalSourceCount == 120)
        #expect(model.hasMoreSources)

        model.showMoreSources()
        #expect(model.visibleStreams.count == 100)
        #expect(model.hasMoreSources)

        model.showMoreSources()
        #expect(model.visibleStreams.count == 120)
        #expect(!model.hasMoreSources)

        model.showMoreSources()
        #expect(model.visibleStreams.count == 120)
    }

    @Test func rejectedSourcesOnlyAppearAfterEligibleOnes() {
        let model = makeModel()
        model.ranked = (0..<3).map { scored($0) }
            + (0..<3).map { scored(100 + $0, eligible: false) }

        #expect(model.visibleStreams.count == 6)
        #expect(model.otherStreams.count == 2)
        #expect(model.visibleRejectedStreams.count == 3)
        #expect(model.rejectedStreams.count == 3)
    }

    @Test func rejectedSourcesBeyondThePageStayHidden() {
        let model = makeModel()
        model.ranked = (0..<60).map { scored($0) }
            + (0..<10).map { scored(100 + $0, eligible: false) }

        #expect(model.visibleRejectedStreams.isEmpty)
        model.showMoreSources()
        #expect(model.visibleRejectedStreams.count == 10)
    }
}
