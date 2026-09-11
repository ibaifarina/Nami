import AppKit

/// Process-wide in-memory cache of decoded remote images. It survives screen
/// changes so revisiting a screen renders posters and heroes without a reload.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let storage = NSCache<NSURL, NSImage>()

    init() {
        storage.countLimit = 600
        storage.totalCostLimit = 256 * 1024 * 1024
    }

    func image(for url: URL) -> NSImage? {
        storage.object(forKey: url as NSURL)
    }

    func insert(_ image: NSImage, for url: URL) {
        let pixels = max(image.size.width * image.size.height, 1)
        storage.setObject(image, forKey: url as NSURL, cost: Int(pixels * 4))
    }

    func removeAll() {
        storage.removeAllObjects()
    }
}
