import SwiftUI

struct AddonsSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isAddingAddon = false
    @State private var isCheckingHealth = false

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
                    AddonRow(addon: addon)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 3, leading: -Spacing.xs, bottom: 3, trailing: 0))
                        .contextMenu {
                            Button("Check Health") {
                                Task { await checkHealth(addon) }
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
                                try? environment.addons.remove(id: addon.id)
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
}

private struct AddonRow: View {
    @Environment(AppEnvironment.self) private var environment
    let addon: InstalledAddon

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
                Text(metadataLine)
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.sm)

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
                try? environment.addons.remove(id: addon.id)
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

    private var healthColor: Color {
        switch addon.lastHealthStatus {
        case .healthy: .green
        case .degraded: .orange
        case .failing: .red
        case .unknown, nil: .gray.opacity(0.6)
        }
    }
}

private struct AddAddonSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case input
        case loading
        case preview(AddonInstallPreview)
        case failed(String)

        var isLoading: Bool {
            if case .loading = self { return true }
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

            PhaseView(phase: phase)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(GlassButtonStyle())
                .hoverFeedback(scale: 1.03)
                .keyboardShortcut(.cancelAction)

                if case .preview(let preview) = phase {
                    Button("Add Addon") {
                        install(preview)
                    }
                    .buttonStyle(BrandButtonStyle())
                    .hoverFeedback(scale: 1.03)
                    .keyboardShortcut(.defaultAction)
                } else {
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

    private struct PhaseView: View {
        let phase: AddAddonSheet.Phase

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
            Task {
                let status = await environment.addonManager.healthCheck(addon)
                try? environment.addons.updateHealth(id: addon.id, status: status)
            }
            dismiss()
        } catch {
            phase = .failed(message(for: error))
        }
    }

    private func message(for error: Error) -> String {
        if let addonError = error as? AddonError {
            return addonError.errorDescription ?? "The addon could not be installed."
        }
        return error.localizedDescription
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
