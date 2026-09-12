import SwiftUI

struct ContinueWatchingCard: View {
    let anime: Anime
    let progress: PlaybackProgress
    var episode: Episode? = nil
    var seasonNumber: Int? = nil
    var onOpen: () -> Void
    var onResume: () -> Void
    var onRemove: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animeTitleLanguage) private var titleLanguage
    @State private var isHovered = false

    var body: some View {
        ZStack {
            Button(action: onOpen) {
                cardContent
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(accessibilityEpisodeLine)")
            .accessibilityHint("Opens anime details")

            resumeButton
        }
        .overlay(alignment: .topTrailing) { removeButton }
        .onHover { hovering in
            withAnimation(.easeOut(duration: Motion.hover)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isHovered && !reduceMotion ? 1.015 : 1)
    }

    private var cardContent: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                RemoteImage(url: anime.bannerURL ?? anime.posterURL, contentMode: .fill)
            }
            .overlay { scrim }
            .overlay(alignment: .bottom) { progressBar }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contentShape(Rectangle())
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
                Text(episodeLine)
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Text(progress.timecode)
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(Spacing.sm)
        }
    }

    private var episodeLine: String {
        var line = "E\(progress.episodeNumber)"
        if let seasonNumber {
            line = "S\(seasonNumber) \u{00B7} " + line
        }
        if let episodeTitle = episode?.title, !episodeTitle.isEmpty {
            line += " \u{2014} \(episodeTitle)"
        }
        return line
    }

    private var accessibilityEpisodeLine: String {
        var parts: [String] = []
        if let seasonNumber {
            parts.append("season \(seasonNumber)")
        }
        parts.append("episode \(progress.episodeNumber)")
        if let episodeTitle = episode?.title, !episodeTitle.isEmpty {
            parts.append(episodeTitle)
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var resumeButton: some View {
        if isHovered {
            Button(action: onResume) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.white)
                    .shadow(radius: 8)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .hoverFeedback(scale: 1.12, shadowRadius: 10, shadowY: 2)
            .transition(.opacity)
            .accessibilityLabel("Resume \(title), \(accessibilityEpisodeLine), \(progress.timecode)")
            .accessibilityHint("Resumes this episode immediately")
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
