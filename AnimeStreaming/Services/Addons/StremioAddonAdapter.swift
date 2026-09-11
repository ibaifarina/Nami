import Foundation

struct StremioAddonAdapter: StreamAddon {
    let descriptor: AddonDescriptor

    private let supportedTypes: [String]
    private let http: any HTTPClient
    private let timeout: TimeInterval
    private let maxResponseBytes: Int

    init(
        descriptor: AddonDescriptor,
        supportedTypes: [String] = [],
        http: any HTTPClient = URLSessionHTTPClient(),
        timeout: TimeInterval = 8,
        maxResponseBytes: Int = 4_000_000
    ) {
        self.descriptor = descriptor
        self.supportedTypes = supportedTypes.map { $0.lowercased() }
        self.http = http
        self.timeout = timeout
        self.maxResponseBytes = maxResponseBytes
    }

    func streams(for media: MediaIdentity, episode: Episode) async throws -> [RawStreamResult] {
        let resolvedID = try Self.resolveID(for: media, namespaces: descriptor.idNamespaces)
        let type = resolvedType
        let identifier = Self.identifier(
            id: resolvedID.value,
            type: type,
            episodeNumber: episode.displayNumber,
            seasonNumber: episode.seasonNumber ?? 1
        )
        guard
            var components = URLComponents(url: descriptor.baseURL, resolvingAgainstBaseURL: false)
        else {
            throw AddonError.invalidURL
        }
        let basePath = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = "\(basePath)/stream/\(type)/\(identifier).json"
        guard let endpoint = components.url else {
            throw AddonError.invalidURL
        }

        let request = RequestBuilder(
            url: endpoint,
            headers: ["Accept": "application/json"],
            timeout: timeout
        ).build()

        let data: Data
        do {
            data = try await http.data(for: request, maxBytes: maxResponseBytes)
        } catch let httpError as HTTPError {
            switch httpError {
            case .responseTooLarge:
                throw AddonError.responseTooLarge
            default:
                throw AddonError.requestFailed(httpError.localizedDescription)
            }
        }

        let response: StremioStreamResponse
        do {
            response = try JSONDecoder().decode(StremioStreamResponse.self, from: data)
        } catch {
            throw AddonError.requestFailed("The addon returned an unsupported response.")
        }
        return response.streams.compactMap { stream in
            Self.normalize(stream, descriptor: descriptor)
        }
    }

    func healthCheck() async -> AddonHealthStatus {
        let request = RequestBuilder(
            url: descriptor.manifestURL,
            headers: ["Accept": "application/json"],
            timeout: 5
        ).build()
        let start = Date()
        do {
            let data = try await http.data(for: request, maxBytes: 256_000)
            _ = try JSONDecoder().decode(AddonManifest.self, from: data)
            return Date().timeIntervalSince(start) > 2.5 ? .degraded : .healthy
        } catch {
            return .failing
        }
    }

    struct ResolvedID: Equatable, Sendable {
        let namespace: AddonIDNamespace
        let value: String
    }

    static func resolveID(
        for media: MediaIdentity,
        namespaces: [AddonIDNamespace]
    ) throws -> ResolvedID {
        for namespace in namespaces {
            switch namespace {
            case .imdb:
                if let imdbID = media.imdbID {
                    let trimmed = imdbID.trimmingCharacters(in: .whitespaces)
                    let value = trimmed.hasPrefix("tt") ? trimmed : "tt\(trimmed)"
                    return ResolvedID(namespace: .imdb, value: value)
                }
            case .kitsu:
                let kitsuID = media.kitsuID.trimmingCharacters(in: .whitespaces)
                if !kitsuID.isEmpty {
                    return ResolvedID(namespace: .kitsu, value: "kitsu:\(kitsuID)")
                }
            case .mal:
                if let malID = media.malID {
                    return ResolvedID(namespace: .mal, value: "mal:\(malID)")
                }
            case .anilist:
                if let anilistID = media.anilistID {
                    return ResolvedID(namespace: .anilist, value: "anilist:\(anilistID)")
                }
            case .tmdb:
                if let tmdbID = media.tmdbID {
                    return ResolvedID(namespace: .tmdb, value: "tmdb:\(tmdbID)")
                }
            }
        }
        throw AddonError.unresolvableMediaID(namespaces)
    }

    private var resolvedType: String {
        if supportedTypes.contains("anime") { return "anime" }
        if supportedTypes.contains("series") { return "series" }
        return "movie"
    }

    static func identifier(
        id: String,
        type: String,
        episodeNumber: Int,
        seasonNumber: Int
    ) -> String {
        switch type {
        case "anime": "\(id):\(episodeNumber)"
        case "series": "\(id):\(max(seasonNumber, 1)):\(episodeNumber)"
        default: id
        }
    }

    static func normalize(_ stream: StremioStream, descriptor: AddonDescriptor) -> RawStreamResult? {
        let infoHash = stream.infoHash?.lowercased()
        let magnetURL = infoHash.flatMap { hash in
            URL(string: "magnet:?xt=urn:btih:\(hash)")
        }
        let directURL = stream.url.flatMap(GenericHTTPAddonAdapter.playableURL(from:))
        guard magnetURL != nil || directURL != nil else {
            return nil
        }
        let rawTitle = stream.title ?? stream.name ?? stream.behaviorHints?.filename
        var metadata: [String: String] = [:]
        if let filename = stream.behaviorHints?.filename { metadata["filename"] = filename }
        if let bingeGroup = stream.behaviorHints?.bingeGroup { metadata["bingeGroup"] = bingeGroup }
        return RawStreamResult(
            addonID: descriptor.id,
            addonName: descriptor.name,
            displayTitle: rawTitle ?? "Untitled release",
            rawTitle: rawTitle,
            infoHash: infoHash,
            magnetURI: magnetURL,
            directURL: directURL,
            fileIndex: stream.fileIdx,
            sizeBytes: stream.behaviorHints?.videoSize,
            seeders: nil,
            providerName: stream.name,
            providerMetadata: metadata
        )
    }
}

struct StremioStreamResponse: Decodable {
    let streams: [StremioStream]
}

struct StremioStream: Decodable {
    struct BehaviorHints: Decodable {
        let filename: String?
        let videoSize: Int64?
        let bingeGroup: String?
    }

    let name: String?
    let title: String?
    let url: String?
    let externalUrl: String?
    let infoHash: String?
    let fileIdx: Int?
    let behaviorHints: BehaviorHints?
}
