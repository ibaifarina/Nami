import SwiftUI

/// Gives a card a slight 3D tilt that follows the cursor plus a holographic
/// foil sheen that slides across the surface as the card moves.
struct TiltCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var maxAngle: Double = 3.5
    var sheenIntensity: Double = 0.3
    var cornerRadius: CGFloat = Radius.card

    @State private var size: CGSize = .zero
    @State private var pointer: CGPoint = .zero
    @State private var presence: Double = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newValue in
                size = newValue
            }
            .overlay {
                foilSheen
                    .opacity(presence * sheenIntensity)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            .rotation3DEffect(
                .degrees(rotationX),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.55
            )
            .rotation3DEffect(
                .degrees(rotationY),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.55
            )
            .scaleEffect(1 + 0.02 * presence)
            .animation(.easeOut(duration: Motion.hover), value: pointer)
            .onContinuousHover(perform: updateHover)
            .onChange(of: reduceMotion) {
                guard reduceMotion else { return }
                pointer = .zero
                presence = 0
            }
    }

    private var rotationX: Double {
        guard !reduceMotion else { return 0 }
        return -Double(pointer.y) * maxAngle
    }

    private var rotationY: Double {
        guard !reduceMotion else { return 0 }
        return Double(pointer.x) * maxAngle
    }

    private var foilSheen: some View {
        ZStack {
            iridescentBands
            glare
            glint
            sparkles
        }
    }

    /// Soft rainbow interference bands that lean and slide with the tilt.
    private var iridescentBands: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.30), location: 0.00),
                .init(color: Color(rgbHex: 0xFF9FD8).opacity(0.85), location: 0.10),
                .init(color: .white.opacity(0.18), location: 0.18),
                .init(color: Color(rgbHex: 0x8FE8F7).opacity(0.85), location: 0.28),
                .init(color: .white.opacity(0.18), location: 0.36),
                .init(color: Color(rgbHex: 0xC9A9FF).opacity(0.85), location: 0.46),
                .init(color: .white.opacity(0.18), location: 0.54),
                .init(color: Color(rgbHex: 0x9FF5D2).opacity(0.85), location: 0.64),
                .init(color: .white.opacity(0.18), location: 0.72),
                .init(color: Color(rgbHex: 0xFFD58F).opacity(0.85), location: 0.82),
                .init(color: .white.opacity(0.18), location: 0.90),
                .init(color: Color(rgbHex: 0xFF9FD8).opacity(0.70), location: 1.00),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .rotationEffect(.degrees(-14 + Double(pointer.y) * 8))
        .scaleEffect(1.6)
        .offset(x: pointer.x * 26, y: pointer.y * 20)
        .blur(radius: 14)
        .opacity(0.45)
    }

    /// Bright specular streak that sweeps across the card.
    private var glare: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.00),
                .init(color: .white.opacity(0.45), location: 0.42),
                .init(color: .white.opacity(0.55), location: 0.52),
                .init(color: .clear, location: 1.00),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: max(size.width * 0.7, 1))
        .rotationEffect(.degrees(-18))
        .scaleEffect(y: 1.8)
        .offset(x: pointer.x * size.width * 0.5, y: pointer.y * size.height * 0.35)
        .blur(radius: 10)
        .opacity(0.5)
    }

    /// Broad highlight that tracks the cursor like a light source.
    private var glint: some View {
        RadialGradient(
            colors: [
                .white.opacity(0.45),
                .white.opacity(0.12),
                .clear,
            ],
            center: .center,
            startRadius: 0,
            endRadius: max(size.width, size.height) * 0.7
        )
        .frame(width: max(size.width, 1) * 1.5, height: max(size.height, 1) * 1.5)
        .position(
            x: (pointer.x * 0.5 + 0.5) * size.width,
            y: (pointer.y * 0.5 + 0.5) * size.height
        )
        .blur(radius: 12)
        .opacity(0.45)
    }

    /// Sparse foil specks that shift against the bands for a grainy shimmer.
    private var sparkles: some View {
        Canvas { context, canvasSize in
            Self.drawSparkles(context: &context, size: canvasSize)
        }
        .offset(x: pointer.x * 5, y: pointer.y * 5)
        .opacity(0.22)
    }

    private func updateHover(_ phase: HoverPhase) {
        guard !reduceMotion else {
            pointer = .zero
            presence = 0
            return
        }
        switch phase {
        case .active(let location):
            if presence == 0 {
                withAnimation(.easeOut(duration: Motion.hover)) { presence = 1 }
            }
            pointer = normalized(location)
        case .ended:
            withAnimation(.easeOut(duration: Motion.hover)) {
                pointer = .zero
                presence = 0
            }
        }
    }

    private func normalized(_ location: CGPoint) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGPoint(
            x: min(max(location.x / size.width * 2 - 1, -1), 1),
            y: min(max(location.y / size.height * 2 - 1, -1), 1)
        )
    }

    private static func drawSparkles(context: inout GraphicsContext, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        for index in 0..<150 {
            let x = pseudoRandom(index * 4) * size.width
            let y = pseudoRandom(index * 4 + 1) * size.height
            let radius = 0.35 + pseudoRandom(index * 4 + 2) * 0.75
            let opacity = 0.05 + pseudoRandom(index * 4 + 3) * 0.3
            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
        }
    }

    private static func pseudoRandom(_ seed: Int) -> CGFloat {
        let value = sin(Double(seed) * 127.1 + 311.7) * 43758.5453
        return CGFloat(value - floor(value))
    }
}

extension View {
    /// Adds a cursor-following 3D tilt with a holographic foil sheen.
    func tiltCard(
        maxAngle: Double = 3.5,
        sheenIntensity: Double = 0.3,
        cornerRadius: CGFloat = Radius.card
    ) -> some View {
        modifier(
            TiltCardModifier(
                maxAngle: maxAngle,
                sheenIntensity: sheenIntensity,
                cornerRadius: cornerRadius
            )
        )
    }
}
