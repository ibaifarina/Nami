import SwiftUI

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openSettings) private var openSettings
    @State private var flow = OnboardingFlow()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            header
            Group {
                switch flow.step {
                case .welcome:
                    welcomeStep
                case .realDebrid:
                    serviceStep(
                        systemImage: "bolt",
                        connected: environment.debridAuth.isConnected,
                        connectedDetail: environment.debridAuth.account?.username,
                        description: "Resolve torrent and hoster sources and start cached streams instantly. Without it you can still play direct sources.",
                        settingsHint: "Settings \u{203A} Real-Debrid"
                    )
                case .addons:
                    addonsStep
                case .preferences:
                    preferencesStep
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            footer
        }
        .padding(Spacing.xxl)
        .frame(width: 580, height: 470)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(flow.step.title)
                .font(AppFont.screenTitle)
            Text("Step \(flow.stepNumber) of \(flow.stepCount)")
                .font(AppFont.cardMeta)
                .foregroundStyle(.secondary)
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AppColor.brand)
            Text("A premium anime streaming experience for your Mac.")
                .font(AppFont.body)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                bullet("Discover anime with Kitsu metadata")
                bullet("Play the best source automatically")
                bullet("Resume exactly where you left off")
            }
        }
    }

    private func serviceStep(
        systemImage: String,
        connected: Bool,
        connectedDetail: String?,
        description: String,
        settingsHint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(connected ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connected ? "Connected" : "Not connected")
                        .font(AppFont.cardTitle)
                    if let connectedDetail {
                        Text(connectedDetail)
                            .font(AppFont.cardMeta)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text(description)
                .font(AppFont.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !connected {
                Button("Open \(settingsHint)") {
                    openSettings()
                }
                .buttonStyle(BrandButtonStyle())
                .hoverFeedback(scale: 1.03)
            }
        }
    }

    private var addonsStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.title2)
                    .foregroundStyle(environment.addons.enabledAddons.isEmpty ? Color.secondary : Color.green)
                Text(
                    environment.addons.enabledAddons.isEmpty
                        ? "No addons configured"
                        : "\(environment.addons.enabledAddons.count) addon\(environment.addons.enabledAddons.count == 1 ? "" : "s") enabled"
                )
                .font(AppFont.cardTitle)
            }
            Text("Addons provide stream sources. Add a compatible addon by entering its manifest URL. The app never bundles content.")
                .font(AppFont.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings \u{203A} Addons") {
                openSettings()
            }
            .buttonStyle(BrandButtonStyle())
            .hoverFeedback(scale: 1.03)
        }
    }

    private var preferencesStep: some View {
        @Bindable var preferences = environment.preferences
        return VStack(alignment: .leading, spacing: Spacing.md) {
            Text("These can be changed anytime in Settings.")
                .font(AppFont.body)
                .foregroundStyle(.secondary)
            Picker("Preferred Quality", selection: $preferences.preferredQuality) {
                ForEach(QualityPreference.allCases) { quality in
                    Text(quality.displayName).tag(quality)
                }
            }
            Picker("Quality Preference", selection: $preferences.qualityBalance) {
                ForEach(QualityBalance.allCases) { balance in
                    Text(balance.displayName).tag(balance)
                }
            }
            Picker("Preferred Audio", selection: $preferences.preferredAudio) {
                ForEach(AudioPreference.allCases) { audio in
                    Text(audio.displayName).tag(audio)
                }
            }
            Picker("Preferred Subtitles", selection: $preferences.preferredSubtitles) {
                ForEach(SubtitlePreference.allCases) { subtitles in
                    Text(subtitles.displayName).tag(subtitles)
                }
            }
            Toggle("Autoplay Next Episode", isOn: $preferences.autoplayNextEpisode)
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip for now") {
                finish()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .hoverFeedback(brightness: 0.2)

            Spacer()

            if !flow.isFirst {
                Button("Back") {
                    flow.back()
                }
                .buttonStyle(GlassButtonStyle())
                .hoverFeedback(scale: 1.03)
            }
            Button(flow.isLast ? "Start Watching" : "Continue") {
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
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(AppColor.brand)
            Text(text)
                .font(AppFont.body)
        }
    }

    private func finish() {
        environment.preferences.hasCompletedOnboarding = true
    }
}

#if DEBUG
#Preview("Onboarding") {
    OnboardingView()
        .environment(AppEnvironment.preview())
}
#endif
