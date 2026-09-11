import Foundation

enum HTTPDefaults {
    static let timeout: TimeInterval = 20
    static let maxResponseBytes = 8_000_000
    static let maxErrorBodyBytes = 64_000
}

protocol HTTPClient: Sendable {
    func data(for request: URLRequest, maxBytes: Int) async throws -> Data
}

extension HTTPClient {
    func send<T: Decodable>(
        _ request: URLRequest,
        as type: T.Type,
        maxBytes: Int = HTTPDefaults.maxResponseBytes,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let data = try await data(for: request, maxBytes: maxBytes)
        do {
            return try decoder.decode(T.self, from: data)
        } catch let error as HTTPError {
            throw error
        } catch {
            throw HTTPError.decoding(Self.conciseDescription(of: error))
        }
    }

    private static func conciseDescription(of error: Error) -> String {
        switch error {
        case let decodingError as DecodingError:
            switch decodingError {
            case .keyNotFound(let key, _):
                "missing key \(key.stringValue)"
            case .typeMismatch(_, let context):
                "unexpected type at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case .valueNotFound(_, let context):
                "missing value at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case .dataCorrupted(let context):
                "corrupt data at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            @unknown default:
                "unknown decoding error"
            }
        default:
            error.localizedDescription
        }
    }
}

struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest, maxBytes: Int) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw HTTPError.transport("unexpected response type")
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = data.count <= HTTPDefaults.maxErrorBodyBytes
                    ? String(data: data, encoding: .utf8)
                    : nil
                throw HTTPError.httpStatus(code: http.statusCode, body: body)
            }
            guard data.count <= maxBytes else {
                throw HTTPError.responseTooLarge(limit: maxBytes)
            }
            return data
        } catch let error as HTTPError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError {
            switch urlError.code {
            case .cancelled: throw CancellationError()
            case .timedOut: throw HTTPError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dataNotAllowed, .internationalRoamingOff:
                throw HTTPError.offline
            default: throw HTTPError.transport(urlError.localizedDescription)
            }
        } catch {
            throw HTTPError.transport(error.localizedDescription)
        }
    }
}
