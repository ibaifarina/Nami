import AppKit
import SwiftUI

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flow = OnboardingFlow()
    @State private var tokenInput = ""
    @State private var isAddingAddon = false

    var body: some View {
        VStack(spacing: 0) {
            header
            contentArea
            footer
        }
        .frame(width: 780, height: 640)
        .background(AppColor.background)
        .sheet(isPresented: $isAddingAddon) {
            AddAddonSheet()
                .environment(environment)
        }
        .animation(stepAnimation, value: flow.step)
    }

    private var stepAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.88)
    }

    /// Setup steps that have actually been configured, driving the checkmarks
    /// in the progress rail. Preferences count as configured once reviewed.
    private var completedSetupSteps: Set<OnboardingFlow.Step> {
        var completed: Set<OnboardingFlow.Step> = []
        if environment.debridAuth.isConnected {
            completed.insert(.realDebrid)
        }
        if !environment.addons.enabledAddons.isEmpty {
            completed.insert(.addons)
        }
        if flow.visited.contains(.preferences) {
            completed.insert(.preferences)
        }
        return completed
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.sm) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Nami")
                        .font(AppFont.cardTitle.weight(.semibold))
                    Text("Anime streaming for Mac")
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Spacing.md)

                if let index = flow.setupIndex {
                    Pill(
                        text: String(localized: "Setup \(index + 1) of \(OnboardingFlow.setupSteps.count)"),
                        systemImage: "checklist",
                        tint: .secondary
                    )
                }
            }

            if flow.step.isSetup {
                SetupRail(
                    flow: flow,
                    completedSteps: completedSetupSteps
                ) { step in
                    flow.go(to: step)
                }
            }
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.lg)
    }

    // MARK: - Content

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if flow.step == .welcome {
                    welcomeStep
                } else {
                    OnboardingStepHeader(step: flow.step)
                    stepContent
                }
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.bottom, Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(flow.step)
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .offset(x: 0, y: 14)),
                    removal: .opacity.combined(with: .offset(x: 0, y: -10))
                )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch flow.step {
        case .welcome:
            EmptyView()
        case .realDebrid:
            realDebridStep
        case .addons:
            addonsStep
        case .preferences:
            preferencesStep
        case .ready:
            readyStep
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 92, height: 92)
                    .shadow(color: .black.opacity(0.28), radius: 20, y: 10)
                    .accessibilityHidden(true)

                VStack(spacing: Spacing.xxs) {
                    Text("Welcome to Nami")
                        .font(.system(size: 30, weight: .bold))
                    Text("Your anime, one clean Play button.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, Spacing.xs)

            SettingsCard {
                featureRow(
                    systemImage: "wand.and.stars",
                    title: String(localized: "Automatic source selection"),
                    detail: String(localized: "Nami ranks every source and plays the best one for you.")
                )
                featureRow(
                    systemImage: "bolt.fill",
                    title: String(localized: "Real-Debrid ready"),
                    detail: String(localized: "Instant cached streams in up to 4K, with a manual picker one click away.")
                )
                featureRow(
                    systemImage: "display",
                    title: String(localized: "Built for macOS"),
                    detail: String(localized: "MKV, ASS subtitles, multiple audio tracks, and hardware decoding.")
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func featureRow(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.brand)
                .frame(width: 32, height: 32)
                .background(
                    Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.cardTitle)
                Text(detail)
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Real-Debrid

    @ViewBuilder
    private var realDebridStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SettingsCard(title: String(localized: "Account")) {
                Group {
                    if let account = environment.debridAuth.account {
                        connectedDebridContent(account)
                    } else {
                        connectDebridContent
                    }
                }
                .padding(Spacing.md)
            }

            if let message = environment.debridAuth.failureMessage {
                SettingsBanner(kind: .warning, message: message)
            }

            Text("Real-Debrid is optional. Without it, Nami still plays direct sources, and you can connect later in Settings.")
                .font(AppFont.cardMeta)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectDebridContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Paste a private API token from real-debrid.com/apitoken. It is stored in your macOS Keychain and never shared with addons.")
                .font(AppFont.cardMeta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.sm) {
                SettingsFieldChrome {
                    SecureField("", text: $tokenInput, prompt: Text("Paste your API token"))
                }
                Button("Paste", action: pasteToken)
                    .controlSize(.small)
                    .disabled(!canPasteToken)
                    .hoverFeedback(scale: 1.03)
            }

            HStack(spacing: Spacing.sm) {
                Button {
                    connectDebrid()
                } label: {
                    if environment.debridAuth.isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Connect Real-Debrid")
                    }
                }
                .buttonStyle(BrandButtonStyle())
                .hoverFeedback(scale: 1.03)
                .disabled(!canConnect)
                .opacity(canConnect ? 1 : 0.5)

                Button("Get a Token") {
                    openTokenPage()
                }
                .buttonStyle(GlassButtonStyle())
                .hoverFeedback(scale: 1.03)
            }
            .padding(.top, Spacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func connectedDebridContent(_ account: DebridAccount) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.green)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.username)
                        .font(AppFont.sectionTitle)
                    Text(account.isPremium ? "Premium account" : "Free account")
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Spacing.sm)

                Pill(
                    text: account.isPremium ? String(localized: "Premium") : String(localized: "Free"),
                    systemImage: account.isPremium ? "star.fill" : nil,
                    tint: account.isPremium ? .green : .secondary
                )
            }

            Button("Disconnect", role: .destructive) {
                Task { await environment.debridAuth.disconnect() }
            }
            .controlSize(.small)
            .hoverFeedback(scale: 1.03)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canConnect: Bool {
        !tokenInput.trimmingCharacters(in: .whitespaces).isEmpty
            && !environment.debridAuth.isConnecting
    }

    private var canPasteToken: Bool {
        NSPasteboard.general.canReadItem(
            withDataConformingToTypes: [NSPasteboard.PasteboardType.string.rawValue]
        )
    }

    private func pasteToken() {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        tokenInput = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func connectDebrid() {
        let token = tokenInput
        tokenInput = ""
        Task { await environment.debridAuth.connect(token: token) }
    }

    private func openTokenPage() {
        guard let url = URL(string: "https://real-debrid.com/apitoken") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Addons

    @ViewBuilder
    private var addonsStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if environment.addons.installed.isEmpty {
                emptyAddonsCard
            } else {
                installedAddonsCard
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Button("Add Addon", systemImage: "plus") {
                    isAddingAddon = true
                }
                .buttonStyle(BrandButtonStyle())
                .hoverFeedback(scale: 1.03)

                Text("You can add more addons later in Settings.")
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyAddonsCard: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No addons yet")
                .font(AppFont.cardTitle)
            Text("Add at least one addon to discover sources.")
                .font(AppFont.cardMeta)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .background(
            AppColor.surface,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(AppColor.stroke, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
    }

    private var installedAddonsCard: some View {
        SettingsCard(
            title: String(localized: "Installed"),
            subtitle: String(localized: "\(environment.addons.installed.count) addons")
        ) {
            ForEach(environment.addons.installed) { addon in
                HStack(spacing: Spacing.sm) {
                    RemoteImage(
                        url: addon.iconURL,
                        contentMode: .fit,
                        placeholderSystemImage: "puzzlepiece.extension"
                    )
                    .frame(width: 32, height: 32)
                    .background(
                        Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(AppColor.stroke, lineWidth: 0.5)
                    }
                    .opacity(addon.isEnabled ? 1 : 0.55)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(addon.name)
                            .font(AppFont.cardTitle)
                        if let description = addon.description {
                            Text(description)
                                .font(AppFont.cardMeta)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: Spacing.sm)

                    Toggle(
                        "Enabled",
                        isOn: Binding(
                            get: { addon.isEnabled },
                            set: { newValue in
                                try? environment.addons.setEnabled(id: addon.id, isEnabled: newValue)
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Enable \(addon.name)")
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
        }
    }

    // MARK: - Preferences

    private var preferencesStep: some View {
        @Bindable var preferences = environment.preferences
        return VStack(alignment: .leading, spacing: Spacing.md) {
            SettingsCard(title: String(localized: "Video")) {
                SettingsSegmentedRow(
                    title: String(localized: "Preferred Quality"),
                    description: String(localized: "Nami picks this resolution when it is available."),
                    options: QualityPreference.allCases,
                    titleForOption: \.displayName,
                    selection: $preferences.preferredQuality
                )
                SettingsSegmentedRow(
                    title: String(localized: "Quality Balance"),
                    options: QualityBalance.allCases,
                    titleForOption: \.displayName,
                    selection: $preferences.qualityBalance
                )
            }

            SettingsCard(title: String(localized: "Language")) {
                SettingsDropdownRow(
                    title: String(localized: "Preferred Audio"),
                    systemImage: "speaker.wave.2",
                    options: AudioPreference.allCases.map {
                        SettingsDropdownOption(value: $0, label: $0.displayName)
                    },
                    selection: $preferences.preferredAudio
                )
                SettingsDropdownRow(
                    title: String(localized: "Preferred Subtitles"),
                    systemImage: "captions.bubble",
                    options: SubtitlePreference.allCases.map {
                        SettingsDropdownOption(value: $0, label: $0.displayName)
                    },
                    selection: $preferences.preferredSubtitles
                )
            }

            SettingsCard(title: String(localized: "Playback")) {
                SettingsToggleRow(
                    title: String(localized: "Autoplay Next Episode"),
                    isOn: $preferences.autoplayNextEpisode
                )
                SettingsToggleRow(
                    title: String(localized: "Skip Intro and Outro"),
                    description: String(localized: "Uses AniSkip timings when they are available."),
                    isOn: $preferences.skipIntroEnabled
                )
            }

            Text("Fine-tune everything later in Settings.")
                .font(AppFont.cardMeta)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Ready

    @ViewBuilder
    private var readyStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SettingsCard {
                summaryRow(
                    systemImage: "bolt.fill",
                    title: String(localized: "Real-Debrid"),
                    value: environment.debridAuth.account?.username ?? String(localized: "Not connected"),
                    isComplete: environment.debridAuth.isConnected
                )
                summaryRow(
                    systemImage: "puzzlepiece.extension.fill",
                    title: String(localized: "Addons"),
                    value: addonSummary,
                    isComplete: !environment.addons.enabledAddons.isEmpty
                )
                summaryRow(
                    systemImage: "slider.horizontal.3",
                    title: String(localized: "Preferences"),
                    value: preferenceSummary,
                    isComplete: true
                )
            }

            Text("You can revisit any of these at any time from Settings.")
                .font(AppFont.cardMeta)
                .foregroundStyle(.tertiary)
        }
    }

    private var addonSummary: String {
        let count = environment.addons.enabledAddons.count
        switch count {
        case 0: return String(localized: "None added")
        default: return String(localized: "\(count) enabled")
        }
    }

    private var preferenceSummary: String {
        let preferences = environment.preferences
        return String(localized: "\(preferences.preferredQuality.displayName) \u{00B7} \(preferences.preferredAudio.displayName) audio")
    }

    private func summaryRow(
        systemImage: String,
        title: String,
        value: String,
        isComplete: Bool
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 17))
                .foregroundStyle(isComplete ? Color.green : Color.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppFont.cardTitle)
                Text(value)
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.sm)

            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AppColor.stroke)
                .frame(height: 0.5)

            HStack(spacing: Spacing.sm) {
                if flow.isFirst {
                    Button("Skip Setup") {
                        finish()
                    }
                    .buttonStyle(.plain)
                    .font(AppFont.cardTitle)
                    .foregroundStyle(.secondary)
                    .hoverFeedback(brightness: 0.2)
                } else if !flow.isLast {
                    Button("Skip") {
                        finish()
                    }
                    .buttonStyle(.plain)
                    .font(AppFont.cardTitle)
                    .foregroundStyle(.secondary)
                    .hoverFeedback(brightness: 0.2)
                }

                Spacer()

                if !flow.isFirst {
                    Button("Back") {
                        flow.back()
                    }
                    .buttonStyle(GlassButtonStyle())
                    .hoverFeedback(scale: 1.03)
                }

                Button(primaryTitle) {
                    if flow.isLast {
                        finish()
                    } else {
                        flow.advance()
                    }
                }
                .buttonStyle(BrandButtonStyle())
                .hoverFeedback(scale: 1.03)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.md)
        }
    }

    private var primaryTitle: String {
        switch flow.step {
        case .welcome: String(localized: "Get Started")
        case .ready: String(localized: "Start Watching")
        default: String(localized: "Continue")
        }
    }

    private func finish() {
        environment.preferences.hasCompletedOnboarding = true
    }
}

// MARK: - Header components

private struct OnboardingStepHeader: View {
    let step: OnboardingFlow.Step

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(step.title)
                .font(.system(size: 25, weight: .bold))
            Text(step.subtitle)
                .font(AppFont.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct SetupRail: View {
    let flow: OnboardingFlow
    let completedSteps: Set<OnboardingFlow.Step>
    let onSelect: (OnboardingFlow.Step) -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(OnboardingFlow.setupSteps) { step in
                railItem(step)
                if step != OnboardingFlow.setupSteps.last {
                    connector(after: step)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func railItem(_ step: OnboardingFlow.Step) -> some View {
        let isCurrent = step == flow.step
        let isComplete = completedSteps.contains(step)
        let canSelect = flow.canJump(to: step)

        return Button {
            guard canSelect else { return }
            onSelect(step)
        } label: {
            HStack(spacing: Spacing.xxs + 2) {
                Image(systemName: isComplete ? "checkmark" : step.systemImage)
                    .font(.system(size: 11, weight: .bold))

                Text(step.shortTitle)
                    .font(AppFont.cardMeta.weight(.medium))
            }
            .foregroundStyle(foreground(isCurrent: isCurrent, isComplete: isComplete))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(
                isCurrent ? AppColor.buttonFill : Color.primary.opacity(0.05),
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(AppColor.stroke, lineWidth: 0.5)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canSelect)
        .hoverFeedback(opacity: canSelect ? 1 : 0.55, shadowRadius: canSelect ? 6 : 0, shadowY: canSelect ? 2 : 0)
        .accessibilityLabel(step.shortTitle)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    private func connector(after step: OnboardingFlow.Step) -> some View {
        Rectangle()
            .fill(completedSteps.contains(step)
                ? AppColor.brand.opacity(0.5)
                : AppColor.stroke)
            .frame(maxWidth: .infinity)
            .frame(height: 1)
    }

    private func foreground(isCurrent: Bool, isComplete: Bool) -> Color {
        if isCurrent { return AppColor.buttonLabel }
        if isComplete { return AppColor.brand }
        return .secondary
    }
}

#if DEBUG
#Preview("Onboarding") {
    OnboardingView()
        .environment(AppEnvironment.preview())
}
#endif
