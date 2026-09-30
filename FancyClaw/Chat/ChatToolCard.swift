import ChatCore
import SwiftUI

struct ChatToolCard: View {
    let tool: ConversationTool
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .foregroundStyle(tool.status == .error ? .red : .secondary)
                        .symbolEffect(.pulse, isActive: tool.status == .running && !reduceMotion)
                    Text(tool.name).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(statusLabel).font(.caption).foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows tool arguments and result")
            .accessibilityIdentifier("chat.tool.\(tool.id)")
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if let arguments = tool.arguments {
                        ChatToolDetail(title: "Arguments", text: ConversationTool.formatted(arguments))
                    }
                    if let result = tool.result {
                        ChatToolDetail(title: "Result", text: ConversationTool.formatted(result))
                    }
                }
                .padding(.top, 12)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func toggle() {
        isExpanded.toggle()
    }

    private var statusLabel: String {
        switch tool.status {
        case .running: "Running"
        case .success: "Completed"
        case .error: "Failed"
        case .interrupted: "Ended"
        }
    }

    private var symbol: String {
        switch tool.status {
        case .running: "gearshape.2"
        case .success: "checkmark.circle"
        case .error: "exclamationmark.circle"
        case .interrupted: "minus.circle"
        }
    }
}
