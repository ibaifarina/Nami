import Foundation

enum AddonProtocolType: String, Codable, Sendable, CaseIterable, Identifiable {
    case animeStreamV1 = "anime-stream-v1"
    case stremio = "stremio"
    case generic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .animeStreamV1: "Anime Stream v1"
        case .stremio: "Stremio"
        case .generic: "Generic HTTP"
        }
    }
}

enum AddonHealthStatus: String, Codable, Sendable {
    case unknown
    case healthy
    case degraded
    case failing

    var displayName: String {
        switch self {
        case .unknown: "Not checked"
        case .healthy: "Healthy"
        case .degraded: "Slow"
        case .failing: "Unreachable"
        }
    }
}

struct InstalledAddon: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var description: String?
    var iconURL: URL?
    var manifestURL: URL
    var baseURL: URL
    var protocolType: AddonProtocolType
    var isEnabled: Bool
    var priority: Int
    var configuration: [String: String]
    var lastHealthStatus: AddonHealthStatus?
    var lastCheckedAt: Date?
    var capabilities: Set<AddonCapability>
    var idNamespaces: [AddonIDNamespace]
    var streamsPath: String?
    var supportedTypes: [String]

    init(
        id: String,
        name: String,
        description: String? = nil,
        iconURL: URL? = nil,
        manifestURL: URL,
        baseURL: URL,
        protocolType: AddonProtocolType,
        isEnabled: Bool = true,
        priority: Int,
        configuration: [String: String] = [:],
        lastHealthStatus: AddonHealthStatus? = nil,
        lastCheckedAt: Date? = nil,
        capabilities: Set<AddonCapability> = [.streams],
        idNamespaces: [AddonIDNamespace] = [],
        streamsPath: String? = nil,
        supportedTypes: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.iconURL = iconURL
        self.manifestURL = manifestURL
        self.baseURL = baseURL
        self.protocolType = protocolType
        self.isEnabled = isEnabled
        self.priority = priority
        self.configuration = configuration
        self.lastHealthStatus = lastHealthStatus
        self.lastCheckedAt = lastCheckedAt
        self.capabilities = capabilities
        self.idNamespaces = idNamespaces
        self.streamsPath = streamsPath
        self.supportedTypes = supportedTypes
    }
}
