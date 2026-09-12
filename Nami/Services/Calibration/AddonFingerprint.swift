import CryptoKit
import Foundation

/// Identifies one *configured* addon installation.
///
/// Addons can be installed from the same manifest URL with different path or
/// query configuration (AIOStreams, for example, can completely change its
/// result formatting per configuration). Calibration therefore belongs to the
/// fingerprint, not just the addon id. The fingerprint stores only a salted
/// digest of the configuration; raw URLs, query values, and credentials never
/// leave this type.
struct AddonFingerprint: Codable, Hashable, Sendable {
    let addonID: String
    let host: String
    let configurationDigest: String
    let parserVersion: Int

    /// Bump when the profile schema or the learned-rule interpreter changes so
    /// existing profiles are recalibrated.
    static let currentParserVersion = 1

    init(
        addonID: String,
        host: String,
        configurationDigest: String,
        parserVersion: Int = AddonFingerprint.currentParserVersion
    ) {
        self.addonID = addonID
        self.host = host
        self.configurationDigest = configurationDigest
        self.parserVersion = parserVersion
    }

    init(addonID: String, manifestURL: URL) {
        let sanitized = Self.sanitized(manifestURL)
        self.init(
            addonID: addonID,
            host: sanitized.host,
            configurationDigest: Self.digest(
                addonID: addonID,
                host: sanitized.host,
                path: sanitized.path,
                query: sanitized.query
            )
        )
    }

    /// Stable storage key. Safe to log: it contains no configuration values.
    var storageKey: String {
        "\(addonID)|\(host)|\(configurationDigest)|v\(parserVersion)"
    }

    // MARK: - Sanitization

    /// Extracts the parts of a manifest URL that describe the configuration
    /// while dropping user info, fragments, and ordering noise.
    static func sanitized(_ url: URL) -> (host: String, path: String, query: String) {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return (url.host?.lowercased() ?? "", url.path, url.query ?? "")
        }
        components.user = nil
        components.password = nil
        components.fragment = nil

        var host = components.host?.lowercased() ?? ""
        if let port = components.port {
            host += ":\(port)"
        }
        let path = components.percentEncodedPath

        let pairs: [(name: String, value: String)] = (components.queryItems ?? []).map {
            (name: $0.name, value: $0.value ?? "")
        }
        let sortedPairs = pairs.sorted { lhs, rhs in
            if lhs.name == rhs.name { return lhs.value < rhs.value }
            return lhs.name < rhs.name
        }
        let queryParts: [String] = sortedPairs.map { pair in
            "\(pair.name)=\(pair.value)"
        }
        return (host, path, queryParts.joined(separator: "&"))
    }

    static func digest(addonID: String, host: String, path: String, query: String) -> String {
        let material = [addonID, host, path, query].joined(separator: "\u{1F}")
        let hash = SHA256.hash(data: Data(material.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
