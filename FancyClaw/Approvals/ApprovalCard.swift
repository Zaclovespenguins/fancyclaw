import ChatCore
import GatewayProtocol
import SwiftUI

struct ApprovalCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    let approval: ConversationApproval
    let store: ApprovalStore
    let isConnected: Bool

    private var statusText: String {
        switch approval.status {
        case .pending: "Command approval"
        case .resolving: "Sending decision…"
        case .resolved(.allowOnce): "Approved once"
        case .resolved(.allowAlways): "Always allowed"
        case .resolved(.deny): "Denied"
        case .resolved(.unknown): "Handled by the Gateway"
        case .alreadyHandled: "Already handled elsewhere or expired"
        case .expired: "Approval expired"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(statusText, systemImage: approval.status.isPending ? "terminal" : "checkmark.shield")
                .font(.headline)
                .accessibilityIdentifier("approval.status.\(approval.id)")
            if approval.sessionKey == nil {
                Text("The Gateway did not identify a chat for this command.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let preview = approval.request.request.commandPreview,
               preview != approval.request.request.command {
                Text(preview).font(.subheadline)
            }
            Text(approval.request.request.command)
                .font(.body.monospaced()).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let cwd = approval.request.request.cwd {
                Text("Directory: \(cwd)").font(.caption).foregroundStyle(.secondary)
            }
            if let host = approval.request.request.host {
                Text("Host: \(host)").font(.caption).foregroundStyle(.secondary)
            }
            if let warning = approval.request.request.warningText {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.subheadline).foregroundStyle(Color.primary)
            }
            if approval.status.isPending {
                Text("Expires in \(max(0, Int(ceil(approval.request.expiresAt.timeIntervalSince(store.currentDate))))) seconds")
                    .font(.caption).foregroundStyle(.secondary)
                if let permission = store.permissionMessage {
                    Text(permission).font(.subheadline)
                        .accessibilityIdentifier("approval.permission")
                } else if !isConnected {
                    Text("Reconnect to send a decision.").font(.subheadline)
                }
                if let error = approval.errorMessage, error != store.permissionMessage {
                    Text(error).font(.subheadline).foregroundStyle(.red)
                }
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 12) { decisions }
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { decisions }
                                .fixedSize(horizontal: true, vertical: false)
                            VStack(alignment: .leading, spacing: 12) { decisions }
                        }
                    }
                }
                .controlSize(.large)
                .disabled(!store.hasApprovalScope || !isConnected || approval.status != .pending)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("approval.card.\(approval.id)")
        .sensoryFeedback(.success, trigger: approval.status) { old, new in
            guard hapticsEnabled, old == .resolving else { return false }
            if case .resolved = new { return true }
            return false
        }
    }

    private var decisions: some View {
        ForEach(approval.request.offeredDecisions, id: \.rawValue) { decision in
            Button(role: decision == .deny ? .destructive : nil) {
                Task { await store.resolve(id: approval.id, decision: decision) }
            } label: {
                Text(label(for: decision))
                    .font(.body.bold())
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .background(.background, in: .capsule)
                    .overlay { Capsule().stroke(.primary.opacity(0.5)) }
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
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
