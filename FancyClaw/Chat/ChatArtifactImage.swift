import DesignSystem
import GatewayProtocol
import SwiftUI

struct ChatArtifactImage: View {
    let media: ContentBlock.Media
    let load: @Sendable (ContentBlock.Media) async throws -> Data
    @Environment(\.appTheme) private var theme
    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0

    private struct LoadID: Hashable {
        let media: ContentBlock.Media
        let attempt: Int
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(.rect(cornerRadius: AppTheme.Radius.chatCard))
                    .accessibilityLabel(media.alt ?? media.fileName ?? "Assistant image")
            } else if failed {
                VStack(spacing: 8) {
                    Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                    Button("Retry image") { attempt += 1 }
                }
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary.color)
                .frame(maxWidth: .infinity, minHeight: 100)
                .surface(in: .rect(cornerRadius: AppTheme.Radius.chatCard), opacity: 0.06)
            } else {
                ProgressView("Loading image")
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .surface(in: .rect(cornerRadius: AppTheme.Radius.chatCard), opacity: 0.06)
            }
        }
        .task(id: LoadID(media: media, attempt: attempt)) { await loadImage() }
    }

    private func loadImage() async {
        failed = false
        image = nil
        do {
            let data = try await load(media)
            try Task.checkCancellation()
            guard let decoded = UIImage(data: data) else { failed = true; return }
            image = decoded
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}
