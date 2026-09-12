import Foundation

actor AddonInstallService {
    private let http: any HTTPClient
    private let manifestTimeout: Duration
    private let maxManifestBytes: Int

    init(
        http: any HTTPClient = URLSessionHTTPClient(),
        manifestTimeout: Duration = .seconds(5),
        maxManifestBytes: Int = 256_000
    ) {
        self.http = http
        self.manifestTimeout = manifestTimeout
        self.maxManifestBytes = maxManifestBytes
    }

    func preview(
        manifestURL: URL,
        allowInsecureHTTP: Bool = false
    ) async throws -> AddonInstallPreview {
        try AddonURLPolicy.validate(manifestURL, allowInsecureHTTP: allowInsecureHTTP)

        let request = RequestBuilder(
            url: manifestURL,
            headers: ["Accept": "application/json"],
            timeout: 5
        ).build()

        let data: Data
        do {
            data = try await withTimeout(manifestTimeout) { [http, maxManifestBytes] in
                try await http.data(for: request, maxBytes: maxManifestBytes)
            }
        } catch TimeoutError.timedOut {
            throw AddonError.requestFailed("The addon did not respond in time.")
        } catch let error as HTTPError {
            if case .responseTooLarge = error {
                throw AddonError.manifestTooLarge
            }
            throw AddonError.requestFailed(error.localizedDescription)
        }

        let manifest: AddonManifest
        do {
            manifest = try JSONDecoder().decode(AddonManifest.self, from: data)
        } catch {
            throw AddonError.invalidManifest("The manifest could not be read.")
        }

        let validated = try manifest.validated()
        guard let protocolType = validated.protocolType else {
            throw AddonError.unsupportedProtocol
        }

        let namespaces: [AddonIDNamespace]
        if protocolType == .animeStreamV1, validated.resolvedNamespaces.isEmpty {
            // Kitsu is the canonical identity; other IDs are optional.
            namespaces = [.kitsu, .mal, .anilist]
        } else if protocolType == .stremio, validated.resolvedNamespaces.isEmpty {
            // Addons that omit idPrefixes accept any ID; IMDb is the format
            // essentially every Stremio stream addon understands.
            namespaces = [.imdb, .kitsu]
        } else {
            namespaces = validated.resolvedNamespaces
        }

        return AddonInstallPreview(
            manifest: validated,
            manifestURL: manifestURL,
            baseURL: manifestURL.deletingLastPathComponent(),
            protocolType: protocolType,
            capabilities: validated.declaredCapabilities,
            idNamespaces: namespaces
        )
    }
}
