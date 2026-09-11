import Foundation
import Testing
@testable import Nami

struct TorrentFileSelectorTests {
    private func file(
        _ id: Int,
        _ path: String,
        bytes: Int64 = 1_000,
        selected: Bool = false
    ) -> DebridFileInfo {
        DebridFileInfo(id: id, path: path, bytes: bytes, selected: selected)
    }

    @Test func selectsFileMatchingRequestedEpisode() throws {
        let files = [
            file(1, "/Show - 01.mkv", bytes: 1_000_000),
            file(2, "/Show - 07.mkv", bytes: 1_400_000_000),
            file(3, "/Show - 07.srt", bytes: 20_000),
            file(4, "/sample.mkv", bytes: 5_000_000),
        ]

        let selection = try TorrentFileSelector.selectFile(from: files, targetEpisode: 7)

        #expect(selection.file.id == 2)
        #expect(selection.file.filename == "Show - 07.mkv")
    }

    @Test func prefersLargestAmongMultipleEpisodeMatches() throws {
        let files = [
            file(1, "/Show - 07 [720p].mkv", bytes: 600_000_000),
            file(2, "/Show - 07 [1080p].mkv", bytes: 1_400_000_000),
        ]

        let selection = try TorrentFileSelector.selectFile(from: files, targetEpisode: 7)

        #expect(selection.file.id == 2)
    }

    @Test func singleVideoFileFallbackWhenFilenameHasNoEpisode() throws {
        let files = [
            file(1, "/Show (Movie).mkv", bytes: 2_000_000_000),
            file(2, "/Show (Movie).srt", bytes: 30_000),
        ]

        let selection = try TorrentFileSelector.selectFile(from: files, targetEpisode: 1)

        #expect(selection.file.id == 1)
        #expect(selection.reason.contains("Only one video file"))
    }

    @Test func throwsWhenBatchMissesRequestedEpisode() {
        let files = [
            file(1, "/Show - 01.mkv"),
            file(2, "/Show - 02.mkv"),
            file(3, "/Show - 03.mkv"),
        ]

        #expect(throws: DebridError.self) {
            try TorrentFileSelector.selectFile(from: files, targetEpisode: 7)
        }
    }

    @Test func ignoresNonVideoFiles() {
        let files = [
            file(1, "/Show - 07.srt"),
            file(2, "/Show - 07.nfo"),
            file(3, "/fonts/font.ttf"),
        ]

        #expect(throws: DebridError.self) {
            try TorrentFileSelector.selectFile(from: files, targetEpisode: 7)
        }
    }

    @Test func excludesExtrasWhenMainEpisodeMissing() {
        let files = [
            file(1, "/NCED.mkv"),
            file(2, "/NCOP.mkv"),
        ]

        #expect(throws: DebridError.self) {
            try TorrentFileSelector.selectFile(from: files, targetEpisode: 7)
        }
    }

    @Test func picksLargestMainFileWhenNoTargetEpisode() throws {
        let files = [
            file(1, "/Show - 01.mkv", bytes: 1_000_000),
            file(2, "/Show - 02.mkv", bytes: 2_000_000),
            file(3, "/NCED.mkv", bytes: 9_000_000),
        ]

        let selection = try TorrentFileSelector.selectFile(from: files, targetEpisode: nil)

        #expect(selection.file.id == 2)
    }

    @Test func playableFilesHidesExtrasWhenMainFilesExist() {
        let files = [
            file(1, "/Movie Part 1.mkv", bytes: 1_000),
            file(2, "/Movie Part 2.mkv", bytes: 2_000),
            file(3, "/NCED.mkv", bytes: 9_000),
            file(4, "/Movie Part 1.srt", bytes: 10),
        ]

        let playable = TorrentFileSelector.playableFiles(from: files)

        #expect(playable.map(\.id) == [1, 2])
    }

    @Test func playableFilesKeepsExtrasWhenNothingElseExists() {
        let files = [
            file(1, "/NCED.mkv"),
            file(2, "/NCOP.mkv"),
            file(3, "/fonts/font.ttf"),
        ]

        let playable = TorrentFileSelector.playableFiles(from: files)

        #expect(playable.map(\.id) == [1, 2])
    }

    @Test func videoAndExtraDetection() {
        #expect(TorrentFileSelector.isVideo("Show - 07.mkv"))
        #expect(TorrentFileSelector.isVideo("Show - 07.MP4"))
        #expect(!TorrentFileSelector.isVideo("Show - 07.ass"))
        #expect(TorrentFileSelector.isExtra("Show - NCOP.mkv"))
        #expect(TorrentFileSelector.isExtra("Show.Sample.mkv"))
        #expect(!TorrentFileSelector.isExtra("Show - 07.mkv"))
    }
}
