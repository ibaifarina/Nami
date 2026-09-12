import Foundation

actor RealDebridService: DebridService {
    private let tokenProvider: any DebridTokenProviding
    private let http: any HTTPClient
    private let maxAvailabilityProbes: Int
    private let resolvePollAttempts: Int
    private let resolvePollInterval: Duration
    private let fileListPollAttempts: Int
    private let fileListPollInterval: Duration

    init(
        tokenProvider: any DebridTokenProviding,
        http: any HTTPClient = URLSessionHTTPClient(),
        maxAvailabilityProbes: Int = 6,
        resolvePollAttempts: Int = 8,
        resolvePollInterval: Duration = .milliseconds(350),
        fileListPollAttempts: Int = 6,
        fileListPollInterval: Duration = .milliseconds(300)
    ) {
        self.tokenProvider = tokenProvider
        self.http = http
        self.maxAvailabilityProbes = maxAvailabilityProbes
        self.resolvePollAttempts = resolvePollAttempts
        self.resolvePollInterval = resolvePollInterval
        self.fileListPollAttempts = fileListPollAttempts
        self.fileListPollInterval = fileListPollInterval
    }

    // MARK: - Account

    func validateAccount() async throws -> DebridAccount {
        let token = try await requiredToken()
        return try await validateAccount(token: token)
    }

    func validateAccount(token: String) async throws -> DebridAccount {
        do {
            let request = try makeRequest(path: "/user", token: token)
            let data = try await send(request)
            let user: RealDebridUser = try decode(RealDebridUser.self, from: data)
            return DebridAccount(realDebrid: user)
        } catch {
            throw DebridError.map(error)
        }
    }

    // MARK: - Availability

    /// Real-Debrid removed the instant-availability endpoint (error_code 37),
    /// so cache status is probed by adding the magnet, selecting files and
    /// inspecting the torrent status. Probes are deleted afterwards, except
    /// torrents that already existed in the user's account.
    func checkAvailability(_ candidates: [StreamCandidate]) async throws -> [DebridCheckResult] {
        guard await tokenProvider.token() != nil else {
            throw DebridError.notConfigured
        }

        var results: [DebridCheckResult] = []
        var probeCount = 0

        for candidate in candidates {
            guard Self.magnet(for: candidate) != nil else {
                results.append(unknownResult(for: candidate))
                continue
            }
            guard probeCount < maxAvailabilityProbes else {
                results.append(unknownResult(for: candidate))
                continue
            }
            probeCount += 1
            do {
                results.append(try await probe(candidate))
            } catch let error as DebridError where error == .unauthorized {
                throw error
            } catch {
                results.append(unknownResult(for: candidate))
            }
        }
        return results
    }

    private func probe(_ candidate: StreamCandidate) async throws -> DebridCheckResult {
        guard let magnet = Self.magnet(for: candidate) else {
            return unknownResult(for: candidate)
        }

        let added: (id: String, created: Bool)
        do {
            added = try await addMagnet(magnet, hash: candidate.infoHash)
        } catch let apiError as RealDebridAPIError {
            if apiError.isUnauthorized {
                throw DebridError.unauthorized
            }
            if apiError.isFileUnavailable {
                return DebridCheckResult(
                    candidateID: candidate.id,
                    availability: .unavailable,
                    files: []
                )
            }
            return unknownResult(for: candidate)
        }

        guard added.created else {
            if let info = try? await torrentInfo(id: added.id) {
                let availability: DebridAvailability = info.status == "downloaded" ? .cached : .notCached
                return DebridCheckResult(
                    candidateID: candidate.id,
                    availability: availability,
                    files: info.fileInfos
                )
            }
            return unknownResult(for: candidate)
        }

        do {
            try? await selectFiles(torrentID: added.id, files: "all")
            let info = try await pollForReady(id: added.id, attempts: 3, interval: .milliseconds(250))
            try? await deleteTorrent(id: added.id)
            let availability: DebridAvailability = info.status == "downloaded" ? .cached : .notCached
            return DebridCheckResult(
                candidateID: candidate.id,
                availability: availability,
                files: info.fileInfos
            )
        } catch {
            try? await deleteTorrent(id: added.id)
            throw error
        }
    }

    // MARK: - Resolve

    func files(for candidate: StreamCandidate) async throws -> [DebridFileInfo] {
        guard let magnet = Self.magnet(for: candidate) else {
            return []
        }
        guard await tokenProvider.token() != nil else {
            throw DebridError.notConfigured
        }
        do {
            let added = try await addMagnet(magnet, hash: candidate.infoHash)
            var info = try await torrentInfo(id: added.id)
            var attempts = 0
            // A freshly added magnet resolves its file list asynchronously.
            while info.fileInfos.isEmpty, attempts < fileListPollAttempts {
                try? await Task.sleep(for: fileListPollInterval)
                info = try await torrentInfo(id: added.id)
                attempts += 1
            }
            return info.fileInfos
        } catch {
            throw DebridError.map(error)
        }
    }

    func resolve(_ candidate: StreamCandidate, fileID: Int?) async throws -> ResolvedStream {
        if candidate.infoHash == nil, candidate.magnetURI == nil {
            if let direct = candidate.directURL, Self.isPlayableURL(direct) {
                return ResolvedStream(
                    url: direct,
                    filename: candidate.rawTitle ?? candidate.displayTitle,
                    sizeBytes: candidate.sizeBytes,
                    streamable: nil,
                    fileID: nil
                )
            }
            throw DebridError.unresolvableCandidate
        }

        guard await tokenProvider.token() != nil else {
            throw DebridError.notConfigured
        }
        guard let magnet = Self.magnet(for: candidate) else {
            throw DebridError.unresolvableCandidate
        }

        var torrentID: String?
        var created = false
        do {
            let added = try await addMagnet(magnet, hash: candidate.infoHash)
            torrentID = added.id
            created = added.created

            let initial = try await torrentInfo(id: added.id)
            let selection = try Self.selection(
                from: initial.fileInfos,
                targetEpisode: candidate.targetEpisode,
                fileID: fileID
            )
            try? await selectFiles(torrentID: added.id, files: String(selection.file.id))

            let ready = try await pollForReady(
                id: added.id,
                attempts: resolvePollAttempts,
                interval: resolvePollInterval
            )
            guard ready.status == "downloaded" else {
                throw DebridError.itemNotReady
            }

            let selectedFiles = ready.fileInfos.filter(\.selected)
            let linkIndex: Int
            if selectedFiles.count > 1 {
                linkIndex = selectedFiles.firstIndex { $0.id == selection.file.id } ?? 0
            } else {
                linkIndex = 0
            }
            guard
                let links = ready.links,
                links.indices.contains(linkIndex)
            else {
                throw DebridError.fileSelectionFailed("Real-Debrid did not generate a download link.")
            }

            let unrestricted = try await unrestrict(link: links[linkIndex])
            guard let url = unrestricted.url else {
                throw DebridError.invalidResponse
            }
            return ResolvedStream(
                url: url,
                filename: unrestricted.filename ?? candidate.rawTitle ?? candidate.displayTitle,
                sizeBytes: unrestricted.sizeBytes ?? candidate.sizeBytes,
                streamable: unrestricted.streamable,
                fileID: selection.file.id
            )
        } catch {
            let mapped = DebridError.map(error)
            if created, let torrentID, mapped != .itemNotReady {
                try? await deleteTorrent(id: torrentID)
            }
            throw mapped
        }
    }

    // MARK: - API primitives

    private func addMagnet(_ magnet: String, hash: String?) async throws -> (id: String, created: Bool) {
        let token = try await requiredToken()
        do {
            let request = try makeRequest(
                path: "/torrents/addMagnet",
                method: "POST",
                token: token,
                form: ["magnet": magnet]
            )
            let data = try await send(request)
            let response: RealDebridAddMagnetResponse = try decode(RealDebridAddMagnetResponse.self, from: data)
            return (response.id, true)
        } catch let apiError as RealDebridAPIError where apiError.isAlreadyActive {
            guard
                let hash,
                let existing = try? await findTorrent(hash: hash)
            else {
                throw apiError
            }
            return (existing.id, false)
        }
    }

    private func findTorrent(hash: String) async throws -> RealDebridTorrentListItem? {
        let token = try await requiredToken()
        let request = try makeRequest(path: "/torrents?limit=100", token: token)
        let data = try await send(request)
        let list: [RealDebridTorrentListItem] = try decode([RealDebridTorrentListItem].self, from: data)
        return list.first { $0.hash?.lowercased() == hash.lowercased() }
    }

    private func torrentInfo(id: String) async throws -> RealDebridTorrentInfo {
        let token = try await requiredToken()
        let request = try makeRequest(path: "/torrents/info/\(id)", token: token)
        let data = try await send(request)
        return try decode(RealDebridTorrentInfo.self, from: data)
    }

    private func selectFiles(torrentID: String, files: String) async throws {
        let token = try await requiredToken()
        let request = try makeRequest(
            path: "/torrents/selectFiles/\(torrentID)",
            method: "POST",
            token: token,
            form: ["files": files]
        )
        _ = try await send(request)
    }

    private func deleteTorrent(id: String) async throws {
        let token = try await requiredToken()
        let request = try makeRequest(path: "/torrents/delete/\(id)", method: "DELETE", token: token)
        _ = try await send(request)
    }

    private func pollForReady(
        id: String,
        attempts: Int,
        interval: Duration
    ) async throws -> RealDebridTorrentInfo {
        var last: RealDebridTorrentInfo?
        for attempt in 0..<max(attempts, 1) {
            if attempt > 0 {
                try? await Task.sleep(for: interval)
            }
            let info = try await torrentInfo(id: id)
            last = info
            switch info.status {
            case "downloaded":
                return info
            case "error", "magnet_error", "virus", "dead":
                throw DebridError.requestFailed(
                    "Real-Debrid could not process this torrent (\(info.status ?? "unknown"))."
                )
            default:
                continue
            }
        }
        guard let last else { throw DebridError.invalidResponse }
        return last
    }

    private func unrestrict(
        link: String
    ) async throws -> (url: URL?, filename: String?, sizeBytes: Int64?, streamable: Bool?, fileID: Int?) {
        let token = try await requiredToken()
        let request = try makeRequest(
            path: "/unrestrict/link",
            method: "POST",
            token: token,
            form: ["link": link]
        )
        let data = try await send(request)
        let response: RealDebridUnrestrictResponse = try decode(RealDebridUnrestrictResponse.self, from: data)
        let url = response.download.flatMap { value -> URL? in
            guard
                let url = URL(string: value),
                let scheme = url.scheme?.lowercased(),
                scheme == "https" || scheme == "http"
            else {
                return nil
            }
            return url
        }
        return (
            url,
            response.filename,
            response.filesize,
            response.streamable.map { $0 == 1 },
            response.id.flatMap(Int.init)
        )
    }

    // MARK: - Helpers

    /// Uses the user's explicit file choice when it still exists, otherwise
    /// falls back to automatic selection.
    static func selection(
        from files: [DebridFileInfo],
        targetEpisode: Int?,
        fileID: Int?
    ) throws -> TorrentFileSelection {
        if let fileID, let file = files.first(where: { $0.id == fileID }) {
            return TorrentFileSelection(file: file, reason: "User-selected file")
        }
        return try TorrentFileSelector.selectFile(from: files, targetEpisode: targetEpisode)
    }

    static func magnet(for candidate: StreamCandidate) -> String? {
        if let magnet = candidate.magnetURI?.absoluteString, !magnet.isEmpty {
            return magnet
        }
        guard let hash = StreamDeduplicator.normalizedHash(candidate.infoHash) else {
            return nil
        }
        return "magnet:?xt=urn:btih:\(hash)"
    }

    static func isPlayableURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    private func unknownResult(for candidate: StreamCandidate) -> DebridCheckResult {
        DebridCheckResult(candidateID: candidate.id, availability: .unknown, files: [])
    }

    private func requiredToken() async throws -> String {
        guard let token = await tokenProvider.token() else {
            throw DebridError.notConfigured
        }
        return token
    }

    private func makeRequest(
        path: String,
        method: String = "GET",
        token: String,
        form: [String: String]? = nil
    ) throws -> URLRequest {
        // Paths are absolute against the versioned API root. `URL(string:relativeTo:)`
        // would treat a leading "/" as a path-absolute reference and drop "/rest/1.0",
        // so concatenate the strings instead.
        let basePath = RealDebridModels.baseURL.absoluteString
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: basePath + normalizedPath) else {
            throw DebridError.invalidResponse
        }
        var headers = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json",
        ]
        var body: Data?
        if let form {
            headers["Content-Type"] = "application/x-www-form-urlencoded"
            var components = URLComponents()
            components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
            body = Data((components.percentEncodedQuery ?? "").utf8)
        }
        return RequestBuilder(
            url: url,
            method: method,
            headers: headers,
            body: body,
            timeout: 20
        ).build()
    }

    private func send(_ request: URLRequest) async throws -> Data {
        do {
            return try await http.data(for: request, maxBytes: 2_000_000)
        } catch let httpError as HTTPError {
            if case .httpStatus(let code, let body) = httpError {
                throw RealDebridAPIError(
                    httpStatus: code,
                    error: RealDebridModels.parseErrorMessage(body),
                    code: RealDebridModels.parseErrorCode(body)
                )
            }
            throw DebridError.map(httpError)
        } catch {
            throw DebridError.map(error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw DebridError.invalidResponse
        }
    }
}
