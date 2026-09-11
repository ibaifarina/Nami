import SwiftUI

struct StreamingSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var preferences = environment.preferences
        Form {
            Section("Stream Selection") {
                Toggle("Auto Select Best Stream", isOn: $preferences.autoSelectBestStream)
                Text("Automatically choose the best available source so playback can start immediately.")
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.secondary)
            }
            Section("Quality") {
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
                Toggle("Prefer Cached Streams", isOn: $preferences.preferCachedStreams)
            }
            Section("Language") {
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
            }
        }
        .formStyle(.grouped)
    }
}

struct AdvancedSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var cacheMessage: String?

    var body: some View {
        @Bindable var preferences = environment.preferences
        Form {
            Section("Auto Select") {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack {
                        Text("Confidence Threshold")
                        Spacer()
                        Text("\(Int((preferences.autoSelectConfidenceThreshold * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $preferences.autoSelectConfidenceThreshold, in: 0.70...0.98, step: 0.02)
                }
                Stepper(
                    "Minimum Seeders (uncached): \(preferences.minimumSeedersForUncached)",
                    value: $preferences.minimumSeedersForUncached,
                    in: 0...50
                )
                Picker("Maximum File Size", selection: $preferences.maximumFileSizeBytes) {
                    Text("Unlimited").tag(Int64(0))
                    Text("2 GB").tag(Int64(2_000_000_000))
                    Text("5 GB").tag(Int64(5_000_000_000))
                    Text("10 GB").tag(Int64(10_000_000_000))
                    Text("20 GB").tag(Int64(20_000_000_000))
                }
                Toggle("Show Stream Scoring Debug Info", isOn: $preferences.showStreamScoringDebugInfo)
            }
            Section("Release Groups") {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Preferred groups")
                    TextField("", text: preferredGroupsBinding, prompt: Text("Comma separated"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Blocked groups")
                    TextField("", text: blockedGroupsBinding, prompt: Text("Comma separated"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                }
                Text("Groups are matched against release titles. Blocked groups are never auto-selected.")
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.secondary)
            }
            Section("Caches") {
                HStack {
                    Button("Clear Cached Metadata") {
                        Task {
                            await environment.clearCaches()
                            cacheMessage = "Metadata cache cleared."
                        }
                    }
                    .hoverFeedback(scale: 1.03)
                    if let cacheMessage {
                        Text(cacheMessage)
                            .font(AppFont.cardMeta)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Cached Kitsu metadata is refreshed periodically. Clearing it forces a fresh fetch.")
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

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
