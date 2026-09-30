import ChatCore
import DesignSystem
import SwiftUI

struct ChatMessageRow: View {
    let message: ConversationMessage

    var body: some View {
        Group {
            if message.role == .user {
                HStack {
                    Spacer(minLength: 48)
                    Text(message.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(.tint.opacity(0.14), in: .rect(cornerRadius: 22))
                }
            } else if message.text.isEmpty && message.isStreaming {
                ChatThinkingIndicator()
            } else {
                MarkdownText(message.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat.message.\(message.id)")
        .transition(.opacity)
    }
}
