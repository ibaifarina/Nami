import Foundation
import Testing
@testable import Nami

struct LanguageDetectorTests {
    // MARK: - Names

    @Test func detectsEnglishLanguageNames() {
        #expect(LanguageDetector.languages(in: "Japanese, English audio") == ["ja", "en"])
    }

    @Test func detectsLocalizedSpanishAndPortugueseNames() {
        #expect(LanguageDetector.languages(in: "Castellano") == ["es"])
        #expect(LanguageDetector.languages(in: "Español") == ["es"])
        #expect(LanguageDetector.languages(in: "Espanol") == ["es"])
        #expect(LanguageDetector.languages(in: "Latino") == ["es"])
        #expect(LanguageDetector.languages(in: "Português") == ["pt"])
        #expect(LanguageDetector.languages(in: "Portugues") == ["pt"])
    }

    @Test func detectsLocalizedEuropeanNames() {
        #expect(LanguageDetector.languages(in: "Deutsch") == ["de"])
        #expect(LanguageDetector.languages(in: "Français") == ["fr"])
        #expect(LanguageDetector.languages(in: "Francais") == ["fr"])
        #expect(LanguageDetector.languages(in: "Italiano") == ["it"])
    }

    @Test func detectsNonLatinNames() {
        #expect(LanguageDetector.languages(in: "Русский") == ["ru"])
        #expect(LanguageDetector.languages(in: "日本語") == ["ja"])
        #expect(LanguageDetector.languages(in: "Español Latino") == ["es"])
    }

    // MARK: - Codes

    @Test func detectsIsoCodes() {
        #expect(LanguageDetector.languages(in: "ENG JPN") == ["en", "ja"])
        #expect(LanguageDetector.languages(in: "SPA ESP GER DEU") == ["es", "de"])
        #expect(LanguageDetector.languages(in: "FRE FRA POR RUS KOR CHI ZHO") == ["fr", "pt", "ru", "ko", "zh"])
    }

    @Test func detectsBracketedShortCodes() {
        #expect(LanguageDetector.languages(in: "[ES][EN]") == ["es", "en"])
        #expect(LanguageDetector.languages(in: "(pt)") == ["pt"])
    }

    @Test func detectsRegionAndScriptVariants() {
        #expect(LanguageDetector.languages(in: "(es-419)") == ["es"])
        #expect(LanguageDetector.languages(in: "pt-BR") == ["pt"])
        #expect(LanguageDetector.languages(in: "[zh-Hans]") == ["zh"])
    }

    @Test func ignoresBareShortCodesAndWordFragments() {
        #expect(LanguageDetector.languages(in: "It was no fun").isEmpty)
        #expect(LanguageDetector.languages(in: "No Game No Life").isEmpty)
        #expect(LanguageDetector.languages(in: "Germanium").isEmpty)
    }

    // MARK: - Context

    @Test func classifiesMentionsPerLine() {
        let sets = LanguageDetector.sets(
            in: "Audio: Japanese, Castellano\nSubtitles: Español, English"
        )

        #expect(sets.audio == ["ja", "es"])
        #expect(sets.subtitles == ["es", "en"])
    }

    @Test func separatesSubtitleMentionsFromAudio() {
        let sets = LanguageDetector.sets(in: "Anime English Sub [1080p]")

        #expect(sets.subtitles == ["en"])
        #expect(sets.audio.isEmpty)
    }

    // MARK: - Release conventions

    @Test func infersFromReleaseTags() {
        #expect(LanguageDetector.sets(in: "Show Dual Audio").audio == ["ja", "en"])
        #expect(LanguageDetector.sets(in: "Show Dubbed").audio == ["en"])
        #expect(LanguageDetector.sets(in: "Show Doblaje").audio == ["es"])
        #expect(LanguageDetector.sets(in: "Show Dublado").audio == ["pt"])
        #expect(LanguageDetector.sets(in: "Show Multi-Subs").subtitles == ["en"])
        #expect(LanguageDetector.sets(in: "Show [1080p] RAW").audio == ["ja"])
    }

    @Test func vostfrAndLegendadoImplySubtitles() {
        let vostfr = LanguageDetector.sets(in: "Show [1080p] VOSTFR")
        #expect(vostfr.subtitles == ["fr"])
        #expect(vostfr.audio.isEmpty)

        let legendado = LanguageDetector.sets(in: "Show [1080p] Legendado")
        #expect(legendado.subtitles == ["pt"])
        #expect(legendado.audio.isEmpty)
    }

    @Test func detectsTrackListFromAddonDescription() {
        let description = """
        Japanese (Opus 2.0)
        English (Opus 5.1)
        Castellano (Opus 2.0) (es)
        Español Latino (EAC3 2.0) (es-419)
        """
        let sets = LanguageDetector.sets(in: description)

        #expect(sets.audio == ["ja", "en", "es"])
        #expect(sets.subtitles.isEmpty)
    }

    // MARK: - Canonicalization

    @Test func canonicalCodeResolvesTrackTokens() {
        #expect(LanguageDetector.canonicalCode(forToken: "ja") == "ja")
        #expect(LanguageDetector.canonicalCode(forToken: "jpn") == "ja")
        #expect(LanguageDetector.canonicalCode(forToken: "Japanese") == "ja")
        #expect(LanguageDetector.canonicalCode(forToken: "Deutsch") == "de")
        #expect(LanguageDetector.canonicalCode(forToken: "pt-BR") == "pt")
        #expect(LanguageDetector.canonicalCode(forToken: "Castellano (Opus 2.0) (es)") == "es")
        #expect(LanguageDetector.canonicalCode(forToken: "Klingon") == nil)
    }

    @Test func displayHelpers() {
        #expect(LanguageDetector.shortCode(for: "es") == "ES")
        #expect(LanguageDetector.displayName(for: "es", locale: Locale(identifier: "en")) == "Spanish")
        #expect(LanguageDetector.displayName(for: "de", locale: Locale(identifier: "de")) == "Deutsch")
    }
}
