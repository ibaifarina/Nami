import Foundation

actor AddonManager {
    private let http: any HTTPClient
    private let healthTimeout: Duration
    private let identityResolver: MediaIdentityResolver?

    init(
        http: any HTTPClient = URLSessionHTTPClient(),
        healthTimeout: Duration = .seconds(5),
        identityResolver: MediaIdentityResolver? = nil
    ) {
        self.http = http
        self.healthTimeout = healthTimeout
        self.identityResolver = identityResolver
    }

    /// Queries every enabled addon concurrently and returns the combined
    /// results once all of them have finished, sorted by addon priority.
    func queryStreams(
        for media: MediaIdentity,
        episode: Episode,
        titles: [String] = [],
        year: Int? = nil,
        isMovie: Bool = false,
        addons: [InstalledAddon],
        timeout: Duration = .seconds(7)
    ) async -> [AddonQueryResult] {
        let enabled = addons
            .filter(\.isEnabled)
            .sorted { $0.priority < $1.priority }
        guard !enabled.isEmpty else { return [] }

        return await withTaskGroup(of: AddonQueryResult.self) { group in
            for addon in enabled {
                group.addTask {
                    await self.query(
                        addon: addon,
                        for: media,
                        episode: episode,
                        titles: titles,
                        year: year,
                        isMovie: isMovie,
                        timeout: timeout
                    )
                }
            }
            var results: [AddonQueryResult] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.addon.priority < $1.addon.priority }
        }
    }

    /// Queries a single addon. Used by the streaming discovery pipeline so
    /// results can be processed in completion order.
    func query(
        addon: InstalledAddon,
        for media: MediaIdentity,
        episode: Episode,
        titles: [String] = [],
        year: Int? = nil,
        isMovie: Bool = false,
        timeout: Duration = .seconds(7)
    ) async -> AddonQueryResult {
        guard let adapter = Self.makeAdapter(for: addon, http: http) else {
            return AddonQueryResult(
                addon: addon,
                outcome: .failure(String(localized: "This addon's protocol is not supported yet."))
            )
        }
        // Resolve interoperability IDs only for addons that cannot use the
        // canonical Kitsu identity.
        let resolvedMedia: MediaIdentity
        if let identityResolver {
            resolvedMedia = await identityResolver.resolve(
                media,
                for: Self.effectiveNamespaces(for: addon),
                context: AddonIdentityContext(titles: titles, year: year, isMovie: isMovie)
            )
        } else {
            resolvedMedia = media
        }
        do {
            let streams = try await withTimeout(timeout) {
                try await adapter.streams(
                    for: resolvedMedia,
                    episode: episode,
                    isMovie: isMovie
                )
            }
            return AddonQueryResult(addon: addon, outcome: .success(streams))
        } catch TimeoutError.timedOut {
            return AddonQueryResult(addon: addon, outcome: .timedOut)
        } catch {
            return AddonQueryResult(
                addon: addon,
                outcome: .failure(Self.failureMessage(for: error))
            )
        }
    }

    func healthCheck(_ addon: InstalledAddon) async -> AddonHealthStatus {
        guard let adapter = Self.makeAdapter(for: addon, http: http) else {
            return .failing
        }
        do {
            return try await withTimeout(healthTimeout) {
                await adapter.healthCheck()
            }
        } catch {
            return .failing
        }
    }

    func healthCheckAll(
        _ addons: [InstalledAddon],
        maxConcurrent: Int = 4
    ) async -> [String: AddonHealthStatus] {
        let enabled = addons.filter(\.isEnabled)
        guard !enabled.isEmpty else { return [:] }

        var results: [String: AddonHealthStatus] = [:]
        var start = 0
        while start < enabled.count {
            let end = min(start + max(maxConcurrent, 1), enabled.count)
            let batch = Array(enabled[start..<end])
            await withTaskGroup(of: (String, AddonHealthStatus).self) { group in
                for addon in batch {
                    group.addTask {
                        (addon.id, await self.healthCheck(addon))
                    }
                }
                for await (id, status) in group {
                    results[id] = status
                }
            }
            start = end
        }
        return results
    }

    static func makeAdapter(
        for addon: InstalledAddon,
        http: any HTTPClient
    ) -> (any StreamAddon)? {
        let descriptor = AddonDescriptor(
            id: addon.id,
            name: addon.name,
            version: nil,
            protocolType: addon.protocolType,
            capabilities: addon.capabilities,
            idNamespaces: effectiveNamespaces(for: addon),
            baseURL: addon.baseURL,
            manifestURL: addon.manifestURL
        )
        switch addon.protocolType {
        case .animeStreamV1:
            guard let path = addon.streamsPath, !path.isEmpty else { return nil }
            return GenericHTTPAddonAdapter(
                descriptor: descriptor,
                streamsPath: path,
                http: http
            )
        case .stremio:
            return StremioAddonAdapter(
                descriptor: descriptor,
                supportedTypes: addon.supportedTypes,
                http: http
            )
        case .generic:
            return nil
        }
    }

    /// Namespaces recorded at install time, with a protocol default for
    /// addons installed before prefixes were captured (or manifests that
    /// declare none). Keeps existing installs working without reinstalling.
    static func effectiveNamespaces(for addon: InstalledAddon) -> [AddonIDNamespace] {
        if !addon.idNamespaces.isEmpty { return addon.idNamespaces }
        switch addon.protocolType {
        case .animeStreamV1: return [.kitsu, .mal, .anilist]
        case .stremio: return [.imdb, .kitsu]
        case .generic: return []
        }
    }

    private static func failureMessage(for error: Error) -> String {
        if let addonError = error as? AddonError {
            return addonError.errorDescription ?? String(localized: "The addon request failed.")
        }
        if let httpError = error as? HTTPError {
            return String(localized: "The addon request failed. \(httpError.localizedDescription)")
        }
        if error is CancellationError {
            return String(localized: "The addon request was cancelled.")
        }
        return String(localized: "The addon request failed.")
    }
}
