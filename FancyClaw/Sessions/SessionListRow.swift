import ChatCore
import DesignSystem
import GatewayProtocol
import SwiftUI

struct SessionListRow: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let session: SessionSummary
    let approvalCount: Int
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { title; metadata }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    title
                    Spacer(minLength: 0)
                    metadata
                }
            }
            if let preview = session.lastMessagePreview, !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary.color)
                    .lineLimit(2)
            }
            if session.hasActiveRun == true || approvalCount > 0 {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 7) { statuses }
                    VStack(alignment: .leading, spacing: 7) { statuses }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 10)
        .multilineTextAlignment(.leading)
        .contentShape(.rect)
    }

    private var title: some View {
        Text(session.title ?? "New chat")
            .font(.callout.weight(.semibold))
            .foregroundStyle(theme.textPrimary.color)
            .lineLimit(2)
    }

    private var metadata: some View {
        HStack(spacing: 7) {
            if let date = SessionListPresentation.activityDate(for: session) {
                Text(date, style: .relative)
                    .font(.footnote)
                    .foregroundStyle(theme.textTertiary.color)
            }
            if selected {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.accent.color)
                    .accessibilityLabel("Selected")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private var statuses: some View {
        if session.hasActiveRun == true {
            SessionStatusChip(title: "Running", needsApproval: false)
                .accessibilityIdentifier("sessions.running.\(session.key)")
        }
        if approvalCount > 0 {
            SessionStatusChip(title: "Needs approval", needsApproval: true)
                .accessibilityLabel("Needs approval, \(approvalCount) pending command approvals")
                .accessibilityIdentifier("sessions.approvals.\(session.key)")
        }
    }
}
