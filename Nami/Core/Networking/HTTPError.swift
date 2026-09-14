import Foundation

enum HTTPError: Error, Equatable, Sendable {
    case invalidURL
    case offline
    case transport(String)
    case timedOut
    case httpStatus(code: Int, body: String?)
    case responseTooLarge(limit: Int)
    case decoding(String)
}

extension HTTPError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            String(localized: "The address could not be understood.")
        case .offline:
            String(localized: "You appear to be offline. Check your internet connection.")
        case .transport:
            String(localized: "The server could not be reached.")
        case .timedOut:
            String(localized: "The server took too long to respond.")
        case .httpStatus(let code, _):
            String(localized: "The server rejected the request (HTTP \(code)).")
        case .responseTooLarge:
            String(localized: "The server returned more data than allowed.")
        case .decoding:
            String(localized: "The server returned an unsupported response.")
        }
    }
}
