import AppKit
import SwiftUI

struct RealDebridSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var tokenInput = ""

    var body: some View {
        Form {
            if let account = environment.debridAuth.account {
                Section("Account") {
                    LabeledContent("Username", value: account.username)
                    LabeledContent("Plan", value: account.isPremium ? "Premium" : "Free")
                    if let expiration = account.expirationDescription {
                        LabeledContent("Premium until", value: expiration)
                    }
                    HStack {
                        Button("Verify") {
                            Task { await environment.debridAuth.verify() }
                        }
                        .hoverFeedback(scale: 1.03)
                        Button("Disconnect", role: .destructive) {
                            Task { await environment.debridAuth.disconnect() }
                        }
                        .hoverFeedback(scale: 1.03)
                    }
                }
            } else {
                Section("Connect") {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("API token")
                        HStack(spacing: Spacing.sm) {
                            SecureField("", text: $tokenInput, prompt: Text("Paste your API token"))
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                            Button("Paste", action: pasteToken)
                                .hoverFeedback(scale: 1.03)
                                .disabled(!canPasteToken)
                        }
                    }
                    Text("Generate a private API token at real-debrid.com/apitoken and paste it here. The token is stored in your macOS Keychain and never logged or sent to addons.")
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.secondary)
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
                        .hoverFeedback(scale: 1.03)
                        .disabled(
                            tokenInput.trimmingCharacters(in: .whitespaces).isEmpty
                                || environment.debridAuth.isConnecting
                        )
                        if let tokenPage = URL(string: "https://real-debrid.com/apitoken") {
                            Link("Open Token Page", destination: tokenPage)
                        }
                    }
                }
            }

            if let message = environment.debridAuth.failureMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section("Usage") {
                Text("Connected sources are resolved through Real-Debrid. Cached torrents start immediately; uncached ones are prepared by Real-Debrid first.")
                    .font(AppFont.cardMeta)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
