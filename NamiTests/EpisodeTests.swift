import Foundation
import Testing
@testable import Nami

struct EpisodeTests {
    private func episode(
        number: Int,
        relativeNumber: Int? = nil,
        seasonNumber: Int? = nil,
        absoluteNumber: Int? = nil,
        title: String? = nil,
        synopsis: String? = nil,
        durationMinutes: Int? = nil,
        airDate: Date? = nil
    ) -> Episode {
        Episode(
            id: "7442-ep-\(number)",
            animeID: "7442",
            number: number,
            relativeNumber: relativeNumber,
            seasonNumber: seasonNumber,
            absoluteNumber: absoluteNumber,
            title: title,
            synopsis: synopsis,
            thumbnailURL: nil,
            airDate: airDate,
            durationMinutes: durationMinutes
        )
    }

    @Test func missingTitleFallsBackToEpisodeNumber() {
        #expect(episode(number: 3).displayTitle == "Episode 3")
        #expect(!episode(number: 3).hasTitle)
        #expect(episode(number: 3, title: "").displayTitle == "Episode 3")
    }

    @Test func presentTitleIsUsed() {
        let value = episode(number: 3, title: "That Day")
        #expect(value.displayTitle == "That Day")
        #expect(value.hasTitle)
    }

    @Test func relativeNumberWinsForDisplay() {
        let value = episode(number: 28, relativeNumber: 3, seasonNumber: 2)
        #expect(value.displayNumber == 3)
        #expect(value.displayTitle == "Episode 3")
    }

    @Test func absoluteNumberIsPreservedIndependently() {
        let value = episode(number: 3, relativeNumber: 3, seasonNumber: 2, absoluteNumber: 28)
        #expect(value.displayNumber == 3)
        #expect(value.absoluteNumber == 28)
    }

    @Test func withAbsoluteNumberAssignsWhenMissing() {
        let value = episode(number: 4).withAbsoluteNumber(29)
        #expect(value.absoluteNumber == 29)
        #expect(value.displayNumber == 4)
    }

    @Test func missingSynopsisIsDetectable() {
        #expect(!episode(number: 1, synopsis: nil).hasSynopsis)
        #expect(!episode(number: 1, synopsis: "   ").hasSynopsis)
        #expect(episode(number: 1, synopsis: "A synopsis").hasSynopsis)
    }

    @Test func displaySynopsisRemovesSourceAttribution() {
        let value = episode(number: 1, synopsis: "A great episode.\n\n(Source: Wikipedia)\n\n")
        #expect(value.displaySynopsis == "A great episode.")
        #expect(value.displaySynopsis?.contains("Source") == false)
    }

    @Test func displaySynopsisKeepsPlainText() {
        let value = episode(number: 1, synopsis: "Just the synopsis.")
        #expect(value.displaySynopsis == "Just the synopsis.")
    }

    @Test func displaySynopsisIsNilWhenOnlySource() {
        #expect(episode(number: 1, synopsis: "(Source: ANN)").displaySynopsis == nil)
        #expect(episode(number: 1, synopsis: nil).displaySynopsis == nil)
    }

    @Test func formatsEpisodeDuration() {
        #expect(episode(number: 1, durationMinutes: 24).durationText == "24m")
        #expect(episode(number: 1, durationMinutes: 60).durationText == "1h")
        #expect(episode(number: 1, durationMinutes: 92).durationText == "1h 32m")
        #expect(episode(number: 1, durationMinutes: nil).durationText == nil)
        #expect(episode(number: 1, durationMinutes: 0).durationText == nil)
    }

    @Test func airDateTextHidesWhenMissing() {
        #expect(episode(number: 1, airDate: nil).airDateText == nil)
        #expect(episode(number: 1, airDate: Date()).airDateText != nil)
    }

    @Test func progressFractionAndRemaining() {
        let progress = PlaybackProgress(
            animeID: "7442",
            episodeNumber: 7,
            positionSeconds: 1_111,
            durationSeconds: 1_452,
            updatedAt: Date()
        )
        #expect(abs(progress.fraction - 0.765) < 0.01)
        #expect(abs(progress.percentage - 76.5) < 1)
        #expect(abs(progress.remainingSeconds - 341) < 0.1)
        #expect(progress.timecode == "18:31 / 24:12")
    }

    @Test func progressFractionIsClamped() {
        let progress = PlaybackProgress(
            animeID: "7442",
            episodeNumber: 1,
            positionSeconds: 5_000,
            durationSeconds: 1_000,
            updatedAt: Date()
        )
        #expect(progress.fraction == 1)
        #expect(progress.remainingSeconds == 0)
    }

    @Test func animeSnapshotIsNilWithoutStoredTitle() {
        let progress = PlaybackProgress(
            animeID: "7442",
            episodeNumber: 1,
            positionSeconds: 10,
            durationSeconds: 100,
            updatedAt: Date()
        )
        #expect(progress.animeSnapshot == nil)

        var withTitle = progress
        withTitle.animeTitle = "Attack on Titan"
        #expect(withTitle.animeSnapshot?.displayTitle == "Attack on Titan")
        #expect(withTitle.animeSnapshot?.id == "7442")
    }

    @Test func timecodeFormatting() {
        #expect(Timecode.format(0) == "0:00")
        #expect(Timecode.format(61) == "1:01")
        #expect(Timecode.format(3_723) == "1:02:03")
        #expect(Timecode.format(.nan) == "0:00")
    }
}
