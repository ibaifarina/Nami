import SwiftUI

struct StreamingSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var preferences = environment.preferences
        SettingsPaneLayout(pane: .streaming) {
            SettingsCard(title: String(localized: "Stream Selection")) {
                SettingsToggleRow(
                    title: String(localized: "Auto Select Best Stream"),
                    description: String(localized: "Automatically choose the best available source so playback can start immediately."),
                    isOn: $preferences.autoSelectBestStream
                )
                SettingsToggleRow(
                    title: String(localized: "Cache Played Sources"),
                    description: String(localized: "Keeps the resolved source for each episode so returning to one starts instantly. Cached sources are kept for \(ResolvedStreamCache.maximumAgeDescription)."),
                    isOn: $preferences.cacheResolvedSources
                )
            }
            SettingsCard(title: String(localized: "Quality")) {
                SettingsSegmentedRow(
                    title: String(localized: "Preferred Quality"),
                    options: QualityPreference.allCases,
                    titleForOption: \.displayName,
                    selection: $preferences.preferredQuality
                )
                SettingsSegmentedRow(
                    title: String(localized: "Quality Preference"),
                    options: QualityBalance.allCases,
                    titleForOption: \.displayName,
                    selection: $preferences.qualityBalance
                )
                SettingsToggleRow(
                    title: String(localized: "Prefer Cached Streams"),
                    description: String(localized: "Cached sources start instantly. Uncached torrents are prepared by Real-Debrid first."),
                    isOn: $preferences.preferCachedStreams
                )
            }
            SettingsCard(title: String(localized: "Language")) {
                SettingsDropdownRow(
                    title: String(localized: "Preferred Audio"),
                    description: String(localized: "Ranks sources by their audio language and picks the default audio track."),
                    systemImage: "speaker.wave.2",
                    options: AudioPreference.allCases.map {
                        SettingsDropdownOption(value: $0, label: $0.displayName)
                    },
                    selection: $preferences.preferredAudio
                )
                SettingsDropdownRow(
                    title: String(localized: "Preferred Subtitles"),
                    description: String(localized: "Ranks sources by their subtitle language and picks the default subtitle track."),
                    systemImage: "captions.bubble",
                    options: SubtitlePreference.allCases.map {
                        SettingsDropdownOption(value: $0, label: $0.displayName)
                    },
                    selection: $preferences.preferredSubtitles
                )
            }
        }
    }
}

struct AdvancedSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var cacheMessage: String?

    var body: some View {
        @Bindable var preferences = environment.preferences
        SettingsPaneLayout(pane: .advanced) {
            SettingsCard(title: String(localized: "Auto Select")) {
                SettingsSliderRow(
                    title: String(localized: "Confidence Threshold"),
                    description: String(localized: "How certain stream scoring must be before a source is picked automatically."),
                    value: $preferences.autoSelectConfidenceThreshold,
                    range: 0.70...0.98,
                    step: 0.02,
                    valueText: { String(localized: "\(Int(($0 * 100).rounded()))%") }
                )
                SettingsStepperRow(
                    title: String(localized: "Minimum Seeders for Uncached"),
                    description: String(localized: "Uncached torrents below this seeder count are skipped."),
                    value: $preferences.minimumSeedersForUncached,
                    range: 0...50
                )
                SettingsDropdownRow(
                    title: String(localized: "Episode Size Limit"),
                    description: String(localized: "Sources larger than this are skipped for episodes. Defaults to 5 GB."),
                    systemImage: "tv",
                    options: Self.fileSizeOptions,
                    selection: $preferences.maximumEpisodeFileSizeBytes
                )
                SettingsDropdownRow(
                    title: String(localized: "Movie Size Limit"),
                    description: String(localized: "Sources larger than this are skipped for movies. Defaults to 20 GB."),
                    systemImage: "film",
                    options: Self.fileSizeOptions,
                    selection: $preferences.maximumMovieFileSizeBytes
                )
                SettingsToggleRow(
                    title: String(localized: "Show Stream Scoring Debug Info"),
                    description: String(localized: "Reveals the scoring breakdown for each source in the source picker."),
                    isOn: $preferences.showStreamScoringDebugInfo
                )
            }
            SettingsCard(title: String(localized: "Release Groups")) {
                SettingsTextFieldRow(
                    title: String(localized: "Preferred Groups"),
                    description: String(localized: "Preferred groups are boosted when ranking sources."),
                    prompt: String(localized: "Comma separated"),
                    text: preferredGroupsBinding
                )
                SettingsTextFieldRow(
                    title: String(localized: "Blocked Groups"),
                    description: String(localized: "Blocked groups are never selected automatically."),
                    prompt: String(localized: "Comma separated"),
                    text: blockedGroupsBinding
                )
            }
            SettingsCard(title: String(localized: "Caches")) {
                SettingsRow(
                    String(localized: "Cached Metadata"),
                    description: String(localized: "Cached Kitsu metadata is refreshed periodically. Clearing it forces a fresh fetch.")
                ) {
                    Button("Clear Cache") {
                        Task {
                            await environment.clearCaches()
                            withAnimation(.easeOut(duration: Motion.transition)) {
                                cacheMessage = String(localized: "Metadata cache cleared.")
                            }
                        }
                    }
                    .controlSize(.small)
                    .hoverFeedback(scale: 1.03)
                }
                if let cacheMessage {
                    SettingsBanner(kind: .success, message: cacheMessage)
                        .padding(.horizontal, Spacing.md)
                        .padding(.bottom, Spacing.sm)
                        .transition(.opacity)
                }
            }
        }
    }

    private static let fileSizeOptions: [SettingsDropdownOption<Int64>] = [
        SettingsDropdownOption(value: 0, label: String(localized: "Unlimited")),
        SettingsDropdownOption(value: 2_000_000_000, label: String(localized: "2 GB")),
        SettingsDropdownOption(value: 5_000_000_000, label: String(localized: "5 GB")),
        SettingsDropdownOption(value: 10_000_000_000, label: String(localized: "10 GB")),
        SettingsDropdownOption(value: 20_000_000_000, label: String(localized: "20 GB")),
        SettingsDropdownOption(value: 50_000_000_000, label: String(localized: "50 GB")),
    ]

    private var preferredGroupsBinding: Binding<String> {
        Binding(
            get: { environment.preferences.preferredReleaseGroups.joined(separator: ", ") },
            set: { environment.preferences.preferredReleaseGroups = Self.parseGroups($0) }
        )
    }

    private var blockedGroupsBinding: Binding<String> {
        Binding(
            get: { environment.preferences.blockedReleaseGroups.joined(separator: ", ") },
            set: { environment.preferences.blockedReleaseGroups = Self.parseGroups($0) }
        )
    }

    private static func parseGroups(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
