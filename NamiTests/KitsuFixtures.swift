import Foundation

/// Kitsu JSON:API fixtures shaped exactly like live responses.
enum KitsuFixtures {
    static let animePageOneJSON = Data("""
    {
      "data": [
        {
          "id": "7442",
          "type": "anime",
          "attributes": {
            "slug": "attack-on-titan",
            "synopsis": "Centuries ago, mankind was slaughtered to near extinction.",
            "canonicalTitle": "Attack on Titan",
            "titles": {
              "en": "Attack on Titan",
              "en_jp": "Shingeki no Kyojin",
              "ja_jp": "進撃の巨人"
            },
            "averageRating": "84.44",
            "startDate": "2013-04-07",
            "endDate": "2013-09-29",
            "popularityRank": 1,
            "ratingRank": 49,
            "ageRating": "R",
            "subtype": "TV",
            "status": "finished",
            "posterImage": {
              "medium": "https://media.kitsu.app/anime/poster_images/7442/medium.jpg",
              "original": "https://media.kitsu.app/anime/poster_images/7442/original.jpg"
            },
            "coverImage": {
              "small": "https://media.kitsu.app/anime/cover_images/7442/small.jpg"
            },
            "episodeCount": 25,
            "episodeLength": 24,
            "nsfw": false
          },
          "relationships": {}
        },
        {
          "id": "46474",
          "type": "anime",
          "attributes": {
            "slug": "sousou-no-frieren",
            "synopsis": null,
            "description": "A <b>great</b> journey",
            "canonicalTitle": "Sousou no Frieren",
            "titles": {
              "en": "Frieren: Beyond Journey's End",
              "en_jp": "Sousou no Frieren",
              "ja_jp": null
            },
            "averageRating": "91.2",
            "startDate": "2023-09-29",
            "endDate": null,
            "popularityRank": 5,
            "ratingRank": 2,
            "ageRating": "PG",
            "subtype": "TV",
            "status": "finished",
            "posterImage": {
              "medium": "https://media.kitsu.app/anime/poster_images/46474/medium.jpg"
            },
            "coverImage": {
              "small": "https://media.kitsu.app/anime/cover_images/46474/small.jpg"
            },
            "episodeCount": 28,
            "episodeLength": 24,
            "nsfw": false
          },
          "relationships": {}
        }
      ],
      "meta": { "count": 3 },
      "links": {
        "first": "https://kitsu.io/api/edge/anime?page%5Blimit%5D=2&page%5Boffset%5D=0",
        "next": "https://kitsu.io/api/edge/anime?page%5Blimit%5D=2&page%5Boffset%5D=2",
        "last": "https://kitsu.io/api/edge/anime?page%5Blimit%5D=2&page%5Boffset%5D=2"
      }
    }
    """.utf8)

    static let animePageTwoJSON = Data("""
    {
      "data": [
        {
          "id": "8671",
          "type": "anime",
          "attributes": {
            "slug": "attack-on-titan-season-2",
            "synopsis": "The mystery deepens.",
            "canonicalTitle": "Attack on Titan Season 2",
            "titles": { "en": "Attack on Titan Season 2", "en_jp": "Shingeki no Kyojin Season 2" },
            "averageRating": "86.0",
            "startDate": "2017-04-01",
            "endDate": "2017-06-17",
            "popularityRank": 20,
            "ratingRank": 120,
            "ageRating": "R",
            "subtype": "TV",
            "status": "finished",
            "posterImage": { "medium": "https://media.kitsu.app/anime/poster_images/8671/medium.jpg" },
            "coverImage": { "small": "https://media.kitsu.app/anime/cover_images/8671/small.jpg" },
            "episodeCount": 12,
            "episodeLength": 24,
            "nsfw": false
          },
          "relationships": {}
        }
      ],
      "meta": { "count": 3 },
      "links": {
        "first": "https://kitsu.io/api/edge/anime?page%5Blimit%5D=2&page%5Boffset%5D=0",
        "last": "https://kitsu.io/api/edge/anime?page%5Blimit%5D=2&page%5Boffset%5D=2"
      }
    }
    """.utf8)

    static let episodePageOneJSON = Data("""
    {
      "data": [
        {
          "id": "104938",
          "type": "episodes",
          "attributes": {
            "synopsis": "After one hundred years of peace.",
            "canonicalTitle": "To You, in 2000 Years",
            "titles": { "en_jp": "Ni Sen-Nen-Go no Kimi e", "en_us": "To You Two Thousand Years Later" },
            "seasonNumber": 1,
            "number": 1,
            "relativeNumber": 1,
            "airdate": "2013-04-06",
            "length": 24,
            "thumbnail": { "original": "https://media.kitsu.app/episodes/thumbnails/104938/original.jpg" }
          },
          "relationships": {}
        },
        {
          "id": "104939",
          "type": "episodes",
          "attributes": {
            "synopsis": null,
            "canonicalTitle": null,
            "titles": { "en_us": "That Day" },
            "seasonNumber": 1,
            "number": 2,
            "relativeNumber": 2,
            "airdate": null,
            "length": null,
            "thumbnail": null
          },
          "relationships": {}
        }
      ],
      "meta": { "count": 3 },
      "links": {
        "next": "https://kitsu.io/api/edge/anime/7442/episodes?page%5Blimit%5D=2&page%5Boffset%5D=2",
        "last": "https://kitsu.io/api/edge/anime/7442/episodes?page%5Blimit%5D=2&page%5Boffset%5D=2"
      }
    }
    """.utf8)

