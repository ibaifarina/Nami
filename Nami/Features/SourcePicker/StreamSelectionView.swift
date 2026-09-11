import SwiftUI

struct StreamSelectionView: View {
    let request: PlaybackRequest

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
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
        .task {
            if case .loading = model.phase {
                await model.start()
            }
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
                Text(request.anime.displayTitle)
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
            loadingView
        case .picker:
            pickerView
        case .started:
            loadingView
        case .failed(let message):
            ErrorStateView(
                title: message,
                message: nil,
                onRetry: { Task { await model.retry() } },
                secondaryTitle: "Open Settings",
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
            Text("Checking \(model.enabledAddonCount) enabled addon\(model.enabledAddonCount == 1 ? "" : "s")")
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
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if let decision = model.decision,
                       !decision.shouldAutoPlay,
                       !request.prefersManualSelection {
                        Text("We couldn't confidently choose a source. Pick one below.")
                            .font(AppFont.body)
                            .foregroundStyle(.secondary)
                    }

                    if let best = model.bestMatch {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            SectionHeader(title: "Best Match")
                            SourceRow(
                                scored: best,
                                isBest: true,
                                isResolving: model.resolvingCandidateID == best.candidate.id,
                                showDebug: model.showDebugInfo,
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
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            SectionHeader(
                                title: "Other Sources",
                                subtitle: "\(model.otherStreams.count) more option\(model.otherStreams.count == 1 ? "" : "s")"
                            )
                            ForEach(model.otherStreams) { scored in
                                SourceRow(
                                    scored: scored,
                                    isResolving: model.resolvingCandidateID == scored.candidate.id,
                                    showDebug: model.showDebugInfo,
                                    onSelect: { Task { await model.choose(scored) } }
                                )
                            }
                        }
                    }

                    if !model.rejectedStreams.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            SectionHeader(
                                title: "Low Confidence",
                                subtitle: "These aren't auto-selected. Choose manually only if you're sure."
                            )
                            ForEach(model.rejectedStreams) { scored in
                                SourceRow(
                                    scored: scored,
                                    isResolving: model.resolvingCandidateID == scored.candidate.id,
                                    showDebug: model.showDebugInfo,
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
                }
                .padding(.bottom, Spacing.xs)
            }
        }
    }

    @ViewBuilder
    private var emptyResultsView: some View {
        if model.enabledAddonCount == 0 {
            VStack(spacing: Spacing.md) {
                EmptyStateView(
                    systemImage: "puzzlepiece.extension",
                    title: "No streaming addons are configured",
                    message: "Add a compatible streaming addon in Settings to discover sources for this episode.",
                    actionTitle: "Open Addon Settings",
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
                    title: "No playable sources were found for this episode",
                    message: model.addonFailureMessages.isEmpty
                        ? "Try again, or add more addons in Settings."
                        : "Some addons failed to respond. Try again in a moment.",
                    actionTitle: "Try Again",
                    action: { Task { await model.retry() } }
                )
                Button("Close") { dismiss() }
                    .hoverFeedback(scale: 1.03)
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
                        hasTorrentSource: hasTorrentSource
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
                Pill(text: "BEST", systemImage: "star.fill", tint: AppColor.brand)
            }
        }
    }

    private var headlineRest: String {
        var parts: [String] = []
        if let source = scored.candidate.source { parts.append(source.label) }
        if let codec = scored.candidate.codec { parts.append(codec.label) }
        if parts.isEmpty, scored.candidate.resolution == nil { parts.append("Unknown quality") }
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

    private var footer: String {
        var parts = scored.candidate.sources.map(\.addonName)
        if let group = scored.candidate.releaseGroup, !group.isEmpty {
            parts.append(group)
        }
        if !scored.candidate.audioLanguages.isEmpty {
            parts.append(scored.candidate.audioLanguages.sorted().joined(separator: "/"))
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
        return "score \(Int(breakdown.total)) "
            + "ep \(Int(breakdown.episodeMatch)) "
            + "cache \(Int(breakdown.cached)) "
            + "res \(Int(breakdown.resolution)) "
            + "src \(Int(breakdown.source)) "
            + "size \(Int(breakdown.size)) "
            + "seed \(Int(breakdown.seeders)) "
            + "lang \(Int(breakdown.language)) "
            + "pen \(Int(breakdown.penalties))"
    }

    private var advancedDetails: String? {
        var parts: [String] = []
        if let hash = scored.candidate.infoHash {
            parts.append("hash \(hash)")
        }
        if let magnet = scored.candidate.magnetURI?.absoluteString {
            parts.append("magnet \(magnet)")
        }
        if let url = scored.candidate.directURL?.absoluteString {
            parts.append("url \(url)")
        }
        if let fileIndex = scored.candidate.fileIndex {
            parts.append("file #\(fileIndex)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private var accessibilityText: String {
        [
            scored.candidate.resolution?.label,
            headlineRest,
            sizeText,
            scored.candidate.seeders.map { "\($0) seeders" },
            footer,
            CacheIndicator.label(for: scored.candidate.debridStatus, hasTorrentSource: hasTorrentSource),
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }
}

private struct CacheIndicator: View {
    let status: DebridAvailability
    let hasTorrentSource: Bool

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
            "Cached on Real-Debrid"
        case .notCached:
            "Not cached, Real-Debrid will download it first"
        case .unavailable:
            "Unavailable on Real-Debrid"
        case .unknown:
            hasTorrentSource
                ? "Cache status unknown"
                : "Direct stream, cache status doesn't apply"
        }
    }

    private var symbol: String {
        switch status {
        case .cached: "bolt.fill"
        case .notCached: "bolt.slash"
        case .unavailable: "bolt.slash.fill"
        case .unknown: "bolt"
        }
    }

    private var tint: Color {
        switch status {
        case .cached: .green
        case .notCached: .secondary
        case .unavailable: .red.opacity(0.85)
        case .unknown: .secondary.opacity(0.55)
        }
    }

    private var background: Color {
        status == .cached ? .green.opacity(0.14) : .clear
    }

    private var description: String {
        Self.label(for: status, hasTorrentSource: hasTorrentSource)
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
