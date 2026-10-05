import ChatCore
import DesignSystem
import GatewayProtocol
import SwiftUI

struct HomeApprovalRow: View {
    let approval: ConversationApproval
    let review: () -> Void
    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { details; reviewButton }
            VStack(alignment: .leading, spacing: 12) { details; reviewButton }
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .surface(in: .rect(cornerRadius: AppTheme.Radius.card), fill: theme.accent.color, opacity: 0.18)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(approval.displayTitle).font(.callout.weight(.semibold)).foregroundStyle(theme.textPrimary.color)
            Text(approval.request.request.command).font(.caption.monospaced()).foregroundStyle(theme.textSecondary.color)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reviewButton: some View {
        Button("Review", action: review)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(theme.bg.color)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .background(theme.textPrimary.color, in: Capsule())
            .buttonStyle(PressScale())
            .accessibilityLabel("Review \(approval.displayTitle)")
            .accessibilityIdentifier("home.review.\(approval.id)")
    }
}
