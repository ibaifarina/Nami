import SwiftUI

/// Indeterminate loading indicator drawn as one continuous rotating arc.
///
/// The system `ProgressView` renders as a spoke of discrete dots on macOS;
/// this keeps a single unbroken ring so the motion reads as a continuous
/// sweep.
struct LoadingSpinner: View {
    var size: CGFloat = 32
    var lineWidth: CGFloat = 3
    var tint: Color = .primary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSpinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(
                tint,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                    isSpinning = true
                }
            }
            .accessibilityLabel("Loading")
    }
}
