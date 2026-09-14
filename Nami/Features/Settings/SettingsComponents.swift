import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case streaming
    case realDebrid
    case addons
    case playback
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .streaming: String(localized: "Streaming")
        case .realDebrid: String(localized: "Real-Debrid")
        case .addons: String(localized: "Addons")
        case .playback: String(localized: "Playback")
        case .advanced: String(localized: "Advanced")
        }
    }

    var subtitle: String {
        switch self {
        case .general: String(localized: "Appearance, version, and local storage.")
        case .streaming: String(localized: "How sources are chosen, ranked, and filtered.")
        case .realDebrid: String(localized: "Resolve torrent and hoster sources through your account.")
        case .addons: String(localized: "Providers that discover playable sources.")
        case .playback: String(localized: "Player engines and what happens between episodes.")
        case .advanced: String(localized: "Fine-tune scoring, release groups, and caches.")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .streaming: "play.rectangle"
        case .realDebrid: "bolt"
        case .addons: "puzzlepiece.extension"
        case .playback: "play.circle"
        case .advanced: "slider.horizontal.3"
        }
    }
}

enum SettingsSidebarAccessory {
    case check
    case count(Int)
}

struct SettingsSidebar: View {
    @Environment(AppEnvironment.self) private var environment
    @Binding var selection: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            ForEach(SettingsPane.allCases) { pane in
                SettingsSidebarItem(
                    pane: pane,
                    isSelected: pane == selection,
                    accessory: accessory(for: pane)
                ) {
                    withAnimation(.easeOut(duration: Motion.hover)) {
                        selection = pane
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.sm)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func accessory(for pane: SettingsPane) -> SettingsSidebarAccessory? {
        switch pane {
        case .realDebrid:
            return environment.debridAuth.isConnected ? .check : nil
        case .addons:
            let count = environment.addons.installed.count
            return count > 0 ? .count(count) : nil
        default:
            return nil
        }
    }
}

private struct SettingsSidebarItem: View {
    let pane: SettingsPane
    let isSelected: Bool
    let accessory: SettingsSidebarAccessory?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: pane.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)

                Text(pane.title)
                    .font(AppFont.cardTitle)
                    .lineLimit(1)

                Spacer(minLength: Spacing.xs)

                accessoryView
            }
            .foregroundStyle(isSelected ? AppColor.buttonLabel : Color.primary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(background)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: Motion.hover)) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(pane.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var accessoryView: some View {
        switch accessory {
        case .check:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? AppColor.buttonLabel.opacity(0.7) : Color.green)
        case .count(let value):
            Text("\(value)")
                .font(AppFont.cardMeta.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? AppColor.buttonLabel : Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    isSelected ? AppColor.buttonLabel.opacity(0.14) : Color.primary.opacity(0.08),
                    in: Capsule()
                )
        case nil:
            EmptyView()
        }
    }

    private var background: Color {
        if isSelected { return AppColor.brand }
        return isHovering ? Color.primary.opacity(0.06) : .clear
    }
}

struct SettingsPaneLayout<Content: View>: View {
    let pane: SettingsPane
    var scrolling = true
    private let content: Content

    init(pane: SettingsPane, scrolling: Bool = true, @ViewBuilder content: () -> Content) {
        self.pane = pane
        self.scrolling = scrolling
        self.content = content()
    }

    var body: some View {
        Group {
            if scrolling {
                ScrollView { stack }
            } else {
                stack
            }
        }
        .background(AppColor.background)
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(pane.title)
                    .font(AppFont.screenTitle)
                Text(pane.subtitle)
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            content
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SettingsCard<Content: View>: View {
    private let title: String?
    private let subtitle: String?
    private let content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let title {
                SectionHeader(title: title, subtitle: subtitle)
            }
            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppColor.surface,
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(AppColor.stroke, lineWidth: 0.5)
            }
        }
    }
}

struct SettingsRow<Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let description: String?
    private let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.cardTitle)
                    if let subtitle {
                        Text(subtitle)
                            .font(AppFont.cardMeta)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: Spacing.md)
                content
            }
            if let description {
                Text(description)
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340, alignment: .leading)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

struct SettingsStackedRow<Content: View>: View {
    private let title: String
    private let value: String?
    private let description: String?
    private let content: Content

