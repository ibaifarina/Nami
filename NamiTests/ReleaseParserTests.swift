import Foundation
import Testing
@testable import Nami

struct ReleaseParserTests {
    // MARK: Resolution

    @Test func parsesResolutions() {
        #expect(ReleaseParser.parse("Show [2160p]").resolution == .p2160)
        #expect(ReleaseParser.parse("Show [4K]").resolution == .p2160)
        #expect(ReleaseParser.parse("Show [UHD]").resolution == .p2160)
        #expect(ReleaseParser.parse("Show [1080p]").resolution == .p1080)
        #expect(ReleaseParser.parse("Show [FHD]").resolution == .p1080)
        #expect(ReleaseParser.parse("Show [720p]").resolution == .p720)
        #expect(ReleaseParser.parse("Show [480p]").resolution == .p480)
        #expect(ReleaseParser.parse("Show [576p]").resolution == .p480)
        #expect(ReleaseParser.parse("Show").resolution == nil)
    }

    // MARK: Codec

    @Test func parsesCodecAliases() {
        #expect(ReleaseParser.parse("Show [AV1]").codec == .av1)
        #expect(ReleaseParser.parse("Show [HEVC]").codec == .hevc)
        #expect(ReleaseParser.parse("Show [H.265]").codec == .hevc)
        #expect(ReleaseParser.parse("Show [H265]").codec == .hevc)
        #expect(ReleaseParser.parse("Show [x265]").codec == .hevc)
        #expect(ReleaseParser.parse("Show [AVC]").codec == .avc)
        #expect(ReleaseParser.parse("Show [H.264]").codec == .avc)
        #expect(ReleaseParser.parse("Show [H264]").codec == .avc)
        #expect(ReleaseParser.parse("Show [x264]").codec == .avc)
        #expect(ReleaseParser.parse("Show [1080p]").codec == nil)
    }

    // MARK: Dynamic range

    @Test func parsesDynamicRange() {
        #expect(ReleaseParser.parse("Show [Dolby Vision]").dynamicRange == .dolbyVision)
        #expect(ReleaseParser.parse("Show DV").dynamicRange == .dolbyVision)
        #expect(ReleaseParser.parse("Show DoVi").dynamicRange == .dolbyVision)
        #expect(ReleaseParser.parse("Show HDR10+").dynamicRange == .hdr10Plus)
        #expect(ReleaseParser.parse("Show HDR10").dynamicRange == .hdr10)
        #expect(ReleaseParser.parse("Show HDR").dynamicRange == .hdr)
        #expect(ReleaseParser.parse("Show SDR 1080p").dynamicRange == nil)
        // DVDRip must not be mistaken for Dolby Vision.
        #expect(ReleaseParser.parse("Show DVDRip").dynamicRange == nil)
    }

    // MARK: Source

    @Test func parsesSources() {
        #expect(ReleaseParser.parse("Show BluRay").source == .bluRay)
        #expect(ReleaseParser.parse("Show BDRip").source == .bluRay)
        #expect(ReleaseParser.parse("Show BD Remux").source == .bluRay)
        #expect(ReleaseParser.parse("Show WEB-DL").source == .webDL)
        #expect(ReleaseParser.parse("Show WEBDL").source == .webDL)
        #expect(ReleaseParser.parse("Show WEBRip").source == .webRip)
        #expect(ReleaseParser.parse("Show HDTV").source == .hdtv)
        #expect(ReleaseParser.parse("Show DVDRip").source == .dvd)
        #expect(ReleaseParser.parse("Show CAM").source == .cam)
        #expect(ReleaseParser.parse("Show TS").source == .ts)
        #expect(ReleaseParser.parse("Show Telesync").source == .ts)
        #expect(ReleaseParser.parse("Show").source == nil)
    }

