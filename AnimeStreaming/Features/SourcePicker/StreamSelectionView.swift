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
        .frame(width: 580, height: 540)
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

            VStack(alignment: .leading, spacing: 3) {
                Text(request.anime.displayTitle)
                    .font(AppFont.sectionTitle)
                    .lineLimit(2)
                Text("Episode \(request.episodeNumber)")
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.secondary)
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
            ProgressView()
                .controlSize(.large)
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
                            SectionHeader(title: "Other Sources")
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

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Spacing.xs) {
                        Text(headline)
                            .font(AppFont.cardTitle)
                        if isBest {
                            Pill(text: "BEST", systemImage: "star.fill", tint: AppColor.brand)
                        }
                        if scored.candidate.debridStatus == .cached {
                            Pill(text: "RD Cached", systemImage: "bolt.fill", tint: .green)
                        }
                    }
                    Text(details)
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.secondary)
                    Text(footer)
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.tertiary)
                    if !scored.isAutoEligible {
                        Text(scored.rejectionReasons.joined(separator: " \u{00B7} "))
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
                Spacer(minLength: 0)
                if isResolving {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppColor.surface,
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(
                        isBest ? AppColor.brand.opacity(0.55) : AppColor.stroke,
                        lineWidth: 0.5
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverFeedback(scale: 1.01, shadowRadius: 10, shadowY: 4)
        .disabled(isResolving)
        .accessibilityLabel(accessibilityText)
    }

    private var headline: String {
        var parts: [String] = []
        if let resolution = scored.candidate.resolution { parts.append(resolution.label) }
        if let source = scored.candidate.source { parts.append(source.label) }
        if let codec = scored.candidate.codec { parts.append(codec.label) }
        if parts.isEmpty { parts.append("Unknown quality") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var details: String {
        var parts: [String] = []
        if let size = scored.candidate.sizeBytes {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        switch scored.candidate.debridStatus {
        case .cached:
            parts.append("RD Cached")
        case .notCached:
            parts.append("Not cached")
        case .unavailable:
            parts.append("Unavailable")
        case .unknown:
            if let seeders = scored.candidate.seeders {
                parts.append("\(seeders) seeders")
            } else {
                parts.append("Cache unknown")
            }
        }
        return parts.joined(separator: " \u{00B7} ")
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
        "\(headline), \(details), \(footer)"
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
            AppColor.surfaceElevated.opacity(0.5),
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
