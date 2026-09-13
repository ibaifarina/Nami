import Foundation

enum AddonCapability: String, Codable, Sendable, CaseIterable, Identifiable {
    case streams
    case catalog
    case meta
    case subtitles

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .streams: "Streams"
        case .catalog: "Catalog"
        case .meta: "Metadata"
        case .subtitles: "Subtitles"
        }
    }
}

enum AddonIDNamespace: String, Codable, Sendable, CaseIterable, Identifiable {
    case anilist
    case mal
    case kitsu
    case imdb
    case tmdb

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anilist: "AniList"
        case .mal: "MyAnimeList"
        case .kitsu: "Kitsu"
        case .imdb: "IMDb"
        case .tmdb: "TMDb"
        }
    }
}

struct AddonDescriptor: Hashable, Sendable {
    let id: String
    let name: String
    let version: String?
    let protocolType: AddonProtocolType
    let capabilities: Set<AddonCapability>
    let idNamespaces: [AddonIDNamespace]
    let baseURL: URL
    let manifestURL: URL
}

/// Text field on a raw Stremio/Generic stream result that a parsing rule can
/// read. Calibration profiles only ever reference these fields, never arbitrary
/// keys or executable expressions.
enum StreamField: String, Codable, CaseIterable, Sendable {
    case title
    case name
    case description
    case filename

    var displayName: String { rawValue }
}

struct RawStreamResult: Hashable, Sendable {
    let addonID: String
    let addonName: String
    let displayTitle: String
    let rawTitle: String?
    let infoHash: String?
    let magnetURI: URL?
    let directURL: URL?
    let fileIndex: Int?
    let sizeBytes: Int64?
    let seeders: Int?
    let providerName: String?
    let providerMetadata: [String: String]
    /// Verbatim text fields exactly as the addon returned them. Used by the
    /// calibrated format parser and by calibration sampling. Never contains
    /// playback URLs, hashes, or credentials.
    let sourceFields: [StreamField: String]

    init(
        addonID: String,
        addonName: String,
        displayTitle: String,
        rawTitle: String? = nil,
        infoHash: String? = nil,
        magnetURI: URL? = nil,
        directURL: URL? = nil,
        fileIndex: Int? = nil,
        sizeBytes: Int64? = nil,
        seeders: Int? = nil,
        providerName: String? = nil,
        providerMetadata: [String: String] = [:],
        sourceFields: [StreamField: String] = [:]
    ) {
        self.addonID = addonID
        self.addonName = addonName
        self.displayTitle = displayTitle
        self.rawTitle = rawTitle
        self.infoHash = infoHash
        self.magnetURI = magnetURI
        self.directURL = directURL
        self.fileIndex = fileIndex
        self.sizeBytes = sizeBytes
        self.seeders = seeders
        self.providerName = providerName
        self.providerMetadata = providerMetadata
        self.sourceFields = sourceFields
    }

    /// Text fields considered by calibrated parsing profiles.
    var profileFields: [StreamField: String] {
        var fields = sourceFields
        if fields[.title] == nil, let rawTitle { fields[.title] = rawTitle }
        if fields[.name] == nil, let providerName { fields[.name] = providerName }
        if fields[.filename] == nil, let filename = providerMetadata["filename"] {
            fields[.filename] = filename
        }
        return fields
    }
}

struct AddonQueryResult: Identifiable, Sendable {
    enum Outcome: Sendable {
        case success([RawStreamResult])
        case failure(String)
        case timedOut
    }

    var id: String { addon.id }

    let addon: InstalledAddon
    let outcome: Outcome

    var streams: [RawStreamResult] {
        if case .success(let streams) = outcome { return streams }
        return []
    }

    var failureMessage: String? {
        switch outcome {
        case .success: nil
        case .failure(let message): message
        case .timedOut: "The addon took too long to respond."
        }
    }
}

protocol StreamAddon: Sendable {
    var descriptor: AddonDescriptor { get }

    func streams(
        for media: MediaIdentity,
        episode: Episode,
        isMovie: Bool
    ) async throws -> [RawStreamResult]

    func healthCheck() async -> AddonHealthStatus
}

extension StreamAddon {
    func streams(
        for media: MediaIdentity,
        episode: Episode
    ) async throws -> [RawStreamResult] {
        try await streams(for: media, episode: episode, isMovie: false)
    }
}

enum AddonError: Error, Equatable, Sendable {
    case invalidURL
    case insecureURL
    case unsupportedScheme(String)
    case credentialsInURL
    case manifestTooLarge
    case responseTooLarge
    case invalidManifest(String)
    /// The manifest is valid JSON but declares no stream resource, which is
    /// what configurable addons such as AIOStreams return when their saved
    /// configuration has no providers enabled.
    case noStreamResources
    /// The addon only accepts provider-private catalog IDs, so Nami cannot
    /// address its stream endpoint using an anime identity.
    case unsupportedIDPrefixes([String])
    case unsupportedProtocol
    case alreadyInstalled(String)
    case unsupportedCapability(String)
    case unresolvableMediaID([AddonIDNamespace])
    case requestFailed(String)
    case noStreams
}

extension AddonError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "That addon address is not valid."
        case .insecureURL:
            "Addons must use HTTPS. Enable the advanced HTTP override for local development if you trust the address."
        case .unsupportedScheme:
            "That address uses an unsupported scheme. Only HTTPS is allowed."
        case .credentialsInURL:
            "Addon addresses must not contain embedded credentials."
        case .manifestTooLarge:
            "This addon's manifest is larger than allowed."
        case .responseTooLarge:
            "The addon returned more data than allowed."
        case .invalidManifest(let detail):
            "This addon returned an invalid manifest. \(detail)"
        case .noStreamResources:
            "This addon's manifest doesn't declare any stream providers. If it's configurable, open its configuration, enable at least one stream provider, then add the addon again."
        case .unsupportedIDPrefixes(let prefixes):
            "This addon only serves its own catalog IDs (\(prefixes.joined(separator: ", "))), which Nami can't match to its anime library. Use a stream addon that supports IMDb, TMDB, Kitsu, MAL, or AniList IDs."
        case .unsupportedProtocol:
            "This addon uses a protocol the app does not support yet."
        case .alreadyInstalled(let name):
            "\(name) is already installed."
        case .unsupportedCapability(let capability):
            "This addon does not support \(capability)."
        case .unresolvableMediaID(let namespaces):
            "This addon needs an ID we could not resolve (\(namespaces.map(\.displayName).joined(separator: ", ")))."
        case .requestFailed(let detail):
            "The addon request failed. \(detail)"
        case .noStreams:
            "No playable sources were found for this episode."
        }
    }
}
