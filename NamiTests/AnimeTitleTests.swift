import Foundation
import Testing
@testable import Nami

struct AnimeTitleTests {
    private func anime(
        title: String,
        canonical: String? = nil,
        english: String? = nil,
        romaji: String? = nil,
        japanese: String? = nil
    ) -> Anime {
        Anime(
            identity: MediaIdentity(kitsuID: "1"),
            title: title,
            canonicalTitle: canonical,
            englishTitle: english,
            romajiTitle: romaji,
            japaneseTitle: japanese
        )
    }

    @Test func standardLanguageKeepsCanonicalTitle() {
        let value = anime(
            title: "Shingeki no Kyojin",
            english: "Attack on Titan",
            japanese: "進撃の巨人"
        )
        #expect(value.displayTitle(for: .standard) == "Shingeki no Kyojin")
    }

    @Test func englishLanguagePrefersEnglishTitle() {
        let value = anime(
            title: "Shingeki no Kyojin",
            english: "Attack on Titan",
            japanese: "進撃の巨人"
        )
        #expect(value.displayTitle(for: .english) == "Attack on Titan")
        #expect(value.alternativeTitle(for: .english) == "進撃の巨人")
    }

    @Test func japaneseLanguagePrefersJapaneseThenRomaji() {
        let withJapanese = anime(
            title: "Attack on Titan",
            english: "Attack on Titan",
            romaji: "Shingeki no Kyojin",
            japanese: "進撃の巨人"
        )
        #expect(withJapanese.displayTitle(for: .japanese) == "進撃の巨人")
        #expect(withJapanese.alternativeTitle(for: .japanese) == "Attack on Titan")

        let withoutJapanese = anime(
            title: "Sousou no Frieren",
            english: "Frieren: Beyond Journey's End",
            romaji: "Sousou no Frieren"
        )
        #expect(withoutJapanese.displayTitle(for: .japanese) == "Sousou no Frieren")
        #expect(withoutJapanese.alternativeTitle(for: .japanese) == "Frieren: Beyond Journey's End")
    }

    @Test func languageResolutionFallsBackToTitle() {
        let value = anime(title: "Untitled Show")
        #expect(value.displayTitle(for: .english) == "Untitled Show")
        #expect(value.displayTitle(for: .japanese) == "Untitled Show")
        #expect(value.alternativeTitle(for: .english) == nil)
        #expect(value.alternativeTitle(for: .japanese) == nil)
    }
}
