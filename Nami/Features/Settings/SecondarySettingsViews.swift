import SwiftUI

struct PlaybackSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var detectedPlayers: [ExternalPlayer] = []

    var body: some View {
        @Bindable var preferences = environment.preferences
        SettingsPaneLayout(pane: .playback) {
            SettingsCard(title: "Episodes") {
                SettingsToggleRow(
                    title: "Autoplay Next Episode",
                    description: "When an episode nears its end, the next one is prepared and can start automatically.",
                    isOn: $preferences.autoplayNextEpisode
                )
            }
            SettingsCard(title: "Player") {
                SettingsSegmentedRow(
                    title: "Playback Engine",
                    description: "MPV plays MKV releases with styled ASS/SSA subtitles and embedded audio tracks. AVPlayer is the legacy system player and cannot play MKV.",
                    options: PlaybackEngineKind.allCases,
                    titleForOption: \.displayName,
                    selection: engineBinding
                )
            }
            SettingsCard(title: "External Player") {
                SettingsRow("Open Streams In", description: externalPlayerDescription) {
                    HStack(spacing: Spacing.xs) {
                        SettingsDropdown(
                            title: "Open Streams In",
                            options: externalPlayerOptions,
                            selection: externalPlayerBinding,
                            systemImage: "play.rectangle",
                            panelWidth: 260
                        )

                        Button {
                            refreshDetectedPlayers()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Rescan for installed players")
                        .accessibilityLabel("Rescan for installed players")
                        .hoverFeedback(scale: 1.05)
                    }
                }
            }
        }
        .task {
            refreshDetectedPlayers()
        }
    }

    private var externalPlayerOptions: [SettingsDropdownOption<String?>] {
        var options = [
            SettingsDropdownOption(
                value: String?.none,
                label: "Built-in Player",
                systemImage: "play.rectangle"
            )
        ]
        for player in detectedPlayers {
            options.append(
                SettingsDropdownOption(
                    value: String?.some(player.bundleID),
                    label: player.displayName,
                    icon: environment.externalPlayers.icon(for: player)
                )
            )
        }
        return options
    }

    private var externalPlayerDescription: String {
        detectedPlayers.isEmpty
            ? "No supported external players were found. Install VLC, IINA, or mpv to enable external playback."
            : "Streams open in the selected app instead of the built-in player. Watch progress isn't tracked for external playback."
    }

    private var externalPlayerBinding: Binding<String?> {
        Binding(
            get: { environment.preferences.externalPlayerBundleID },
            set: { environment.preferences.externalPlayerBundleID = $0 }
        )
    }

    private func refreshDetectedPlayers() {
        detectedPlayers = environment.externalPlayers.detectedPlayers()
        if let selected = environment.preferences.externalPlayerBundleID,
           !detectedPlayers.contains(where: { $0.bundleID == selected }) {
            environment.preferences.externalPlayerBundleID = nil
        }
    }

    private var engineBinding: Binding<PlaybackEngineKind> {
        Binding(
            get: { environment.preferences.playbackEngine },
            set: { kind in
                environment.preferences.playbackEngine = kind
                environment.playback.selectEngine(kind)
            }
        )
    }
}
