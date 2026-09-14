import AppKit
import SwiftUI

struct RealDebridSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var tokenInput = ""

    var body: some View {
        SettingsPaneLayout(pane: .realDebrid) {
            if let account = environment.debridAuth.account {
                connectedCard(account)
            } else {
                connectCard
            }
            if let message = environment.debridAuth.failureMessage {
                SettingsBanner(kind: .warning, message: message)
            }
            SettingsCard(title: String(localized: "Usage")) {
                SettingsRow(
                    String(localized: "Source Resolution"),
                    description: String(localized: "Connected sources are resolved through Real-Debrid. Cached torrents start immediately; uncached ones are prepared by Real-Debrid first.")
                ) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func connectedCard(_ account: DebridAccount) -> some View {
        SettingsCard(title: String(localized: "Account")) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.green)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.username)
                        .font(AppFont.sectionTitle)
                    Text(account.isPremium ? "Premium account" : "Free account")
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.md)

            SettingsValueRow(title: String(localized: "Username"), value: account.username)
            SettingsRow(String(localized: "Plan")) {
                Pill(
                    text: account.isPremium ? String(localized: "Premium") : String(localized: "Free"),
                    systemImage: account.isPremium ? "star.fill" : nil,
                    tint: account.isPremium ? .green : .secondary
                )
            }
            if let expiration = account.expirationDescription {
                SettingsValueRow(title: String(localized: "Premium Until"), value: expiration)
            }
            SettingsRow(
                String(localized: "Connection"),
                description: String(localized: "Verifying re-checks your token with Real-Debrid. Disconnecting removes it from your Keychain.")
            ) {
                HStack(spacing: Spacing.xs) {
                    Button("Verify") {
                        Task { await environment.debridAuth.verify() }
                    }
                    .controlSize(.small)
                    .hoverFeedback(scale: 1.03)

                    Button("Disconnect", role: .destructive) {
                        Task { await environment.debridAuth.disconnect() }
                    }
                    .controlSize(.small)
                    .hoverFeedback(scale: 1.03)
                }
            }
        }
    }

    private var connectCard: some View {
        SettingsCard(title: String(localized: "Connect")) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 40, height: 40)
                    Image(systemName: "bolt")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Real-Debrid")
                        .font(AppFont.sectionTitle)
                    Text("Not connected")
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.md)

            SettingsStackedRow(
                String(localized: "API Token"),
                description: String(localized: "Generate a private token at real-debrid.com/apitoken. It is stored in your macOS Keychain and never logged or sent to addons.")
            ) {
                HStack(spacing: Spacing.sm) {
                    SettingsFieldChrome {
                        SecureField("", text: $tokenInput, prompt: Text("Paste your API token"))
                    }
                    Button("Paste", action: pasteToken)
                        .controlSize(.small)
                        .disabled(!canPasteToken)
                        .hoverFeedback(scale: 1.03)
                }
                HStack(spacing: Spacing.sm) {
                    Button {
                        let token = tokenInput
                        tokenInput = ""
                        Task { await environment.debridAuth.connect(token: token) }
                    } label: {
                        if environment.debridAuth.isConnecting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Connect Real-Debrid")
                        }
                    }
                    .buttonStyle(BrandButtonStyle())
                    .disabled(!canConnect)
                    .opacity(canConnect ? 1 : 0.5)

                    if let tokenPage = URL(string: "https://real-debrid.com/apitoken") {
                        Link("Open Token Page", destination: tokenPage)
                            .font(AppFont.cardMeta.weight(.medium))
                    }
                }
                .padding(.top, Spacing.xxs)
            }
        }
    }

    private var canConnect: Bool {
        !tokenInput.trimmingCharacters(in: .whitespaces).isEmpty
            && !environment.debridAuth.isConnecting
    }

    private var canPasteToken: Bool {
        NSPasteboard.general.canReadItem(
            withDataConformingToTypes: [NSPasteboard.PasteboardType.string.rawValue]
        )
    }

    private func pasteToken() {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        tokenInput = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#if DEBUG
#Preview("Real-Debrid Settings") {
    SettingsScene()
        .environment(AppEnvironment.preview())
}
#endif
