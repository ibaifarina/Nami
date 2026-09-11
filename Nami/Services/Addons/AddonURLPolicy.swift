import Foundation

enum AddonURLPolicy {
    static func validate(_ url: URL, allowInsecureHTTP: Bool) throws {
        guard url.user == nil, url.password == nil else {
            throw AddonError.credentialsInURL
        }
        guard let scheme = url.scheme?.lowercased() else {
            throw AddonError.invalidURL
        }
        switch scheme {
        case "https":
            break
        case "http":
            guard allowInsecureHTTP else { throw AddonError.insecureURL }
        default:
            throw AddonError.unsupportedScheme(scheme)
        }
        guard let host = url.host, !host.isEmpty else {
            throw AddonError.invalidURL
        }
    }
}
