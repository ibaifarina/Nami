import SwiftUI

struct ErrorStateView: View {
    let title: String
    var message: String?
    var technicalDetail: String?
    var retryTitle = String(localized: "Try Again")
    var onRetry: (() -> Void)?
    var secondaryTitle: String?
    var onSecondary: (() -> Void)?

    @State private var showsDetails = false

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(AppFont.sectionTitle)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(AppFont.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            HStack(spacing: Spacing.sm) {
                if let onRetry {
                    Button(retryTitle, action: onRetry)
                        .buttonStyle(BrandButtonStyle())
                        .hoverFeedback(scale: 1.03)
                }
                if let secondaryTitle, let onSecondary {
                    Button(secondaryTitle, action: onSecondary)
                        .buttonStyle(GlassButtonStyle())
                        .hoverFeedback(scale: 1.03)
                }
            }
            .padding(.top, Spacing.xxs)
            if let technicalDetail {
                DisclosureGroup("Technical details", isExpanded: $showsDetails) {
                    Text(technicalDetail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: 460, alignment: .leading)
                }
                .font(AppFont.cardMeta)
                .frame(maxWidth: 460)
                .padding(.top, Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xxl)
        .accessibilityElement(children: .combine)
    }
}
