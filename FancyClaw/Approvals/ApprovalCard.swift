import ChatCore
import DesignSystem
import GatewayProtocol
import SwiftUI

/// A command approval in the transcript: an accent-tinted card while it needs a decision, then a one-line receipt.
struct ApprovalCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.appTheme) private var theme
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    let approval: ConversationApproval
    let store: ApprovalStore
    let isConnected: Bool

    private var details: ExecApprovalRequest.Details { approval.request.request }

    var body: some View {
        Group {
            if let receipt = approval.receipt {
                receiptRow(receipt)
            } else {
                card
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("approval.card.\(approval.id)")
        // Decision haptics: success for an approval, a warning for a denial; both gated by the haptics preference.
        .sensoryFeedback(trigger: approval.status) { old, new in
            guard hapticsEnabled, old == .resolving, case .resolved(let decision) = new else { return nil }
            return decision == .deny ? .warning : .success
        }
    }

    private func receiptRow(_ receipt: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: receiptSymbol)
                .foregroundStyle(theme.textSecondary.color)
                .accessibilityHidden(true)
            Text(receipt)
                .font(.footnote)
                .foregroundStyle(theme.textSecondary.color)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .truncationMode(.tail)
                .accessibilityIdentifier("approval.status.\(approval.id)")
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .surface(in: .rect(cornerRadius: AppTheme.Radius.chatCard), opacity: 0.06)
    }

    private var receiptSymbol: String {
        switch approval.status {
        case .resolved(.allowOnce), .resolved(.allowAlways): "checkmark.shield"
        case .resolved(.deny): "xmark.shield"
        case .expired: "clock.badge.xmark"
        default: "shield"
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("APPROVAL NEEDED")
                .font(.footnote.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(theme.accentText.color)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("approval.status.\(approval.id)")
            Text(approval.displayTitle)
                .font(.callout.weight(.semibold))
                .foregroundStyle(theme.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            Text(details.command)
                .font(.footnote.monospaced())
                .foregroundStyle(theme.textPrimary.color)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface(in: .rect(cornerRadius: AppTheme.Radius.codeBlock), opacity: 0.10)
            VStack(alignment: .leading, spacing: 4) {
                if approval.sessionKey == nil {
                    secondary("The Gateway did not identify a chat for this command.")
                }
                if let cwd = details.cwd { secondary("Directory: \(cwd)") }
                if let host = details.host { secondary("Host: \(host)") }
                if let warning = details.warningText, warning != approval.displayTitle {
                    Label {
                        Text(warning)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
                }
                if approval.status == .resolving {
                    secondary("Sending decision…")
                } else {
                    secondary("Expires in \(max(0, Int(ceil(approval.request.expiresAt.timeIntervalSince(store.currentDate))))) seconds")
                }
            }
            if let permission = store.permissionMessage {
                Text(permission).font(.subheadline).foregroundStyle(theme.textPrimary.color)
                    .accessibilityIdentifier("approval.permission")
            } else if !isConnected {
                Text("Reconnect to send a decision.").font(.subheadline).foregroundStyle(theme.textPrimary.color)
            }
            if let error = approval.errorMessage, error != store.permissionMessage {
                Text(error).font(.subheadline).foregroundStyle(theme.danger.color)
            }
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) { decisions }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { decisions }
                            .fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 10) { decisions }
                    }
                }
            }
            .disabled(!store.hasApprovalScope || !isConnected || approval.status != .pending)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A flat accent tint rather than tinted glass: glass over the glow made the card text fail contrast.
        .surface(in: .rect(cornerRadius: AppTheme.Radius.chatCard), fill: theme.accent.color, opacity: 0.18)
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.chatCard)
                .stroke(theme.accent.color.opacity(0.4), lineWidth: 0.5)
        }
    }

    private func secondary(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(theme.textSecondary.color)
    }

    /// Deny, then Always allow, then Approve, limited to the decisions the Gateway offered.
    private var orderedDecisions: [ApprovalDecision] {
        func rank(_ decision: ApprovalDecision) -> Int {
            switch decision {
            case .deny: 0
            case .allowAlways: 1
            case .allowOnce: 2
            case .unknown: 3
            }
        }
        return approval.request.offeredDecisions.sorted { rank($0) < rank($1) }
    }

    private var decisions: some View {
        ForEach(orderedDecisions, id: \.rawValue) { decision in
            Button {
                Task { await store.resolve(id: approval.id, decision: decision) }
            } label: {
                Text(label(for: decision))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(decision == .allowOnce ? theme.bg.color : theme.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, minHeight: 44)
                    .background(decision == .allowOnce ? theme.textPrimary.color : theme.textPrimary.color.opacity(0.12), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(PressScale())
            .accessibilityIdentifier("approval.\(decision.rawValue).\(approval.id)")
        }
    }

    private func label(for decision: ApprovalDecision) -> String {
        switch decision {
        case .allowOnce: "Approve"
        case .allowAlways: "Always allow"
        case .deny: "Deny"
        case .unknown: "Unavailable"
        }
    }
}
