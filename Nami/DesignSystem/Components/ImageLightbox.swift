import AppKit
import SwiftUI

/// Coordinates presentation of the full-window image lightbox. The owning view
/// presents an ``ImageLightbox`` while a request is set and clears it once the
/// lightbox finishes dismissing.
@MainActor
@Observable
final class ImageLightboxPresenter {
    var request: ImageLightboxRequest?

    func present(_ request: ImageLightboxRequest) {
        self.request = request
    }

    func dismiss() {
        request = nil
    }
}

/// Describes the image to preview and the frame it should zoom out of.
struct ImageLightboxRequest: Identifiable, Equatable {
    let id = UUID()
    /// Candidate image URLs in preference order. The first one that loads is
    /// shown; the rest act as fallbacks.
    let imageURLs: [URL]
    let aspectRatio: CGFloat
    /// The originating frame in the window's global coordinate space.
    let sourceFrame: CGRect
    let cornerRadius: CGFloat
    let accessibilityLabel: String
}

/// Full-window image preview that springs out of the frame it was invoked from,
/// fades in a frosted backdrop, and refines into a higher-resolution rendition.
struct ImageLightbox: View {
    let request: ImageLightboxRequest
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isExpanded = false
    @State private var isClosing = false
    @State private var highResolutionImage: NSImage?
    @State private var placeholderImage: NSImage?

    private static let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8)
    private static let closeAnimation = Animation.spring(response: 0.32, dampingFraction: 0.92)
    private static let closeDuration: Duration = .milliseconds(320)

    var body: some View {
        GeometryReader { proxy in
            let container = proxy.frame(in: .global)
            ZStack {
                backdrop
                artwork(in: container)
                closeButton
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { isExpanded = true }
        .task(id: request.id) { await loadImages() }
    }

    private var backdrop: some View {
        ZStack {
            if !reduceTransparency {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.7)
            }
            Color.black.opacity(backdropOpacity)
        }
        .ignoresSafeArea()
        .opacity(isExpanded ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .animation(backdropAnimation, value: isExpanded)
        .accessibilityHidden(true)
    }

    private func artwork(in container: CGRect) -> some View {
        let target = targetRect(in: container)
        let rect = reduceMotion ? target : (isExpanded ? target : sourceRect(in: container))
        let cornerRadius = reduceMotion || isExpanded ? Radius.hero : request.cornerRadius
        let artworkAnimation: Animation? = reduceMotion
            ? .easeOut(duration: Motion.transition)
            : (isClosing ? Self.closeAnimation : Self.openAnimation)
        let spinAngle: Double = reduceMotion ? 0 : (isExpanded ? 0 : -360)

        return ZStack {
            if highResolutionImage == nil {
                LoadingSkeleton(cornerRadius: 0)
            }
            if let placeholderImage {
                image(placeholderImage)
            }
            if let highResolutionImage {
                image(highResolutionImage)
                    .transition(.opacity)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    .white.opacity(contrast == .increased ? 0.3 : 0.14),
                    lineWidth: 0.5
                )
        }
        .tiltCard(cornerRadius: Radius.hero)
        .rotation3DEffect(
            .degrees(spinAngle),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.55
        )
        .shadow(
            color: .black.opacity(isExpanded ? 0.5 : 0.32),
            radius: isExpanded ? 44 : 16,
            y: isExpanded ? 26 : 8
        )
        .scaleEffect(reduceMotion && !isExpanded ? 0.96 : 1)
        .opacity(reduceMotion && !isExpanded ? 0 : 1)
        .position(x: rect.midX, y: rect.midY)
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .animation(artworkAnimation, value: isExpanded)
        .accessibilityLabel(request.accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }

    private func image(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
    }

    private var closeButton: some View {
        Button(action: dismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(9)
                .background(.black.opacity(0.45), in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverFeedback(scale: 1.1)
        .opacity(isExpanded ? 1 : 0)
        .scaleEffect(isExpanded ? 1 : 0.85)
        .animation(
            .easeOut(duration: 0.2).delay(isExpanded ? 0.1 : 0),
            value: isExpanded
        )
        .allowsHitTesting(isExpanded)
        .keyboardShortcut(.cancelAction)
        .help("Close (Esc)")
        .accessibilityLabel("Close cover art")
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .zIndex(1)
    }

    private var backdropAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: Motion.transition)
        }
        return isClosing ? .easeIn(duration: 0.18) : .easeOut(duration: 0.26)
    }

    private var backdropOpacity: Double {
        var opacity = reduceTransparency ? 0.88 : 0.6
        if contrast == .increased {
            opacity = min(opacity + 0.12, 0.95)
        }
        return opacity
    }

    /// The resting frame of the expanded artwork, centered in the window and
    /// sized to leave a comfortable margin. Coordinates are local to the
    /// lightbox container.
    private func targetRect(in container: CGRect) -> CGRect {
        let size = container.size
        guard size.width > 0, size.height > 0 else { return request.sourceFrame }
        let aspect = request.aspectRatio > 0 ? request.aspectRatio : 2.0 / 3.0
        let maxWidth = size.width * 0.5
        let maxHeight = size.height * 0.7
        var height = maxHeight
        var width = height * aspect
        if width > maxWidth {
            width = maxWidth
            height = width / aspect
        }
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }

    private func sourceRect(in container: CGRect) -> CGRect {
        request.sourceFrame.offsetBy(dx: -container.minX, dy: -container.minY)
    }

    private func dismiss() {
        guard !isClosing else { return }
        isClosing = true
        isExpanded = false
        let delay: Duration = reduceMotion ? .milliseconds(180) : Self.closeDuration
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            onDismiss()
        }
    }

    private func loadImages() async {
        let urls = request.imageURLs
        guard let preferredURL = urls.first else { return }

        if let cached = ImageCache.shared.image(for: preferredURL) {
            highResolutionImage = cached
            return
        }
        if let cached = urls.reversed().compactMap({ ImageCache.shared.image(for: $0) }).first {
            placeholderImage = cached
        }

        for url in urls {
            do {
                let image = try await ImageLoader.shared.image(for: url)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: Motion.transition)) {
                    highResolutionImage = image
                }
                return
            } catch {
                continue
            }
        }
    }
}

extension URL {
    /// Returns a copy of the URL with the trailing image size token replaced,
    /// used to fetch higher-resolution renditions of provider-hosted artwork
    /// (for example Kitsu's `medium` → `original`). Returns `nil` when the URL
    /// does not end in a file name.
    func replacingImageVariant(_ variant: String) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var pathComponents = components.path.split(separator: "/")
        guard let fileName = pathComponents.last else { return nil }
        var nameParts = fileName.split(separator: ".")
        guard nameParts.count >= 2, !nameParts[0].isEmpty else { return nil }
        nameParts[0] = Substring(variant)
        pathComponents[pathComponents.count - 1] = Substring(nameParts.joined(separator: "."))
        components.path = "/" + pathComponents.joined(separator: "/")
        return components.url
    }
}
