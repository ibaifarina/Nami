import Foundation

enum CatalogError: Error, Equatable, Sendable {
    case unavailable
    case offline
    case timeout
    case unauthorized
    case notFound
    case server(String)
    case decoding
    case unknown

    var technicalDetail: String? {
        switch self {
        case .server(let detail): detail
        case .unavailable: String(localized: "Kitsu returned 403 (service unavailable)")
        default: nil
        }
    }
}

extension CatalogError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unavailable:
            String(localized: "Kitsu is temporarily unavailable.")
        case .offline:
            String(localized: "You appear to be offline. Check your internet connection and try again.")
        case .timeout:
            String(localized: "The request took too long. Please try again.")
        case .unauthorized:
            String(localized: "That request was not authorized.")
        case .notFound:
            String(localized: "That anime could not be found.")
        case .server:
            String(localized: "Kitsu returned an unexpected response. Please try again.")
        case .decoding:
            String(localized: "Kitsu sent data we could not read.")
        case .unknown:
            String(localized: "Something went wrong while loading this content.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unavailable:
            String(localized: "Kitsu is temporarily unavailable. Cached content is shown where available.")
        case .offline:
            String(localized: "Reconnect and try again.")
        default:
            String(localized: "Please try again in a moment.")
        }
    }
}

extension CatalogError {
    static func map(_ error: Error) -> CatalogError {
        if let catalogError = error as? CatalogError { return catalogError }
        if error is CancellationError { return .unknown }

        if let httpError = error as? HTTPError {
            switch httpError {
            case .invalidURL:
                return .unknown
            case .offline:
                return .offline
            case .timedOut:
                return .timeout
            case .transport(let message):
                return .server(message)
            case .httpStatus(let code, let body):
                let loweredBody = body?.lowercased() ?? ""
                if code == 401
                    || loweredBody.contains("unauthorized")
                    || loweredBody.contains("invalid token") {
                    return .unauthorized
                }
                switch code {
                case 403: return .unavailable
                case 404: return .notFound
                case 429: return .server(String(localized: "Kitsu rate limit reached. Try again shortly."))
                default:
                    let detail = body.map { ": \(String($0.prefix(200)))" } ?? ""
                    return .server("HTTP \(code)\(detail)")
                }
            case .responseTooLarge:
                return .server(String(localized: "Response exceeded the size limit"))
            case .decoding:
                return .decoding
            }
        }

        return .server(error.localizedDescription)
    }
}
