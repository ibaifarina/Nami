import Foundation
import SwiftData

@Model
final class StoredAddon {
    @Attribute(.unique) var id: String
    var name: String
    var addonDescription: String?
    var iconURLString: String?
    var manifestURLString: String
    var baseURLString: String
    var protocolTypeRaw: String
    var isEnabled: Bool
    var priority: Int
    var configurationData: Data
    var healthRaw: String?
    var lastCheckedAt: Date?
    var capabilitiesRaw: [String]
    var idNamespacesRaw: [String]
    var streamsPath: String?
    var supportedTypesRaw: [String]

    init(
        id: String,
        name: String,
        addonDescription: String?,
        iconURLString: String?,
        manifestURLString: String,
        baseURLString: String,
        protocolTypeRaw: String,
        isEnabled: Bool,
        priority: Int,
        configurationData: Data,
        healthRaw: String?,
        lastCheckedAt: Date?,
        capabilitiesRaw: [String],
        idNamespacesRaw: [String],
        streamsPath: String?,
        supportedTypesRaw: [String]
    ) {
        self.id = id
        self.name = name
        self.addonDescription = addonDescription
        self.iconURLString = iconURLString
        self.manifestURLString = manifestURLString
        self.baseURLString = baseURLString
        self.protocolTypeRaw = protocolTypeRaw
        self.isEnabled = isEnabled
        self.priority = priority
        self.configurationData = configurationData
        self.healthRaw = healthRaw
        self.lastCheckedAt = lastCheckedAt
        self.capabilitiesRaw = capabilitiesRaw
        self.idNamespacesRaw = idNamespacesRaw
        self.streamsPath = streamsPath
        self.supportedTypesRaw = supportedTypesRaw
    }

    convenience init(_ addon: InstalledAddon) {
        self.init(
            id: addon.id,
            name: addon.name,
            addonDescription: addon.description,
            iconURLString: addon.iconURL?.absoluteString,
            manifestURLString: addon.manifestURL.absoluteString,
            baseURLString: addon.baseURL.absoluteString,
            protocolTypeRaw: addon.protocolType.rawValue,
            isEnabled: addon.isEnabled,
            priority: addon.priority,
            configurationData: (try? JSONEncoder().encode(addon.configuration)) ?? Data(),
            healthRaw: addon.lastHealthStatus?.rawValue,
            lastCheckedAt: addon.lastCheckedAt,
            capabilitiesRaw: addon.capabilities.map(\.rawValue).sorted(),
            idNamespacesRaw: addon.idNamespaces.map(\.rawValue),
            streamsPath: addon.streamsPath,
            supportedTypesRaw: addon.supportedTypes
        )
    }

    func update(from addon: InstalledAddon) {
        name = addon.name
        addonDescription = addon.description
        iconURLString = addon.iconURL?.absoluteString
        manifestURLString = addon.manifestURL.absoluteString
        baseURLString = addon.baseURL.absoluteString
        protocolTypeRaw = addon.protocolType.rawValue
        isEnabled = addon.isEnabled
        priority = addon.priority
        configurationData = (try? JSONEncoder().encode(addon.configuration)) ?? Data()
        healthRaw = addon.lastHealthStatus?.rawValue
        lastCheckedAt = addon.lastCheckedAt
        capabilitiesRaw = addon.capabilities.map(\.rawValue).sorted()
        idNamespacesRaw = addon.idNamespaces.map(\.rawValue)
        streamsPath = addon.streamsPath
        supportedTypesRaw = addon.supportedTypes
    }

    func toDomain() -> InstalledAddon? {
        guard
            let manifestURL = URL(string: manifestURLString),
            let baseURL = URL(string: baseURLString),
            let protocolType = AddonProtocolType(rawValue: protocolTypeRaw)
        else {
            return nil
        }
        let configuration = (try? JSONDecoder().decode([String: String].self, from: configurationData)) ?? [:]
        return InstalledAddon(
            id: id,
            name: name,
            description: addonDescription,
            iconURL: iconURLString.flatMap(URL.init(string:)),
            manifestURL: manifestURL,
            baseURL: baseURL,
            protocolType: protocolType,
            isEnabled: isEnabled,
            priority: priority,
            configuration: configuration,
            lastHealthStatus: healthRaw.flatMap(AddonHealthStatus.init(rawValue:)),
            lastCheckedAt: lastCheckedAt,
            capabilities: Set(capabilitiesRaw.compactMap(AddonCapability.init(rawValue:))),
            idNamespaces: idNamespacesRaw.compactMap(AddonIDNamespace.init(rawValue:)),
            streamsPath: streamsPath,
            supportedTypes: supportedTypesRaw
        )
    }
}
