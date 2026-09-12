import AVFoundation
import Foundation

/// A concrete problem discovered while validating a resolved stream.
struct StreamValidationIssue: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case infringing
        case unavailableFile
        case unsupportedHoster
        case hosterMaintenance
        case serviceUnavailable
        case accessDenied
        case rateLimited
        case fairUseLimit
        case trafficExhausted
        case premiumRequired
        case accountIssue
        case unauthorized
        case errorPage
        case nonMedia
        case slateVideo
    }

    let kind: Kind
    let detail: String?

    init(kind: Kind, detail: String? = nil) {
        self.kind = kind
        self.detail = detail
    }

    /// Problems that affect every source, so trying another candidate is
    /// pointless and the user should be told about the account instead.
    var isGlobal: Bool {
        switch kind {
        case .fairUseLimit, .trafficExhausted, .premiumRequired, .accountIssue, .unauthorized:
            true
        default:
            false
        }
    }

    /// Problems that are caused by an outage or throttling rather than by the
    /// file itself. The candidate should not be remembered as bad.
    var isTransient: Bool {
        switch kind {
        case .hosterMaintenance, .serviceUnavailable, .rateLimited:
            true
        default:
            false
        }
    }
}

enum StreamValidationVerdict: Equatable, Sendable {
    /// The probe saw a plausible media response.
    case playable
    /// The candidate itself is unusable; skip it for this session.
    case candidateInvalid(StreamValidationIssue)
    /// Infrastructure hiccup; do not blacklist the candidate.
    case transient(StreamValidationIssue)
    /// Real-Debrid account/auth/traffic problem; other sources will not help.
    case accountIssue(StreamValidationIssue)
    /// The probe could not decide (offline, timeout, odd server). Playback
    /// should be attempted instead of being blocked.
    case uncertain
}

struct StreamValidationContext: Equatable, Sendable {
    var expectedSizeBytes: Int64?
    var expectedDurationMinutes: Int?

    init(expectedSizeBytes: Int64? = nil, expectedDurationMinutes: Int? = nil) {
        self.expectedSizeBytes = expectedSizeBytes
        self.expectedDurationMinutes = expectedDurationMinutes
    }
}

protocol StreamValidating: Sendable {
    func validate(
        _ stream: ResolvedStream,
        context: StreamValidationContext
    ) async -> StreamValidationVerdict
}

// MARK: - Probe transport

struct StreamProbeResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let bodyPrefix: Data
}

protocol StreamProbing: Sendable {
    func probe(_ request: URLRequest) async throws -> StreamProbeResponse
}

enum StreamProbeError: Error, Equatable, Sendable {
    case timedOut
    case offline
    case transport(String)
}

/// Performs a single ranged GET with redirects disabled. The caller decides
/// what a redirect means, which keeps error/slate redirects cheap to detect.
struct URLSessionStreamProbe: StreamProbing {
    private let session: URLSession
    private let maxPrefixBytes: Int

    init(session: URLSession? = nil, maxPrefixBytes: Int = 8192) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 12
            configuration.httpAdditionalHeaders = ["User-Agent": "Nami/1.0"]
            self.session = URLSession(configuration: configuration)
        }
        self.maxPrefixBytes = maxPrefixBytes
    }

    func probe(_ request: URLRequest) async throws -> StreamProbeResponse {
        let delegate = RedirectBlockingDelegate()
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
            guard let http = response as? HTTPURLResponse else {
                throw StreamProbeError.transport("Unexpected response type")
            }
            var prefix = Data()
            prefix.reserveCapacity(maxPrefixBytes)
            var iterator = bytes.makeAsyncIterator()
            while prefix.count < maxPrefixBytes, let byte = try await iterator.next() {
                prefix.append(byte)
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                guard let key = key as? String, let value = value as? String else { continue }
                headers[key.lowercased()] = value
            }
            return StreamProbeResponse(
                statusCode: http.statusCode,
                headers: headers,
                bodyPrefix: prefix
            )
        } catch let error as StreamProbeError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError {
            switch urlError.code {
            case .cancelled:
                throw CancellationError()
            case .timedOut:
                throw StreamProbeError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dataNotAllowed, .internationalRoamingOff:
                throw StreamProbeError.offline
            default:
                throw StreamProbeError.transport(urlError.localizedDescription)
            }
        } catch {
            throw StreamProbeError.transport(error.localizedDescription)
        }
    }
}

private final class RedirectBlockingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

// MARK: - Validation service

/// Checks that a resolved playback URL actually serves media, using only a
/// tiny ranged request. It understands Real-Debrid error envelopes and the
/// HTML error/slate pages hosters redirect to when a file is gone.
struct StreamValidationService: StreamValidating, Sendable {
    typealias DurationProbe = @Sendable (URL) async -> Double?

