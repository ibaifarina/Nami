import SwiftUI

struct AddonsSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isAddingAddon = false
    @State private var isCheckingHealth = false
    @State private var calibrationSummaries: [String: AddonCalibrationSummary] = [:]
    @State private var recalibratingAddonID: String?

    var body: some View {
        SettingsPaneLayout(pane: .addons, scrolling: false) {
            if environment.addons.installed.isEmpty {
                EmptyStateView(
                    systemImage: "puzzlepiece.extension",
                    title: "No addons installed",
                    message: "Add a compatible streaming addon to discover sources for your anime.",
                    actionTitle: "Add Addon",
                    action: { isAddingAddon = true }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                installedContent
            }
        }
        .sheet(isPresented: $isAddingAddon) {
            AddAddonSheet()
                .environment(environment)
        }
        .task(id: environment.addons.installed) {
            await refreshCalibrationSummaries()
        }
    }

    private var installedContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                SectionHeader(
                    title: "Installed",
                    subtitle: "\(count) addon\(count == 1 ? "" : "s") \u{00B7} Drag to reorder"
                )

                Button {
                    Task { await checkAllHealth() }
                } label: {
                    if isCheckingHealth {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Check All", systemImage: "waveform.path.ecg")
                    }
                }
                .buttonStyle(GlassButtonStyle())
                .hoverFeedback(scale: 1.03)
                .disabled(isCheckingHealth)

                Button("Add Addon", systemImage: "plus") {
                    isAddingAddon = true
                }
                .buttonStyle(BrandButtonStyle())
                .hoverFeedback(scale: 1.03)
            }

            List {
                ForEach(environment.addons.installed) { addon in
                    AddonRow(
                        addon: addon,
                        calibration: calibrationSummaries[addon.id],
                        isRecalibrating: recalibratingAddonID == addon.id,
                        onRecalibrate: { Task { await recalibrate(addon) } },
                        onRemove: { Task { await remove(addon) } }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 3, leading: -Spacing.xs, bottom: 3, trailing: 0))
                    .contextMenu {
                        Button("Check Health") {
                            Task { await checkHealth(addon) }
                        }
                        Button("Recalibrate Format") {
                            Task { await recalibrate(addon) }
                        }
                        Divider()
                        Button("Move Up") {
                            try? environment.addons.move(id: addon.id, direction: .up)
                        }
                        Button("Move Down") {
                            try? environment.addons.move(id: addon.id, direction: .down)
                        }
                        Divider()
                        Button("Remove", role: .destructive) {
                            Task { await remove(addon) }
                        }
                    }
                }
                .onMove { indices, newOffset in
                    try? environment.addons.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity)
        }
    }

    private var count: Int {
        environment.addons.installed.count
    }

    private func checkHealth(_ addon: InstalledAddon) async {
        let status = await environment.addonManager.healthCheck(addon)
        try? environment.addons.updateHealth(id: addon.id, status: status)
    }

    private func checkAllHealth() async {
        isCheckingHealth = true
        defer { isCheckingHealth = false }
        let results = await environment.addonManager.healthCheckAll(environment.addons.installed)
        for (id, status) in results {
            try? environment.addons.updateHealth(id: id, status: status)
        }
    }

    private func recalibrate(_ addon: InstalledAddon) async {
        guard recalibratingAddonID == nil else { return }
        recalibratingAddonID = addon.id
        _ = await environment.addonCalibration.calibrate(addon: addon, force: true)
        environment.addons.configurationDidChange()
        await refreshCalibrationSummaries()
        recalibratingAddonID = nil
    }

    private func remove(_ addon: InstalledAddon) async {
        await environment.addonCalibration.removeProfile(for: addon)
        try? environment.addons.remove(id: addon.id)
    }

    private func refreshCalibrationSummaries() async {
        calibrationSummaries = await environment.addonCalibration.summaries(
            for: environment.addons.installed
        )
    }
}