    init(
        _ title: String,
        value: String? = nil,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.value = value
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(AppFont.cardTitle)
                Spacer(minLength: Spacing.md)
                if let value {
                    Text(value)
                        .font(AppFont.cardTitle)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            content
            if let description {
                Text(description)
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340, alignment: .leading)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

struct SettingsToggleRow: View {
    let title: String
    var subtitle: String?
    var description: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title, subtitle: subtitle, description: description) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(title)
        }
    }
}

struct SettingsSegmentedRow<Value: Hashable & Identifiable>: View {
    let title: String
    var subtitle: String?
    var description: String?
    let options: [Value]
    let titleForOption: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        SettingsStackedRow(title, description: description) {
            SegmentedSwitcher(
                options: options,
                selection: $selection,
                title: titleForOption
            )
        }
    }
}

struct SettingsDropdownOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var systemImage: String?
    var icon: NSImage?

    var id: Value { value }
}

struct SettingsDropdownRow<Value: Hashable>: View {
    let title: String
    var subtitle: String?
    var description: String?
    var systemImage: String?
    let options: [SettingsDropdownOption<Value>]
    @Binding var selection: Value
    var panelWidth: CGFloat = 240

    var body: some View {
        SettingsRow(title, subtitle: subtitle, description: description) {
            SettingsDropdown(
                title: title,
                options: options,
                selection: $selection,
                systemImage: systemImage,
                panelWidth: panelWidth
            )
        }
    }
}

struct SettingsDropdown<Value: Hashable>: View {
    let title: String
    let options: [SettingsDropdownOption<Value>]
    @Binding var selection: Value
    var systemImage: String?
    var panelWidth: CGFloat = 240

    @State private var isExpanded = false

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            SettingsMenuChip(
                text: selectedOption?.label ?? "\u{2014}",
                systemImage: systemImage,
                isExpanded: isExpanded
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isExpanded, arrowEdge: .top) {
            SettingsDropdownPanel(
                options: options,
                selection: selection,
                onSelect: { value in
                    selection = value
                    isExpanded = false
                }
            )
            .frame(width: panelWidth)
        }
        .accessibilityLabel(title)
        .accessibilityValue(selectedOption?.label ?? "")
    }

    private var selectedOption: SettingsDropdownOption<Value>? {
        options.first { $0.value == selection }
    }
}

struct SettingsDropdownAction {
    let label: String
    var systemImage: String?
    var isDestructive = false
    let handler: () -> Void
}

struct SettingsDropdownPanel<Value: Hashable>: View {
    let options: [SettingsDropdownOption<Value>]
    let selection: Value
    let onSelect: (Value) -> Void
    var action: SettingsDropdownAction? = nil

    @State private var hoveredValue: Value?
    @State private var isActionHovered = false

    var body: some View {
        Group {
            if options.count > 8 {
                ScrollView {
                    rows
                }
                .frame(height: 300)
            } else {
                rows
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                optionRow(
                    options[index],
                    isFirst: index == 0,
                    isLast: index == options.count - 1 && action == nil
                )
            }

            if let action {
                Divider()
                    .padding(.vertical, Spacing.xxs)

                actionRow(action, isFirst: options.isEmpty, isLast: true)
            }
        }
        .padding(Spacing.xxs)
    }

