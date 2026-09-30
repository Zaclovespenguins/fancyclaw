import ChatCore
import DesignSystem
import GatewayProtocol
import SwiftUI

struct ChatMessageRow: View {
    let message: ConversationMessage
    let gatewayBaseURL: URL?
    let loadImage: @Sendable (ContentBlock.Media) async throws -> Data

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if message.role == .user {
                HStack {
                    Spacer(minLength: 48)
                    UserMarkdownText(message.text)
                        .font(.body)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(.tint.opacity(0.14), in: .rect(cornerRadius: 22))
                }
            } else {
                ForEach(message.tools) { tool in ChatToolCard(tool: tool) }
                if !message.text.isEmpty {
                    MarkdownText(message.text, baseURL: gatewayBaseURL, imageLoader: { url in
                        try await loadImage(.init(kind: .image, url: url.absoluteString))
                    })
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if message.isStreaming && message.tools.isEmpty {
                    ChatThinkingIndicator()
                }
            }
            ForEach(Array(message.images.enumerated()), id: \.offset) { _, media in
                ChatArtifactImage(media: media, load: loadImage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.message.\(message.id)")
        .transition(.opacity)
    }
}
