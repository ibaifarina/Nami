import Foundation

protocol DebridService: Sendable {
    func validateAccount() async throws -> DebridAccount
    func validateAccount(token: String) async throws -> DebridAccount
    func checkAvailability(_ candidates: [StreamCandidate]) async throws -> [DebridCheckResult]
    func resolve(_ candidate: StreamCandidate, fileID: Int?) async throws -> ResolvedStream
    /// Lists the files inside a torrent candidate. Returns an empty array for
    /// candidates that are not torrents, such as direct URLs.
    func files(for candidate: StreamCandidate) async throws -> [DebridFileInfo]
}

extension DebridService {
    func resolve(_ candidate: StreamCandidate) async throws -> ResolvedStream {
        try await resolve(candidate, fileID: nil)
    }
}

struct RealDebridAPIError: Error, Equatable, Sendable {
    let httpStatus: Int
    let error: String?
    let code: Int?

    var isUnauthorized: Bool {
        httpStatus == 401 || code == 8
    }

    var isAlreadyActive: Bool {
        code == 33
    }

    var isInfringing: Bool {
        code == 35
            || httpStatus == 451
            || (error?.localizedCaseInsensitiveContains("infring") ?? false)
    }

    var isDisabledEndpoint: Bool {
        code == 37
    }
}

enum DebridError: Error, Equatable, Sendable {
    case notConfigured
    case unauthorized
    case accountLocked
    case notPremium
    case rateLimited
    case infringingContent
    case torrentTooBig
    case itemNotReady
    case fileSelectionFailed(String)
    case unresolvableCandidate
    case invalidResponse
    case requestFailed(String)
}

extension DebridError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Real-Debrid isn't connected yet."
        case .unauthorized:
            "Real-Debrid rejected the request. Check your API token in Settings."
        case .accountLocked:
            "Your Real-Debrid account is locked."
        case .notPremium:
            "Resolving torrents requires an active Real-Debrid premium account."
        case .rateLimited:
            "Real-Debrid is rate limiting requests. Please wait a moment and try again."
        case .infringingContent:
            "Real-Debrid cannot download this torrent because of a copyright filter."
        case .torrentTooBig:
            "This torrent is too large for Real-Debrid to process."
        case .itemNotReady:
            "Real-Debrid is still preparing this source. Try again in a few minutes."
        case .fileSelectionFailed:
            "The correct file could not be selected inside this torrent."
        case .unresolvableCandidate:
            "This source cannot be resolved for playback."
        case .invalidResponse:
            "Real-Debrid returned an unsupported response."
        case .requestFailed:
            "The Real-Debrid request failed. Please try again."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notConfigured:
            "Add your Real-Debrid API token in Settings \u{203A} Real-Debrid."
        case .unauthorized:
            "Generate a token at real-debrid.com/apitoken and paste it in Settings."
        case .rateLimited:
            "Wait about a minute before trying again."
        case .itemNotReady:
            "Real-Debrid downloads uncached torrents before playback. It can take a few minutes for popular releases."
        default:
            nil
        }
    }

    var technicalDetail: String? {
        switch self {
        case .requestFailed(let detail): detail
        case .fileSelectionFailed(let detail): detail
        default: nil
        }
    }

    static func map(_ error: Error) -> DebridError {
        if let debridError = error as? DebridError { return debridError }
        if let apiError = error as? RealDebridAPIError {
            return map(apiError)
        }
        if let httpError = error as? HTTPError {
            switch httpError {
            case .offline:
                return .requestFailed("You appear to be offline.")
            case .timedOut:
                return .requestFailed("The request timed out.")
            case .httpStatus(let code, let body):
                let apiError = RealDebridAPIError(
                    httpStatus: code,
                    error: RealDebridModels.parseErrorMessage(body),
                    code: RealDebridModels.parseErrorCode(body)
                )
                return map(apiError)
            case .decoding:
                return .invalidResponse
            case .responseTooLarge:
                return .invalidResponse
            case .transport(let detail):
                return .requestFailed(detail)
            case .invalidURL:
                return .invalidResponse
            }
        }
        if let secureError = error as? SecureTokenError {
            return .requestFailed("The token could not be read from the Keychain (\(secureError)).")
        }
        return .requestFailed(error.localizedDescription)
    }

    static func map(_ apiError: RealDebridAPIError) -> DebridError {
        if apiError.isUnauthorized {
            return .unauthorized
        }
        if apiError.isInfringing {
            return .infringingContent
        }
        switch apiError.code {
        case 14:
            return .accountLocked
        case 9:
            return .notPremium
        case 34, 5:
            return .rateLimited
        case 29, 30:
            return .torrentTooBig
        case 24, 25, 26, 27, 28:
            return .requestFailed(apiError.error ?? "Real-Debrid returned error \(apiError.code ?? -1).")
        default:
            break
        }
        if apiError.httpStatus == 429 {
            return .rateLimited
        }
        if apiError.httpStatus == 403 {
            return .notPremium
        }
        return .requestFailed(apiError.error ?? "HTTP \(apiError.httpStatus)")
    }
}
