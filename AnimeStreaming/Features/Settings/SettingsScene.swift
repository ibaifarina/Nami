import SwiftUI

struct SettingsScene: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            StreamingSettingsView()
                .tabItem { Label("Streaming", systemImage: "play.rectangle") }
            RealDebridSettingsView()
                .tabItem { Label("Real-Debrid", systemImage: "bolt") }
            AddonsSettingsView()
                .tabItem { Label("Addons", systemImage: "puzzlepiece.extension") }
            PlaybackSettingsView()
                .tabItem { Label("Playback", systemImage: "play.circle") }
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .environment(environment)
        .frame(width: 560, height: 460)
    }
}

struct GeneralSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var preferences = environment.preferences
        Form {
            Section("About") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: buildNumber)
            }
            Section("Home") {
                Picker("Hero Background Blur", selection: $preferences.heroBackgroundBlur) {
                    ForEach(HeroBackgroundBlur.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Text("Softens the artwork behind the featured hero on Home and anime details.")
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.secondary)
            }
            Section("Library") {
                Text("Your library and watch progress are stored locally on this Mac. No account is required.")
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
}
#endif