    @Test func webSourcePrefersWebDLOverWebRip() {
        #expect(ReleaseParser.parse("Show WEB-DL 1080p").source == .webDL)
        #expect(ReleaseParser.parse("Show WEB 1080p").source == .webDL)
    }

    // MARK: Release group

    @Test func parsesLeadingBracketGroup() {
        let parsed = ReleaseParser.parse("[SubsPlease] Sousou no Frieren - 07 [1080p]")
        #expect(parsed.releaseGroup == "SubsPlease")
    }

    @Test func parsesTrailingDashGroup() {
        let parsed = ReleaseParser.parse("Sousou no Frieren - 07 [1080p]-ASW")
        #expect(parsed.releaseGroup == "ASW")
    }

    @Test func ignoresNoiseBracketAsGroup() {
        let parsed = ReleaseParser.parse("[1080p] Sousou no Frieren - 07")
        #expect(parsed.releaseGroup == nil)
    }

    @Test func doesNotTreatEpisodeAsGroup() {
        let parsed = ReleaseParser.parse("Sousou no Frieren - 07")
        #expect(parsed.releaseGroup == nil)
    }

    // MARK: Episode patterns

    @Test func parsesDashEpisode() {
        let parsed = ReleaseParser.parse("Anime Name - 07")
        #expect(parsed.episode == 7)
        #expect(parsed.season == nil)
        #expect(parsed.episodeVersion == nil)
    }

    @Test func parsesDashEpisodeVersion() {
        let parsed = ReleaseParser.parse("Anime Name - 07v2")
        #expect(parsed.episode == 7)
        #expect(parsed.episodeVersion == 2)
    }

    @Test func parsesSeasonEpisode() {
        let parsed = ReleaseParser.parse("Anime Name S01E07")
        #expect(parsed.season == 1)
        #expect(parsed.episode == 7)
    }

    @Test func parsesShortSeasonEpisode() {
        let parsed = ReleaseParser.parse("Anime Name S1E7")
        #expect(parsed.season == 1)
        #expect(parsed.episode == 7)
    }

    @Test func parsesEpisodeWord() {
        #expect(ReleaseParser.parse("Anime Name Episode 07").episode == 7)
        #expect(ReleaseParser.parse("Anime Name EP07").episode == 7)
        #expect(ReleaseParser.parse("Anime Name E7").episode == 7)
    }

    @Test func parsesBracketEpisode() {
        let parsed = ReleaseParser.parse("Anime Name [07]")
        #expect(parsed.episode == 7)
    }

    @Test func parsesNthSeason() {
        let parsed = ReleaseParser.parse("Anime Name 2nd Season - 07")
        #expect(parsed.season == 2)
        #expect(parsed.episode == 7)
    }

    @Test func parsesSeasonWord() {
        let parsed = ReleaseParser.parse("Anime Name Season 2 - 07")
        #expect(parsed.season == 2)
        #expect(parsed.episode == 7)
    }

    @Test func parsesSeasonOnly() {
        let parsed = ReleaseParser.parse("Anime Name Season 2 [1080p]")
        #expect(parsed.season == 2)
        #expect(parsed.episode == nil)
    }

    @Test func parsesAbsoluteEpisodeNumber() {
        let parsed = ReleaseParser.parse("ONE PIECE - 1100 [1080p]")
        #expect(parsed.episode == 1100)
    }

    @Test func rejectsYearAsEpisode() {
        #expect(ReleaseParser.parse("Anime Name - 2023").episode == nil)
        #expect(ReleaseParser.parse("Anime Name (2023)").episode == nil)
    }

    // MARK: Batch

    @Test func detectsBatchWord() {
        #expect(ReleaseParser.parse("Anime Batch [1080p]").isBatch)
        #expect(ReleaseParser.parse("Anime Complete Series [1080p]").isBatch)
    }

    @Test func detectsEpisodeRangeBatch() {
        let parsed = ReleaseParser.parse("Anime 01-12 [1080p]")
        #expect(parsed.isBatch)
        #expect(parsed.episode == nil)
        #expect(parsed.episodeRange == 1...12)
    }

