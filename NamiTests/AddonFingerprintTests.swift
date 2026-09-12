import Foundation
import Testing
@testable import Nami

struct AddonFingerprintTests {
    @Test func sameURLProducesSameFingerprint() {
        let first = AddonFingerprint(
            addonID: "org.example.addon",
            manifestURL: testURL("https://example.com/addon/manifest.json")
        )
        let second = AddonFingerprint(
            addonID: "org.example.addon",
            manifestURL: testURL("https://example.com/addon/manifest.json")
        )

        #expect(first == second)
        #expect(first.storageKey == second.storageKey)
    }

    @Test func queryOrderDoesNotChangeFingerprint() {
        let first = AddonFingerprint(
            addonID: "org.example.addon",
            manifestURL: testURL("https://example.com/manifest.json?b=2&a=1")
        )
        let second = AddonFingerprint(
            addonID: "org.example.addon",
            manifestURL: testURL("https://example.com/manifest.json?a=1&b=2")
        )

        #expect(first == second)
    }

    @Test func configurationChangeInvalidatesFingerprint() {
        let first = AddonFingerprint(
            addonID: "org.example.addon",
            manifestURL: testURL("https://example.com/manifest.json?config=one")
        )
        let second = AddonFingerprint(
            addonID: "org.example.addon",
            manifestURL: testURL("https://example.com/manifest.json?config=two")
        )

        #expect(first != second)
    }

    @Test func userInfoIsIgnored() {
        let withCredentials = AddonFingerprint(
            addonID: "org.example.addon",
            manifestURL: testURL("https://user:password@example.com/manifest.json")
        )
        let withoutCredentials = AddonFingerprint(
            addonID: "org.example.addon",
            manifestURL: testURL("https://example.com/manifest.json")
        )

        #expect(withCredentials == withoutCredentials)
    }

    @Test func credentialsNeverAppearInStorageKey() {
        let fingerprint = AddonFingerprint(
            addonID: "org.example.addon",
            manifestURL: testURL(
                "https://user:password@example.com/u/supersecretconfig/manifest.json?token=topsecret"
            )
        )

        #expect(!fingerprint.storageKey.contains("supersecretconfig"))
        #expect(!fingerprint.storageKey.contains("topsecret"))
        #expect(!fingerprint.storageKey.contains("password"))
    }

    @Test func differentAddonsNeverShareFingerprint() {
        let first = AddonFingerprint(
            addonID: "org.example.one",
            manifestURL: testURL("https://example.com/manifest.json")
        )
        let second = AddonFingerprint(
            addonID: "org.example.two",
            manifestURL: testURL("https://example.com/manifest.json")
        )

        #expect(first != second)
    }
}
