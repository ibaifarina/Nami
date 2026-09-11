import AppKit
import Foundation
import Testing
@testable import Nami

@MainActor
struct ImageCacheTests {
    @Test func storesAndReturnsImage() {
        let cache = ImageCache()
        let url = testURL("https://images.example/poster.png")
        let image = NSImage(size: NSSize(width: 4, height: 4))

        cache.insert(image, for: url)

        #expect(cache.image(for: url) === image)
    }

    @Test func returnsNilForUnknownURL() {
        let cache = ImageCache()
        #expect(cache.image(for: testURL("https://images.example/missing.png")) == nil)
    }

    @Test func removeAllClearsEntries() {
        let cache = ImageCache()
        let url = testURL("https://images.example/poster.png")
        cache.insert(NSImage(size: NSSize(width: 4, height: 4)), for: url)

        cache.removeAll()

        #expect(cache.image(for: url) == nil)
    }
}

@MainActor
struct ImageLoaderTests {
    @Test func loadsImageAndPopulatesCache() async throws {
        StubImageURLProtocol.reset()
        StubImageURLProtocol.configure(data: makePNGData())
        let cache = ImageCache()
        let loader = ImageLoader(session: makeSession(), cache: cache)
        let url = testURL("https://images.example/poster.png")

        let image = try await loader.image(for: url)

        #expect(image.size == NSSize(width: 8, height: 8))
        #expect(cache.image(for: url) === image)
        #expect(StubImageURLProtocol.requestCount == 1)
    }

    @Test func coalescesConcurrentRequestsForSameURL() async throws {
        StubImageURLProtocol.reset()
        StubImageURLProtocol.configure(data: makePNGData(), delay: .milliseconds(100))
        let loader = ImageLoader(session: makeSession(), cache: ImageCache())
        let url = testURL("https://images.example/shared.png")

        async let first = loader.image(for: url)
        async let second = loader.image(for: url)
        let images = try await [first, second]

        #expect(images[0] === images[1])
        #expect(StubImageURLProtocol.requestCount == 1)
    }

    @Test func servesFromMemoryCacheWithoutNetworkRequest() async throws {
        StubImageURLProtocol.reset()
        StubImageURLProtocol.configure(data: makePNGData())
        let cache = ImageCache()
        let url = testURL("https://images.example/cached.png")
        let cached = NSImage(size: NSSize(width: 4, height: 4))
        cache.insert(cached, for: url)
        let loader = ImageLoader(session: makeSession(), cache: cache)

        let image = try await loader.image(for: url)

        #expect(image === cached)
        #expect(StubImageURLProtocol.requestCount == 0)
    }

    @Test func failsForNonSuccessStatus() async {
        StubImageURLProtocol.reset()
        StubImageURLProtocol.configure(data: Data([0, 1, 2]), statusCode: 404)
        let loader = ImageLoader(session: makeSession(), cache: ImageCache())
        let url = testURL("https://images.example/missing.png")

        await #expect(throws: ImageLoadError.self) {
            try await loader.image(for: url)
        }
        #expect(StubImageURLProtocol.requestCount == 1)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubImageURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makePNGData() -> Data {
        let size = NSSize(width: 8, height: 8)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            Issue.record("Unable to render test image")
            return Data()
        }
        return png
    }
}

private final class StubImageURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var requests: [URLRequest] = []
        var responseData = Data()
        var statusCode = 200
        var delay: Duration = .zero
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var state = State()

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        state = State()
    }

    static func configure(data: Data, statusCode: Int = 200, delay: Duration = .zero) {
        lock.lock()
        defer { lock.unlock() }
        state.responseData = data
        state.statusCode = statusCode
        state.delay = delay
    }

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return state.requests.count
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.state.requests.append(request)
        let data = Self.state.responseData
        let status = Self.state.statusCode
        let delay = Self.state.delay
        Self.lock.unlock()

        guard let url = request.url else { return }

        Task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "image/png"]
            )!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
