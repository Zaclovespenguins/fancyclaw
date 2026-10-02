import ChatCore
import DesignSystem
import SwiftUI

/// One capsule per assistant message: icon, client-built summary, chevron. Expanding lists each tool.
struct ChatToolSummaryChip: View {
    let messageID: String
    let tools: [ConversationTool]
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme

    var body: some View {
        if let summary = ToolSummary.make(for: tools) {
            VStack(alignment: .leading, spacing: 8) {
                Button { withAnimation(reduceMotion ? nil : .snappy) { isExpanded.toggle() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: symbol(summary.state))
                            .foregroundStyle(summary.state == .failed ? theme.danger.color : theme.accentText.color)
                            .symbolEffect(.pulse, isActive: summary.state == .running && !reduceMotion)
                            .accessibilityHidden(true)
                        Text(summary.text)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(theme.textPrimary.color)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.textSecondary.color)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .frame(minHeight: 44)
                    .surface(in: .capsule, opacity: 0.07)
                    .contentShape(.capsule)
                }
                .buttonStyle(PressScale())
                .accessibilityLabel(summary.text)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint("Shows each tool")
                .accessibilityIdentifier("chat.toolchip.\(messageID)")

                if isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(tools) { tool in ChatToolCard(tool: tool) }
                    }
                }
            }
        }
    }

    private func symbol(_ state: ToolSummary.State) -> String {
        switch state {
        case .running: "gearshape.2"
        case .failed: "exclamationmark.circle"
        case .done: "checkmark.circle"
        }
    }
}

/// A single tool inside the expanded chip, with its arguments and result disclosure.
struct ChatToolCard: View {
    let tool: ConversationTool
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .foregroundStyle(tool.status == .error ? theme.danger.color : theme.textSecondary.color)
                        .symbolEffect(.pulse, isActive: tool.status == .running && !reduceMotion)
                        .accessibilityHidden(true)
                    Text(tool.name).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textPrimary.color)
                    Spacer()
                    Text(statusLabel).font(.caption).foregroundStyle(theme.textSecondary.color)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.textSecondary.color)
                        .accessibilityHidden(true)
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
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .surface(in: .rect(cornerRadius: AppTheme.Radius.chatCard - 6), opacity: 0.06)
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
