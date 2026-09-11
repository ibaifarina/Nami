import SwiftUI

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.sectionTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.cardMeta)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppColor.brand)
                    .hoverFeedback(brightness: 0.2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
