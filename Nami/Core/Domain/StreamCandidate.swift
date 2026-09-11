import Foundation

enum VideoResolution: String, Codable, CaseIterable, Sendable, Identifiable {
    case p2160 = "2160p"
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"

    var id: String { rawValue }
    var label: String { rawValue }
}

enum VideoCodec: String, Codable, CaseIterable, Sendable, Identifiable {
    case av1
    case hevc
    case avc

    var id: String { rawValue }

    var label: String {
        switch self {
        case .av1: "AV1"
        case .hevc: "HEVC"
        case .avc: "AVC"
        }
    }
}

enum ReleaseSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case bluRay
    case webDL
    case webRip
    case hdtv
    case dvd
    case cam
    case ts

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bluRay: "BluRay"
        case .webDL: "WEB-DL"
        case .webRip: "WEBRip"
        case .hdtv: "HDTV"
        case .dvd: "DVD"
        case .cam: "CAM"
        case .ts: "TS"
        }
    }
}

enum DebridAvailability: String, Codable, Sendable {
    case unknown
    case cached
    case notCached
    case unavailable

    var label: String {
        switch self {
        case .unknown: "Cache unknown"
        case .cached: "Cached"
        case .notCached: "Not cached"
        case .unavailable: "Unavailable"
        }
    }
}

struct ParsedEpisodeInfo: Hashable, Codable, Sendable {
    let season: Int?
    let episode: Int?
    let isBatch: Bool
    let isSpecial: Bool
}

struct StreamSource: Hashable, Codable, Sendable, Identifiable {
    var id: String { addonID }
    let addonID: String
    let addonName: String
}

struct StreamCandidate: Identifiable, Hashable, Codable, Sendable {
    let id: String

    let addonID: String
    let addonName: String

    let displayTitle: String
    let rawTitle: String?

    let infoHash: String?
    let magnetURI: URL?
    let directURL: URL?
    let fileIndex: Int?

    let resolution: VideoResolution?
    let codec: VideoCodec?
    let source: ReleaseSource?
    let releaseGroup: String?

    let sizeBytes: Int64?
    let seeders: Int?

    let audioLanguages: Set<String>
    let subtitleLanguages: Set<String>

    let parsedEpisode: ParsedEpisodeInfo?
    let isBatch: Bool

    var debridStatus: DebridAvailability
    var episodeMatchConfidence: Double
    var targetEpisode: Int?
    var sources: [StreamSource] = []

    init(
        id: String,
        addonID: String,
        addonName: String,
        displayTitle: String,
        rawTitle: String? = nil,
        infoHash: String? = nil,
        magnetURI: URL? = nil,
        directURL: URL? = nil,
        fileIndex: Int? = nil,
        resolution: VideoResolution? = nil,
        codec: VideoCodec? = nil,
        source: ReleaseSource? = nil,
        releaseGroup: String? = nil,
        sizeBytes: Int64? = nil,
        seeders: Int? = nil,
        audioLanguages: Set<String> = [],
        subtitleLanguages: Set<String> = [],
        parsedEpisode: ParsedEpisodeInfo? = nil,
        isBatch: Bool = false,
        debridStatus: DebridAvailability = .unknown,
        episodeMatchConfidence: Double = 0,
        targetEpisode: Int? = nil,
        sources: [StreamSource]? = nil
    ) {
        self.id = id
        self.addonID = addonID
        self.addonName = addonName
        self.displayTitle = displayTitle
        self.rawTitle = rawTitle
        self.infoHash = infoHash
        self.magnetURI = magnetURI
        self.directURL = directURL
        self.fileIndex = fileIndex
        self.resolution = resolution
        self.codec = codec
        self.source = source
        self.releaseGroup = releaseGroup
        self.sizeBytes = sizeBytes
        self.seeders = seeders
        self.audioLanguages = audioLanguages
        self.subtitleLanguages = subtitleLanguages
        self.parsedEpisode = parsedEpisode
        self.isBatch = isBatch
        self.debridStatus = debridStatus
        self.episodeMatchConfidence = episodeMatchConfidence
        self.targetEpisode = targetEpisode
        self.sources = sources ?? [StreamSource(addonID: addonID, addonName: addonName)]
    }
}