    private let probe: any StreamProbing
    private let durationProbe: DurationProbe
    private let maximumRedirects: Int
    private let probeRangeBytes: Int

    private static let slateMinimumExpectedMinutes = 10
    private static let slateMaximumSeconds: Double = 180
    private static let suspiciousSizeFloorBytes: Int64 = 24 * 1024 * 1024
    private static let suspiciousSizeCeilingBytes: Int64 = 128 * 1024 * 1024

    init(
        probe: any StreamProbing = URLSessionStreamProbe(),
        maximumRedirects: Int = 3,
        probeRangeBytes: Int = 2048,
        durationProbe: @escaping DurationProbe = StreamValidationService.mediaDurationProbe
    ) {
        self.probe = probe
        self.maximumRedirects = maximumRedirects
        self.probeRangeBytes = probeRangeBytes
        self.durationProbe = durationProbe
    }

    func validate(
        _ stream: ResolvedStream,
        context: StreamValidationContext
    ) async -> StreamValidationVerdict {
        var url = stream.url
        var visited: Set<String> = []
        var redirectCount = 0

        while true {
            guard
                let scheme = url.scheme?.lowercased(),
                scheme == "http" || scheme == "https"
            else {
                return .candidateInvalid(StreamValidationIssue(kind: .nonMedia, detail: "Unsupported URL"))
            }
            guard visited.insert(url.absoluteString).inserted else {
                return .candidateInvalid(StreamValidationIssue(kind: .errorPage, detail: "Redirect loop"))
            }

            let response: StreamProbeResponse
            do {
                response = try await probe.probe(
                    Self.probeRequest(for: url, rangeBytes: probeRangeBytes)
                )
            } catch is CancellationError {
                return .uncertain
            } catch {
                // A network hiccup is not proof that the source is dead.
                return .uncertain
            }

            if (300..<400).contains(response.statusCode) {
                redirectCount += 1
                guard redirectCount <= maximumRedirects else {
                    return .candidateInvalid(
                        StreamValidationIssue(kind: .errorPage, detail: "Too many redirects")
                    )
                }
                guard
                    let location = response.headers["location"],
                    let next = URL(string: location, relativeTo: url)?.absoluteURL
                else {
                    return .candidateInvalid(
                        StreamValidationIssue(kind: .errorPage, detail: "Redirect without target")
                    )
                }
                if let issue = Self.issue(forErrorURL: next) {
                    return Self.verdict(for: issue)
                }
                url = next
                continue
            }

            return await classify(response, url: url, context: context)
        }
    }

    // MARK: Classification

    private func classify(
        _ response: StreamProbeResponse,
        url: URL,
        context: StreamValidationContext
    ) async -> StreamValidationVerdict {
        let status = response.statusCode
        let contentType = response.headers["content-type"]?.lowercased() ?? ""
        let body = response.bodyPrefix

        if let issue = Self.apiIssue(from: body) {
            return Self.verdict(for: issue)
        }

        switch status {
        case 200, 206:
            break
        case 401:
            return .accountIssue(
                StreamValidationIssue(kind: .unauthorized, detail: "HTTP 401")
            )
        case 403:
            if let issue = Self.issue(fromBody: body) {
                return Self.verdict(for: issue)
            }
            return .candidateInvalid(
                StreamValidationIssue(kind: .accessDenied, detail: "HTTP 403")
            )
        case 404, 410:
            return .candidateInvalid(
                StreamValidationIssue(kind: .unavailableFile, detail: "HTTP \(status)")
            )
        case 451:
            return .candidateInvalid(
                StreamValidationIssue(kind: .infringing, detail: "HTTP 451")
            )
        case 429:
            return .transient(
                StreamValidationIssue(kind: .rateLimited, detail: "HTTP 429")
            )
        case 500...599:
            if let issue = Self.issue(fromBody: body) {
                return Self.verdict(for: issue)
            }
            return .transient(
                StreamValidationIssue(kind: .serviceUnavailable, detail: "HTTP \(status)")
            )
        default:
            return .candidateInvalid(
                StreamValidationIssue(kind: .errorPage, detail: "HTTP \(status)")
            )
        }

        if contentType.contains("text/html") || Self.looksLikeHTML(body) {
            if let issue = Self.issue(fromBody: body) {
                return Self.verdict(for: issue)
            }
            return .candidateInvalid(
                StreamValidationIssue(kind: .errorPage, detail: "HTML page")
            )
        }
        if contentType.contains("application/json") {
            return .candidateInvalid(
                StreamValidationIssue(kind: .nonMedia, detail: "JSON response")
            )
        }
        if !Self.isMediaContentType(contentType), !Self.looksLikeMedia(body) {
            return .candidateInvalid(
                StreamValidationIssue(
                    kind: .nonMedia,
                    detail: contentType.isEmpty ? nil : contentType
                )
            )
        }

        if let totalBytes = Self.totalBytes(from: response),
           Self.shouldCheckForSlate(totalBytes: totalBytes, context: context),
           let duration = await durationProbe(url),
           let expectedMinutes = context.expectedDurationMinutes,
           expectedMinutes >= Self.slateMinimumExpectedMinutes,
           duration < Self.slateMaximumSeconds,
           duration < Double(expectedMinutes * 60) * 0.35 {
            return .candidateInvalid(
                StreamValidationIssue(kind: .slateVideo, detail: "\(Int(duration.rounded()))s video")
            )
        }

        return .playable
    }

