import SwiftUI

struct HeroSection: View {
    let anime: Anime
    var blurRadius: CGFloat = Effects.heroBlur
    var onPlay: () -> Void
    var onDetails: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .scrollView)
            let topOverscroll = max(frame.minY, 0)
            let leadingOverscroll = max(frame.minX, 0)
            let horizontalOverscroll = abs(frame.minX)

            ZStack(alignment: .topLeading) {
                ZStack {
                    ParallaxHeroImage(url: anime.bannerURL ?? anime.posterURL, blurRadius: blurRadius)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .mask { AppColor.heroMask }
                    Color.black.opacity(0.7)
                    AppColor.heroFade
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(
                    width: proxy.size.width + horizontalOverscroll,
                    height: Layout.heroHeight + topOverscroll
                )
                .offset(x: -leadingOverscroll, y: -topOverscroll)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(anime.displayTitle)
                        .font(AppFont.heroTitle)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    HStack(spacing: Spacing.xs) {
                        if let score = anime.averageScore {
                            Pill(text: "\(score)", systemImage: "star.fill")
                        }
                        if let subtype = anime.subtype { Pill(text: subtype.displayName) }
                        if let year = anime.startYear { Pill(text: String(year)) }
                        if let status = anime.status { Pill(text: status.displayName) }
                    }
                    if let synopsis = anime.synopsis {
                        Text(synopsis)
                            .font(AppFont.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .frame(maxWidth: 620, alignment: .leading)
                    }
                    HStack(spacing: Spacing.sm) {
                        Button("Play", systemImage: "play.fill", action: onPlay)
                            .buttonStyle(BrandButtonStyle())
                        Button("Details", action: onDetails)
                            .buttonStyle(GlassButtonStyle())
                    }
                    .padding(.top, Spacing.xxs)
                }
                .contentPadding()
                .padding(.vertical, Spacing.xl)
                .frame(
                    width: proxy.size.width,
                    height: Layout.heroHeight,
                    alignment: .bottomLeading
                )
                .offset(x: -frame.minX, y: -topOverscroll)
            }
            .frame(width: proxy.size.width, height: Layout.heroHeight)
        }
        .frame(height: Layout.heroHeight)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}