    private func optionRow(
        _ option: SettingsDropdownOption<Value>,
        isFirst: Bool,
        isLast: Bool
    ) -> some View {
        Button {
            onSelect(option.value)
        } label: {
            HStack(spacing: Spacing.xs) {
                optionIcon(option)

                Text(option.label)
                    .font(AppFont.cardTitle)
                    .lineLimit(1)

                Spacer(minLength: Spacing.sm)

                if option.value == selection {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppColor.brand)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                highlightShape(isFirst: isFirst, isLast: isLast)
                    .fill(rowBackground(for: option))
            }
            .contentShape(highlightShape(isFirst: isFirst, isLast: isLast))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredValue = option.value
            } else if hoveredValue == option.value {
                hoveredValue = nil
            }
        }
        .accessibilityAddTraits(option.value == selection ? .isSelected : [])
    }

    private func actionRow(
        _ action: SettingsDropdownAction,
        isFirst: Bool,
        isLast: Bool
    ) -> some View {
        Button {
            action.handler()
        } label: {
            HStack(spacing: Spacing.xs) {
                if let systemImage = action.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(action.isDestructive ? Color.red : Color.secondary)
                        .frame(width: 16)
                }

                Text(action.label)
                    .font(AppFont.cardTitle)
                    .lineLimit(1)

                Spacer(minLength: Spacing.sm)
            }
            .foregroundStyle(action.isDestructive ? Color.red : Color.primary)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                highlightShape(isFirst: isFirst, isLast: isLast)
                    .fill(actionBackground(for: action))
            }
            .contentShape(highlightShape(isFirst: isFirst, isLast: isLast))
        }
        .buttonStyle(.plain)
        .onHover { isActionHovered = $0 }
    }

    /// Matches the corner curvature of the enclosing popover so the first and
    /// last row highlights nest concentrically inside the dropdown container.
    private func highlightShape(isFirst: Bool, isLast: Bool) -> UnevenRoundedRectangle {
        let inner = Radius.control - 2
        return UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? Self.containerRadius - Spacing.xxs : inner,
            bottomLeadingRadius: isLast ? Self.containerRadius - Spacing.xxs : inner,
            bottomTrailingRadius: isLast ? Self.containerRadius - Spacing.xxs : inner,
            topTrailingRadius: isFirst ? Self.containerRadius - Spacing.xxs : inner,
            style: .circular
        )
    }

    private static var containerRadius: CGFloat { 18 }

    @ViewBuilder
    private func optionIcon(_ option: SettingsDropdownOption<Value>) -> some View {
        if let icon = option.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
        } else if let systemImage = option.systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)
        }
    }

    private func rowBackground(for option: SettingsDropdownOption<Value>) -> Color {
        if option.value == selection {
            return AppColor.brand.opacity(0.12)
        }
        if hoveredValue == option.value {
            return Color.primary.opacity(0.05)
        }
        return .clear
    }

    private func actionBackground(for action: SettingsDropdownAction) -> Color {
        guard isActionHovered else { return .clear }
        return action.isDestructive ? Color.red.opacity(0.08) : Color.primary.opacity(0.05)
    }
}

struct SettingsSliderRow: View {
    let title: String
    var description: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let valueText: (Double) -> String

    var body: some View {
        SettingsStackedRow(title, value: valueText(value), description: description) {
            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
        }
    }
}

struct SettingsStepperRow: View {
    let title: String
    var description: String?
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        SettingsRow(title, description: description) {
            HStack(spacing: Spacing.xs) {
                Text("\(value)")
                    .font(AppFont.cardTitle)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper("", value: $value, in: range)
                    .labelsHidden()
                    .accessibilityLabel(title)
            }
        }
    }
}

struct SettingsTextFieldRow: View {
    let title: String
    var description: String?
    let prompt: String
    @Binding var text: String

    var body: some View {
        SettingsStackedRow(title, description: description) {
            SettingsFieldChrome {
                TextField("", text: $text, prompt: Text(prompt))
            }
        }
    }
}

struct SettingsFieldChrome<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .textFieldStyle(.plain)
            .font(AppFont.body)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 7)
            .background(
                Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(AppColor.stroke, lineWidth: 0.5)
            }
    }
}

struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        SettingsRow(title) {
            Text(value)
                .font(AppFont.cardTitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

struct SettingsMenuChip: View {
    let text: String
    var systemImage: String?
    var isExpanded = false

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Spacing.xxs + 2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(AppFont.cardTitle)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .animation(.easeOut(duration: Motion.hover), value: isExpanded)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(background, in: Capsule())
        .overlay {
            Capsule().strokeBorder(isHovering ? Color.primary.opacity(0.18) : AppColor.stroke, lineWidth: 1)
        }
        .contentShape(Capsule())
        .animation(.easeOut(duration: Motion.hover), value: isHovering)
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        isHovering ? AppColor.surfaceElevated : Color.primary.opacity(0.06)
    }
}

struct SettingsBanner: View {
    enum Kind {
        case success
        case warning
        case info

        var tint: Color {
            switch self {
            case .success: .green
            case .warning: .orange
            case .info: .blue
            }
        }

        var systemImage: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .info: "info.circle.fill"
            }
        }
    }

    let kind: Kind
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Image(systemName: kind.systemImage)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(AppFont.cardMeta.weight(.medium))
        .foregroundStyle(kind.tint)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            kind.tint.opacity(0.1),
            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(kind.tint.opacity(0.25), lineWidth: 0.5)
        }
    }
}

struct WarningNote: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Text(message)
                .font(AppFont.cardMeta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
