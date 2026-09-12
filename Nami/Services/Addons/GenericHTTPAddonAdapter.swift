import Foundation

struct GenericHTTPAddonAdapter: StreamAddon {
    let descriptor: AddonDescriptor

    private let streamsPath: String
    private let http: any HTTPClient
    private let timeout: TimeInterval
    private let maxResponseBytes: Int

    init(
        descriptor: AddonDescriptor,
        streamsPath: String,
        http: any HTTPClient = URLSessionHTTPClient(),
        timeout: TimeInterval = 8,
        maxResponseBytes: Int = 4_000_000
    ) {
        self.descriptor = descriptor
        self.streamsPath = streamsPath
        self.http = http
        self.timeout = timeout
        self.maxResponseBytes = maxResponseBytes
    }

    func streams(
        for media: MediaIdentity,
        episode: Episode,
        isMovie: Bool
    ) async throws -> [RawStreamResult] {
        guard let endpoint = URL(string: streamsPath, relativeTo: descriptor.baseURL)?.absoluteURL else {
            throw AddonError.invalidURL
        }
        let payload = StreamRequest(
            anilistId: media.anilistID,
            malId: media.malID,
            kitsuId: media.kitsuID,
            episode: episode.displayNumber,
            relativeEpisode: episode.relativeNumber,
            absoluteEpisode: episode.absoluteNumber,
            season: episode.seasonNumber ?? 1
        )
        let body: Data
        do {
            body = try JSONEncoder().encode(payload)
        } catch {
            throw AddonError.requestFailed("The request could not be encoded.")
        }
        let request = RequestBuilder(
            url: endpoint,
            method: "POST",
            headers: [
                "Content-Type": "application/json",
                "Accept": "application/json",
            ],
            body: body,
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

        let response: GenericStreamResponse
        do {
            response = try JSONDecoder().decode(GenericStreamResponse.self, from: data)
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

    static func normalize(_ stream: GenericStream, descriptor: AddonDescriptor) -> RawStreamResult? {
        let magnetURL = (stream.magnetUri ?? stream.magnetURI ?? stream.magnet).flatMap(URL.init(string:))
        let infoHash = stream.infoHash?.lowercased()
        let directURL = stream.url.flatMap(Self.playableURL(from:))
        guard magnetURL != nil || infoHash != nil || directURL != nil else {
            return nil
        }
        let rawTitle = stream.title ?? stream.name
        var metadata: [String: String] = [:]
        if let quality = stream.quality { metadata["quality"] = quality }
        if let audio = stream.audio { metadata["audio"] = audio }
        if let subtitles = stream.subtitles { metadata["subtitles"] = subtitles }
        if let group = stream.group { metadata["group"] = group }
        return RawStreamResult(
            addonID: descriptor.id,
            addonName: descriptor.name,
            displayTitle: rawTitle ?? "Untitled release",
            rawTitle: rawTitle,
            infoHash: infoHash,
            magnetURI: magnetURL,
            directURL: directURL,
            fileIndex: stream.fileIndex,
            sizeBytes: stream.sizeBytes,
            seeders: stream.seeders,
            providerName: stream.provider ?? descriptor.name,
            providerMetadata: metadata
        )
    }

    static func playableURL(from string: String) -> URL? {
        guard
            let url = URL(string: string),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return url
    }

    private struct StreamRequest: Encodable {
        let anilistId: Int?
        let malId: Int?
        let kitsuId: String?
        let episode: Int
        let relativeEpisode: Int?
        let absoluteEpisode: Int?
        let season: Int
    }
}

struct GenericStreamResponse: Decodable {
    let streams: [GenericStream]
}

struct GenericStream: Decodable {
    let title: String?
    let name: String?
    let provider: String?
    let group: String?
    let quality: String?
    let audio: String?
    let subtitles: String?
    let url: String?
    let infoHash: String?
    let magnetUri: String?
    let magnetURI: String?
    let magnet: String?
    let fileIndex: Int?
    let sizeBytes: Int64?
    let seeders: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        title = try container.decodeIfPresent(String.self, forKey: .init("title"))
        name = try container.decodeIfPresent(String.self, forKey: .init("name"))
        provider = try container.decodeIfPresent(String.self, forKey: .init("provider"))
        group = try container.decodeIfPresent(String.self, forKey: .init("group"))
        quality = try container.decodeIfPresent(String.self, forKey: .init("quality"))
        audio = try container.decodeIfPresent(String.self, forKey: .init("audio"))
        subtitles = try container.decodeIfPresent(String.self, forKey: .init("subtitles"))
        url = try container.decodeIfPresent(String.self, forKey: .init("url"))
        infoHash = try container.decodeIfPresent(String.self, forKey: .init("infoHash"))
        magnetUri = try container.decodeIfPresent(String.self, forKey: .init("magnetUri"))
        magnetURI = try container.decodeIfPresent(String.self, forKey: .init("magnetURI"))
        magnet = try container.decodeIfPresent(String.self, forKey: .init("magnet"))
        fileIndex = try container.decodeIfPresent(Int.self, forKey: .init("fileIndex"))
        sizeBytes = try container.decodeIfPresent(Int64.self, forKey: .init("sizeBytes"))
        seeders = try container.decodeIfPresent(Int.self, forKey: .init("seeders"))
    }
}

struct DynamicCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) {
        stringValue = string
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}
