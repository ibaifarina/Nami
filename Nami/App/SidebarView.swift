import SwiftUI

struct SidebarView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var router = environment.router
        VStack(spacing: Spacing.xs) {
            ForEach(AppRouter.SidebarItem.allCases) { item in
                Button {
                    router.select(item)
                } label: {
                    railIcon(
                        item.systemImage(isSelected: router.selection == item),
                        isSelected: router.selection == item
                    )
                }
                .buttonStyle(.plain)
                .hoverFeedback(scale: 1.08, brightness: router.selection == item ? 0 : 0.12)
                .help(item.title)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(router.selection == item ? .isSelected : [])
            }

            Spacer(minLength: Spacing.md)

            Button {
                openSettings()
            } label: {
                railIcon("gearshape")
            }
            .buttonStyle(.plain)
            .hoverFeedback(scale: 1.08, brightness: 0.12)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.vertical, Spacing.sm)
        .frame(maxHeight: .infinity, alignment: .top)
        .frame(width: Layout.sidebarIdealWidth)
    }

    private func railIcon(_ systemImage: String, isSelected: Bool = false) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .medium))
            .frame(width: Layout.sidebarIconSize, height: Layout.sidebarIconSize)
            .foregroundStyle(isSelected ? AppColor.buttonLabel : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(AppColor.brand) : AnyShapeStyle(Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}
