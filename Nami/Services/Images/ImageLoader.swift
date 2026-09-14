import AppKit
import Foundation

enum ImageLoadError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: "The image request returned an unexpected response.")
        case .httpStatus(let code):
            String(localized: "The image request failed with status \(code).")
        case .invalidData:
            String(localized: "The image data could not be decoded.")
        }
    }
}

/// Loads remote images through a session backed by the shared `URLCache`,
/// coalescing concurrent requests for the same URL and populating
/// ``ImageCache`` once an image is decoded.
@MainActor
final class ImageLoader {
    static let shared = ImageLoader()

    private let session: URLSession
    private let cache: ImageCache
    private var inFlight: [URL: Task<NSImage, any Error>] = [:]

    init(session: URLSession? = nil, cache: ImageCache? = nil) {
        self.cache = cache ?? .shared
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = URLCache.shared
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            configuration.timeoutIntervalForRequest = HTTPDefaults.timeout
            self.session = URLSession(configuration: configuration)
        }
    }

    func image(for url: URL) async throws -> NSImage {
        if let cached = cache.image(for: url) {
            return cached
        }
        if let existing = inFlight[url] {
            return try await existing.value
        }

        let session = session
        let task = Task<NSImage, any Error> {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw ImageLoadError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                throw ImageLoadError.httpStatus(http.statusCode)
            }
            guard let image = NSImage(data: data) else {
                throw ImageLoadError.invalidData
            }
            return image
        }
        inFlight[url] = task

        do {
            let image = try await task.value
            cache.insert(image, for: url)
            inFlight[url] = nil
            return image
        } catch {
            inFlight[url] = nil
            throw error
        }
    }
}
