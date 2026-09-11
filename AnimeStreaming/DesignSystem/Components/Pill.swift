import SwiftUI

struct Pill: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(AppFont.cardMeta.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.45), in: Capsule())
    }
}
