import AppKit
import SwiftUI

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
    static let huge: CGFloat = 48
    static let massive: CGFloat = 64
}

enum Radius {
    static let control: CGFloat = 8
    static let button: CGFloat = 10
    static let card: CGFloat = 14
    static let hero: CGFloat = 20
}

enum Motion {
    static let hover: Double = 0.15
    static let transition: Double = 0.25
    /// Fraction of the scroll distance the hero backdrop drifts behind the content.
    static let heroParallaxFactor: CGFloat = 0.4
    /// Resting oversize of the hero backdrop so its edges stay out of frame.
    static let heroParallaxBaseScale: CGFloat = 1.04
    /// Extra scale applied to the hero backdrop by the time it scrolls out of view.
    static let heroParallaxMaxScale: CGFloat = 0.08
}

enum Effects {
    static let heroBlur: CGFloat = 5
}

enum Layout {
    static let windowMinWidth: CGFloat = 1000
    static let windowMinHeight: CGFloat = 680
    static let contentPadding: CGFloat = 28
    static let sidebarIconSize: CGFloat = 36
    static let sidebarIdealWidth: CGFloat = 64
    static let contentLeadingPadding: CGFloat = sidebarIdealWidth
    static let posterAspectRatio: CGFloat = 2.0 / 3.0
    static let heroHeight: CGFloat = 480
    static let detailHeroHeight: CGFloat = 560
    /// Bottom inset that lifts the detail hero's title/actions off the base of the backdrop.
    static let detailHeroContentInset: CGFloat = 120
    /// How far the detail page's content rises over the bottom of the backdrop.
    static let detailHeroOverlap: CGFloat = 120
    static let posterCardMinWidth: CGFloat = 148
    static let posterCardMaxWidth: CGFloat = 186
    static let topBarScrimHeight: CGFloat = 72
    /// Scroll distance over which the top bar scrim reaches full opacity.
    static let topBarScrimDistance: CGFloat = 32
}

extension Color {
    init(rgbHex: UInt32) {
        self.init(
            .sRGB,
            red: Double((rgbHex >> 16) & 0xFF) / 255,
            green: Double((rgbHex >> 8) & 0xFF) / 255,
            blue: Double(rgbHex & 0xFF) / 255,
            opacity: 1
        )
    }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum AppColor {
    static let background = Color.adaptive(light: 0xF5F5F7, dark: 0x0B0B0F)
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x15151B)
    static let surfaceElevated = Color.adaptive(light: 0xE9E9EE, dark: 0x21212B)
    static let stroke = Color.adaptive(light: 0x1C1C1E, dark: 0xFFFFFF).opacity(0.08)

    static let brand = Color.adaptive(light: 0x1C1C1E, dark: 0xF2F2F7)
    static let brandSecondary = Color.adaptive(light: 0x48484A, dark: 0xCFCFD4)
    static let brandGradient = LinearGradient(
        colors: [brand, brandSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let buttonFill = Color.adaptive(light: 0x1C1C1E, dark: 0xF2F2F7)
    static let buttonLabel = Color.adaptive(light: 0xF5F5F7, dark: 0x0B0B0F)

    static let heroFade = LinearGradient(
        stops: [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: 0.35),
            .init(color: background.opacity(0.3), location: 0.6),
            .init(color: background.opacity(0.85), location: 0.85),
            .init(color: background, location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let heroMask = LinearGradient(
        stops: [
            .init(color: .black, location: 0),
            .init(color: .black, location: 0.45),
            .init(color: .black.opacity(0.85), location: 0.68),
            .init(color: .black.opacity(0.5), location: 0.86),
            .init(color: .clear, location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let detailHeroMask = LinearGradient(
        stops: [
            .init(color: .black, location: 0),
            .init(color: .black, location: 0.6),
            .init(color: .black.opacity(0.85), location: 0.78),
            .init(color: .black.opacity(0.55), location: 0.9),
            .init(color: .clear, location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let detailHeroFade = LinearGradient(
        stops: [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: 0.42),
            .init(color: background.opacity(0.18), location: 0.6),
            .init(color: background.opacity(0.42), location: 0.78),
            .init(color: background.opacity(0.8), location: 0.93),
            .init(color: background, location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let topBarScrim = LinearGradient(
        stops: [
            .init(color: background.opacity(0.9), location: 0),
            .init(color: background.opacity(0.45), location: 0.5),
            .init(color: background.opacity(0), location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension View {
    /// Horizontal padding for screen content that clears the floating sidebar rail.
    func contentPadding() -> some View {
        padding(.leading, Layout.contentLeadingPadding)
            .padding(.trailing, Layout.contentPadding)
    }
}
