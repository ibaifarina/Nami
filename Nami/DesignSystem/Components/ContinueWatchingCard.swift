import SwiftUI

struct ContinueWatchingCard: View {
    let anime: Anime
    let progress: PlaybackProgress
    var onResume: () -> Void
    var onRemove: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animeTitleLanguage) private var titleLanguage
    @State private var isHovered = false

    var body: some View {
        Button(action: onResume) {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    RemoteImage(url: anime.bannerURL ?? anime.posterURL, contentMode: .fill)
                }
                .overlay { scrim }
                .overlay { resumeButton }
                .overlay(alignment: .bottom) { progressBar }
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(AppColor.stroke, lineWidth: 0.5)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) { removeButton }
        .onHover { hovering in
            withAnimation(.easeOut(duration: Motion.hover)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isHovered && !reduceMotion ? 1.015 : 1)
        .accessibilityLabel(
            "Resume \(title), episode \(progress.episodeNumber), \(progress.timecode)"
        )
    }

    private var title: String {
        anime.displayTitle(for: titleLanguage)
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
                Text(title)
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
            Image(systemName: "play.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.white)
                .shadow(radius: 8)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var removeButton: some View {
        if isHovered {
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .hoverFeedback(scale: 1.15)
            .padding(Spacing.xs)
            .transition(.opacity)
            .accessibilityLabel("Remove \(title) from Continue Watching")
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
