import SwiftUI

struct PlaybackSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var preferences = environment.preferences
        Form {
            Section("Episodes") {
                Toggle("Autoplay Next Episode", isOn: $preferences.autoplayNextEpisode)
                Text("When an episode nears its end, the next one is prepared and can start automatically.")
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.secondary)
            }
            Section("Player") {
                Text("Player controls, subtitle styling, and playback quality options will appear here once the player is available.")
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
