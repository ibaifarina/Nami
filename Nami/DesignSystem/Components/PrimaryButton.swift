import SwiftUI

struct BrandButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        BrandButtonBody(configuration: configuration, reduceMotion: reduceMotion)
    }

    private struct BrandButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let reduceMotion: Bool

        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(AppFont.button)
                .foregroundStyle(AppColor.buttonLabel)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.xs + 1)
                .background(AppColor.buttonFill.opacity(isHovering ? 1 : 0.88), in: Capsule())
                .overlay {
                    if configuration.isPressed {
                        Capsule().fill(.black.opacity(0.15))
                    }
                }
                .scaleEffect(scale)
                .shadow(color: .black.opacity(isHovering ? 0.22 : 0), radius: isHovering ? 10 : 0, y: isHovering ? 4 : 0)
                .animation(.easeOut(duration: Motion.hover), value: configuration.isPressed)
                .animation(.easeOut(duration: Motion.hover), value: isHovering)
                .pointerStyle(.link)
                .onHover { isHovering = $0 }
        }

        private var scale: CGFloat {
            guard !reduceMotion else { return 1 }
            if configuration.isPressed { return 0.98 }
            return isHovering ? 1.03 : 1
        }
    }
}

struct GlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration, reduceMotion: reduceMotion)
    }

    private struct GlassButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let reduceMotion: Bool

        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(AppFont.button)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.xs + 1)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().fill(.white.opacity(isHovering ? 0.12 : 0))
                }
                .overlay {
                    Capsule().strokeBorder(.white.opacity(isHovering ? 0.28 : 0.12), lineWidth: 0.5)
                }
                .scaleEffect(scale)
                .shadow(color: .black.opacity(isHovering ? 0.18 : 0), radius: isHovering ? 8 : 0, y: isHovering ? 3 : 0)
                .animation(.easeOut(duration: Motion.hover), value: configuration.isPressed)
                .animation(.easeOut(duration: Motion.hover), value: isHovering)
                .pointerStyle(.link)
                .onHover { isHovering = $0 }
        }

        private var scale: CGFloat {
            guard !reduceMotion else { return 1 }
            if configuration.isPressed { return 0.98 }
            return isHovering ? 1.03 : 1
        }
    }
}

struct HoverFeedbackModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var scale: CGFloat = 1
    var brightness: Double = 0
    var opacity: Double = 1
    var shadowRadius: CGFloat = 0
    var shadowY: CGFloat = 0

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering && !reduceMotion ? scale : 1)
            .brightness(isHovering ? brightness : 0)
            .opacity(isHovering ? opacity : 1)
            .shadow(
                color: .black.opacity(isHovering ? 0.18 : 0),
                radius: isHovering ? shadowRadius : 0,
                y: isHovering ? shadowY : 0
            )
            .animation(.easeOut(duration: Motion.hover), value: isHovering)
            .pointerStyle(.link)
            .onHover { isHovering = $0 }
    }
}

extension View {
    func hoverFeedback(
        scale: CGFloat = 1,
        brightness: Double = 0,
        opacity: Double = 1,
        shadowRadius: CGFloat = 0,
        shadowY: CGFloat = 0
    ) -> some View {
        modifier(
            HoverFeedbackModifier(
                scale: scale,
                brightness: brightness,
                opacity: opacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }
}
