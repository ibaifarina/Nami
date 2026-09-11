import SwiftUI

struct AnimePosterCard: View {
    let anime: Anime
    var metaOverride: String? = nil
    var onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                poster
                VStack(alignment: .leading, spacing: 2) {
                    Text(anime.displayTitle)
                        .font(AppFont.cardTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(metaOverride ?? metaLine)
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: Motion.hover)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isHovered && !reduceMotion ? 1.02 : 1)
        .contextMenu {
            Button("Open Details", action: onOpen)
            if let kitsuURL = anime.kitsuURL {
                Button("Open on Kitsu") {
                    openURL(kitsuURL)
                }
            }
        }
        .accessibilityLabel("\(anime.displayTitle), \(metaOverride ?? metaLine)")
    }

    private var poster: some View {
        Color.clear
            .aspectRatio(Layout.posterAspectRatio, contentMode: .fit)
            .overlay {
                RemoteImage(url: anime.posterURL, contentMode: .fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(AppColor.stroke, lineWidth: 0.5)
            }
            .overlay {
                if isHovered {
                    hoverOverlay
                }
            }
            .shadow(
                color: .black.opacity(isHovered ? 0.35 : 0),
                radius: isHovered ? 14 : 0,
                y: isHovered ? 8 : 0
            )
    }

    private var hoverOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(systemName: "play.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.white)
                .shadow(radius: 8)
            if let score = anime.averageScore {
                VStack {
                    Spacer()
                    HStack {
                        Pill(
                            text: "\(score)",
                            systemImage: "star.fill",
                            tint: .white
                        )
                        Spacer()
                    }
                }
                .padding(Spacing.xs)
            }
        }
        .transition(.opacity)
    }

    private var metaLine: String {
        var parts: [String] = []
        if let subtype = anime.subtype { parts.append(subtype.displayName) }
        if let year = anime.startYear { parts.append(String(year)) }
        if parts.isEmpty, let status = anime.status { parts.append(status.displayName) }
        return parts.joined(separator: " \u{00B7} ")
    }
}

#if DEBUG
#Preview("Poster Card") {
    AnimePosterCard(anime: PreviewFixtures.anime) {}
        .frame(width: 160)
        .padding()
}

#Preview("Continue Watching Card") {
    ContinueWatchingCard(
        anime: PreviewFixtures.anime,
        progress: PlaybackProgress(
            animeID: "7442",
            episodeNumber: 7,
            positionSeconds: 1_111,
            durationSeconds: 1_452,
            updatedAt: Date()
        )
    ) {}
    .frame(width: 280)
    .padding()
}
#endif
