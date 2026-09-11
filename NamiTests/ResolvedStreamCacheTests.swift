import Foundation
import Testing
@testable import Nami

struct ResolvedStreamCacheTests {
    private func stream(_ name: String) -> ResolvedStream {
        ResolvedStream(
            url: testURL("https://resolved.example/\(name).mp4"),
            filename: "\(name).mp4",
            sizeBytes: 1_000_000,
            streamable: true,
            fileID: 1
        )
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "resolved-stream-cache-\(UUID().uuidString).json")
    }

    @Test func storesAndReturnsStreamForEpisode() async {
        let cache = ResolvedStreamCache(fileURL: nil)
        let saved = stream("a")
        await cache.store(saved, candidateID: "one", animeID: "1", episodeNumber: 7)

        let loaded = await cache.stream(animeID: "1", episodeNumber: 7)
        #expect(loaded == saved)
    }

    @Test func candidateMismatchReturnsNil() async {
        let cache = ResolvedStreamCache(fileURL: nil)
        await cache.store(stream("a"), candidateID: "one", animeID: "1", episodeNumber: 7)

        let mismatch = await cache.stream(animeID: "1", episodeNumber: 7, candidateID: "two")
        let match = await cache.stream(animeID: "1", episodeNumber: 7, candidateID: "one")
        #expect(mismatch == nil)
        #expect(match != nil)
    }

    @Test func expiredEntriesAreNotServed() async {
        let cache = ResolvedStreamCache(fileURL: nil, maximumAge: 60 * 60)
        await cache.store(
            stream("a"),
            candidateID: "one",
            animeID: "1",
            episodeNumber: 7,
            now: Date().addingTimeInterval(-2 * 60 * 60)
        )

        let loaded = await cache.stream(animeID: "1", episodeNumber: 7)
        #expect(loaded == nil)
    }

    @Test func removeClearsEntry() async {
        let cache = ResolvedStreamCache(fileURL: nil)
        await cache.store(stream("a"), candidateID: "one", animeID: "1", episodeNumber: 7)

        await cache.remove(animeID: "1", episodeNumber: 7)

        let loaded = await cache.stream(animeID: "1", episodeNumber: 7)
        #expect(loaded == nil)
    }

    @Test func persistsAcrossInstances() async {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let cache = ResolvedStreamCache(fileURL: fileURL)
        let saved = stream("a")
        await cache.store(saved, candidateID: "one", animeID: "1", episodeNumber: 7)

        let reloaded = ResolvedStreamCache(fileURL: fileURL)
        let loaded = await reloaded.stream(animeID: "1", episodeNumber: 7)
        #expect(loaded == saved)
    }

    @Test func removeAllDeletesPersistedEntries() async {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let cache = ResolvedStreamCache(fileURL: fileURL)
        await cache.store(stream("a"), candidateID: "one", animeID: "1", episodeNumber: 7)
        await cache.removeAll()

        let reloaded = ResolvedStreamCache(fileURL: fileURL)
        let loaded = await reloaded.stream(animeID: "1", episodeNumber: 7)
        #expect(loaded == nil)
    }

    @Test func evictsOldestEntriesBeyondLimit() async {
        let cache = ResolvedStreamCache(fileURL: nil, maximumEntries: 2)
        await cache.store(
            stream("a"),
            candidateID: "a",
            animeID: "1",
            episodeNumber: 1,
            now: Date().addingTimeInterval(-30)
        )
        await cache.store(
            stream("b"),
            candidateID: "b",
            animeID: "1",
            episodeNumber: 2,
            now: Date().addingTimeInterval(-20)
        )
        await cache.store(
            stream("c"),
            candidateID: "c",
            animeID: "1",
            episodeNumber: 3,
            now: Date().addingTimeInterval(-10)
        )

        let evicted = await cache.stream(animeID: "1", episodeNumber: 1)
        let keptSecond = await cache.stream(animeID: "1", episodeNumber: 2)
        let keptThird = await cache.stream(animeID: "1", episodeNumber: 3)
        #expect(evicted == nil)
        #expect(keptSecond != nil)
        #expect(keptThird != nil)
    }
}
