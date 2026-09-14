import SwiftUI

struct StreamSelectionView: View {
    let request: PlaybackRequest

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @Environment(\.animeTitleLanguage) private var titleLanguage
    @State private var model: StreamSelectionViewModel

    init(request: PlaybackRequest, environment: AppEnvironment) {
        self.request = request
        _model = State(initialValue: StreamSelectionViewModel(request: request, environment: environment))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            Divider()
            content
        }
        .padding(Spacing.xl)
        .frame(width: 600, height: 560)
        .task(id: environment.addons.revision) {
            await model.refreshForAddonChange()
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .started {
                dismiss()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Color.clear
                .aspectRatio(Layout.posterAspectRatio, contentMode: .fit)
                .frame(width: 64)
                .overlay {
                    RemoteImage(url: request.anime.posterURL, contentMode: .fill)
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(AppColor.stroke, lineWidth: 0.5)
                }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(request.anime.displayTitle(for: titleLanguage))
                    .font(AppFont.sectionTitle)
                    .lineLimit(2)
                Text("Episode \(request.episodeNumber)")
                    .font(AppFont.cardMeta.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            Spacer()
            Button("Close") {
                dismiss()
            }
            .hoverFeedback(scale: 1.03)
            .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            if model.isChoosingFile {
                filePickerView
            } else if model.hasAnyCandidates {
                pickerView
            } else {
                loadingView
            }
        case .picker:
            if model.isChoosingFile {
                filePickerView
            } else {
                pickerView
            }
        case .started:
            loadingView
        case .failed(let message):
            ErrorStateView(
                title: message,
                message: nil,
                onRetry: { Task { await model.retry() } },
                secondaryTitle: String(localized: "Open Settings"),
                onSecondary: { openSettings() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var loadingView: some View {
        VStack(spacing: Spacing.sm) {
            LoadingSpinner(size: 32, lineWidth: 3)
            Text("Searching for the best source\u{2026}")
                .font(AppFont.body)
            Text("Checking \(model.enabledAddonCount) enabled addons")
                .font(AppFont.cardMeta)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var pickerView: some View {
        if !model.hasAnyCandidates {
            emptyResultsView
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                    if let decision = model.decision,
                       !decision.shouldAutoPlay,
                       !model.isDiscovering,
                       !request.prefersManualSelection {
                        Text("We couldn't confidently choose a source. Pick one below.")
                            .font(AppFont.body)
                            .foregroundStyle(.secondary)
                    }

                    if let best = model.bestMatch {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            SectionHeader(title: String(localized: "Best Match"))
                            SourceRow(
                                scored: best,
                                isBest: true,
                                isResolving: model.resolvingCandidateID == best.candidate.id,
                                showDebug: model.showDebugInfo,
                                preferredAudio: environment.preferences.preferredAudio.languageCode,
                                preferredSubtitles: environment.preferences.preferredSubtitles.languageCode,
                                onSelect: { Task { await model.choose(best) } }
                            )
                            if model.showDebugInfo, let decision = model.decision {
                                WhyThisStreamView(
                                    reasons: decision.reasons,
                                    breakdown: best.breakdown,
                                    confidence: decision.confidence
                                )
                            }
                        }
                    }

                    if !model.otherStreams.isEmpty {
                        LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                            SectionHeader(
                                title: String(localized: "Other Sources"),
                                subtitle: String(localized: "\(model.otherSourceCount) more options")
                            )
                            ForEach(model.otherStreams) { scored in
                                SourceRow(
                                    scored: scored,
                                    isResolving: model.resolvingCandidateID == scored.candidate.id,
                                    showDebug: model.showDebugInfo,
                                    preferredAudio: environment.preferences.preferredAudio.languageCode,
                                    preferredSubtitles: environment.preferences.preferredSubtitles.languageCode,
                                    onSelect: { Task { await model.choose(scored) } }
                                )
                            }
                        }
                    }

                    if !model.visibleRejectedStreams.isEmpty {
                        LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                            SectionHeader(
                                title: String(localized: "Low Confidence"),
                                subtitle: String(localized: "These aren't auto-selected. Choose manually only if you're sure.")
                            )
                            ForEach(model.visibleRejectedStreams) { scored in
                                SourceRow(
                                    scored: scored,
                                    isResolving: model.resolvingCandidateID == scored.candidate.id,
                                    showDebug: model.showDebugInfo,
                                    preferredAudio: environment.preferences.preferredAudio.languageCode,
                                    preferredSubtitles: environment.preferences.preferredSubtitles.languageCode,
                                    onSelect: { Task { await model.choose(scored) } }
                                )
                                .opacity(0.75)
                            }
                        }
                    }

                    if !model.addonFailureMessages.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            ForEach(model.addonFailureMessages, id: \.self) { message in
                                Text(message)
                                    .font(AppFont.cardMeta)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    if model.hasMoreSources {
                        HStack(spacing: Spacing.xs) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Showing \(model.visibleSourceLimit) of \(model.totalSourceCount) sources")
                                .font(AppFont.cardMeta)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xs)
                        .id(model.visibleSourceLimit)
                        .onAppear { model.showMoreSources() }
                    }
                }
                .padding(.bottom, Spacing.xs)
            }
        }
    }

    @ViewBuilder
    private var filePickerView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(
                title: String(localized: "Choose a file"),
                subtitle: String(localized: "This source contains \(model.pendingFiles.count) video files. Pick the one to play.")
            )

            ScrollView {
                VStack(spacing: Spacing.sm) {
                    ForEach(model.pendingFiles, id: \.id) { file in
                        MovieFileRow(
                            file: file,
                            isResolving: model.resolvingCandidateID == model.pendingFileCandidate?.id,
                            isLargest: file.id == largestFileID,
                            onSelect: { Task { await model.chooseFile(file) } }
                        )
                    }
                }
                .padding(.bottom, Spacing.xs)
            }

            HStack {
                Button("Back") {
                    model.cancelFileSelection()
                }
                .hoverFeedback(scale: 1.03)
                Spacer()
                Text("Parts are often labelled by episode number or size.")
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var largestFileID: Int? {
        model.pendingFiles.max(by: { $0.bytes < $1.bytes })?.id
    }

    @ViewBuilder
    private var emptyResultsView: some View {
        if model.enabledAddonCount == 0 {
            VStack(spacing: Spacing.md) {
                EmptyStateView(
                    systemImage: "puzzlepiece.extension",
                    title: String(localized: "No streaming addons are configured"),
                    message: String(localized: "Add a compatible streaming addon in Settings to discover sources for this episode."),
                    actionTitle: String(localized: "Open Addon Settings"),
                    action: { openSettings() }
                )
                Button("Close") { dismiss() }
                    .hoverFeedback(scale: 1.03)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: Spacing.md) {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: String(localized: "No playable sources were found for this episode"),
                    message: model.addonFailureMessages.isEmpty
                        ? String(localized: "Try again, or add more addons in Settings.")
                        : String(localized: "Some addons failed to respond. Try again in a moment."),
                    actionTitle: String(localized: "Try Again"),
                    action: { Task { await model.retry() } }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

}

private struct SourceRow: View {
    let scored: ScoredStream
    var isBest = false
    var isResolving = false
    var showDebug = false
    var preferredAudio: String?
    var preferredSubtitles: String?
    var onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    headlineRow
                    if sizeText != nil || seedersText != nil {
                        HStack(spacing: Spacing.sm) {
                            if let sizeText {
                                metadataLabel(sizeText, systemImage: "internaldrive")
                            }
                            if let seedersText {
                                metadataLabel(seedersText, systemImage: "person.2.fill")
                            }
                        }
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.secondary)
                    }
                    if !audioLanguages.isEmpty {
                        languageRow(
                            kind: .audio,
                            languages: audioLanguages,
                            preferred: preferredAudio
                        )
                    }
                    if !subtitleLanguages.isEmpty {
                        languageRow(
                            kind: .subtitle,
                            languages: subtitleLanguages,
                            preferred: preferredSubtitles
                        )
                    }
                    if !footer.isEmpty {
                        Text(footer)
                            .font(AppFont.cardMeta)
                            .foregroundStyle(.tertiary)
                    }
                    if !scored.isAutoEligible {
                        Label(
                            scored.rejectionReasons.joined(separator: " \u{00B7} "),
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.orange)
                    }
                    if showDebug {
                        Text(debugLine)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        if let advancedDetails {
                            Text(advancedDetails)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(4)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                }
                Spacer(minLength: Spacing.xs)
                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    CacheIndicator(
                        status: scored.candidate.debridStatus,
                        hasTorrentSource: hasTorrentSource,
                        isCachedHint: scored.candidate.isCachedHint
                    )
                    if isResolving {
                        LoadingSpinner(size: 16, lineWidth: 2)
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                cardBackground,
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(cardBorder, lineWidth: isBest ? 1 : 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: Motion.hover)) {
                isHovering = hovering
            }
        }
        .disabled(isResolving)
        .accessibilityLabel(accessibilityText)
    }

    private var headlineRow: some View {
        HStack(spacing: Spacing.xs) {
            if let resolution = scored.candidate.resolution {
                Text(resolution.label)
                    .font(AppFont.cardTitle.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, Spacing.xs - 2)
                    .padding(.vertical, 1)
                    .background(
                        Color.primary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: Radius.control - 2, style: .continuous)
                    )
            }
            if !headlineRest.isEmpty {
                Text(headlineRest)
                    .font(AppFont.cardTitle)
                    .foregroundStyle(.secondary)
            }
            if isBest {
                Pill(text: String(localized: "BEST"), systemImage: "star.fill", tint: AppColor.brand)
            }
        }
    }

    private var headlineRest: String {
        var parts: [String] = []
        if let source = scored.candidate.source { parts.append(source.label) }
        if let codec = scored.candidate.codec { parts.append(codec.label) }
        if let dynamicRange = scored.candidate.dynamicRange { parts.append(dynamicRange.label) }
        if parts.isEmpty, scored.candidate.resolution == nil { parts.append(String(localized: "Unknown quality")) }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var sizeText: String? {
        guard let size = scored.candidate.sizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private var seedersText: String? {
        guard let seeders = scored.candidate.seeders else { return nil }
        return "\(seeders)"
    }

    private func metadataLabel(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .monospacedDigit()
        }
    }

    private var audioLanguages: [String] {
        sortedLanguages(scored.candidate.audioLanguages, preferred: preferredAudio)
    }

    private var subtitleLanguages: [String] {
        sortedLanguages(scored.candidate.subtitleLanguages, preferred: preferredSubtitles)
    }

    private func languageRow(
        kind: LanguageTag.Kind,
        languages: [String],
        preferred: String?
    ) -> some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(languages, id: \.self) { language in
                LanguageTag(
                    language: language,
                    kind: kind,
                    isPreferred: language == preferred
                )
            }
        }
    }

    private func sortedLanguages(_ languages: Set<String>, preferred: String?) -> [String] {
        languages.sorted { lhs, rhs in
            if lhs == preferred { return true }
            if rhs == preferred { return false }
            return LanguageDetector.displayName(for: lhs) < LanguageDetector.displayName(for: rhs)
        }
    }

    private var footer: String {
        var parts = scored.candidate.sources.map(\.addonName)
        if let group = scored.candidate.releaseGroup, !group.isEmpty {
            parts.append(group)
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var hasTorrentSource: Bool {
        scored.candidate.infoHash != nil || scored.candidate.magnetURI != nil
    }

    private var cardBackground: Color {
        let resting = isBest ? 0.065 : 0.035
        let hovering = isBest ? 0.10 : 0.075
        return Color.primary.opacity(isHovering ? hovering : resting)
    }

    private var cardBorder: Color {
        if isBest {
            return Color.primary.opacity(isHovering ? 0.32 : 0.2)
        }
        return isHovering ? Color.primary.opacity(0.16) : AppColor.stroke
    }

    private var debugLine: String {
        let breakdown = scored.breakdown
        return String(localized: "score \(Int(breakdown.total)) ")
            + String(localized: "ep \(Int(breakdown.episodeMatch)) ")
            + String(localized: "cache \(Int(breakdown.cached)) ")
            + String(localized: "res \(Int(breakdown.resolution)) ")
            + String(localized: "src \(Int(breakdown.source)) ")
            + String(localized: "size \(Int(breakdown.size)) ")
            + String(localized: "seed \(Int(breakdown.seeders)) ")
            + String(localized: "pen \(Int(breakdown.penalties))")
    }

    private var advancedDetails: String? {
        var parts: [String] = []
        if let hash = scored.candidate.infoHash {
            parts.append(String(localized: "hash \(hash)"))
        }
        if let magnet = scored.candidate.magnetURI?.absoluteString {
            parts.append(String(localized: "magnet \(magnet)"))
        }
        if let url = scored.candidate.directURL?.absoluteString {
            parts.append(String(localized: "url \(url)"))
        }
        if let fileIndex = scored.candidate.fileIndex {
            parts.append(String(localized: "file #\(fileIndex)"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private var accessibilityText: String {
        [
            scored.candidate.resolution?.label,
            headlineRest,
            sizeText,
            scored.candidate.seeders.map { String(localized: "\($0) seeders") },
            languageAccessibilityText,
            footer,
            CacheIndicator.label(for: scored.candidate.debridStatus, hasTorrentSource: hasTorrentSource),
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    private var languageAccessibilityText: String? {
        var parts: [String] = []
        if !audioLanguages.isEmpty {
            parts.append(
                LanguageTag.Kind.audio.label
                    + ": "
                    + audioLanguages.map { LanguageDetector.displayName(for: $0) }.joined(separator: ", ")
            )
        }
        if !subtitleLanguages.isEmpty {
            parts.append(
                LanguageTag.Kind.subtitle.label
                    + ": "
                    + subtitleLanguages.map { LanguageDetector.displayName(for: $0) }.joined(separator: ", ")
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

private struct LanguageTag: View {
    enum Kind {
        case audio
        case subtitle

        var systemImage: String {
            switch self {
            case .audio: "speaker.wave.2.fill"
            case .subtitle: "captions.bubble.fill"
            }
        }

        var label: String {
            switch self {
            case .audio: String(localized: "Audio")
            case .subtitle: String(localized: "Subtitles")
            }
        }
    }

    let language: String
    let kind: Kind
    var isPreferred = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 9, weight: .semibold))
            Text(LanguageDetector.shortCode(for: language))
                .font(AppFont.cardMeta.weight(.semibold).monospaced())
        }
        .foregroundStyle(isPreferred ? Color.primary : Color.secondary)
        .padding(.horizontal, Spacing.xs - 2)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(Color.primary.opacity(isPreferred ? 0.12 : 0.05))
        )
        .help(description)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
    }

    private var description: String {
        kind.label + " \u{00B7} " + LanguageDetector.displayName(for: language)
    }
}

private struct MovieFileRow: View {
    let file: DebridFileInfo
    var isResolving = false
    var isLargest = false
    var onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                Image(systemName: "film")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.filename)
                        .font(AppFont.cardTitle)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: Spacing.xs) {
                        if let sizeText {
                            Text(sizeText)
                                .monospacedDigit()
                        }
                        Text(subtitle)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: Spacing.xs)
                if isLargest {
                    Pill(text: String(localized: "LARGEST"))
                }
                if isResolving {
                    LoadingSpinner(size: 16, lineWidth: 2)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.primary.opacity(isHovering ? 0.075 : 0.035),
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(
                        isHovering ? Color.primary.opacity(0.16) : AppColor.stroke,
                        lineWidth: 0.5
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: Motion.hover)) {
                isHovering = hovering
            }
        }
        .disabled(isResolving)
        .accessibilityLabel(accessibilityText)
    }

    private var sizeText: String? {
        guard file.bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: file.bytes, countStyle: .file)
    }

    private var subtitle: String {
        file.path == file.filename ? String(localized: "Video file") : file.path
    }

    private var accessibilityText: String {
        [file.filename, sizeText, isLargest ? String(localized: "largest file") : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

private struct CacheIndicator: View {
    let status: DebridAvailability
    let hasTorrentSource: Bool
    var isCachedHint = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .background(background, in: Circle())
            .help(description)
            .accessibilityLabel(description)
    }

    static func label(for status: DebridAvailability, hasTorrentSource: Bool) -> String {
        switch status {
        case .cached:
            String(localized: "Cached on Real-Debrid")
        case .notCached:
            String(localized: "Not cached, Real-Debrid will download it first")
        case .unavailable:
            String(localized: "Unavailable on Real-Debrid")
        case .unknown:
            hasTorrentSource
                ? String(localized: "Cache status unknown")
                : String(localized: "Direct stream, cache status doesn't apply")
        }
    }

    private var symbol: String {
        switch status {
        case .cached: "bolt.fill"
        case .notCached: "bolt.slash"
        case .unavailable: "bolt.slash.fill"
        case .unknown: isCachedHint ? "bolt.fill" : "bolt"
        }
    }

    private var tint: Color {
        switch status {
        case .cached: .green
        case .notCached: .secondary
        case .unavailable: .red.opacity(0.85)
        case .unknown: isCachedHint ? .yellow : .secondary.opacity(0.55)
        }
    }

    private var background: Color {
        if status == .cached { return .green.opacity(0.14) }
        if status == .unknown, isCachedHint { return .yellow.opacity(0.14) }
        return .clear
    }

    private var description: String {
        if status == .unknown, isCachedHint {
            return String(localized: "The addon lists this source as cached; not yet verified")
        }
        return Self.label(for: status, hasTorrentSource: hasTorrentSource)
    }
}

private struct WhyThisStreamView: View {
    let reasons: [ScoreReason]
    let breakdown: StreamScoreBreakdown
    let confidence: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack {
                Text("Why this stream?")
                    .font(AppFont.cardTitle)
                Spacer()
                Text("\(Int((confidence * 100).rounded()))% confidence")
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.secondary)
            }
            ForEach(reasons) { reason in
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: icon(for: reason.kind))
                        .font(.system(size: 10, weight: .semibold))
                    Text(reason.text)
                    Spacer()
                }
                .font(AppFont.cardMeta)
                .foregroundStyle(color(for: reason.kind))
            }
            Text("Total score \(Int(breakdown.total))")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(Spacing.sm)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
    }

    private func icon(for kind: ScoreReason.Kind) -> String {
        switch kind {
        case .positive: "checkmark"
        case .caution: "exclamationmark"
        case .negative: "xmark"
        }
    }

    private func color(for kind: ScoreReason.Kind) -> Color {
        switch kind {
        case .positive: .secondary
        case .caution: .orange
        case .negative: .red
        }
    }
}

#if DEBUG
#Preview("Source Picker") {
    let environment = AppEnvironment.preview()
    StreamSelectionView(
        request: PlaybackRequest(anime: PreviewFixtures.anime, episodeNumber: 7),
        environment: environment
    )
    .environment(environment)
}
#endif
