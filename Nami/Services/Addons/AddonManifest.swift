import Foundation

struct AddonManifest: Decodable, Sendable {
    let id: String
    let name: String
    let version: String?
    let description: String?
    let logo: String?
    let protocolIdentifier: String?
    let capabilities: [String]?
    let endpoints: [String: String]?
    let resources: [ManifestResource]?
    let types: [String]?
    let idPrefixes: [String]?
    let idNamespaces: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case version
        case description
        case logo
        case protocolIdentifier = "protocol"
        case capabilities
        case endpoints
        case resources
        case types
        case idPrefixes
        case idNamespaces
    }
}

enum ManifestResource: Decodable, Sendable, Hashable {
    case name(String)
    case detailed(name: String, types: [String]?, idPrefixes: [String]?)

    var resourceName: String {
        switch self {
        case .name(let name): name
        case .detailed(let name, _, _): name
        }
    }

    var idPrefixes: [String] {
        if case .detailed(_, _, let prefixes) = self { return prefixes ?? [] }
        return []
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .name(string)
            return
        }
        let keyed = try decoder.container(keyedBy: DetailedKeys.self)
        self = .detailed(
            name: try keyed.decode(String.self, forKey: .name),
            types: try keyed.decodeIfPresent([String].self, forKey: .types),
            idPrefixes: try keyed.decodeIfPresent([String].self, forKey: .idPrefixes)
        )
    }

    private enum DetailedKeys: String, CodingKey {
        case name
        case types
        case idPrefixes
    }
}

extension AddonManifest {
    var protocolType: AddonProtocolType? {
        if let identifier = protocolIdentifier?.lowercased(), identifier == AddonProtocolType.animeStreamV1.rawValue {
            return .animeStreamV1
        }
        if endpoints?["streams"] != nil {
            return .animeStreamV1
        }
        if resources != nil {
            return .stremio
        }
        if (capabilities ?? []).contains(where: { $0.lowercased() == "streams" }) {
            return .stremio
        }
        return nil
    }

    var declaredCapabilities: Set<AddonCapability> {
        var result: Set<AddonCapability> = []
        for raw in capabilities ?? [] {
            if let capability = Self.capability(from: raw) {
                result.insert(capability)
            }
        }
        for resource in resources ?? [] {
            if let capability = Self.capability(from: resource.resourceName) {
                result.insert(capability)
            }
        }
        return result
    }

    var resolvedNamespaces: [AddonIDNamespace] {
        if let idNamespaces {
            let mapped = idNamespaces.compactMap { AddonIDNamespace(rawValue: $0.lowercased()) }
            if !mapped.isEmpty { return mapped }
        }
        let prefixes = idPrefixes ?? []
        if !prefixes.isEmpty {
            return Self.namespaces(fromPrefixes: prefixes)
        }
        let resourcePrefixes = (resources ?? []).flatMap(\.idPrefixes)
        if !resourcePrefixes.isEmpty {
            return Self.namespaces(fromPrefixes: resourcePrefixes)
        }
        return []
    }

    var streamsEndpointPath: String? {
        endpoints?["streams"]
    }

    func validated() throws -> AddonManifest {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty, trimmedID.count <= 128 else {
            throw AddonError.invalidManifest("The manifest is missing a valid id.")
        }
        guard !trimmedName.isEmpty, trimmedName.count <= 128 else {
            throw AddonError.invalidManifest("The manifest is missing a valid name.")
        }
        guard protocolType != nil else {
            throw AddonError.unsupportedProtocol
        }
        guard declaredCapabilities.contains(.streams) else {
            throw AddonError.invalidManifest("The addon does not declare stream support.")
        }
        return self
    }

    static func namespaces(fromPrefixes prefixes: [String]) -> [AddonIDNamespace] {
        var result: [AddonIDNamespace] = []
        for prefix in prefixes {
            let namespace: AddonIDNamespace? = switch prefix.lowercased() {
            case "tt", "imdb": .imdb
            case "kitsu": .kitsu
            case "mal", "myanimelist": .mal
            case "anilist": .anilist
            case "tmdb": .tmdb
            default: nil
            }
            if let namespace, !result.contains(namespace) {
                result.append(namespace)
            }
        }
        return result
    }

    private static func capability(from raw: String) -> AddonCapability? {
        switch raw.lowercased() {
        case "stream", "streams": .streams
        case "catalog", "catalogs": .catalog
        case "meta", "metadata": .meta
        case "subtitle", "subtitles": .subtitles
        default: nil
        }
    }
}

struct AddonInstallPreview: Identifiable, Sendable {
    let manifest: AddonManifest
    let manifestURL: URL
    let baseURL: URL
    let protocolType: AddonProtocolType
    let capabilities: Set<AddonCapability>
    let idNamespaces: [AddonIDNamespace]

    var id: String { manifest.id }
    var name: String { manifest.name }
    var version: String? { manifest.version }
    var descriptionText: String? { manifest.description }
    var iconURL: URL? { manifest.logo.flatMap(URL.init(string:)) }

    func makeInstalledAddon(priority: Int) -> InstalledAddon {
        InstalledAddon(
            id: manifest.id,
            name: manifest.name,
            description: manifest.description,
            iconURL: iconURL,
            manifestURL: manifestURL,
            baseURL: baseURL,
            protocolType: protocolType,
            isEnabled: true,
            priority: priority,
            capabilities: capabilities,
            idNamespaces: idNamespaces,
            streamsPath: manifest.streamsEndpointPath,
            supportedTypes: (manifest.types ?? []).map { $0.lowercased() }
        )
    }
}
