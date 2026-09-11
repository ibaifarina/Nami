import SwiftUI

struct SegmentedSwitcher<Value: Hashable & Identifiable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var systemImage: ((Value) -> String)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(Spacing.xxs + 2)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(AppColor.stroke))
    }

    private func segment(_ option: Value) -> some View {
        let isSelected = option == selection
        return Button {
            guard !isSelected else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82)) {
                selection = option
            }
        } label: {
            HStack(spacing: Spacing.xxs + 2) {
                if let systemImage {
                    Image(systemName: systemImage(option))
                }
                Text(title(option))
            }
            .font(AppFont.cardTitle)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isSelected ? AppColor.buttonLabel : Color.secondary)
            .padding(.horizontal, Spacing.sm + 2)
            .padding(.vertical, Spacing.xs - 2)
            .background {
                if isSelected {
                    Capsule()
                        .fill(AppColor.buttonFill)
                        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(SegmentButtonStyle(isSelected: isSelected))
    }
}

private struct SegmentButtonStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        SegmentButtonBody(
            configuration: configuration,
            isSelected: isSelected,
            reduceMotion: reduceMotion
        )
    }

    private struct SegmentButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        let reduceMotion: Bool

        @State private var isHovering = false

        var body: some View {
            configuration.label
                .background {
                    if isHovering && !isSelected {
                        Capsule().fill(Color.primary.opacity(0.06))
                    }
                }
                .scaleEffect(scale)
                .animation(.easeOut(duration: Motion.hover), value: configuration.isPressed)
                .animation(.easeOut(duration: Motion.hover), value: isHovering)
                .onHover { isHovering = $0 }
        }

        private var scale: CGFloat {
            guard !reduceMotion else { return 1 }
            if configuration.isPressed { return 0.97 }
            return isHovering && !isSelected ? 1.02 : 1
        }
    }
}
