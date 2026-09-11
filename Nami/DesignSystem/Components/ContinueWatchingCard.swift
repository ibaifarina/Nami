import SwiftUI

struct ContinueWatchingCard: View {
    let anime: Anime
    let progress: PlaybackProgress
    var onResume: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: onResume) {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    RemoteImage(url: anime.bannerURL ?? anime.posterURL, contentMode: .fill)
                }
                .overlay { scrim }
                .overlay(alignment: .topTrailing) { resumeButton }
                .overlay(alignment: .bottom) { progressBar }
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(AppColor.stroke, lineWidth: 0.5)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: Motion.hover)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isHovered && !reduceMotion ? 1.015 : 1)
        .accessibilityLabel(
            "Resume \(anime.displayTitle), episode \(progress.episodeNumber), \(progress.timecode)"
        )
    }

    private var scrim: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: .black.opacity(0.78), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(anime.displayTitle)
                    .font(AppFont.cardTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: Spacing.xs) {
                    Text("Episode \(progress.episodeNumber)")
                    Text(progress.timecode)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .font(AppFont.cardMeta)
                .foregroundStyle(.white.opacity(0.85))
            }
            .padding(Spacing.sm)
        }
    }

    @ViewBuilder
    private var resumeButton: some View {
        if isHovered {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "play.fill")
                Text("Resume")
            }
            .font(AppFont.cardMeta.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs + 2)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(Spacing.xs)
            .transition(.opacity)
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.25))
                Rectangle()
                    .fill(AppColor.brandGradient)
                    .frame(width: max(3, geometry.size.width * progress.fraction))
            }
        }
        .frame(height: 3)
    }
}
