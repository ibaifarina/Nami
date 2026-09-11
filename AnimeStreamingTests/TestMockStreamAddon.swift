import Foundation
@testable import AnimeStreaming

struct MockStreamAddon: StreamAddon {
    let descriptor: AddonDescriptor
    var seeds: [RawStreamResult]
    var latency: Duration
    var failure: AddonError?

    init(
        descriptor: AddonDescriptor = MockStreamAddon.defaultDescriptor,
        seeds: [RawStreamResult] = MockStreamAddon.defaultSeeds,
        latency: Duration = .milliseconds(60),
        failure: AddonError? = nil
    ) {
        self.descriptor = descriptor
        self.seeds = seeds
        self.latency = latency
        self.failure = failure
    }

    func streams(for media: MediaIdentity, episode: Episode) async throws -> [RawStreamResult] {
        if latency > .zero {
            try await Task.sleep(for: latency)
        }
        if let failure {
            throw failure
        }
        return seeds.map { seed in
            RawStreamResult(
                addonID: descriptor.id,
                addonName: descriptor.name,
                displayTitle: seed.displayTitle,
                rawTitle: seed.rawTitle,
                infoHash: seed.infoHash,
                magnetURI: seed.magnetURI,
                directURL: seed.directURL,
                fileIndex: seed.fileIndex,
                sizeBytes: seed.sizeBytes,
                seeders: seed.seeders,
                providerName: seed.providerName,
                providerMetadata: seed.providerMetadata
            )
        }
    }

    func healthCheck() async -> AddonHealthStatus {
        failure == nil ? .healthy : .failing
    }

    static let defaultDescriptor = AddonDescriptor(
        id: "sample.sources",
        name: "Sample Sources",
        version: "1.0.0",
        protocolType: .animeStreamV1,
        capabilities: [.streams],
        idNamespaces: [.anilist, .mal],
        baseURL: url("https://sample.invalid"),
        manifestURL: url("https://sample.invalid/manifest.json")
    )

    static let defaultSeeds: [RawStreamResult] = [
        RawStreamResult(
            addonID: defaultDescriptor.id,
            addonName: defaultDescriptor.name,
            displayTitle: "[Sample] Frieren - 07 [1080p][HEVC]",
            rawTitle: "[Sample] Frieren - 07 [1080p][HEVC]",
            infoHash: "aabbccddeeff00112233445566778899aabbccdd",
            sizeBytes: 1_450_000_000,
            seeders: 42
        ),
        RawStreamResult(
            addonID: defaultDescriptor.id,
            addonName: defaultDescriptor.name,
            displayTitle: "[Sample] Frieren - 07 [720p][AVC]",
            rawTitle: "[Sample] Frieren - 07 [720p][AVC]",
            directURL: url("https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"),
            sizeBytes: 620_000_000
        ),
        RawStreamResult(
            addonID: defaultDescriptor.id,
            addonName: defaultDescriptor.name,
            displayTitle: "[Sample] Frieren - 07 [2160p][HEVC]",
            rawTitle: "[Sample] Frieren - 07 [2160p][HEVC]",
            magnetURI: URL(string: "magnet:?xt=urn:btih:00112233445566778899aabbccddeeff00112233"),
            sizeBytes: 7_400_000_000,
            seeders: 8
        ),
    ]

    static func sampleInstalled(priority: Int = 0) -> InstalledAddon {
        InstalledAddon(
            id: defaultDescriptor.id,
            name: defaultDescriptor.name,
            description: "Bundled sample sources for development and previews.",
            manifestURL: defaultDescriptor.manifestURL,
            baseURL: defaultDescriptor.baseURL,
            protocolType: .animeStreamV1,
            isEnabled: true,
            priority: priority,
            capabilities: [.streams],
            idNamespaces: [.anilist, .mal],
            streamsPath: "/v1/streams",
            supportedTypes: ["tv", "movie"]
        )
    }

    private static func url(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Invalid mock addon URL: \(string)")
        }
        return url
    }
}
