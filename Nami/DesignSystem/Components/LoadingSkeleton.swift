import SwiftUI

struct LoadingSkeleton: View {
    var cornerRadius: CGFloat = Radius.card
    var color: Color = AppColor.surfaceElevated

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(color)
            .opacity(reduceMotion ? 1 : (isPulsing ? 0.55 : 1))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
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

struct ContinueWatchingCardSkeleton: View {
    var body: some View {
        LoadingSkeleton()
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    LoadingSkeleton(cornerRadius: 4, color: AppColor.surface)
                        .frame(width: 150, height: 12)
                    LoadingSkeleton(cornerRadius: 4, color: AppColor.surface)
                        .frame(width: 90, height: 9)
                }
                .padding(Spacing.sm)
            }
            .overlay(alignment: .bottom) {
                LoadingSkeleton(cornerRadius: 0, color: AppColor.surface)
                    .frame(height: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

struct ContinueWatchingRowSkeleton: View {
    var count = 4

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            ForEach(0..<count, id: \.self) { _ in
                ContinueWatchingCardSkeleton()
                    .frame(width: Layout.continueWatchingCardWidth)
            }
        }
        .redacted(reason: .placeholder)
    }
}
