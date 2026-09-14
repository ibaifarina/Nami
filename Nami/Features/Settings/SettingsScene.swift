import AppKit
import SwiftUI

struct SettingsScene: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var pane: SettingsPane = .general

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $pane)
                .frame(width: 198)
                .background(AppColor.surface)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(AppColor.stroke)
                        .frame(width: 0.5)
                }

            ZStack {
                paneContent
                    .id(pane)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppColor.background)
        .frame(width: 780, height: 580)
        .containerBackground(AppColor.background, for: .window)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .animation(.easeOut(duration: Motion.transition), value: pane)
        .environment(environment)
    }

    @ViewBuilder
    private var paneContent: some View {
        switch pane {
        case .general:
            GeneralSettingsView()
        case .streaming:
            StreamingSettingsView()
        case .realDebrid:
            RealDebridSettingsView()
        case .addons:
            AddonsSettingsView()
        case .playback:
            PlaybackSettingsView()
        case .advanced:
            AdvancedSettingsView()
        }
    }
}

struct GeneralSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppLocalization.self) private var localization
    @State private var showsRestartAlert = false

    var body: some View {
        @Bindable var preferences = environment.preferences
        SettingsPaneLayout(pane: .general) {
            SettingsCard {
                aboutRow
            }
            SettingsCard(title: String(localized: "Language")) {
                SettingsDropdownRow(
                    title: String(localized: "App Language"),
                    description: String(localized: "Choose the language used across the app. Changing it restarts Nami."),
                    options: AppLanguage.allCases.map {
                        SettingsDropdownOption(value: $0, label: $0.displayName)
                    },
                    selection: languageBinding
                )
            }
            SettingsCard(title: String(localized: "Home")) {
                SettingsSegmentedRow(
                    title: String(localized: "Hero Background Blur"),
                    description: String(localized: "Softens the artwork behind the featured hero on Home and anime details."),
                    options: HeroBackgroundBlur.allCases,
                    titleForOption: \.displayName,
                    selection: $preferences.heroBackgroundBlur
                )
            }
            SettingsCard(title: String(localized: "Titles")) {
                SettingsSegmentedRow(
                    title: String(localized: "Anime Names"),
                    description: String(localized: "How anime titles are shown across the app. Original (Japanese) uses the Japanese title when available."),
                    options: AnimeTitleLanguage.allCases,
                    titleForOption: \.displayName,
                    selection: $preferences.animeTitleLanguage
                )
            }
            SettingsCard(title: String(localized: "Library")) {
                SettingsRow(
                    String(localized: "Stored on This Mac"),
                    subtitle: String(localized: "No account required"),
                    description: String(localized: "Your library and watch progress are saved locally. Nothing is uploaded.")
                ) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert("Restart Required", isPresented: $showsRestartAlert) {
            Button("Restart Now") {
                localization.relaunch()
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Nami needs to restart to apply the new language.")
        }
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { localization.language },
            set: { newLanguage in
                localization.select(newLanguage)
                showsRestartAlert = localization.requiresRestart
            }
        )
    }

    private var aboutRow: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Nami")
                    .font(AppFont.sectionTitle)
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.secondary)
                Text("Discover, stream, and keep watching \u{2014} natively on your Mac.")
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .accessibilityElement(children: .combine)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsScene()
        .environment(AppEnvironment.preview())
        .environment(AppLocalization.preview())
}
#endif
