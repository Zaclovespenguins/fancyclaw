import ChatCore
import DesignSystem
import GatewayProtocol
import SwiftUI

struct ChatMessageRow: View {
    let message: ConversationMessage
    let gatewayBaseURL: URL?
    let loadImage: @Sendable (ContentBlock.Media) async throws -> Data
    let loadFile: @Sendable (ContentBlock.Media) async throws -> Data
    var onRetry: (() -> Void)?

    @Environment(\.appTheme) private var theme
    @State private var rowWidth: CGFloat = 0

    /// User bubbles take at most 82% of the row.
    private var bubbleMaxWidth: CGFloat { rowWidth > 0 ? rowWidth * 0.82 : .infinity }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if message.role == .user {
                if !message.text.isEmpty {
                    UserMarkdownText(message.text)
                        .font(.callout)
                        .foregroundStyle(theme.textPrimary.color)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .surface(in: UnevenRoundedRectangle(topLeadingRadius: AppTheme.Radius.chatCard, bottomLeadingRadius: AppTheme.Radius.chatCard,
                                                            bottomTrailingRadius: 6, topTrailingRadius: AppTheme.Radius.chatCard),
                                 fill: theme.accent.color, opacity: 0.30)
                        .overlay(
                            UnevenRoundedRectangle(topLeadingRadius: AppTheme.Radius.chatCard, bottomLeadingRadius: AppTheme.Radius.chatCard,
                                                   bottomTrailingRadius: 6, topTrailingRadius: AppTheme.Radius.chatCard)
                                .stroke(theme.accent.color.opacity(0.35), lineWidth: 0.5)
                        )
                        .frame(maxWidth: bubbleMaxWidth, alignment: .trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if message.deliveryFailed, let onRetry {
                    Button(action: onRetry) {
                        Label("Not sent · Retry", systemImage: "exclamationmark.arrow.circlepath")
                            .font(.footnote)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.danger.color)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("Message not sent. Retry")
                    .accessibilityIdentifier("chat.retry.\(message.id)")
                }
            } else {
                ChatToolSummaryChip(messageID: message.id, tools: message.tools)
                if !message.text.isEmpty {
                    MarkdownText(message.text, baseURL: gatewayBaseURL, imageLoader: { url in
                        try await loadImage(.init(kind: .image, url: url.absoluteString))
                    })
                    .foregroundStyle(theme.textPrimary.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if message.isStreaming && message.tools.isEmpty {
                    ChatThinkingIndicator()
                }
            }
            ForEach(Array(message.files.enumerated()), id: \.offset) { _, file in
                ChatFileCard(media: file, load: loadFile)
            }
            if !message.attachments.isEmpty {
                AttachmentTray(attachments: message.attachments)
            }
            ForEach(Array(message.images.enumerated()), id: \.offset) { _, media in
                ChatArtifactImage(media: media, load: loadImage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.message.\(message.id)")
        .transition(.opacity)
    }
}
