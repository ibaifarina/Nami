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
            "The address could not be understood."
        case .offline:
            "You appear to be offline. Check your internet connection."
        case .transport:
            "The server could not be reached."
        case .timedOut:
            "The server took too long to respond."
        case .httpStatus(let code, _):
            "The server rejected the request (HTTP \(code))."
        case .responseTooLarge:
            "The server returned more data than allowed."
        case .decoding:
            "The server returned an unsupported response."
        }
    }
}
