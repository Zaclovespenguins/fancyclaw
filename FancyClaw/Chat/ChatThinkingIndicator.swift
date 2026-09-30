import SwiftUI

struct ChatThinkingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            if reduceMotion {
                Image(systemName: "ellipsis")
                    .font(.body.bold())
                    .accessibilityHidden(true)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }

            Text("Thinking…")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Assistant is thinking")
        .accessibilityIdentifier("chat.thinking")
    }
}
