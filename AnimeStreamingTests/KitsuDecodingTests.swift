import Foundation
import Testing
@testable import AnimeStreaming

struct KitsuDecodingTests {
    private func decodeCollection(
        _ data: Data
    ) throws -> JSONAPIDocument<[JSONAPIResource<KitsuAnimeAttributes>], KitsuIncludedResource> {
        try JSONDecoder().decode(
            JSONAPIDocument<[JSONAPIResource<KitsuAnimeAttributes>], KitsuIncludedResource>.self,
            from: data
        )
    }

    @Test func decodesAnimeCollectionWithPagination() throws {
        let document = try decodeCollection(KitsuFixtures.animePageOneJSON)

        #expect(document.data.count == 2)
        #expect(document.meta?.count == 3)
        #expect(document.links?.next != nil)

        let anime = KitsuMapping.anime(document.data[0])
        #expect(anime.id == "7442")
        #expect(anime.title == "Attack on Titan")
        #expect(anime.englishTitle == "Attack on Titan")
        #expect(anime.romajiTitle == "Shingeki no Kyojin")
        #expect(anime.japaneseTitle == "進撃の巨人")
        #expect(anime.status == .finished)
        #expect(anime.subtype == .tv)
        #expect(anime.episodeCount == 25)
        #expect(anime.episodeLength == 24)
        #expect(anime.popularityRank == 1)
        #expect(anime.ratingRank == 49)
        #expect(anime.averageRating == 84.44)
        #expect(anime.ageRating == "R")
        #expect(anime.startYear == 2013)
        #expect(anime.startDate != nil)
        #expect(anime.posterURL?.absoluteString.contains("medium.jpg") == true)
        #expect(anime.bannerURL?.absoluteString.contains("small.jpg") == true)
    }

    @Test func usesFallbacksForMissingTitles() throws {
        let document = try decodeCollection(KitsuFixtures.animePageOneJSON)
        let anime = KitsuMapping.anime(document.data[1])

        #expect(anime.title == "Sousou no Frieren")
        #expect(anime.englishTitle == "Frieren: Beyond Journey's End")
        #expect(anime.japaneseTitle == nil)
        #expect(anime.synopsis == "A <b>great</b> journey")
        #expect(anime.subtype == .tv)
    }

    @Test func decodesDetailsWithRelationsGenresAndMappings() throws {
        let document = try JSONDecoder().decode(
            JSONAPIDocument<JSONAPIResource<KitsuAnimeAttributes>, KitsuIncludedResource>.self,
            from: KitsuFixtures.animeDetailsJSON
        )

        let details = KitsuMediaRepository.makeDetails(
            from: document.data,
            included: document.included ?? []
        )

        #expect(details.anime.id == "8671")
        #expect(details.anime.genres.contains("Action"))
        #expect(details.anime.genres.contains("Drama"))
        #expect(details.anime.identity.malID == 25777)
        #expect(details.anime.identity.anilistID == 20958)

        #expect(details.relations.count == 2)
        let prequel = details.relations.first { $0.role == .prequel }
        #expect(prequel?.anime.id == "7442")
        let sequel = details.relations.first { $0.role == .sequel }
        #expect(sequel?.anime.id == "13569")

        // The manga adaptation must not be exposed as an anime relation.
        #expect(!details.relations.contains { $0.anime.id == "14916" })
    }

    @Test func decodesEpisodeListPage() throws {
        let document = try JSONDecoder().decode(
            JSONAPIDocument<[JSONAPIResource<KitsuEpisodeAttributes>], KitsuIncludedResource>.self,
            from: KitsuFixtures.episodePageOneJSON
        )

        #expect(document.meta?.count == 3)
        #expect(document.links?.next != nil)

        let first = try #require(KitsuMapping.episode(document.data[0], animeID: "7442"))
        #expect(first.id == "104938")
        #expect(first.animeID == "7442")
        #expect(first.number == 1)
        #expect(first.relativeNumber == 1)
        #expect(first.seasonNumber == 1)
        #expect(first.title == "To You, in 2000 Years")
        #expect(first.synopsis?.contains("hundred years") == true)
        #expect(first.airDate != nil)
        #expect(first.durationMinutes == 24)
        #expect(first.thumbnailURL?.absoluteString.contains("104938") == true)
    }

    @Test func episodeFallbacksTolerateMissingValues() throws {
        let document = try JSONDecoder().decode(
            JSONAPIDocument<[JSONAPIResource<KitsuEpisodeAttributes>], KitsuIncludedResource>.self,
            from: KitsuFixtures.episodePageOneJSON
        )

        let second = try #require(KitsuMapping.episode(document.data[1], animeID: "7442"))
        #expect(second.title == "That Day")
        #expect(second.synopsis == nil)
        #expect(second.airDate == nil)
        #expect(second.durationMinutes == nil)
        #expect(second.thumbnailURL == nil)
        #expect(second.displayTitle == "That Day")
    }

    @Test func animeStatusAndSubtypeParseCaseInsensitively() {
        #expect(AnimeStatus(kitsuValue: "CURRENT") == .current)
        #expect(AnimeStatus(kitsuValue: "finished") == .finished)
        #expect(AnimeStatus(kitsuValue: "nonsense") == nil)
        #expect(AnimeSubtype(kitsuValue: "tv") == .tv)
        #expect(AnimeSubtype(kitsuValue: "Movie") == .movie)
        #expect(AnimeSubtype(kitsuValue: "TV special") == .tvSpecial)
        #expect(AnimeSubtype(kitsuValue: "nonsense") == nil)
    }
}