    static let episodePageTwoJSON = Data("""
    {
      "data": [
        {
          "id": "104940",
          "type": "episodes",
          "attributes": {
            "synopsis": "The third episode.",
            "canonicalTitle": "A Dim Light Amid Despair",
            "titles": {},
            "seasonNumber": 1,
            "number": 3,
            "relativeNumber": 3,
            "airdate": "2013-04-20",
            "length": 24,
            "thumbnail": { "original": "https://media.kitsu.app/episodes/thumbnails/104940/original.jpg" }
          },
          "relationships": {}
        }
      ],
      "meta": { "count": 3 },
      "links": {}
    }
    """.utf8)

    static let animeDetailsJSON = Data("""
    {
      "data": {
        "id": "8671",
        "type": "anime",
        "attributes": {
          "slug": "attack-on-titan-season-2",
          "synopsis": "The mystery deepens.",
          "canonicalTitle": "Attack on Titan Season 2",
          "titles": {
            "en": "Attack on Titan Season 2",
            "en_jp": "Shingeki no Kyojin Season 2",
            "ja_jp": "進撃の巨人 Season 2"
          },
          "averageRating": "86.0",
          "startDate": "2017-04-01",
          "popularityRank": 20,
          "ratingRank": 120,
          "ageRating": "R",
          "subtype": "TV",
          "status": "finished",
          "posterImage": { "medium": "https://media.kitsu.app/anime/poster_images/8671/medium.jpg" },
          "coverImage": { "small": "https://media.kitsu.app/anime/cover_images/8671/small.jpg" },
          "episodeCount": 12,
          "episodeLength": 24,
          "nsfw": false
        },
        "relationships": {}
      },
      "included": [
        {
          "id": "197",
          "type": "categories",
          "attributes": { "title": "Action", "slug": "action", "nsfw": false },
          "relationships": {}
        },
        {
          "id": "108",
          "type": "categories",
          "attributes": { "title": "Drama", "slug": "drama", "nsfw": false },
          "relationships": {}
        },
        {
          "id": "2740",
          "type": "mediaRelationships",
          "attributes": { "role": "prequel" },
          "relationships": {
            "destination": { "data": { "type": "anime", "id": "7442" } }
          }
        },
        {
          "id": "18376",
          "type": "mediaRelationships",
          "attributes": { "role": "sequel" },
          "relationships": {
            "destination": { "data": { "type": "anime", "id": "13569" } }
          }
        },
        {
          "id": "2741",
          "type": "mediaRelationships",
          "attributes": { "role": "adaptation" },
          "relationships": {
            "destination": { "data": { "type": "manga", "id": "14916" } }
          }
        },
        {
          "id": "7442",
          "type": "anime",
          "attributes": {
            "canonicalTitle": "Attack on Titan",
            "titles": { "en": "Attack on Titan", "en_jp": "Shingeki no Kyojin" },
            "averageRating": "84.44",
            "startDate": "2013-04-07",
            "subtype": "TV",
            "status": "finished",
            "posterImage": { "medium": "https://media.kitsu.app/anime/poster_images/7442/medium.jpg" },
            "coverImage": { "small": "https://media.kitsu.app/anime/cover_images/7442/small.jpg" },
            "episodeCount": 25,
            "episodeLength": 24,
            "nsfw": false
          },
          "relationships": {}
        },
        {
          "id": "13569",
          "type": "anime",
          "attributes": {
            "canonicalTitle": "Attack on Titan Season 3",
            "titles": { "en": "Attack on Titan Season 3", "en_jp": "Shingeki no Kyojin Season 3" },
            "averageRating": "87.0",
            "startDate": "2018-07-23",
            "subtype": "TV",
            "status": "finished",
            "posterImage": { "medium": "https://media.kitsu.app/anime/poster_images/13569/medium.jpg" },
            "coverImage": { "small": "https://media.kitsu.app/anime/cover_images/13569/small.jpg" },
            "episodeCount": 12,
            "episodeLength": 24,
            "nsfw": false
          },
          "relationships": {}
        },
        {
          "id": "254628",
          "type": "mappings",
          "attributes": { "externalSite": "anilist/anime", "externalId": "20958" },
          "relationships": {}
        },
        {
          "id": "5686",
          "type": "mappings",
          "attributes": { "externalSite": "myanimelist/anime", "externalId": "25777" },
          "relationships": {}
        }
      ],
      "meta": {}
    }
    """.utf8)

    static let mappingsJSON = Data("""
    {
      "data": [
        {
          "id": "5686",
          "type": "mappings",
          "attributes": { "externalSite": "myanimelist/anime", "externalId": "25777" }
        },
        {
          "id": "64656",
          "type": "mappings",
          "attributes": { "externalSite": "thetvdb", "externalId": "267440/1" }
        },
        {
          "id": "254628",
          "type": "mappings",
          "attributes": { "externalSite": "anilist/anime", "externalId": "20958" }
        }
      ],
      "meta": { "count": 3 },
      "links": {}
    }
    """.utf8)

    static let emptyCollectionJSON = Data("""
    {
      "data": [],
      "meta": { "count": 0 },
      "links": {}
    }
    """.utf8)
}
