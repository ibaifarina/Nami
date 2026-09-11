import Foundation
import Testing
@testable import Nami

@MainActor
struct AddonRegistryTests {
    private func makePreview(id: String, name: String? = nil) -> AddonInstallPreview {
        AddonInstallPreview(
            manifest: AddonManifest(
                id: id,
                name: name ?? id,
                version: "1.0.0",
                description: "Test addon",
                logo: nil,
                protocolIdentifier: "anime-stream-v1",
                capabilities: ["streams"],
                endpoints: ["streams": "/v1/streams"],
                resources: nil,
                types: nil,
                idPrefixes: nil,
                idNamespaces: nil
            ),
            manifestURL: testURL("https://example.com/manifest.json"),
            baseURL: testURL("https://example.com"),
            protocolType: .animeStreamV1,
            capabilities: [.streams],
            idNamespaces: [.anilist, .mal]
        )
    }

    @Test func installAssignsPrioritiesInOrder() throws {
        let persistence = InMemoryAddonPersistence()
        let registry = AddonRegistry(persistence: persistence)

        _ = try registry.install(makePreview(id: "one"))
        _ = try registry.install(makePreview(id: "two"))

        #expect(registry.installed.map(\.id) == ["one", "two"])
        #expect(registry.installed.map(\.priority) == [0, 1])
        #expect(registry.installed.allSatisfy { $0.isEnabled })
    }

    @Test func installingDuplicateThrows() throws {
        let registry = AddonRegistry(persistence: InMemoryAddonPersistence())
        _ = try registry.install(makePreview(id: "one", name: "One"))

        do {
            _ = try registry.install(makePreview(id: "one", name: "One"))
            Issue.record("Expected already-installed error")
        } catch let error as AddonError {
            #expect(error == .alreadyInstalled("One"))
        }
    }

    @Test func enableAndDisableAffectsEnabledList() throws {
        let registry = AddonRegistry(persistence: InMemoryAddonPersistence())
        _ = try registry.install(makePreview(id: "one"))
        _ = try registry.install(makePreview(id: "two"))

        try registry.setEnabled(id: "one", isEnabled: false)

        #expect(registry.enabledAddons.map(\.id) == ["two"])
        #expect(registry.installed.first?.isEnabled == false)
    }

    @Test func removeReindexesPriorities() throws {
        let registry = AddonRegistry(persistence: InMemoryAddonPersistence())
        _ = try registry.install(makePreview(id: "one"))
        _ = try registry.install(makePreview(id: "two"))
        _ = try registry.install(makePreview(id: "three"))

        try registry.remove(id: "two")

        #expect(registry.installed.map(\.id) == ["one", "three"])
        #expect(registry.installed.map(\.priority) == [0, 1])
    }

    @Test func moveUpAndDownReorders() throws {
        let registry = AddonRegistry(persistence: InMemoryAddonPersistence())
        _ = try registry.install(makePreview(id: "one"))
        _ = try registry.install(makePreview(id: "two"))
        _ = try registry.install(makePreview(id: "three"))

        try registry.move(id: "three", direction: .up)
        #expect(registry.installed.map(\.id) == ["one", "three", "two"])
        #expect(registry.installed.map(\.priority) == [0, 1, 2])

        try registry.move(id: "one", direction: .down)
        #expect(registry.installed.map(\.id) == ["three", "one", "two"])
    }

    @Test func moveFromOffsetsReorders() throws {
        let registry = AddonRegistry(persistence: InMemoryAddonPersistence())
        _ = try registry.install(makePreview(id: "one"))
        _ = try registry.install(makePreview(id: "two"))
        _ = try registry.install(makePreview(id: "three"))

        try registry.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        #expect(registry.installed.map(\.id) == ["three", "one", "two"])
        #expect(registry.installed.map(\.priority) == [0, 1, 2])
    }

    @Test func inMemoryPersistenceRoundTrips() throws {
        let persistence = InMemoryAddonPersistence()
        let registry = AddonRegistry(persistence: persistence)
        _ = try registry.install(makePreview(id: "one"))
        try registry.setEnabled(id: "one", isEnabled: false)

        let reloaded = AddonRegistry(persistence: persistence)

        #expect(reloaded.installed.map(\.id) == ["one"])
        #expect(reloaded.installed.first?.isEnabled == false)
    }

    @Test func updateHealthRecordsTimestamp() throws {
        let registry = AddonRegistry(persistence: InMemoryAddonPersistence())
        _ = try registry.install(makePreview(id: "one"))
        #expect(registry.installed.first?.lastCheckedAt == nil)

        try registry.updateHealth(id: "one", status: .healthy)

        #expect(registry.installed.first?.lastHealthStatus == .healthy)
        #expect(registry.installed.first?.lastCheckedAt != nil)
    }

    @Test func swiftDataPersistenceRoundTrips() throws {
        let container = try #require(SwiftDataAddonPersistence.makeContainer(inMemory: true))
        let registry = AddonRegistry(
            persistence: SwiftDataAddonPersistence(container: container)
        )

        _ = try registry.install(makePreview(id: "one"))
        _ = try registry.install(makePreview(id: "two"))
        try registry.setEnabled(id: "two", isEnabled: false)
        try registry.updateHealth(id: "one", status: .healthy)
        try registry.move(id: "two", direction: .up)

        let reloaded = AddonRegistry(
            persistence: SwiftDataAddonPersistence(container: container)
        )

        #expect(reloaded.installed.map(\.id) == ["two", "one"])
        #expect(reloaded.installed.map(\.priority) == [0, 1])
        #expect(reloaded.installed.first?.isEnabled == false)
        #expect(reloaded.installed.last?.lastHealthStatus == .healthy)
        #expect(reloaded.installed.last?.idNamespaces == [.anilist, .mal])
        #expect(reloaded.installed.last?.capabilities == [.streams])
    }
}
