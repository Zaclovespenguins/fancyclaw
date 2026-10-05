import DesignSystem
import SwiftUI

/// Status text stays readable while the dot and surface carry the green/coral distinction.
struct SessionStatusChip: View {
    @Environment(\.appTheme) private var theme
    @ScaledMetric(relativeTo: .caption) private var dotSize: CGFloat = 6
    let title: String
    let needsApproval: Bool

    var body: some View {
        HStack(spacing: 6) {
            if needsApproval {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(theme.accent.color)
            } else {
                Circle().fill(theme.online.color).frame(width: dotSize, height: dotSize)
            }
            Text(title).foregroundStyle(theme.textPrimary.color)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .surface(in: .capsule, fill: needsApproval ? theme.accent.color : theme.online.color, opacity: 0.12)
    }
}
