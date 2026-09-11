import Foundation
import Testing
@testable import Nami

@MainActor
struct ExternalPlayerServiceTests {
    @Test func knownPlayersHaveUniqueBundleIDs() {
        let bundleIDs = ExternalPlayer.known.map(\.bundleID)
        #expect(Set(bundleIDs).count == bundleIDs.count)
        #expect(ExternalPlayer.known.allSatisfy { !$0.displayName.isEmpty })
    }

    @Test func openingUnknownPlayerThrowsNotInstalled() async {
        let service = ExternalPlayerService()
        let player = ExternalPlayer(
            bundleID: "com.example.ghost-\(UUID().uuidString)",
            displayName: "Ghost Player"
        )

        await #expect(throws: ExternalPlayerError.notInstalled("Ghost Player")) {
            try await service.open(testURL("https://cdn.example/video.mp4"), in: player)
        }
    }

    @Test func detectedPlayersAreResolvable() {
        let service = ExternalPlayerService()
        let detected = service.detectedPlayers()
        #expect(detected.allSatisfy { service.applicationURL(for: $0) != nil })
    }
}
