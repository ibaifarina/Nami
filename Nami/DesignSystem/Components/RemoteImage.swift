import AppKit
import SwiftUI

struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var placeholderSystemImage: String = "photo"

    @State private var phase: Phase

    init(url: URL?, contentMode: ContentMode = .fill, placeholderSystemImage: String = "photo") {
        self.url = url
        self.contentMode = contentMode
        self.placeholderSystemImage = placeholderSystemImage
        _phase = State(initialValue: Self.initialPhase(for: url))
    }

    var body: some View {
        Group {
            switch phase {
            case .empty:
                LoadingSkeleton(cornerRadius: 0)
            case .success(let image):
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            case .failure:
                placeholder
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url else { return }
        if let cached = ImageCache.shared.image(for: url) {
            phase = .success(cached)
            return
        }
        phase = .empty
        do {
            let image = try await ImageLoader.shared.image(for: url)
            guard !Task.isCancelled, url == self.url else { return }
            withAnimation(.easeOut(duration: Motion.transition)) {
                phase = .success(image)
            }
        } catch {
            guard !Task.isCancelled, url == self.url else { return }
            phase = .failure
        }
    }

    @MainActor
    private static func initialPhase(for url: URL?) -> Phase {
        guard let url, let image = ImageCache.shared.image(for: url) else {
            return url == nil ? .failure : .empty
        }
        return .success(image)
    }

    private var placeholder: some View {
        ZStack {
            AppColor.surfaceElevated
            Image(systemName: placeholderSystemImage)
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
    }

    private enum Phase {
        case empty
        case success(NSImage)
        case failure
    }
}