private struct AddonRow: View {
    @Environment(AppEnvironment.self) private var environment
    let addon: InstalledAddon
    var calibration: AddonCalibrationSummary?
    var isRecalibrating = false
    var onRecalibrate: () -> Void = {}
    var onRemove: () -> Void = {}

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(addon.name)
                        .font(AppFont.cardTitle)
                    Circle()
                        .fill(healthColor)
                        .frame(width: 7, height: 7)
                        .help(addon.lastHealthStatus?.displayName ?? "Not checked")
                }
                if let description = addon.description {
                    Text(description)
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: Spacing.xs) {
                    Text(metadataLine)
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    if let calibrationStatus {
                        Text(calibrationStatus.label)
                            .font(AppFont.cardMeta)
                            .foregroundStyle(calibrationStatus.tint)
                    }
                }
            }

            Spacer(minLength: Spacing.sm)

            if isRecalibrating {
                ProgressView()
                    .controlSize(.small)
                    .help("Recalibrating stream format")
            } else if calibration?.isStale == true {
                Button {
                    onRecalibrate()
                } label: {
                    Label("Recalibrate", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("This addon's format may have changed. Recalibrate to restore accurate source selection.")
            }

            Toggle(
                "Enabled",
                isOn: Binding(
                    get: { addon.isEnabled },
                    set: { newValue in
                        try? environment.addons.setEnabled(id: addon.id, isEnabled: newValue)
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel("Enable \(addon.name)")

            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(isHovering ? Color.red.opacity(0.9) : Color.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(isHovering ? 1 : 0.6)
            .help("Remove \(addon.name)")
            .accessibilityLabel("Remove \(addon.name)")
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm - 2)
        .background(
            AppColor.surface,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(
                    isHovering ? Color.primary.opacity(0.18) : AppColor.stroke,
                    lineWidth: 0.5
                )
        }
        .opacity(addon.isEnabled ? 1 : 0.55)
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .animation(.easeOut(duration: Motion.hover), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var icon: some View {
        RemoteImage(
            url: addon.iconURL,
            contentMode: .fit,
            placeholderSystemImage: "puzzlepiece.extension"
        )
        .frame(width: 34, height: 34)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(AppColor.stroke, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private var metadataLine: String {
        var parts = [addon.protocolType.displayName]
        if !addon.idNamespaces.isEmpty {
            parts.append(addon.idNamespaces.map(\.displayName).joined(separator: ", "))
        }
        if !addon.capabilities.isEmpty {
            parts.append(addon.capabilities.map(\.displayName).sorted().joined(separator: ", "))
        }
        if let lastChecked = addon.lastCheckedAt {
            parts.append("Checked \(lastChecked.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var calibrationStatus: (label: String, tint: Color)? {
        guard let calibration else { return nil }
        if calibration.isStale {
            return ("Format may have changed", .orange)
        }
        switch calibration.status {
        case .success:
            return ("Format calibrated", .green)
        case .partial:
            return ("Limited format support", .orange)
        case .failure:
            return ("Format not recognized", .secondary)
        case .unavailable:
            return ("Built-in parsing", .secondary)
        case .skipped:
            return ("Optimized parsing", .secondary)
        }
    }

    private var healthColor: Color {
        switch addon.lastHealthStatus {
        case .healthy: .green
        case .degraded: .orange
        case .failing: .red
        case .unknown, nil: .gray.opacity(0.6)
        }
    }
}

struct AddAddonSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case input
        case loading
        case preview(AddonInstallPreview)
        case calibrating(AddonCalibrationPhase)
        case result(AddonCalibrationReport)
        case failed(String)

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }

        var isCalibrating: Bool {
            if case .calibrating = self { return true }
            return false
        }
    }

    @State private var urlString = ""
    @State private var phase: Phase = .input

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AppColor.brand)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Addon")
                        .font(AppFont.sectionTitle)
                    Text("Enter the addon's manifest URL, usually ending in manifest.json.")
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsFieldChrome {
                TextField("https://example.com/manifest.json", text: $urlString)
            }
            .onSubmit {
                Task { await fetchPreview() }
            }

            PhaseView(phase: phase, onAutoDismiss: { dismiss() })
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(GlassButtonStyle())
                .hoverFeedback(scale: 1.03)
                .keyboardShortcut(.cancelAction)

                switch phase {
                case .preview(let preview):
                    Button("Add Addon") {
                        install(preview)
                    }
                    .buttonStyle(BrandButtonStyle())
                    .hoverFeedback(scale: 1.03)
                    .keyboardShortcut(.defaultAction)
                case .result(let report):
                    resultActions(for: report)
                case .calibrating:
                    EmptyView()
                default:
                    Button("Fetch Manifest") {
                        Task { await fetchPreview() }
                    }
                    .buttonStyle(BrandButtonStyle())
                    .hoverFeedback(scale: 1.03)
                    .disabled(isFetchDisabled)
                    .opacity(isFetchDisabled ? 0.5 : 1)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(Spacing.xl)
        .frame(width: 540)
        .background(AppColor.surface)
    }

    private var isFetchDisabled: Bool {
        urlString.trimmingCharacters(in: .whitespaces).isEmpty || phase.isLoading
    }

    @ViewBuilder
    private func resultActions(for report: AddonCalibrationReport) -> some View {
        switch report.status {
        case .success, .skipped, .unavailable:
            Button("Done") {
                dismiss()
            }
            .buttonStyle(BrandButtonStyle())
            .hoverFeedback(scale: 1.03)
            .keyboardShortcut(.defaultAction)
        case .partial, .failure:
            Button("Remove Addon", role: .destructive) {
                Task {
                    await environment.addonCalibration.removeProfile(fingerprint: report.fingerprint)
                    try? environment.addons.remove(id: report.addonID)
                    dismiss()
                }
            }
            .buttonStyle(GlassButtonStyle())
            .hoverFeedback(scale: 1.03)
            Button(report.status == .partial ? "Keep Addon" : "Keep Anyway") {
                dismiss()
            }
            .buttonStyle(BrandButtonStyle())
            .hoverFeedback(scale: 1.03)
            .keyboardShortcut(.defaultAction)
        }
    }

    private struct PhaseView: View {
        let phase: AddAddonSheet.Phase
        var onAutoDismiss: () -> Void = {}

        var body: some View {
            switch phase {
            case .input:
                EmptyView()
            case .loading:
                HStack(spacing: Spacing.xs) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Fetching manifest\u{2026}")
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.secondary)
                }
            case .preview(let preview):
                SettingsCard {
                    AddonPreviewView(preview: preview)
                }
            case .calibrating(let progress):
                CalibrationProgressView(phase: progress)
            case .result(let report):
                CalibrationResultView(report: report)
                    .task {
                        guard report.status == .success else { return }
                        try? await Task.sleep(for: .seconds(2.4))
                        guard !Task.isCancelled else { return }
                        onAutoDismiss()
                    }
            case .failed(let message):
                SettingsBanner(kind: .warning, message: message)
            }
        }
    }

    @MainActor
    private func fetchPreview() async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else {
            phase = .failed("Enter a valid manifest URL.")
            return
        }
        phase = .loading
        do {
            let preview = try await environment.addonInstaller.preview(manifestURL: url)
            phase = .preview(preview)
        } catch {
            phase = .failed(message(for: error))
        }
    }

    private func install(_ preview: AddonInstallPreview) {
        do {
            let addon = try environment.addons.install(preview)
            phase = .calibrating(.preparing)
            Task { await calibrate(addon) }
        } catch {
            phase = .failed(message(for: error))
        }
    }

    @MainActor
    private func calibrate(_ addon: InstalledAddon) async {
        Task {
            let status = await environment.addonManager.healthCheck(addon)
            try? environment.addons.updateHealth(id: addon.id, status: status)
        }
        let report = await environment.addonCalibration.calibrate(addon: addon) { progress in
            await MainActor.run { phase = .calibrating(progress) }
        }
        phase = .result(report)
        environment.addons.configurationDidChange()
    }

    private func message(for error: Error) -> String {
        if let addonError = error as? AddonError {
            return addonError.errorDescription ?? "The addon could not be installed."
        }
        return error.localizedDescription
    }
}

private struct CalibrationProgressView: View {
    let phase: AddonCalibrationPhase

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text("Setting up addon\u{2026}")
                    .font(AppFont.cardTitle)
                Text(detail)
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppColor.surface,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(AppColor.stroke, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Setting up addon. Analyzing stream format.")
    }

    private var detail: String {
        switch phase {
        case .preparing:
            "Analyzing stream format"
        case .collecting(let title, let index, let total):
            "Analyzing stream format \u{00B7} \(title) (\(index)/\(total))"
        case .analyzing:
            "Analyzing stream format \u{00B7} this can take up to a minute"
        case .validating:
            "Verifying parsing profile"
        }
    }
}

private struct CalibrationResultView: View {
    let report: AddonCalibrationReport

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(report.title)
                    .font(AppFont.cardTitle)
            }

            Text(report.message)
                .font(AppFont.cardMeta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if showsCoverage, let coverage = report.coverage {
                Text("Stream format coverage \(Int((coverage * 100).rounded()))%")
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppColor.surface,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(AppColor.stroke, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch report.status {
        case .success: "checkmark.circle.fill"
        case .partial, .failure: "exclamationmark.triangle.fill"
        case .unavailable, .skipped: "info.circle.fill"
        }
    }

    private var tint: Color {
        switch report.status {
        case .success: .green
        case .partial: .orange
        case .failure: .red
        case .unavailable, .skipped: .secondary
        }
    }

    private var showsCoverage: Bool {
        report.status == .success || report.status == .partial
    }
}

private struct AddonPreviewView: View {
    let preview: AddonInstallPreview

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                RemoteImage(
                    url: preview.iconURL,
                    contentMode: .fit,
                    placeholderSystemImage: "puzzlepiece.extension"
                )
                .frame(width: 40, height: 40)
                .background(
                    Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(AppColor.stroke, lineWidth: 0.5)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.name)
                        .font(AppFont.cardTitle)
                    Text(preview.version.map { "Version \($0)" } ?? "Unknown version")
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if let description = preview.descriptionText {
                Text(description)
                    .font(AppFont.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Spacing.xs) {
                Pill(text: preview.protocolType.displayName)
                ForEach(preview.capabilities.sorted { $0.rawValue < $1.rawValue }) { capability in
                    Pill(text: capability.displayName)
                }
            }

            if !preview.idNamespaces.isEmpty {
                Text("Media IDs: \(preview.idNamespaces.map(\.displayName).joined(separator: ", "))")
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.secondary)
            }

            Text(preview.manifestURL.absoluteString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(Spacing.md)
    }
}

#if DEBUG
#Preview("Addons Settings") {
    AddonsSettingsView()
        .environment(AppEnvironment.preview())
        .frame(width: 620, height: 500)
}
#endif
