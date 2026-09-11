import SwiftUI

struct StreamingSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var preferences = environment.preferences
        SettingsPaneLayout(pane: .streaming) {
            SettingsCard(title: "Stream Selection") {
                SettingsToggleRow(
                    title: "Auto Select Best Stream",
                    description: "Automatically choose the best available source so playback can start immediately.",
                    isOn: $preferences.autoSelectBestStream
                )
                SettingsToggleRow(
                    title: "Cache Played Sources",
                    description: "Keeps the resolved source for each episode so returning to one starts instantly. Cached sources are kept for \(ResolvedStreamCache.maximumAgeDescription).",
                    isOn: $preferences.cacheResolvedSources
                )
            }
            SettingsCard(title: "Quality") {
                SettingsSegmentedRow(
                    title: "Preferred Quality",
                    options: QualityPreference.allCases,
                    titleForOption: \.displayName,
                    selection: $preferences.preferredQuality
                )
                SettingsSegmentedRow(
                    title: "Quality Preference",
                    options: QualityBalance.allCases,
                    titleForOption: \.displayName,
                    selection: $preferences.qualityBalance
                )
                SettingsToggleRow(
                    title: "Prefer Cached Streams",
                    description: "Cached sources start instantly. Uncached torrents are prepared by Real-Debrid first.",
                    isOn: $preferences.preferCachedStreams
                )
            }
            SettingsCard(title: "Language") {
                SettingsDropdownRow(
                    title: "Preferred Audio",
                    description: "Ranks sources by their audio language and picks the default audio track.",
                    systemImage: "speaker.wave.2",
                    options: AudioPreference.allCases.map {
                        SettingsDropdownOption(value: $0, label: $0.displayName)
                    },
                    selection: $preferences.preferredAudio
                )
                SettingsDropdownRow(
                    title: "Preferred Subtitles",
                    description: "Ranks sources by their subtitle language and picks the default subtitle track.",
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
            SettingsCard(title: "Auto Select") {
                SettingsSliderRow(
                    title: "Confidence Threshold",
                    description: "How certain stream scoring must be before a source is picked automatically.",
                    value: $preferences.autoSelectConfidenceThreshold,
                    range: 0.70...0.98,
                    step: 0.02,
                    valueText: { "\(Int(($0 * 100).rounded()))%" }
                )
                SettingsStepperRow(
                    title: "Minimum Seeders for Uncached",
                    description: "Uncached torrents below this seeder count are skipped.",
                    value: $preferences.minimumSeedersForUncached,
                    range: 0...50
                )
                SettingsDropdownRow(
                    title: "Episode Size Limit",
                    description: "Sources larger than this are skipped for episodes. Defaults to 5 GB.",
                    systemImage: "tv",
                    options: Self.fileSizeOptions,
                    selection: $preferences.maximumEpisodeFileSizeBytes
                )
                SettingsDropdownRow(
                    title: "Movie Size Limit",
                    description: "Sources larger than this are skipped for movies. Defaults to 20 GB.",
                    systemImage: "film",
                    options: Self.fileSizeOptions,
                    selection: $preferences.maximumMovieFileSizeBytes
                )
                SettingsToggleRow(
                    title: "Show Stream Scoring Debug Info",
                    description: "Reveals the scoring breakdown for each source in the source picker.",
                    isOn: $preferences.showStreamScoringDebugInfo
                )
            }
            SettingsCard(title: "Release Groups") {
                SettingsTextFieldRow(
                    title: "Preferred Groups",
                    description: "Preferred groups are boosted when ranking sources.",
                    prompt: "Comma separated",
                    text: preferredGroupsBinding
                )
                SettingsTextFieldRow(
                    title: "Blocked Groups",
                    description: "Blocked groups are never selected automatically.",
                    prompt: "Comma separated",
                    text: blockedGroupsBinding
                )
            }
            SettingsCard(title: "Caches") {
                SettingsRow(
                    "Cached Metadata",
                    description: "Cached Kitsu metadata is refreshed periodically. Clearing it forces a fresh fetch."
                ) {
                    Button("Clear Cache") {
                        Task {
                            await environment.clearCaches()
                            withAnimation(.easeOut(duration: Motion.transition)) {
                                cacheMessage = "Metadata cache cleared."
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
        SettingsDropdownOption(value: 0, label: "Unlimited"),
        SettingsDropdownOption(value: 2_000_000_000, label: "2 GB"),
        SettingsDropdownOption(value: 5_000_000_000, label: "5 GB"),
        SettingsDropdownOption(value: 10_000_000_000, label: "10 GB"),
        SettingsDropdownOption(value: 20_000_000_000, label: "20 GB"),
        SettingsDropdownOption(value: 50_000_000_000, label: "50 GB"),
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
