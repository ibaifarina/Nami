import Foundation
import Testing
@testable import AnimeStreaming

struct PlaybackCompletionServiceTests {
    private let service = PlaybackCompletionService()

    @Test func completesAtEightyEightPercent() {
        #expect(service.isComplete(positionSeconds: 880, durationSeconds: 1000))
        #expect(service.isComplete(positionSeconds: 900, durationSeconds: 1000))
    }

    @Test func completesNearEndForLongEpisode() {
        // 52 seconds remaining after watching ~23 minutes.
        #expect(service.isComplete(positionSeconds: 1400, durationSeconds: 1452))
    }

    @Test func doesNotCompleteWhenBarelyWatched() {
        #expect(!service.isComplete(positionSeconds: 30, durationSeconds: 1400))
        #expect(!service.isComplete(positionSeconds: 120, durationSeconds: 1400))
    }

    @Test func doesNotCompleteAtHalfway() {
        #expect(!service.isComplete(positionSeconds: 700, durationSeconds: 1400))
    }

    @Test func zeroDurationIsNeverComplete() {
        #expect(!service.isComplete(positionSeconds: 100, durationSeconds: 0))
        #expect(!service.isComplete(positionSeconds: 0, durationSeconds: 0))
    }

    @Test func shortSpecialCompletesNearEnd() {
        #expect(service.isComplete(positionSeconds: 50, durationSeconds: 60))
    }

    @Test func positionBeyondDurationIsComplete() {
        #expect(service.isComplete(positionSeconds: 1500, durationSeconds: 1400))
    }

    @Test func completionFractionClamps() {
        #expect(service.completionFraction(positionSeconds: 700, durationSeconds: 1400) == 0.5)
        #expect(service.completionFraction(positionSeconds: 2000, durationSeconds: 1400) == 1)
        #expect(service.completionFraction(positionSeconds: 100, durationSeconds: 0) == 0)
    }

    @Test func customThresholdsAreRespected() {
        var strict = PlaybackCompletionService()
        strict.thresholds.completionFraction = 0.95
        strict.thresholds.remainingSeconds = 10
        #expect(!strict.isComplete(positionSeconds: 900, durationSeconds: 1000))
        #expect(strict.isComplete(positionSeconds: 960, durationSeconds: 1000))
    }
}