    // MARK: Response helpers

    private static func probeRequest(for url: URL, rangeBytes: Int) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-\(max(rangeBytes, 1) - 1)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8
        return request
    }

    private static func totalBytes(from response: StreamProbeResponse) -> Int64? {
        if let contentRange = response.headers["content-range"],
           let total = contentRange.split(separator: "/").last,
           let bytes = Int64(total.trimmingCharacters(in: .whitespaces)) {
            return bytes
        }
        if let length = response.headers["content-length"], let bytes = Int64(length) {
            return bytes
        }
        return nil
    }

    private static func shouldCheckForSlate(
        totalBytes: Int64,
        context: StreamValidationContext
    ) -> Bool {
        guard totalBytes > 0, (context.expectedDurationMinutes ?? 0) >= slateMinimumExpectedMinutes
        else {
            return false
        }
        if totalBytes < suspiciousSizeFloorBytes {
            return true
        }
        if let expected = context.expectedSizeBytes, expected > 0,
           totalBytes < expected / 10, totalBytes < suspiciousSizeCeilingBytes {
            return true
        }
        return false
    }

    private static func isMediaContentType(_ contentType: String) -> Bool {
        if contentType.hasPrefix("video/") || contentType.hasPrefix("audio/") {
            return true
        }
        let knownPrefixes = [
            "application/octet-stream",
            "binary/octet-stream",
            "application/x-matroska",
            "application/x-mpegurl",
            "application/vnd.apple.mpegurl",
            "application/mp4",
            "application/ogg",
            "application/x-ogg",
        ]
        return knownPrefixes.contains { contentType.hasPrefix($0) }
    }

    private static func looksLikeHTML(_ data: Data) -> Bool {
        guard let text = String(data: data.prefix(512), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else {
            return false
        }
        return text.hasPrefix("<!doctype html") || text.hasPrefix("<html")
    }

    private static func looksLikeMedia(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        guard bytes.count >= 4 else { return false }
        if bytes.count >= 8,
           bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 {
            return true // ftyp (MP4/MOV)
        }
        if bytes[0] == 0x1A, bytes[1] == 0x45, bytes[2] == 0xDF, bytes[3] == 0xA3 {
            return true // Matroska/WebM
        }
        if bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46 {
            return true // RIFF (AVI)
        }
        if bytes[0] == 0x4F, bytes[1] == 0x67, bytes[2] == 0x67, bytes[3] == 0x53 {
            return true // Ogg
        }
        if bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 {
            return true // ID3 (MP3)
        }
        if bytes[0] == 0xFF, bytes[1] & 0xE0 == 0xE0 {
            return true // MPEG audio
        }
        if bytes[0] == 0x47 {
            return true // MPEG-TS sync byte
        }
        return false
    }

    /// Only whole path/query tokens count, so a release file named
    /// `The.Expired.mkv` is not mistaken for an expired-link page.
    private static func issue(forErrorURL url: URL) -> StreamValidationIssue? {
        var tokens: Set<String> = []
        if let host = url.host?.lowercased() {
            tokens.insert(host)
        }
        for component in url.pathComponents {
            tokens.insert(component.lowercased())
        }
        if let query = url.query?.lowercased() {
            for pair in query.split(separator: "&") {
                for keyOrValue in pair.split(separator: "=") {
                    tokens.insert(String(keyOrValue))
                }
            }
        }
        let markers = ["error", "expired", "infringing", "copyright", "removed", "unavailable", "gone", "slate"]
        guard tokens.contains(where: { markers.contains($0) }) else { return nil }
        if let issue = issue(fromMessage: tokens.joined(separator: " ")) {
            return issue
        }
        return StreamValidationIssue(kind: .errorPage, detail: url.host)
    }

    private static func issue(fromBody body: Data) -> StreamValidationIssue? {
        guard !body.isEmpty, let text = String(data: body, encoding: .utf8) else { return nil }
        return issue(fromMessage: text)
    }

    private static func issue(fromMessage message: String) -> StreamValidationIssue? {
        let lower = message.lowercased()
        if lower.contains("infring") || lower.contains("copyright") || lower.contains("dmca") {
            return StreamValidationIssue(kind: .infringing)
        }
        if lower.contains("fair use") || lower.contains("fair usage") {
            return StreamValidationIssue(kind: .fairUseLimit)
        }
        if lower.contains("traffic") && (lower.contains("exhaust") || lower.contains("limit")) {
            return StreamValidationIssue(kind: .trafficExhausted)
        }
        if lower.contains("account locked") {
            return StreamValidationIssue(kind: .accountIssue)
        }
        if lower.contains("not premium") || lower.contains("premium account")
            || lower.contains("premium is required") {
            return StreamValidationIssue(kind: .premiumRequired)
        }
        if lower.contains("unsupported host") {
            return StreamValidationIssue(kind: .unsupportedHoster)
        }
        if lower.contains("maintenance") {
            return StreamValidationIssue(kind: .hosterMaintenance)
        }
        if lower.contains("temporarily unavailable") || lower.contains("service unavailable") {
            return StreamValidationIssue(kind: .serviceUnavailable)
        }
        if lower.contains("too many") {
            return StreamValidationIssue(kind: .rateLimited)
        }
        if lower.contains("file not found") || lower.contains("file unavailable")
            || lower.contains("no longer available") || lower.contains("file was removed")
            || lower.contains("removed from debrid") || lower.contains("deleted")
            || lower.contains("expired") || lower.contains("link dead") {
            return StreamValidationIssue(kind: .unavailableFile)
        }
        if lower.contains("permission denied") {
            return StreamValidationIssue(kind: .accessDenied)
        }
        return nil
    }

    private static func apiIssue(from body: Data) -> StreamValidationIssue? {
        struct Payload: Decodable {
            let error: String?
            let error_code: Int?
        }
        guard !body.isEmpty, let payload = try? JSONDecoder().decode(Payload.self, from: body)
        else {
            return nil
        }
        let detail = payload.error
        guard let code = payload.error_code else {
            return detail.flatMap { issue(fromMessage: $0) }
        }
        switch code {
        case 8:
            return StreamValidationIssue(kind: .unauthorized, detail: detail)
        case 9, 20:
            return StreamValidationIssue(kind: .premiumRequired, detail: detail)
        case 14:
            return StreamValidationIssue(kind: .accountIssue, detail: detail)
        case 15:
            return StreamValidationIssue(kind: .accountIssue, detail: detail ?? "Account not activated")
        case 16:
            return StreamValidationIssue(kind: .unsupportedHoster, detail: detail)
        case 17, 19:
            return StreamValidationIssue(kind: .hosterMaintenance, detail: detail)
        case 18, 23:
            return StreamValidationIssue(kind: .trafficExhausted, detail: detail)
        case 21, 34:
            return StreamValidationIssue(kind: .rateLimited, detail: detail)
        case 22:
            return StreamValidationIssue(kind: .accountIssue, detail: detail ?? "IP address not allowed")
        case 24:
            return StreamValidationIssue(kind: .unavailableFile, detail: detail)
        case 25:
            return StreamValidationIssue(kind: .serviceUnavailable, detail: detail)
        case 28, 29, 30:
            return StreamValidationIssue(kind: .unavailableFile, detail: detail)
        case 35:
            return StreamValidationIssue(kind: .infringing, detail: detail)
        case 36:
            return StreamValidationIssue(kind: .fairUseLimit, detail: detail)
        default:
            return detail.flatMap { issue(fromMessage: $0) }
        }
    }

    private static func verdict(for issue: StreamValidationIssue) -> StreamValidationVerdict {
        if issue.isGlobal {
            return .accountIssue(issue)
        }
        if issue.isTransient {
            return .transient(issue)
        }
        return .candidateInvalid(issue)
    }

    // MARK: Last-resort duration probe

    static let mediaDurationProbe: DurationProbe = { url in
        await StreamValidationService.mediaDuration(for: url)
    }

    private static func mediaDuration(for url: URL) async -> Double? {
        await withTaskGroup(of: Double?.self) { group in
            group.addTask {
                let asset = AVURLAsset(url: url)
                do {
                    let duration = try await asset.load(.duration)
                    let seconds = duration.seconds
                    guard seconds.isFinite, seconds > 0 else { return nil }
                    return seconds
                } catch {
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(4))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}
