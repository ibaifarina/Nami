import SwiftUI

struct AnimePosterCard: View {
    let anime: Anime
    var metaOverride: String? = nil
    var onRemove: (() -> Void)? = nil
    var onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.animeTitleLanguage) private var titleLanguage
    @State private var isHovered = false

    var body: some View {
        ZStack {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    poster
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
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
        }
        .overlay(alignment: .topTrailing) { removeButton }
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
        .accessibilityLabel("\(title), \(metaOverride ?? metaLine)")
    }

    @ViewBuilder
    private var removeButton: some View {
        if isHovered, let onRemove {
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
            .accessibilityLabel("Remove \(title) from Library")
        }
    }

    private var title: String {
        anime.displayTitle(for: titleLanguage)
    }

    private var poster: some View {
        Color.clear
            .aspectRatio(Layout.posterAspectRatio, contentMode: .fit)
            .overlay {
                RemoteImage(url: anime.posterURL, contentMode: .fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
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
            episodeNumber: 4,
            positionSeconds: 1_038,
            durationSeconds: 1_440,
            updatedAt: Date()
        ),
        episode: Episode(
            id: "7442-4",
            animeID: "7442",
            number: 4,
            relativeNumber: 4,
            title: "The Hero's Resolve"
        ),
        seasonNumber: 2,
        onOpen: {
        },
        onResume: {
        },
        onRemove: {
        }
    )
    .frame(width: 280)
    .padding()
}
#endif