    @Test func singleEpisodeIsNotBatch() {
        #expect(ReleaseParser.parse("Anime - 07 [1080p]").isBatch == false)
    }

    // MARK: Extras and specials

    @Test func detectsSpecials() {
        #expect(ReleaseParser.parse("Anime OVA [1080p]").isSpecial)
        #expect(ReleaseParser.parse("Anime Special [1080p]").isSpecial)
    }

    @Test func detectsExtras() {
        #expect(ReleaseParser.parse("Anime NCOP [1080p]").isExtra)
        #expect(ReleaseParser.parse("Anime Trailer [1080p]").isExtra)
        #expect(ReleaseParser.parse("Anime Preview [1080p]").isExtra)
    }

    // MARK: Audio flags

    @Test func detectsDualAudio() {
        let parsed = ReleaseParser.parse("Anime Dual Audio [1080p]")
        #expect(parsed.isDualAudio)
        #expect(parsed.isDubbed == false)
    }

    @Test func detectsMultiAudio() {
        #expect(ReleaseParser.parse("Anime Multi-Audio [1080p]").isDualAudio)
    }

    @Test func detectsDubAndSub() {
        let dubbed = ReleaseParser.parse("Anime English Dub [1080p]")
        #expect(dubbed.isDubbed)
        #expect(dubbed.audioLanguages.contains("english"))

        let subbed = ReleaseParser.parse("Anime Multi Sub Spanish [1080p]")
        #expect(subbed.isSubbed)
        #expect(subbed.isDualAudio == false)
        #expect(subbed.subtitleLanguages.contains("spanish"))
    }

    // MARK: Extension and normalization

    @Test func parsesFileSize() {
        #expect(ReleaseParser.parse("Show - 07 [1080p][1.4 GB]").sizeBytes == 1_400_000_000)
        #expect(ReleaseParser.parse("Show - 07 700MB").sizeBytes == 700_000_000)
        #expect(ReleaseParser.parse("Show - 07 [2.5 GiB]").sizeBytes == 2_684_354_560)
        #expect(ReleaseParser.parse("Show - 07 [1,45 GB]").sizeBytes == 1_450_000_000)
        #expect(ReleaseParser.parse("\u{1F4BE} 1.45 GB").sizeBytes == 1_450_000_000)
        #expect(ReleaseParser.parse("Show - 07 [1080p]").sizeBytes == nil)
        #expect(ReleaseParser.parse("Show - 07").sizeBytes == nil)
    }

    @Test func parsesSeeders() {
        #expect(ReleaseParser.parse("Show - 07\n\u{1F464} 142 \u{1F4BE} 2.1 GB").seeders == 142)
        #expect(ReleaseParser.parse("Show - 07 Seeders: 50").seeders == 50)
        #expect(ReleaseParser.parse("Show - 07 50 seeders").seeders == 50)
        #expect(ReleaseParser.parse("Show - 07").seeders == nil)
    }

    @Test func parsesFileExtension() {
        #expect(ReleaseParser.parse("Anime - 07.mkv").fileExtension == "mkv")
        #expect(ReleaseParser.parse("Anime - 07.MKV").fileExtension == "mkv")
        #expect(ReleaseParser.parse("Anime - 07").fileExtension == nil)
    }

    @Test func normalizesTitles() {
        #expect(
            ReleaseParser.normalizedTitle(for: "[SubsPlease] Sousou no Frieren - 07 [1080p][HEVC].mkv")
                == "sousou no frieren"
        )
        #expect(
            ReleaseParser.normalizedTitle(for: "Frieren S01E07 [1080p]") == "frieren"
        )
        #expect(
            ReleaseParser.titleTokens(for: "Sousou no Frieren - 07 [1080p]")
                == ["sousou", "no", "frieren"]
        )
    }
}
