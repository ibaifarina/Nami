import SwiftUI

/// Hero backdrop that drifts against the scroll direction and eases upward in scale.
struct ParallaxHeroImage: View {
    let url: URL?
    var height: CGFloat = Layout.heroHeight
    var blurRadius: CGFloat = Effects.heroBlur

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        -proxy.frame(in: .scrollView).minY
                    } action: { newValue in
                        scrollOffset = max(0, newValue)
                    }
                RemoteImage(url: url, contentMode: .fill)
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
                    .scaleEffect(scale)
                    .blur(radius: blurRadius, opaque: true)
                    .offset(y: progress * Motion.heroParallaxFactor)
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height
            )
            .clipped()
        }
        .frame(height: height)
    }

    private var progress: CGFloat {
        guard !reduceMotion else { return 0 }
        return min(scrollOffset, height)
    }

    private var scale: CGFloat {
        guard !reduceMotion else { return 1 }
        return Motion.heroParallaxBaseScale
            + progress / height * Motion.heroParallaxMaxScale
    }
}
