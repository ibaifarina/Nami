import Foundation

struct PlaybackCompletionService: Sendable {
    struct Thresholds: Hashable, Sendable {
        var completionFraction: Double = 0.88
        var remainingSeconds: Double = 90
        var minimumWatchedSeconds: Double = 300
        var minimumWatchedFraction: Double = 0.5
    }

    var thresholds = Thresholds()

    func isComplete(positionSeconds: Double, durationSeconds: Double) -> Bool {
        guard durationSeconds > 0, positionSeconds > 0 else { return false }
        let position = min(positionSeconds, durationSeconds)
        let fraction = position / durationSeconds
        if fraction >= thresholds.completionFraction {
            return true
        }
        let remaining = durationSeconds - position
        let watchedSubstantially = position >= thresholds.minimumWatchedSeconds
            || fraction >= thresholds.minimumWatchedFraction
        return remaining <= thresholds.remainingSeconds && watchedSubstantially
    }

    func completionFraction(positionSeconds: Double, durationSeconds: Double) -> Double {
        guard durationSeconds > 0 else { return 0 }
        return min(max(positionSeconds / durationSeconds, 0), 1)
    }
}
