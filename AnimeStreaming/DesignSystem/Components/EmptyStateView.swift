import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(AppFont.sectionTitle)
                .multilineTextAlignment(.center)
            Text(message)
                .font(AppFont.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(BrandButtonStyle())
                    .hoverFeedback(scale: 1.03)
                    .padding(.top, Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xxl)
        .accessibilityElement(children: .combine)
    }
}
