import SwiftUI
import Textual
import UIKit

/// Bytes live only in Textual's attachment memory, never in the transcript cache.
struct GatewayImageAttachment: Attachment {
    let data: Data
    let description: String
    let size: CGSize

    @MainActor var body: some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit()
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityLabel(description.isEmpty ? "Assistant image" : description)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, in environment: TextEnvironmentValues) -> CGSize {
        let width = min(proposal.width ?? size.width, size.width)
        return CGSize(width: width, height: width * size.height / max(size.width, 1))
    }
}
