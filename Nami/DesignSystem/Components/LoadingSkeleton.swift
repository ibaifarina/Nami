import SwiftUI

struct LoadingSkeleton: View {
    var cornerRadius: CGFloat = Radius.card

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            shape
        } else {
            PhaseAnimator([false, true]) { dimmed in
                shape.opacity(dimmed ? 0.55 : 1)
            } animation: { _ in
                .easeInOut(duration: 1.1)
            }
        }
    }

    private var shape: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppColor.surfaceElevated)
    }
}

struct PosterSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            LoadingSkeleton()
                .aspectRatio(Layout.posterAspectRatio, contentMode: .fit)
            LoadingSkeleton(cornerRadius: 4)
                .frame(height: 12)
                .frame(maxWidth: 140)
            LoadingSkeleton(cornerRadius: 4)
                .frame(width: 80, height: 9)
        }
    }
}

struct RowSkeleton: View {
    var count = 8

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            ForEach(0..<count, id: \.self) { _ in
                PosterSkeleton()
                    .frame(width: Layout.posterCardMinWidth)
            }
        }
        .redacted(reason: .placeholder)
    }
}
