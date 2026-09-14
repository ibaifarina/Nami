import Foundation
import Testing
@testable import Nami

struct PlaybackTrackSelectorTests {
    private func track(
        _ id: String,
        kind: MediaTrack.Kind,
        title: String,
        language: String? = nil,
        isDefault: Bool = false,
        isForced: Bool = false
    ) -> MediaTrack {
        MediaTrack(
            id: id,
            kind: kind,
            title: title,
            language: language,
            isDefault: isDefault,
            isForced: isForced
        )
    }

    @Test func preferredAudioLanguageWinsOverOtherLanguages() {
        let tracks = [
            track("audio-0", kind: .audio, title: "Japanese", language: "jpn"),
            track("audio-1", kind: .audio, title: "Spanish", language: "spa"),
            track("audio-2", kind: .audio, title: "English Commentary", language: "eng"),
        ]

        let selected = PlaybackTrackSelector.selectAudio(from: tracks, preference: .spanish)

        #expect(selected?.id == "audio-1")
    }

    @Test func japaneseIsPreferredFallbackWhenPreferenceIsMissing() {
        let tracks = [
            track("audio-0", kind: .audio, title: "Japanese", language: "jpn"),
            track("audio-1", kind: .audio, title: "English", language: "eng"),
        ]

        let selected = PlaybackTrackSelector.selectAudio(from: tracks, preference: .spanish)

        #expect(selected?.id == "audio-0")
    }

    @Test func commentaryNeverBeatsMainAudioInPreferredLanguage() {
        let tracks = [
            track("audio-0", kind: .audio, title: "English Commentary", language: "eng"),
            track("audio-1", kind: .audio, title: "English", language: "eng"),
        ]

        let selected = PlaybackTrackSelector.selectAudio(from: tracks, preference: .english)

        #expect(selected?.id == "audio-1")
    }

    @Test func fullSubtitlesWinOverSignsAndSongsInPreferredLanguage() {
        let tracks = [
            track("subtitle-0", kind: .subtitle, title: "Spanish Signs & Songs", language: "spa"),
            track("subtitle-1", kind: .subtitle, title: "Spanish Full", language: "spa"),
            track("subtitle-2", kind: .subtitle, title: "English Full", language: "eng"),
        ]

        let selected = PlaybackTrackSelector.selectSubtitle(from: tracks, preference: .spanish)

        #expect(selected?.id == "subtitle-1")
    }

    @Test func englishFullIsPreferredFallbackOverForced() {
        let tracks = [
            track("subtitle-0", kind: .subtitle, title: "English Full", language: "eng"),
            track("subtitle-1", kind: .subtitle, title: "English Forced", language: "eng", isForced: true),
        ]

        let selected = PlaybackTrackSelector.selectSubtitle(from: tracks, preference: .spanish)

        #expect(selected?.id == "subtitle-0")
    }

    @Test func sdhWinsOverForcedInPreferredLanguage() {
        let tracks = [
            track("subtitle-0", kind: .subtitle, title: "Spanish SDH", language: "spa"),
            track("subtitle-1", kind: .subtitle, title: "Spanish Forced", language: "spa", isForced: true),
        ]

        let selected = PlaybackTrackSelector.selectSubtitle(from: tracks, preference: .spanish)

        #expect(selected?.id == "subtitle-0")
    }

    @Test func iso639_2LanguageCodeIsNormalized() {
        let audio = track("audio-0", kind: .audio, title: "Spanish Full", language: "spa")

        #expect(PlaybackTrackSelector.language(of: audio) == "es")
    }

    @Test func titleFallbackResolvesASingleLanguage() {
        let audio = track("audio-0", kind: .audio, title: "Español Latino Full")

        #expect(PlaybackTrackSelector.language(of: audio) == "es")
    }

    @Test func titleWithMultipleLanguagesIsUnknown() {
        let audio = track("audio-0", kind: .audio, title: "English / Spanish")

        #expect(PlaybackTrackSelector.language(of: audio) == nil)
    }

    @Test func unknownSubtitleTitlesRemainStrongCandidates() {
        let tracks = [
            track("subtitle-0", kind: .subtitle, title: "Spanish Forced", language: "spa", isForced: true),
            track("subtitle-1", kind: .subtitle, title: "Español", language: "spa"),
        ]

        let selected = PlaybackTrackSelector.selectSubtitle(from: tracks, preference: .spanish)

        #expect(selected?.id == "subtitle-1")
    }

    @Test func commentarySubtitlesAreNotAutoSelected() {
        let tracks = [
            track("subtitle-0", kind: .subtitle, title: "English Commentary", language: "eng"),
        ]

        let selected = PlaybackTrackSelector.selectSubtitle(from: tracks, preference: .english)

        #expect(selected == nil)
    }

    @Test func anyAudioPreferenceUsesDefaultNormalTrack() {
        let tracks = [
            track("audio-0", kind: .audio, title: "Japanese", language: "jpn"),
            track("audio-1", kind: .audio, title: "English", language: "eng", isDefault: true),
        ]

        let selected = PlaybackTrackSelector.selectAudio(from: tracks, preference: .any)

        #expect(selected?.id == "audio-1")
    }

    @Test func anySubtitlePreferencePrefersDialogueOverForcedDefault() {
        let tracks = [
            track("subtitle-0", kind: .subtitle, title: "English Forced", language: "eng", isDefault: true, isForced: true),
            track("subtitle-1", kind: .subtitle, title: "Spanish", language: "spa"),
        ]

        let selected = PlaybackTrackSelector.selectSubtitle(from: tracks, preference: .any)

        #expect(selected?.id == "subtitle-1")
    }
}
