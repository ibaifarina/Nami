import Foundation
import Testing
@testable import Nami

struct ParsingProfileStoreTests {
    private func fingerprint(_ path: String = "manifest.json") -> AddonFingerprint {
        AddonFingerprint(
            addonID: "org.example.addon",
            manifestURL: testURL("https://example.com/\(path)")
        )
    }

    private func episodeProfile(coverage: Double = 0.9) -> ContentParsingProfile {
        ContentParsingProfile(
            rules: [
                AddonParsingRule(
                    attribute: .resolution,
                    field: .title,
                    kind: .keyword,
                    pattern: "1080p",
                    value: "1080p"
                ),
            ],
            confidence: 0.9,
            coverage: coverage,
            sampleCount: 8
        )
    }

    @Test func savesAndLoadsByFingerprint() async {
        let store = ParsingProfileStore(directory: nil)
        let key = fingerprint()
        let record = StoredAddonParsingProfile(
            fingerprint: key,
            episode: episodeProfile(),
            status: .success
        )

        await store.save(record)

        let loaded = await store.profile(for: key)
        #expect(loaded?.status == .success)
        #expect(loaded?.episode?.coverage == 0.9)
        #expect(await store.contentProfile(for: .episode, fingerprint: key) != nil)
        #expect(await store.contentProfile(for: .movie, fingerprint: key) == nil)
    }

    @Test func configurationChangeMissesOldProfile() async {
        let store = ParsingProfileStore(directory: nil)
        await store.save(
            StoredAddonParsingProfile(
                fingerprint: fingerprint("manifest.json?config=one"),
                episode: episodeProfile(),
                status: .success
            )
        )

        let changed = fingerprint("manifest.json?config=two")

        #expect(await store.profile(for: changed) == nil)
    }

    @Test func savingNewConfigurationRemovesOldConfigurations() async {
        let store = ParsingProfileStore(directory: nil)
        let old = fingerprint("manifest.json?config=one")
        let new = fingerprint("manifest.json?config=two")
        await store.save(
            StoredAddonParsingProfile(fingerprint: old, episode: episodeProfile(), status: .success)
        )
        await store.save(
            StoredAddonParsingProfile(fingerprint: new, episode: episodeProfile(), status: .success)
        )

        #expect(await store.profile(for: old) == nil)
        #expect(await store.profile(for: new) != nil)
    }

    @Test func oneLowCoverageBatchDoesNotMarkProfileStale() async {
        let store = ParsingProfileStore(directory: nil)
        let key = fingerprint()
        await store.save(
            StoredAddonParsingProfile(fingerprint: key, episode: episodeProfile(), status: .success)
        )

        await store.recordObservation(fingerprint: key, kind: .episode, matched: 1, total: 8)

        #expect(await store.profile(for: key)?.isStale == false)
    }

    @Test func repeatedLowCoverageMarksProfileStale() async {
        let store = ParsingProfileStore(directory: nil)
        let key = fingerprint()
        await store.save(
            StoredAddonParsingProfile(fingerprint: key, episode: episodeProfile(), status: .success)
        )

        for _ in 0..<4 {
            await store.recordObservation(fingerprint: key, kind: .episode, matched: 1, total: 8)
        }

        #expect(await store.profile(for: key)?.isStale == true)
        #expect(await store.summary(for: key)?.isStale == true)
    }

    @Test func recoveredCoverageClearsStaleMarker() async {
        let store = ParsingProfileStore(directory: nil)
        let key = fingerprint()
        await store.save(
            StoredAddonParsingProfile(fingerprint: key, episode: episodeProfile(), status: .success)
        )
        for _ in 0..<4 {
            await store.recordObservation(fingerprint: key, kind: .episode, matched: 1, total: 8)
        }
        #expect(await store.profile(for: key)?.isStale == true)

        for _ in 0..<4 {
            await store.recordObservation(fingerprint: key, kind: .episode, matched: 8, total: 8)
        }

        #expect(await store.profile(for: key)?.isStale == false)
    }

    @Test func failedCalibrationNeverBecomesStale() async {
        let store = ParsingProfileStore(directory: nil)
        let key = fingerprint()
        await store.save(
            StoredAddonParsingProfile(fingerprint: key, status: .failure)
        )

        for _ in 0..<5 {
            await store.recordObservation(fingerprint: key, kind: .episode, matched: 0, total: 10)
        }

        #expect(await store.profile(for: key)?.isStale == false)
    }

    @Test func removeAllClearsEveryConfiguration() async {
        let store = ParsingProfileStore(directory: nil)
        let one = fingerprint("manifest.json?config=one")
        let two = fingerprint("manifest.json?config=two")
        await store.save(StoredAddonParsingProfile(fingerprint: one, status: .partial))
        await store.save(StoredAddonParsingProfile(fingerprint: two, status: .partial))

        await store.removeAll(addonID: "org.example.addon")

        #expect(await store.profile(for: one) == nil)
        #expect(await store.profile(for: two) == nil)
    }
}
