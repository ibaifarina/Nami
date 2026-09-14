import SwiftUI

/// Detail modal for a single episode, presented from the episode cards.
struct EpisodeDetailSheet: View {
    let episode: Episode
    let fallbackImageURL: URL?
    let isWatched: Bool
    let progress: PlaybackProgress?
    let onPlay: () -> Void
    let onToggleWatched: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            backdrop
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            closeButton
                .padding(Spacing.md)
        }
        .frame(width: 640, height: 380)
        .overlay(alignment: .bottom) { progressBar }
        .clipShape(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
    }

    private var backdrop: some View {
        ZStack {
            Color.clear
                .overlay {
                    RemoteImage(url: episode.thumbnailURL ?? fallbackImageURL, contentMode: .fill)
                        .scaleEffect(1.08)
                        .blur(radius: 12)
                        .allowsHitTesting(false)
                }
                .clipped()
                .contentShape(Rectangle())
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.35), location: 0),
                    .init(color: .black.opacity(0.55), location: 0.45),
                    .init(color: .black.opacity(0.88), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            synopsis
            Spacer(minLength: Spacing.md)
            actions
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.top, Spacing.xxl)
        .padding(.bottom, Spacing.lg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if episode.hasTitle {
                Text("Episode \(episode.displayNumber)")
                    .font(AppFont.cardMeta.weight(.semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text(episode.displayTitle)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
            metadataPills
                .padding(.top, Spacing.xxs)
        }
        .shadow(color: .black.opacity(0.35), radius: 10, y: 2)
    }

    @ViewBuilder
    private var metadataPills: some View {
        HStack(spacing: Spacing.xs) {
            if let duration = episode.durationText {
                metadataPill(duration, systemImage: "clock")
            }
            if let airDate = episode.airDateText {
                metadataPill(airDate, systemImage: "calendar")
            }
            if let progress {
                metadataPill(progress.timecode, systemImage: "play.fill")
            }
        }
    }

    private func metadataPill(_ text: String, systemImage: String) -> some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(AppFont.cardMeta.weight(.medium))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 3)
        .background(.black.opacity(0.3), in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
        }
    }

    private var synopsis: some View {
        Text(episode.hasSynopsis ? (episode.synopsis ?? "") : String(localized: "No synopsis is available for this episode yet."))
            .font(AppFont.body)
            .foregroundStyle(.white.opacity(0.82))
            .lineSpacing(3)
            .lineLimit(5)
    }

    private var actions: some View {
        HStack(spacing: Spacing.sm) {
            Button("Play", systemImage: "play.fill", action: onPlay)
                .buttonStyle(BrandButtonStyle())
            Button(
                isWatched ? "Mark as Unwatched" : "Mark as Watched",
                systemImage: isWatched ? "eye.slash" : "eye",
                action: onToggleWatched
            )
            .buttonStyle(GlassButtonStyle())
            Spacer()
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.45), in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverFeedback(scale: 1.1)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Close")
    }

    @ViewBuilder
    private var progressBar: some View {
        if let progress {
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
}
