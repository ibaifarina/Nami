import Foundation
import Testing
@testable import Nami

struct AddonInstallServiceTests {
    @Test func previewsGenericManifest() async throws {
        let service = AddonInstallService(
            http: MockHTTPClient { _ in AddonFixtures.genericManifestJSON }
        )

        let preview = try await service.preview(
            manifestURL: testURL("https://example.com/addons/manifest.json")
        )

        #expect(preview.id == "example.provider")
        #expect(preview.name == "Example Provider")
        #expect(preview.protocolType == .animeStreamV1)
        #expect(preview.baseURL.absoluteString == "https://example.com/addons/")
        #expect(preview.capabilities == [.streams])
        #expect(preview.idNamespaces == [.kitsu, .mal, .anilist])

        let installed = preview.makeInstalledAddon(priority: 0)
        #expect(installed.streamsPath == "/v1/streams")
        #expect(installed.isEnabled)
    }

    @Test func previewsStremioManifest() async throws {
        let service = AddonInstallService(
            http: MockHTTPClient { _ in AddonFixtures.stremioManifestJSON }
        )

        let preview = try await service.preview(
            manifestURL: testURL("https://stremio.example/manifest.json")
        )

        #expect(preview.protocolType == .stremio)
        #expect(preview.idNamespaces == [.kitsu, .imdb])
        #expect(preview.iconURL?.absoluteString == "https://example.com/logo.png")

        let installed = preview.makeInstalledAddon(priority: 0)
        #expect(installed.supportedTypes == ["anime", "series"])
        #expect(installed.streamsPath == nil)
    }

    @Test func previewsStremioManifestWithoutPrefixes() async throws {
        let service = AddonInstallService(
            http: MockHTTPClient { _ in
                Data("""
                {
                  "id": "org.example.noprefixes",
                  "name": "No Prefixes",
                  "resources": ["stream"],
                  "types": ["movie", "series"]
                }
                """.utf8)
            }
        )

        let preview = try await service.preview(
            manifestURL: testURL("https://stremio.example/manifest.json")
        )

        #expect(preview.idNamespaces == [.imdb, .kitsu])
    }

    @Test func rejectsHTTPManifestByDefault() async {
        let service = AddonInstallService(http: MockHTTPClient())
        do {
            _ = try await service.preview(manifestURL: testURL("http://example.com/manifest.json"))
            Issue.record("Expected insecure URL error")
        } catch let error as AddonError {
            #expect(error == .insecureURL)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func acceptsHTTPManifestWithOverride() async throws {
        let service = AddonInstallService(
            http: MockHTTPClient { _ in AddonFixtures.genericManifestJSON }
        )

        let preview = try await service.preview(
            manifestURL: testURL("http://localhost:8080/manifest.json"),
            allowInsecureHTTP: true
        )

        #expect(preview.protocolType == .animeStreamV1)
    }

    @Test func rejectsManifestMissingName() async {
        let service = AddonInstallService(
            http: MockHTTPClient { _ in AddonFixtures.manifestWithoutNameJSON }
        )
        await expectAddonFailure(service, matching: { error in
            if case .invalidManifest = error { return true }
            return false
        })
    }

    @Test func rejectsManifestWithoutStreams() async {
        let service = AddonInstallService(
            http: MockHTTPClient { _ in AddonFixtures.manifestWithoutStreamsJSON }
        )
        await expectAddonFailure(service, matching: { $0 == .noStreamResources })
    }

    @Test func rejectsConfigurableManifestWithEmptyResources() async {
        let service = AddonInstallService(
            http: MockHTTPClient { _ in AddonFixtures.emptyResourcesManifestJSON }
        )
        await expectAddonFailure(service, matching: { $0 == .noStreamResources })
    }

    @Test func rejectsUnsupportedProtocol() async {
        let service = AddonInstallService(
            http: MockHTTPClient { _ in AddonFixtures.unsupportedManifestJSON }
        )
        await expectAddonFailure(service, matching: { $0 == .unsupportedProtocol })
    }

    @Test func rejectsMalformedJSON() async {
        let service = AddonInstallService(
            http: MockHTTPClient { _ in Data("not json".utf8) }
        )
        await expectAddonFailure(service, matching: { error in
            if case .invalidManifest = error { return true }
            return false
        })
    }

    @Test func mapsOversizedManifest() async {
        let service = AddonInstallService(
            http: MockHTTPClient { _ in
                throw HTTPError.responseTooLarge(limit: 10)
            }
        )
        await expectAddonFailure(service, matching: { $0 == .manifestTooLarge })
    }

    @Test func timesOutSlowManifest() async {
        let service = AddonInstallService(
            http: MockHTTPClient { _ in
                try await Task.sleep(for: .milliseconds(400))
                return AddonFixtures.genericManifestJSON
            },
            manifestTimeout: .milliseconds(40)
        )
        await expectAddonFailure(service, matching: { error in
            if case .requestFailed = error { return true }
            return false
        })
    }

    private func expectAddonFailure(
        _ service: AddonInstallService,
        matching predicate: (AddonError) -> Bool
    ) async {
        do {
            _ = try await service.preview(manifestURL: testURL("https://example.com/manifest.json"))
            Issue.record("Expected an addon error")
        } catch let error as AddonError {
            #expect(predicate(error), "Unexpected addon error: \(error)")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
