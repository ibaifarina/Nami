import SwiftUI

/// Fades a gradient below the window's top bar as content scrolls beneath it.
private struct TopBarScrim: ViewModifier {
    @State private var progress: Double = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                progress = min(max(offset / Layout.topBarScrimDistance, 0), 1)
            }
            .overlay(alignment: .top) {
                AppColor.topBarScrim
                    .frame(height: Layout.topBarScrimHeight)
                    .frame(maxWidth: .infinity)
                    .ignoresSafeArea(edges: .top)
                    .opacity(progress)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .animation(.easeOut(duration: Motion.hover), value: progress)
    }
}

extension View {
    /// Shows an adaptive scrim behind the window's top bar while the
    /// attached scroll view's content passes under it.
    func topBarScrim() -> some View {
        modifier(TopBarScrim())
    }
}
