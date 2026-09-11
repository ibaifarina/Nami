import SwiftUI

struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: Motion.transition))) { phase in
            switch phase {
            case .empty:
                LoadingSkeleton(cornerRadius: 0)
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            case .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            AppColor.surfaceElevated
            Image(systemName: "photo")
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
    }
}
