import Foundation
import Testing
@testable import Nami

enum AddonFixtures {
    static let genericManifestJSON = Data("""
    {
      "id": "example.provider",
      "name": "Example Provider",
      "version": "1.0.0",
      "description": "A test provider",
      "protocol": "anime-stream-v1",
      "capabilities": ["streams"],
      "endpoints": { "streams": "/v1/streams" }
    }
    """.utf8)

    static let stremioManifestJSON = Data("""
    {
      "id": "org.example.stremio",
      "version": "2.0.0",
      "name": "Example Stremio",
      "description": "A Stremio-compatible addon",
      "resources": ["stream"],
      "types": ["anime", "series"],
      "idPrefixes": ["kitsu", "tt"],
      "logo": "https://example.com/logo.png"
    }
    """.utf8)

    static let detailedResourcesManifestJSON = Data("""
    {
      "id": "org.example.detailed",
      "version": "1.0.0",
      "name": "Detailed Resources",
      "resources": [
        { "name": "stream", "types": ["anime"], "idPrefixes": ["mal"] }
      ],
      "types": ["anime"]
    }
    """.utf8)

    static let manifestWithoutNameJSON = Data("""
    {
      "id": "missing.name",
      "protocol": "anime-stream-v1",
      "capabilities": ["streams"],
      "endpoints": { "streams": "/v1/streams" }
    }
    """.utf8)

    static let manifestWithoutStreamsJSON = Data("""
    {
      "id": "no.streams",
      "name": "No Streams",
      "protocol": "anime-stream-v1",
      "capabilities": ["catalog"]
    }
    """.utf8)

    static let unsupportedManifestJSON = Data("""
    {
      "id": "unsupported.addon",
      "name": "Unsupported"
    }
    """.utf8)

    static let genericStreamsJSON = Data("""
    {
      "streams": [
        {
          "title": "[Group] Show - 07 [1080p][HEVC]",
          "infoHash": "AABBCCDDEEFF",
          "sizeBytes": 1450000000,
          "seeders": 120,
          "quality": "1080p",
          "group": "Group"
        },
        {
          "title": "[Group] Show - 07 [720p]",
          "magnetUri": "magnet:?xt=urn:btih:00112233445566778899aabbccddeeff00112233",
          "sizeBytes": 600000000
        },
        {
          "title": "Direct stream",
          "url": "https://example.com/stream.mp4"
        },
        {
          "title": "Local file",
          "url": "file:///etc/passwd"
        },
        {
          "title": "Nothing usable"
        }
      ]
    }
    """.utf8)

    static let stremioStreamsJSON = Data("""
    {
      "streams": [
        {
          "name": "Torrentio",
          "title": "Show 1080p",
          "infoHash": "DDEEFF001122",
          "fileIdx": 2,
          "behaviorHints": {
            "filename": "Show.S01E07.mkv",
            "videoSize": 1400000000,
            "bingeGroup": "show-1080"
          }
        },
        {
          "name": "Provider",
          "title": "Direct link",
          "url": "https://example.com/a.mp4"
        },
        {
          "title": "Nothing usable"
        }
      ]
    }
    """.utf8)

    static func addon(
        id: String,
        baseURL: URL,
        streamsPath: String = "/v1/streams",
        protocolType: AddonProtocolType = .animeStreamV1,
        priority: Int = 0,
        isEnabled: Bool = true,
        idNamespaces: [AddonIDNamespace] = [.anilist, .mal]
    ) -> InstalledAddon {
        InstalledAddon(
            id: id,
            name: id,
            manifestURL: baseURL.appending(path: "manifest.json"),
            baseURL: baseURL,
            protocolType: protocolType,
            isEnabled: isEnabled,
            priority: priority,
            idNamespaces: idNamespaces,
            streamsPath: streamsPath
        )
    }
}

struct AddonManifestTests {
    @Test func decodesGenericManifest() throws {
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: AddonFixtures.genericManifestJSON)

        #expect(manifest.id == "example.provider")
        #expect(manifest.name == "Example Provider")
        #expect(manifest.protocolType == .animeStreamV1)
        #expect(manifest.streamsEndpointPath == "/v1/streams")
        #expect(manifest.declaredCapabilities == [.streams])
    }

    @Test func decodesStremioManifest() throws {
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: AddonFixtures.stremioManifestJSON)

        #expect(manifest.protocolType == .stremio)
        #expect(manifest.declaredCapabilities == [.streams])
        #expect(manifest.resolvedNamespaces == [.kitsu, .imdb])
        #expect(manifest.types == ["anime", "series"])
    }

    @Test func decodesDetailedResourcePrefixes() throws {
        let manifest = try JSONDecoder().decode(
            AddonManifest.self,
            from: AddonFixtures.detailedResourcesManifestJSON
        )

        #expect(manifest.resolvedNamespaces == [.mal])
        #expect(manifest.declaredCapabilities == [.streams])
    }

    @Test func decodingMissingNameFails() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AddonManifest.self, from: AddonFixtures.manifestWithoutNameJSON)
        }
    }

    @Test func validationRejectsMissingStreamsCapability() throws {
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: AddonFixtures.manifestWithoutStreamsJSON)
        do {
            _ = try manifest.validated()
            Issue.record("Expected validation failure")
        } catch let error as AddonError {
            guard case .invalidManifest = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test func validationRejectsUnsupportedProtocol() throws {
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: AddonFixtures.unsupportedManifestJSON)
        #expect(throws: AddonError.unsupportedProtocol) {
            try manifest.validated()
        }
    }

    @Test func mapsPrefixAliases() {
        #expect(AddonManifest.namespaces(fromPrefixes: ["tt", "myanimelist", "kitsu"]) == [.imdb, .mal, .kitsu])
        #expect(AddonManifest.namespaces(fromPrefixes: ["unknown"]) == [])
    }

    @Test func mapsPrefixedNamespaceColons() {
        #expect(
            AddonManifest.namespaces(fromPrefixes: ["tt", "tmdb:", "mal:", "tvdb:", "anilist:"])
                == [.imdb, .tmdb, .mal, .anilist]
        )
    }

    @Test func streamTypesPreferDetailedStreamResource() throws {
        let manifest = try JSONDecoder().decode(
            AddonManifest.self,
            from: Data("""
            {
              "id": "stremio.addons.mediafusion",
              "name": "MediaFusion",
              "resources": [
                "catalog",
                {
                  "name": "stream",
                  "types": ["movie", "series", "tv"],
                  "idPrefixes": ["tt", "mal:"]
                }
              ],
              "types": ["movie", "series", "tv", "events"]
            }
            """.utf8)
        )

        #expect(manifest.streamTypes == ["movie", "series", "tv"])
        #expect(manifest.resolvedNamespaces == [.imdb, .mal])
    }

    @Test func streamTypesFallBackToTopLevelTypes() throws {
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: AddonFixtures.stremioManifestJSON)
        #expect(manifest.streamTypes == ["anime", "series"])
    }
}
